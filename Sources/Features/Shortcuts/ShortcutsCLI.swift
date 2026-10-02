import Foundation

/// Systemowe narzędzie `shortcuts` (macOS 12+). Nazwy skrótów przekazujemy jako argumenty procesu, bez powłoki.
public enum ShortcutsCLI {
    static let executable = URL(fileURLWithPath: "/usr/bin/shortcuts")

    public struct Failure: Error, Equatable, LocalizedError {
        public let message: String
        public var errorDescription: String? { message }
    }

    /// Wyjście `shortcuts list`: jedna nazwa w wierszu.
    public static func parseList(_ output: String) -> [String] {
        var seen = Set<String>()
        return output
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// Lista skrótów nie powinna trwać dłużej (np. zaraz po zalogowaniu).
    static let listTimeout: TimeInterval = 15
    /// Skrót może pracować długo (pobieranie, przetwarzanie), ale nie bez końca.
    static let runTimeout: TimeInterval = 600

    public static func list() async throws(Failure) -> [String] {
        parseList(try await run(["list"], timeout: listTimeout))
    }

    public static func run(shortcut name: String) async throws(Failure) {
        // Nazwa zaczynająca się od „-” zostałaby potraktowana jak opcja narzędzia.
        guard !name.hasPrefix("-") else { throw Failure(message: "Nazwy skrótu zaczynającej się od „-” nie da się bezpiecznie uruchomić.") }
        _ = try await run(["run", name], timeout: runTimeout)
    }

    /// Uruchamia narzędzie bez powłoki. Oba potoki są czytane równolegle (duży stderr nie zakleszczy procesu),
    /// koniec procesu przez `terminationHandler`, a po limicie czasu proces jest kończony.
    private static func run(_ arguments: [String], timeout: TimeInterval) async throws(Failure) -> String {
        let process = Process()
        let output = Pipe(), errors = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = errors
        let collected = Collected()
        output.fileHandleForReading.readabilityHandler = { collected.appendOutput($0.availableData) }
        errors.fileHandleForReading.readabilityHandler = { collected.appendError($0.availableData) }

        let box = ProcessBox(process: process)
        let status: Int32 = await withCheckedContinuation { continuation in
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(returning: -1)
                return
            }
            // Strażnik: po limicie czasu kończy proces (terminationHandler zgłosi wtedy kod zakończenia).
            Task.detached {
                try? await Task.sleep(for: .seconds(timeout))
                if box.process.isRunning { box.process.terminate() }
            }
        }
        output.fileHandleForReading.readabilityHandler = nil
        errors.fileHandleForReading.readabilityHandler = nil
        collected.appendOutput(output.fileHandleForReading.readDataToEndOfFile())
        collected.appendError(errors.fileHandleForReading.readDataToEndOfFile())

        guard status == 0 else {
            if status == -1 { throw Failure(message: "Nie można uruchomić narzędzia Skróty.") }
            let detail = collected.errorText.trimmingCharacters(in: .whitespacesAndNewlines)
            throw Failure(message: detail.isEmpty ? "Skrót zakończył się błędem (\(status))." : detail)
        }
        return collected.outputText
    }
}

/// Process nie jest Sendable; `isRunning` i `terminate()` są bezpieczne z innego wątku.
private struct ProcessBox: @unchecked Sendable {
    let process: Process
}

/// Bufory wyjścia procesu zapisywane z wątków potoków.
private final class Collected: @unchecked Sendable {
    private let lock = NSLock()
    private var output = Data()
    private var error = Data()

    func appendOutput(_ data: Data) { lock.withLock { output.append(data) } }
    func appendError(_ data: Data) { lock.withLock { error.append(data) } }
    var outputText: String { lock.withLock { String(data: output, encoding: .utf8) ?? "" } }
    var errorText: String { lock.withLock { String(data: error, encoding: .utf8) ?? "" } }
}
