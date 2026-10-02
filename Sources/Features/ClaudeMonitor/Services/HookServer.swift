import Foundation
import WyspaCore
import WyspaHookKit

/// Serwer gniazda Unix dla `wyspa-hook`: jedna linia JSON od hooka, opcjonalnie potwierdzenie i jedna linia decyzji.
///
/// Bezpieczeństwo: katalog 0700, gniazdo dostaje 0600 między `bind` a `listen` — przed `listen` nikt nie może się
/// połączyć, więc nie ma okna z szerszymi prawami. (Bez `umask`: to ustawienie całego procesu i psułoby
/// równoległe zakładanie plików w innych wątkach.)
/// Połączenia mają własne, rosnące identyfikatory — decyzja nigdy nie trafi do innego hooka, nawet gdy system
/// ponownie użyje tego samego numeru deskryptora.
public final class HookServer: @unchecked Sendable {
    public typealias MessageHandler = @Sendable (HookProtocol.Envelope, ReplyChannel?) -> Void

    /// Najwięcej jednocześnie otwartych połączeń (obrona przed zalaniem gniazda).
    static let maxClients = 64

    /// Kanał odpowiedzi do jednego hooka czekającego na decyzję.
    public struct ReplyChannel: Hashable, Sendable {
        public let id: UInt64
        fileprivate let server: HookServer

        /// Potwierdzenie z głównego wątku Wyspy: hook wie, że aplikacja żyje i pokaże prośbę.
        public func acknowledge() {
            server.write(to: id, data: HookProtocol.acknowledgement, closing: false)
        }

        public func send(_ behavior: HookProtocol.Behavior, message: String? = nil, answers: [String: String]? = nil) {
            server.write(to: id, data: HookProtocol.reply(behavior, message: message, answers: answers), closing: true)
        }

        public static func == (lhs: ReplyChannel, rhs: ReplyChannel) -> Bool { lhs.id == rhs.id }
        public func hash(into hasher: inout Hasher) { hasher.combine(id) }
    }

    public enum StartError: Error, LocalizedError {
        case socket(String)

        public var errorDescription: String? {
            if case .socket(let detail) = self { return "Nie udało się otworzyć gniazda dla hooków: \(detail)" }
            return nil
        }
    }

    private struct Client {
        let fd: Int32
        let source: DispatchSourceRead
        var buffer = Data()
        var awaitingReply = false
    }

    private let path: String
    private let queue = DispatchQueue(label: "pl.net.kurant.wyspa.claude-socket")
    private let onMessage: MessageHandler
    private let onClosed: @Sendable (UInt64) -> Void
    private var listener: Int32 = -1
    /// Tożsamość naszego pliku gniazda: `stop()` usuwa tylko je, nigdy gniazda innej kopii Wyspy.
    private var socketIdentity: (device: dev_t, inode: ino_t)?
    private var acceptSource: DispatchSourceRead?
    private var clients: [UInt64: Client] = [:]
    private var nextID: UInt64 = 1
    private let log = Log.logger("claude.socket")

    public init(path: String = HookProtocol.socketURL.path, onMessage: @escaping MessageHandler,
                onClosed: @escaping @Sendable (UInt64) -> Void) {
        self.path = path
        self.onMessage = onMessage
        self.onClosed = onClosed
    }

