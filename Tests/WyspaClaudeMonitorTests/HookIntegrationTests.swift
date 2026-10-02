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

    private func runHook(socket: String, input: [String: Any], decisionTimeout: Int = 5,
                         arguments: [String] = []) async throws -> (output: String, seconds: Double) {
        let process = Process()
        process.executableURL = try #require(HelperLocator.helperURL)
        process.arguments = ["--decision-timeout", String(decisionTimeout)] + arguments
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

    @Test("Druga kopia nie przejmuje działającego gniazda; zatrzymanie usuwa tylko własne gniazdo")
    func singleInstance() throws {
        let path = socketPath()
        let first = HookServer(path: path, onMessage: { _, _ in }, onClosed: { _ in })
        try first.start()
        defer { first.stop() }
        let second = HookServer(path: path, onMessage: { _, _ in }, onClosed: { _ in })
        #expect(throws: HookServer.StartError.self) { try second.start() }
        second.stop()
        #expect(HookServer.isListening(path))
        first.stop()
        #expect(!FileManager.default.fileExists(atPath: path))
    }

    @Test("Linia statusu: tekst w terminalu i same limity do Wyspy (także bez Wyspy)")
    func statusLine() async throws {
        let path = socketPath()
        let received = Received()
        let server = HookServer(path: path, onMessage: { envelope, _ in received.record(envelope) }, onClosed: { _ in })
        try server.start()
        defer { server.stop() }
        let input: [String: Any] = [
            "session_id": "s1", "cwd": "/tmp/projekt", "model": ["display_name": "Opus"],
            "rate_limits": ["five_hour": ["used_percentage": 50, "resets_at": 1_738_425_600]],
        ]
        let result = try await runHook(socket: path, input: input, arguments: ["--statusline"])
        #expect(result.output == "5h 50%\n")
        try await Task.sleep(for: .milliseconds(200))
        #expect(received.events.first?.event.name == HookEvent.statusLineEvent)
        #expect(received.events.first?.event.cwd == nil, "do Wyspy idą tylko limity")
        #expect(received.events.first?.event.rateLimits?.fiveHour?.usedPercentage == 50)
        server.stop()
        let offline = try await runHook(socket: path, input: input, arguments: ["--statusline"])
        #expect(offline.output == "5h 50%\n")
    }

    @Test("Pośrednik: bez aplikacji kończy się po cichu (kod 0, bez wyjścia); z aplikacją przekazuje argumenty")
    func shim() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("wyspa-shim-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let missing = directory.appendingPathComponent("brak/wyspa-hook")
        try HookShim.install(helperPath: "/Applications/Usunięta Wyspa's.app/Contents/Helpers/wyspa-hook", at: missing)
        let silent = try runShell(missing.path, arguments: ["--statusline"], input: #"{"rate_limits":{}}"#)
        #expect(silent.status == 0 && silent.output.isEmpty)
        let mode = try FileManager.default.attributesOfItem(atPath: missing.path)[.posixPermissions] as? Int
        #expect(mode == 0o700)

        let helper = try #require(HelperLocator.helperURL)
        let working = directory.appendingPathComponent("ok/wyspa-hook")
        try HookShim.install(helperPath: helper.path, at: working)
        let input = #"{"session_id":"s","rate_limits":{"five_hour":{"used_percentage":12,"resets_at":1738425600}}}"#
        let passed = try runShell(working.path, arguments: ["--statusline"], input: input,
                                  environment: ["WYSPA_SOCKET_PATH": "/tmp/wyspa-brak-\(UUID().uuidString.prefix(6)).sock"])
        #expect(passed.status == 0 && passed.output == "5h 12%\n")
    }

    private func runShell(_ path: String, arguments: [String], input: String,
                          environment: [String: String] = [:]) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.environment = environment
        let stdin = Pipe(), stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        try process.run()
        stdin.fileHandleForWriting.write(Data(input.utf8))
        try stdin.fileHandleForWriting.close()
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: output, as: UTF8.self))
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
