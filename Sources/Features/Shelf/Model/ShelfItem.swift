import Foundation

/// Element półki: odnośnik do pliku użytkownika albo kopia treści bez pliku (obraz z przeglądarki, link, tekst).
public struct ShelfItem: Codable, Equatable, Identifiable, Sendable {
    public enum Source: Codable, Equatable, Sendable {
        /// Plik z dysku: bookmark śledzi przeniesienia i zmiany nazwy oryginału.
        case reference(bookmark: Data, lastKnownPath: String)
        /// Kopia w katalogu półki (ścieżka względna wobec katalogu magazynu).
        case stored(relativePath: String)
    }

    public let id: UUID
    public let name: String
    public let source: Source
    public let addedAt: Date

    public init(id: UUID = UUID(), name: String, source: Source, addedAt: Date) {
        self.id = id
        self.name = name
        self.source = source
        self.addedAt = addedAt
    }

    public var isStoredCopy: Bool {
        if case .stored = source { return true }
        return false
    }
}