    public func start() throws(StartError) {
        let directory = (path as NSString).deletingLastPathComponent
        do {
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
        } catch {
            throw .socket(error.localizedDescription)
        }
        // `attributes` działa tylko przy zakładaniu; katalog mógł już istnieć (np. założony przez Notatki) z 0755.
        // Zaciskamy go do 0700, ale tylko gdy należy do nas — cudzych katalogów (np. /tmp w testach) nie ruszamy.
        var directoryInfo = stat()
        if lstat(directory, &directoryInfo) == 0, directoryInfo.st_uid == getuid() {
            // Nasz katalog podmieniony na dowiązanie: nie zakładamy gniazda w nieznanym miejscu.
            guard directoryInfo.st_mode & S_IFMT == S_IFDIR else { throw .socket("katalog gniazda nie jest katalogiem") }
            if directoryInfo.st_mode & 0o777 != 0o700, chmod(directory, 0o700) != 0 {
                throw .socket("nie udało się ustawić uprawnień katalogu: \(String(cString: strerror(errno)))")
            }
        }
        // Usuwamy tylko stare, martwe gniazdo — nigdy zwykły plik, dowiązanie ani gniazdo działającej kopii Wyspy.
        var info = stat()
        if lstat(path, &info) == 0 {
            guard info.st_mode & S_IFMT == S_IFSOCK else { throw .socket("pod ścieżką gniazda jest coś innego niż gniazdo") }
            if Self.isListening(path) { throw .socket("inna kopia Wyspy już obsługuje hooki Claude Code") }
            unlink(path)
        }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw .socket(String(cString: strerror(errno))) }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
            close(fd)
            throw .socket("za długa ścieżka gniazda")
        }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: bytes)
            buffer[bytes.count] = 0
        }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        var boundInfo = stat()
        guard bound == 0, chmod(path, 0o600) == 0, lstat(path, &boundInfo) == 0, listen(fd, 16) == 0 else {
            let reason = String(cString: strerror(errno))
            close(fd)
            throw .socket(reason)
        }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        socketIdentity = (boundInfo.st_dev, boundInfo.st_ino)
        listener = fd
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptClients() }
        // Deskryptor zamykany dopiero po anulowaniu źródła (zamknięcie pod aktywnym źródłem to błąd użycia GCD).
        source.setCancelHandler { close(fd) }
        source.resume()
        acceptSource = source
    }

    /// Zatrzymuje serwer. Czekające hooki dostają „ask” (prompt w terminalu) zamiast czekać do końca limitu.
    public func stop() {
        queue.sync {
            for client in clients.values {
                if client.awaitingReply { writeAll(client.fd, HookProtocol.reply(.ask)) }
                client.source.cancel()
            }
            clients = [:]
            acceptSource?.cancel()
            acceptSource = nil
            listener = -1
            var info = stat()
            if let socketIdentity, lstat(path, &info) == 0, info.st_dev == socketIdentity.device, info.st_ino == socketIdentity.inode {
                unlink(path)
            }
            socketIdentity = nil
        }
    }

    /// Czy pod ścieżką słucha żywy serwer (inna kopia Wyspy).
    static func isListening(_ path: String) -> Bool {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else { return false }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: bytes)
            buffer[bytes.count] = 0
        }
        return withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        } == 0
    }

    // MARK: - Na kolejce gniazda

    private func acceptClients() {
        while true {
            let fd = accept(listener, nil, nil)
            guard fd >= 0 else { return }
            // Tylko procesy tego samego użytkownika (gniazdo 0600 i katalog 0700 to i tak wymuszają).
            var uid: uid_t = 0, gid: gid_t = 0
            guard getpeereid(fd, &uid, &gid) == 0, uid == getuid(), clients.count < Self.maxClients else {
                close(fd)
                continue
            }
            _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
            var noSigPipe: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
            let id = nextID
            nextID += 1
            let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
            source.setEventHandler { [weak self] in self?.read(id) }
            source.setCancelHandler { close(fd) }
            clients[id] = Client(fd: fd, source: source)
            source.resume()
        }
    }

    private func read(_ id: UInt64) {
        guard var client = clients[id] else { return }
        var chunk = [UInt8](repeating: 0, count: 64 * 1024)
        let count = Darwin.read(client.fd, &chunk, chunk.count)
        if count <= 0 {
            // Hook zamknął połączenie: zwykły koniec albo minął jego czas na decyzję.
            let wasWaiting = client.awaitingReply
            client.source.cancel()
            clients[id] = nil
            if wasWaiting { onClosed(id) }
            return
        }
        guard !client.awaitingReply else { return }
        client.buffer.append(contentsOf: chunk[0..<count])
        guard client.buffer.count <= HookProtocol.maxMessageBytes else {
            log.error("Za duża wiadomość od hooka — odrzucona")
            client.source.cancel()
            clients[id] = nil
            return
        }
        guard let newline = client.buffer.firstIndex(of: UInt8(ascii: "\n")) else {
            clients[id] = client
            return
        }
        let line = client.buffer[client.buffer.startIndex..<newline]
        do {
            let envelope = try HookProtocol.parse(Data(line))
            if envelope.wantsReply {
                client.awaitingReply = true
                clients[id] = client
                onMessage(envelope, ReplyChannel(id: id, server: self))
            } else {
                client.source.cancel()
                clients[id] = nil
                onMessage(envelope, nil)
            }
        } catch {
            log.error("Nieczytelna wiadomość od hooka: \(String(describing: error))")
            client.source.cancel()
            clients[id] = nil
        }
    }

    fileprivate func write(to id: UInt64, data: Data, closing: Bool) {
        queue.async { [self] in
            guard let client = clients[id], client.awaitingReply else { return }
            writeAll(client.fd, data)
            if closing {
                client.source.cancel()
                clients[id] = nil
            }
        }
    }

    private func writeAll(_ fd: Int32, _ data: Data) {
        data.withUnsafeBytes { buffer in
            var offset = 0
            var attempts = 0
            while offset < buffer.count, attempts < 1000 {
                let written = Darwin.write(fd, buffer.baseAddress! + offset, buffer.count - offset)
                if written > 0 {
                    offset += written
                } else if written < 0 && errno == EAGAIN {
                    attempts += 1
                    usleep(1000)
                } else {
                    return
                }
            }
        }
    }
}
