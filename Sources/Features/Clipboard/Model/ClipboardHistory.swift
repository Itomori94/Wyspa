import Foundation

public struct ClipboardEntry: Equatable, Identifiable, Sendable {
    public enum Content: Equatable, Sendable {
        case text(String)
        case files([URL])
        case image(png: Data, width: Int, height: Int)
    }

    public let id: UUID
    public let content: Content
    public let copiedAt: Date
    public let sourceBundleID: String?

    public init(id: UUID = UUID(), content: Content, copiedAt: Date, sourceBundleID: String? = nil) {
        self.id = id
        self.content = content
        self.copiedAt = copiedAt
        self.sourceBundleID = sourceBundleID
    }

    /// Klucz identyczności treści: ten sam tekst skopiowany ponownie przesuwa wpis na górę zamiast go dublować.
    var contentKey: String {
        switch content {
        case .text(let text): "t:" + text
        case .files(let urls): "f:" + urls.map(\.path).joined(separator: "\n")
        case .image(let png, _, _): "i:\(png.count):\(png.hashValue)"
        }
    }

    /// Tekst do wyszukiwania i podglądu.
    public var searchableText: String {
        switch content {
        case .text(let text): text
        case .files(let urls): urls.map(\.lastPathComponent).joined(separator: ", ")
        case .image(_, let width, let height): "Obraz \(width)×\(height)"
        }
    }
}

/// Historia schowka: najnowsze na górze, bez duplikatów, z limitem. Niemutowalna.
public struct ClipboardHistory: Equatable, Sendable {
    public static let limitRange = 10...500
    public static let defaultLimit = 50

    public let entries: [ClipboardEntry]
    public let limit: Int

    public init(entries: [ClipboardEntry] = [], limit: Int = ClipboardHistory.defaultLimit) {
        let clamped = min(max(limit, Self.limitRange.lowerBound), Self.limitRange.upperBound)
        self.limit = clamped
        self.entries = Array(entries.prefix(clamped))
    }

    public func adding(_ entry: ClipboardEntry) -> ClipboardHistory {
        let rest = entries.filter { $0.contentKey != entry.contentKey }
        return ClipboardHistory(entries: [entry] + rest, limit: limit)
    }

    public func removing(_ id: UUID) -> ClipboardHistory {
        ClipboardHistory(entries: entries.filter { $0.id != id }, limit: limit)
    }

    public func cleared() -> ClipboardHistory {
        ClipboardHistory(limit: limit)
    }

    public func withLimit(_ newLimit: Int) -> ClipboardHistory {
        ClipboardHistory(entries: entries, limit: newLimit)
    }

    /// Wyszukiwanie bez rozróżniania wielkości liter i polskich znaków („zolw” znajdzie „żółw”).
    public func matching(_ query: String) -> [ClipboardEntry] {
        let needle = SearchNormalizer.normalize(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !needle.isEmpty else { return entries }
        return entries.filter { SearchNormalizer.normalize($0.searchableText).contains(needle) }
    }
}

/// Typy oznaczające treść, której nie wolno zapisywać w historii (konwencja nspasteboard.org).
public enum PasteboardPrivacy {
    public static let concealed = "org.nspasteboard.ConcealedType"
    public static let transient = "org.nspasteboard.TransientType"

    /// Hasła z menedżerów haseł i treści tymczasowe są pomijane.
    public static func shouldIgnore(types: [String]) -> Bool {
        types.contains(concealed) || types.contains(transient)
    }
}

enum SearchNormalizer {
    /// Małe litery bez znaków diakrytycznych. „ł” to w Unicode osobna litera (nie „l” + znak),
    /// więc `diacriticInsensitive` jej nie zamienia — robimy to jawnie.
    static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "pl_PL"))
            .replacingOccurrences(of: "ł", with: "l")
    }
}
