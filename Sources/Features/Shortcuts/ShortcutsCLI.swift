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

    public static func list() async throws(Failure) -> [String] {
        parseList(try await run(["list"]))
    }

    public static func run(shortcut name: String) async throws(Failure) {
        _ = try await run(["run", name])
    }

    private static func run(_ arguments: [String]) async throws(Failure) -> String {
        let result: Result<String, Failure> = await Task.detached {
            let process = Process()
            let output = Pipe()
            let errors = Pipe()
            process.executableURL = executable
            process.arguments = arguments
            process.standardOutput = output
            process.standardError = errors
            do {
                try process.run()
            } catch {
                return .failure(Failure(message: "Nie można uruchomić narzędzia Skróty: \(error.localizedDescription)"))
            }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            let errorData = errors.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                let detail = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return .failure(Failure(message: detail.isEmpty ? "Skrót zakończył się błędem (\(process.terminationStatus))." : detail))
            }
            return .success(String(data: data, encoding: .utf8) ?? "")
        }.value
        return try result.get()
    }
}
