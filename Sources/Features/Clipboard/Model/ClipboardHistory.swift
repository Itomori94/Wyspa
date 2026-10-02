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
    /// Przypięty wpis nie wypada z historii (limit, pamięć, „Wyczyść”); usuwa się go tylko ręcznie.
    public let isPinned: Bool
    /// Klucz identyczności treści, liczony raz przy tworzeniu (porównanie wpisów nie hashuje ponownie dużych danych).
    let contentKey: Int
    /// Przybliżony rozmiar treści w bajtach (do limitu pamięci historii).
    let byteCount: Int

    public init(id: UUID = UUID(), content: Content, copiedAt: Date, sourceBundleID: String? = nil, isPinned: Bool = false) {
        self.id = id
        self.content = content
        self.copiedAt = copiedAt
        self.sourceBundleID = sourceBundleID
        self.isPinned = isPinned
        var hasher = Hasher()
        switch content {
        case .text(let text):
            hasher.combine("t"); hasher.combine(text)
            byteCount = text.utf8.count
        case .files(let urls):
            hasher.combine("f"); urls.forEach { hasher.combine($0.path) }
            byteCount = urls.map(\.path.utf8.count).reduce(0, +)
        case .image(let png, _, _):
            hasher.combine("i"); hasher.combine(png)
            byteCount = png.count
        }
        contentKey = hasher.finalize()
    }

    public static func == (lhs: ClipboardEntry, rhs: ClipboardEntry) -> Bool {
        lhs.id == rhs.id && lhs.content == rhs.content && lhs.copiedAt == rhs.copiedAt && lhs.sourceBundleID == rhs.sourceBundleID
            && lhs.isPinned == rhs.isPinned
    }

    func pinned(_ pinned: Bool) -> ClipboardEntry {
        ClipboardEntry(id: id, content: content, copiedAt: copiedAt, sourceBundleID: sourceBundleID, isPinned: pinned)
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

/// Historia schowka: przypięte na górze, potem najnowsze, bez duplikatów, z limitem. Niemutowalna.
public struct ClipboardHistory: Equatable, Sendable {
    public static let limitRange = 10...500
    public static let defaultLimit = 50
    /// Górna granica pamięci całej historii; najstarsze wpisy odpadają, gdy zostanie przekroczona.
    public static let maxTotalBytes = 64 * 1024 * 1024
    /// Pojedynczy tekst większy niż to nie trafia do historii.
    public static let maxTextBytes = 1024 * 1024
    /// Przypiętych nie obejmuje limit historii, ale ich liczba też ma granicę.
    public static let maxPinned = 50

    public let entries: [ClipboardEntry]
    public let limit: Int

    public init(entries: [ClipboardEntry] = [], limit: Int = ClipboardHistory.defaultLimit) {
        let clamped = min(max(limit, Self.limitRange.lowerBound), Self.limitRange.upperBound)
        self.limit = clamped
        let pinned = Array(entries.filter(\.isPinned).prefix(Self.maxPinned))
        var total = pinned.map(\.byteCount).reduce(0, +)
        // Najnowsze mają pierwszeństwo: po przekroczeniu limitu pamięci odcinamy najstarsze (poza przypiętymi).
        let recent = entries.filter { !$0.isPinned }.prefix(clamped).prefix { entry in
            total += entry.byteCount
            return total <= Self.maxTotalBytes
        }
        self.entries = pinned + recent
    }

    public var pinnedEntries: [ClipboardEntry] { entries.filter(\.isPinned) }

    /// Nowy wpis na górę; ponowne skopiowanie przypiętego zostawia go przypiętym (na górze przypiętych).
    public func adding(_ entry: ClipboardEntry) -> ClipboardHistory {
        let wasPinned = entries.contains { $0.contentKey == entry.contentKey && $0.isPinned }
        let rest = entries.filter { $0.contentKey != entry.contentKey }
        return ClipboardHistory(entries: [entry.pinned(wasPinned || entry.isPinned)] + rest, limit: limit)
    }

    /// Przypina albo odpina; odpięty wraca między zwykłe wpisy na miejsce wg daty skopiowania.
    public func togglingPin(_ id: UUID) -> ClipboardHistory {
        guard let entry = entries.first(where: { $0.id == id }) else { return self }
        let others = entries.filter { $0.id != id }
        if entry.isPinned {
            let unpinned = entry.pinned(false)
            let index = others.firstIndex { !$0.isPinned && $0.copiedAt < unpinned.copiedAt } ?? others.count
            var reordered = others
            reordered.insert(unpinned, at: max(index, others.filter(\.isPinned).count))
            return ClipboardHistory(entries: reordered, limit: limit)
        }
        return ClipboardHistory(entries: [entry.pinned(true)] + others, limit: limit)
    }

    public func removing(_ id: UUID) -> ClipboardHistory {
        ClipboardHistory(entries: entries.filter { $0.id != id }, limit: limit)
    }

    /// „Wyczyść”: znikają zwykłe wpisy, przypięte zostają.
    public func cleared() -> ClipboardHistory {
        ClipboardHistory(entries: pinnedEntries, limit: limit)
    }

    /// Wyłączenie modułu: pamięć zwolniona w całości (także przypięte — historia jest tylko w pamięci).
    public func clearedAll() -> ClipboardHistory {
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
    public static let autoGenerated = "org.nspasteboard.AutoGeneratedType"

    /// Hasła z menedżerów haseł, treści tymczasowe i generowane automatycznie są pomijane.
    public static func shouldIgnore(types: [String]) -> Bool {
        types.contains(concealed) || types.contains(transient) || types.contains(autoGenerated)
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

/// Wybór wpisu strzałkami w wynikach (bez zawijania). Czyste funkcje.
public enum ClipboardSelection {
    /// Pierwsze ↓ wybiera pierwszy wpis, pierwsze ↑ też (lista zaczyna się od góry).
    public static func moved(_ current: Int?, by step: Int, count: Int) -> Int? {
        guard count > 0 else { return nil }
        guard let current else { return 0 }
        return min(max(current + step, 0), count - 1)
    }

    /// Enter bez wyboru wkleja pierwszy wynik; wybór poza zakresem (lista się skróciła) — ostatni.
    public static func chosen(_ current: Int?, count: Int) -> Int? {
        guard count > 0 else { return nil }
        return min(current ?? 0, count - 1)
    }
}
