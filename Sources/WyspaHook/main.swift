import Foundation
import WyspaHookKit

// wyspa-hook: uruchamiany przez Claude Code dla zdarzeń hooków (bez powłoki).
//
// Zasady:
// - Wejście hooka (JSON) przychodzi na stdin; wysyłamy je do Wyspy przez gniazdo Unix.
// - Połączenie ma ~1 s. Gdy Wyspa nie działa albo nie odpowiada — natychmiastowe wyjście bez wyjścia na stdout,
//   więc Claude Code działa dokładnie tak, jakby hooka nie było.
// - Tylko PermissionRequest czeka na decyzję (najdłużej --decision-timeout sekund). Brak decyzji = prompt w terminalu.
// - Zawsze kod wyjścia 0: hook nigdy nie blokuje pracy Claude Code błędem.

let connectTimeoutMilliseconds: Int32 = 1000

signal(SIGPIPE, SIG_IGN)

func finish(_ output: String? = nil) -> Never {
    if let output { FileHandle.standardOutput.write(Data((output + "\n").utf8)) }
    exit(0)
}

let arguments = CommandLine.arguments
let decisionTimeout: Int = {
    guard let index = arguments.firstIndex(of: "--decision-timeout"), index + 1 < arguments.count,
          let value = Int(arguments[index + 1]), value > 0 else { return 300 }
    return value
}()

let input = FileHandle.standardInput.readDataToEndOfFile()
guard let event = try? JSONSerialization.jsonObject(with: input) as? [String: Any] else { finish() }
let wantsReply = event["hook_event_name"] as? String == "PermissionRequest"

let environment = ProcessInfo.processInfo.environment
var envelope: [String: Any] = [
    "v": HookProtocol.version,
    "event": event,
    // Bez powłoki rodzicem jest proces Claude Code (do wykrywania zamkniętych sesji i okna terminala).
    "claudePid": Int(getppid()),
    "wantsReply": wantsReply,
]
envelope["bundleID"] = environment["__CFBundleIdentifier"]
envelope["termProgram"] = environment["TERM_PROGRAM"]
guard var message = try? JSONSerialization.data(withJSONObject: envelope) else { finish() }
message.append(UInt8(ascii: "\n"))
guard message.count <= HookProtocol.maxMessageBytes else { finish() }

// Gniazdo musi być gniazdem należącym do bieżącego użytkownika — inaczej to nie Wyspa.
let socketPath = HookProtocol.socketURL.path
var socketInfo = stat()
guard lstat(socketPath, &socketInfo) == 0, socketInfo.st_mode & S_IFMT == S_IFSOCK, socketInfo.st_uid == getuid() else { finish() }

// Połączenie z limitem czasu (gniazdo nieblokujące + poll).
let fd = socket(AF_UNIX, SOCK_STREAM, 0)
guard fd >= 0 else { finish() }
var address = sockaddr_un()
address.sun_family = sa_family_t(AF_UNIX)
let pathBytes = Array(socketPath.utf8)
guard pathBytes.count < MemoryLayout.size(ofValue: address.sun_path) else { finish() }
withUnsafeMutableBytes(of: &address.sun_path) { buffer in
    buffer.copyBytes(from: pathBytes)
    buffer[pathBytes.count] = 0
}
_ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
let connected = withUnsafePointer(to: &address) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
}
if connected != 0 {
    guard errno == EINPROGRESS else { finish() }
    var pollDescriptor = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
    guard poll(&pollDescriptor, 1, connectTimeoutMilliseconds) == 1 else { finish() }
    var socketError: Int32 = 0
    var length = socklen_t(MemoryLayout<Int32>.size)
    getsockopt(fd, SOL_SOCKET, SO_ERROR, &socketError, &length)
    guard socketError == 0 else { finish() }
}
_ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) & ~O_NONBLOCK)
var peerUID: uid_t = 0, peerGID: gid_t = 0
guard getpeereid(fd, &peerUID, &peerGID) == 0, peerUID == getuid() else { finish() }

// Wysłanie całej wiadomości.
var sent = 0
let sendFailed = message.withUnsafeBytes { buffer -> Bool in
    while sent < buffer.count {
        let written = write(fd, buffer.baseAddress! + sent, buffer.count - sent)
        if written <= 0 { return true }
        sent += written
    }
    return false
}
guard !sendFailed, wantsReply else {
    close(fd)
    finish()
}

/// Czyta kolejne linie do `deadline`; nil = czas minął albo połączenie zamknięte.
var pending = Data()
var buffer = [UInt8](repeating: 0, count: 4096)
@MainActor
func readLine(until deadline: Date) -> Data? {
    while true {
        if let newline = pending.firstIndex(of: UInt8(ascii: "\n")) {
            let line = Data(pending[pending.startIndex..<newline])
            pending = Data(pending[pending.index(after: newline)...])
            return line
        }
        // Ograniczenie do Int32 (poll przyjmuje milisekundy jako Int32).
        let remaining = Int32(clamping: Int(max(0, deadline.timeIntervalSinceNow) * 1000))
        guard remaining > 0, pending.count <= 64 * 1024 else { return nil }
        var pollDescriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        guard poll(&pollDescriptor, 1, remaining) == 1 else { return nil }
        let count = read(fd, &buffer, buffer.count)
        guard count > 0 else { return nil }
        pending.append(contentsOf: buffer[0..<count])
    }
}

// Najpierw potwierdzenie z głównego wątku Wyspy: zawieszona aplikacja nie zablokuje terminala na pełny limit.
guard let acknowledgement = readLine(until: Date().addingTimeInterval(HookProtocol.acknowledgementTimeout)),
      (try? JSONSerialization.jsonObject(with: acknowledgement) as? [String: Any])?["ack"] as? Bool == true
else {
    close(fd)
    finish()
}

// Potem decyzja użytkownika: jedna linia JSON albo zamknięcie połączenia.
let decision = readLine(until: Date().addingTimeInterval(TimeInterval(decisionTimeout)))
close(fd)

guard let line = decision,
      let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
      let behavior = (object["behavior"] as? String).flatMap(HookProtocol.Behavior.init(rawValue:))
else { finish() }
finish(HookProtocol.hookOutput(for: behavior, message: object["message"] as? String))
