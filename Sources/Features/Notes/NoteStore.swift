import Foundation
import WyspaCore

/// Szybka notatka w jednym pliku tekstowym; zapis atomowy.
public struct NoteStore: Sendable {
    public let fileURL: URL

    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Wyspa/Notes/notatka.md")
    }

    public init(fileURL: URL = NoteStore.defaultURL) {
        self.fileURL = fileURL
    }

    /// Brak pliku = pusta notatka; nieczytelny plik zgłasza błąd zamiast cicho zwracać pustą (żeby go nie nadpisać).
    public func load() throws -> String {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return "" }
        return try String(contentsOf: fileURL, encoding: .utf8)
    }

    public func save(_ text: String) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: fileURL, options: .atomic)
    }
}
