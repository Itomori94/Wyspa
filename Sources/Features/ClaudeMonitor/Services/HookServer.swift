import Foundation
import WyspaCore
import WyspaHookKit

/// Serwer gniazda Unix dla `wyspa-hook`: jedna linia JSON od hooka, opcjonalnie jedna linia odpowiedzi.
///
/// Gniazdo ma prawa 0600 (tylko właściciel). Prośba o uprawnienie trzyma połączenie otwarte do decyzji;
/// zamknięcie połączenia przez hook (minął jego czas) zgłasza `onClosed`.
public final class HookServer: @unchecked Sendable {
    public typealias MessageHandler = @Sendable (HookProtocol.Envelope, ReplyChannel?) -> Void

    /// Kanał odpowiedzi do jednego hooka czekającego na decyzję.
    public struct ReplyChannel: Hashable, Sendable {
        public let id: Int32
        fileprivate let server: HookServer

        public func send(_ behavior: HookProtocol.Behavior, message: String? = nil) {
            server.reply(to: id, data: HookProtocol.reply(behavior, message: message))
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
        let source: DispatchSourceRead
        var buffer = Data()
        var awaitingReply = false
    }

    private let path: String
    private let queue = DispatchQueue(label: "pl.net.kurant.wyspa.claude-socket")
    private let onMessage: MessageHandler
    private let onClosed: @Sendable (Int32) -> Void
    private var listener: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var clients: [Int32: Client] = [:]
    private let log = Log.logger("claude.socket")

    public init(path: String = HookProtocol.socketURL.path, onMessage: @escaping MessageHandler,
                onClosed: @escaping @Sendable (Int32) -> Void) {
        self.path = path
        self.onMessage = onMessage
        self.onClosed = onClosed
    }

    public func start() throws(StartError) {
        do {
            try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                                    withIntermediateDirectories: true)
        } catch {
            throw .socket(error.localizedDescription)
        }
        unlink(path)
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
        guard bound == 0, chmod(path, 0o600) == 0, listen(fd, 16) == 0 else {
            let reason = String(cString: strerror(errno))
            close(fd)
            throw .socket(reason)
        }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        listener = fd
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptClients() }
        source.resume()
        acceptSource = source
    }

    /// Zatrzymuje serwer. Czekające hooki dostają „ask” (prompt w terminalu) zamiast czekać do końca limitu.
    public func stop() {
        queue.sync {
            for (fd, client) in clients {
                if client.awaitingReply { writeAll(fd, HookProtocol.reply(.ask)) }
                client.source.cancel()
            }
            clients = [:]
            acceptSource?.cancel()
            acceptSource = nil
            if listener >= 0 { close(listener) }
            listener = -1
            unlink(path)
        }
    }

    // MARK: - Na kolejce gniazda

    private func acceptClients() {
        while true {
            let fd = accept(listener, nil, nil)
            guard fd >= 0 else { return }
            _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
            var noSigPipe: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
            let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
            source.setEventHandler { [weak self] in self?.read(fd) }
            source.setCancelHandler { close(fd) }
            clients[fd] = Client(source: source)
            source.resume()
        }
    }

    private func read(_ fd: Int32) {
        guard var client = clients[fd] else { return }
        var chunk = [UInt8](repeating: 0, count: 64 * 1024)
        let count = Darwin.read(fd, &chunk, chunk.count)
        if count <= 0 {
            // Hook zamknął połączenie: zwykły koniec albo minął jego czas na decyzję.
            let wasWaiting = client.awaitingReply
            client.source.cancel()
            clients[fd] = nil
            if wasWaiting { onClosed(fd) }
            return
        }
        guard !client.awaitingReply else { return }
        client.buffer.append(contentsOf: chunk[0..<count])
        guard client.buffer.count <= HookProtocol.maxMessageBytes else {
            log.error("Za duża wiadomość od hooka — odrzucona")
            client.source.cancel()
            clients[fd] = nil
            return
        }
        guard let newline = client.buffer.firstIndex(of: UInt8(ascii: "\n")) else {
            clients[fd] = client
            return
        }
        let line = client.buffer[client.buffer.startIndex..<newline]
        do {
            let envelope = try HookProtocol.parse(Data(line))
            if envelope.wantsReply {
                client.awaitingReply = true
                clients[fd] = client
                onMessage(envelope, ReplyChannel(id: fd, server: self))
            } else {
                client.source.cancel()
                clients[fd] = nil
                onMessage(envelope, nil)
            }
        } catch {
            log.error("Nieczytelna wiadomość od hooka: \(String(describing: error))")
            client.source.cancel()
            clients[fd] = nil
        }
    }

    fileprivate func reply(to fd: Int32, data: Data) {
        queue.async { [self] in
            guard let client = clients[fd], client.awaitingReply else { return }
            writeAll(fd, data)
            client.source.cancel()
            clients[fd] = nil
        }
    }

    private func writeAll(_ fd: Int32, _ data: Data) {
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) & ~O_NONBLOCK)
        data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let written = write(fd, buffer.baseAddress! + offset, buffer.count - offset)
                if written <= 0 { return }
                offset += written
            }
        }
    }
}
