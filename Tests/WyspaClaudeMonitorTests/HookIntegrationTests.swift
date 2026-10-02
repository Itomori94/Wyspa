import Foundation
import Testing
@testable import WyspaClaudeMonitor
@testable import WyspaHookKit

/// Prawdziwy `wyspa-hook` przeciwko prawdziwemu serwerowi Wyspy (gniazdo tymczasowe).
/// Wymaga zbudowanego helpera (`scripts/test.sh` robi to przed testami).
enum HelperLocator {
    static let helperURL: URL? = {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return [".build/debug/wyspa-hook", ".build/out/Products/Debug/wyspa-hook", ".build/arm64-apple-macosx/debug/wyspa-hook"]
            .map { root.appendingPathComponent($0) }
            .filter { FileManager.default.isExecutableFile(atPath: $0.path) }
            .max { lhs, rhs in
                let l = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let r = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return l < r
            }
    }()
}

@Suite("Hook ↔ Wyspa (integracja)", .serialized, .enabled(if: HelperLocator.helperURL != nil))
struct HookIntegrationTests {

    /// Krótka ścieżka: sun_path ma limit 104 bajtów.
    private func socketPath() -> String { "/tmp/wyspa-test-\(UUID().uuidString.prefix(8)).sock" }

    private func runHook(socket: String, input: [String: Any], decisionTimeout: Int = 5) async throws -> (output: String, seconds: Double) {
        let process = Process()
        process.executableURL = try #require(HelperLocator.helperURL)
        process.arguments = ["--decision-timeout", String(decisionTimeout)]
        process.environment = ["WYSPA_SOCKET_PATH": socket, "__CFBundleIdentifier": "com.apple.Terminal"]
        let stdin = Pipe(), stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        let started = Date()
        // terminationHandler zamiast waitUntilExit: to drugie potrafi przegapić koniec procesu poza głównym wątkiem.
        let status = await withCheckedContinuation { (continuation: CheckedContinuation<Int32, Never>) in
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do {
                try process.run()
                stdin.fileHandleForWriting.write(try JSONSerialization.data(withJSONObject: input))
                try stdin.fileHandleForWriting.close()
            } catch {
                continuation.resume(returning: -1)
            }
        }
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        #expect(status == 0)
        return (String(data: output, encoding: .utf8) ?? "", Date().timeIntervalSince(started))
    }

    let permission: [String: Any] = [
        "hook_event_name": "PermissionRequest", "session_id": "s1", "cwd": "/tmp/projekt",
        "tool_name": "Bash", "tool_input": ["command": "echo test"],
    ]

    @Test("Zatwierdzenie w wyspie daje decyzję allow dla Claude Code")
    func allowFromIsland() async throws {
        let path = socketPath()
        let received = Received()
        let server = HookServer(path: path, onMessage: { envelope, channel in
            received.record(envelope)
            channel?.acknowledge()
            channel?.send(.allow)
        }, onClosed: { _ in })
        try server.start()
        defer { server.stop() }

        let result = try await runHook(socket: path, input: permission)
        let object = try JSONSerialization.jsonObject(with: Data(result.output.utf8)) as? [String: Any]
        let decision = (object?["hookSpecificOutput"] as? [String: Any])?["decision"] as? [String: Any]
        #expect(decision?["behavior"] as? String == "allow")
        #expect(received.events.first?.event.toolInput?.command == "echo test")
        #expect(received.events.first?.bundleID == "com.apple.Terminal")
    }

    @Test("Zawieszona Wyspa (brak potwierdzenia): hook wraca do terminala po ~2 s, nie po pełnym limicie")
    func hungApp() async throws {
        let path = socketPath()
        let server = HookServer(path: path, onMessage: { _, _ in }, onClosed: { _ in })
        try server.start()
        defer { server.stop() }
        let result = try await runHook(socket: path, input: permission, decisionTimeout: 60)
        #expect(result.output.isEmpty)
        #expect(result.seconds < 4)
    }

