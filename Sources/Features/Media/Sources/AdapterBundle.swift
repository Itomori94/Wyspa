import Foundation
import WyspaCore

/// Pliki mediaremote-adapter wbudowane w Wyspa.app przez scripts/build-app.sh.
struct AdapterBundle: Sendable {
    static let perl = URL(fileURLWithPath: "/usr/bin/perl")

    let script: URL
    let framework: URL
    let testClient: URL

    static func locate(in bundle: Bundle = .main) -> AdapterBundle? {
        let contents = bundle.bundleURL.appendingPathComponent("Contents")
        let candidate = AdapterBundle(
            script: contents.appendingPathComponent("Resources/mediaremote-adapter/mediaremote-adapter.pl"),
            framework: contents.appendingPathComponent("Frameworks/MediaRemoteAdapter.framework"),
            testClient: contents.appendingPathComponent("Helpers/MediaRemoteAdapterTestClient")
        )
        let fileManager = FileManager.default
        let complete = [candidate.script, candidate.framework, candidate.testClient]
            .allSatisfy { fileManager.fileExists(atPath: $0.path) }
        return complete ? candidate : nil
    }

    /// Minimalne środowisko Perla: PERL5OPT/PERL5LIB z sesji nie wstrzykną kodu do procesu z dostępem do MediaRemote.
    static var environment: [String: String] {
        ["PATH": "/usr/bin:/bin", "HOME": NSHomeDirectory(), "LANG": "en_US.UTF-8"]
    }

    func arguments(_ command: [String]) -> [String] {
        [script.path, framework.path, testClient.path] + command
    }
}

/// Jednorazowe wywołania skryptu adaptera (test, send, seek) poza głównym wątkiem.
enum AdapterRunner {
    static let testTimeout: TimeInterval = 10
    static let commandTimeout: TimeInterval = 3

    struct Outcome: Sendable {
        let exitCode: Int32
        let stderr: String
        let timedOut: Bool
    }

    /// Uruchamia skrypt adaptera i czeka na zakończenie (bez odpytywania), najdłużej `timeout`.
    static func run(_ bundle: AdapterBundle, _ command: [String], timeout: TimeInterval) async -> Outcome {
        let process = Process()
        let errorPipe = Pipe()
        process.executableURL = AdapterBundle.perl
        process.arguments = bundle.arguments(command)
        process.environment = AdapterBundle.environment
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errorPipe

        let finished = ProcessCompletion()
        process.terminationHandler = { finished.resume(with: $0.terminationStatus) }
        do {
            try process.run()
        } catch {
            return Outcome(exitCode: -1, stderr: error.localizedDescription, timedOut: false)
        }

        let watchdog = Task.detached {
            try? await Task.sleep(for: .seconds(timeout))
            guard !Task.isCancelled, process.isRunning else { return }
            finished.markTimedOut()
            process.terminate()
        }
        let status = await finished.value
        watchdog.cancel()
        let errorText = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return Outcome(exitCode: status, stderr: errorText, timedOut: finished.timedOut)
    }

    /// Kończy strumienie adaptera osierocone po awarii poprzedniej instancji (rodzic = launchd, PID 1).
    static func terminateOrphans(of bundle: AdapterBundle) async {
        let pkill = Process()
        pkill.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        // Ścieżka jako dosłowny tekst we wzorcu ERE (znaki jak „.”, „+”, „(” w ścieżce nie dopasują za dużo).
        let script = NSRegularExpression.escapedPattern(for: bundle.script.path)
        pkill.arguments = ["-P", "1", "-f", "^/usr/bin/perl \(script) .* stream"]
        pkill.standardOutput = FileHandle.nullDevice
        pkill.standardError = FileHandle.nullDevice
        let finished = ProcessCompletion()
        pkill.terminationHandler = { finished.resume(with: $0.terminationStatus) }
        do {
            try pkill.run()
            _ = await finished.value
        } catch {
            // Brak sprzątania nie blokuje startu: sierota zakończy się przy następnym zapisie do zamkniętego potoku.
        }
    }

    /// Wbudowany test adaptera: kod 0 oznacza, że MediaRemote jest dostępny przez /usr/bin/perl.
    static func health(of bundle: AdapterBundle?) async -> AdapterHealth {
        guard let bundle else { return .broken(reason: "brak plików adaptera w pakiecie aplikacji") }
        let outcome = await run(bundle, ["test"], timeout: testTimeout)
        if outcome.timedOut { return .broken(reason: "test adaptera przekroczył czas \(Int(testTimeout)) s") }
        guard outcome.exitCode == 0 else {
            let detail = outcome.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return .broken(reason: "test adaptera zakończył się kodem \(outcome.exitCode)" + (detail.isEmpty ? "" : " (\(detail))"))
        }
        return .functional
    }
}

/// Jednorazowe oczekiwanie na zakończenie procesu; bezpieczne dla wywołań z dowolnego wątku.
private final class ProcessCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var status: Int32?
    private var continuation: CheckedContinuation<Int32, Never>?
    private var didTimeOut = false

    var timedOut: Bool { lock.withLock { didTimeOut } }

    var value: Int32 {
        get async {
            await withCheckedContinuation { continuation in
                let ready: Int32? = lock.withLock {
                    if let status { return status }
                    self.continuation = continuation
                    return nil
                }
                if let ready { continuation.resume(returning: ready) }
            }
        }
    }

    func markTimedOut() {
        lock.withLock { didTimeOut = true }
    }

    func resume(with status: Int32) {
        let waiting: CheckedContinuation<Int32, Never>? = lock.withLock {
            guard self.status == nil else { return nil }
            self.status = status
            defer { continuation = nil }
            return continuation
        }
        waiting?.resume(returning: status)
    }
}