    @Test("Gniazdo 0600, istniejący katalog gniazda z 0755 dostaje 0700 przy starcie serwera")
    func tightensDirectory() throws {
        let directory = "/tmp/wyspa-dir-\(UUID().uuidString.prefix(8))"
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o755])
        defer { try? FileManager.default.removeItem(atPath: directory) }
        let server = HookServer(path: directory + "/s.sock", onMessage: { _, _ in }, onClosed: { _ in })
        try server.start()
        defer { server.stop() }
        let permissions = try FileManager.default.attributesOfItem(atPath: directory)[.posixPermissions] as? Int
        #expect(permissions == 0o700)
        let socketMode = try FileManager.default.attributesOfItem(atPath: directory + "/s.sock")[.posixPermissions] as? Int
        #expect(socketMode == 0o600)
    }

    @Test("Odmowa z wyspy przekazuje powód do Claude Code")
    func denyFromIsland() async throws {
        let path = socketPath()
        let server = HookServer(path: path, onMessage: { _, channel in
            channel?.acknowledge()
            channel?.send(.deny, message: "Nie teraz")
        }, onClosed: { _ in })
        try server.start()
        defer { server.stop() }
        let result = try await runHook(socket: path, input: permission)
        #expect(result.output.contains(#""behavior":"deny""#) && result.output.contains("Nie teraz"))
    }

    @Test("Zdarzenie bez decyzji: hook nie czeka i nic nie wypisuje")
    func fireAndForget() async throws {
        let path = socketPath()
        let received = Received()
        let server = HookServer(path: path, onMessage: { envelope, _ in received.record(envelope) }, onClosed: { _ in })
        try server.start()
        defer { server.stop() }
        let result = try await runHook(socket: path, input: ["hook_event_name": "PreToolUse", "session_id": "s1", "tool_name": "Read"])
        #expect(result.output.isEmpty)
        try await Task.sleep(for: .milliseconds(100))
        #expect(received.events.map(\.event.name) == ["PreToolUse"])
    }

    @Test("Wyspa nie działa: hook kończy się szybko, bez wyjścia")
    func appNotRunning() async throws {
        let result = try await runHook(socket: socketPath(), input: permission)
        #expect(result.output.isEmpty)
        #expect(result.seconds < 1.5)
    }

    @Test("Brak decyzji w czasie: hook oddaje terminalowi, Wyspa dostaje sygnał zamknięcia")
    func decisionTimeout() async throws {
        let path = socketPath()
        let closed = Received()
        let server = HookServer(path: path, onMessage: { _, channel in channel?.acknowledge() },
                                onClosed: { _ in closed.markClosed() })
        try server.start()
        defer { server.stop() }
        let result = try await runHook(socket: path, input: permission, decisionTimeout: 1)
        #expect(result.output.isEmpty)
        try await Task.sleep(for: .milliseconds(200))
        #expect(closed.wasClosed)
    }

    @Test("Zatrzymanie Wyspy w trakcie oczekiwania: od razu prompt w terminalu")
    func stopWhileWaiting() async throws {
        let path = socketPath()
        let server = HookServer(path: path, onMessage: { _, channel in channel?.acknowledge() }, onClosed: { _ in })
        try server.start()
        Task.detached {
            try? await Task.sleep(for: .milliseconds(400))
            server.stop()
        }
        let result = try await runHook(socket: path, input: permission, decisionTimeout: 30)
        #expect(result.output.isEmpty)
        #expect(result.seconds < 5)
    }
}

/// Zbieranie zdarzeń z kolejki gniazda w testach.
final class Received: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [HookProtocol.Envelope] = []
    private var closed = false

    func record(_ envelope: HookProtocol.Envelope) { lock.withLock { stored.append(envelope) } }
    func markClosed() { lock.withLock { closed = true } }
    var events: [HookProtocol.Envelope] { lock.withLock { stored } }
    var wasClosed: Bool { lock.withLock { closed } }
}
