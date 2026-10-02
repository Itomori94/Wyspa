import Foundation
import WyspaCore

public enum ShelfStoreError: LocalizedError, Equatable {
    case cannotCreateDirectory(String)
    case cannotSave(String)
    case cannotStore(String)

    public var errorDescription: String? {
        switch self {
        case .cannotCreateDirectory(let detail): "Nie można utworzyć katalogu półki: \(detail)"
        case .cannotSave(let detail): "Nie można zapisać półki: \(detail)"
        case .cannotStore(let detail): "Nie można zachować elementu: \(detail)"
        }
    }
}

/// Trwały magazyn półki: lista w `shelf.json`, kopie treści w `Items/<uuid>/`.
///
/// Każda zmiana zapisuje się od razu, więc półka przetrwa restart i awarię aplikacji.
@MainActor
public final class ShelfStore {
    static let indexFileName = "shelf.json"
    static let itemsDirectoryName = "Items"

    public private(set) var items: [ShelfItem]
    public let directory: URL
    private let fileManager: FileManager
    private let now: () -> Date
    private let log = Log.logger("shelf.store")

    public static var defaultDirectory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Wyspa/Shelf", isDirectory: true)
    }

    public init(directory: URL, fileManager: FileManager = .default, now: @escaping () -> Date = Date.init) throws(ShelfStoreError) {
        self.directory = directory
        self.fileManager = fileManager
        self.now = now
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw .cannotCreateDirectory(error.localizedDescription)
        }
        items = Self.loadIndex(from: directory.appendingPathComponent(Self.indexFileName))
        removeOrphanedCopies()
    }

    /// Katalog kopii elementu — wyliczany wyłącznie z jego identyfikatora, nigdy ze ścieżki z indeksu.
    func copyFolder(for id: UUID) -> URL {
        directory.appendingPathComponent(Self.itemsDirectoryName, isDirectory: true).appendingPathComponent(id.uuidString, isDirectory: true)
    }

    /// Ścieżka kopii z indeksu jest ważna tylko jako `Items/<id elementu>/<nazwa pliku>` (bez `..` i podkatalogów).
    func storedURL(for item: ShelfItem, relativePath: String) -> URL? {
        let parts = relativePath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3, parts[0] == Self.itemsDirectoryName, parts[1] == item.id.uuidString,
              !parts[2].isEmpty, parts[2] != ".", parts[2] != ".."
        else { return nil }
        return copyFolder(for: item.id).appendingPathComponent(parts[2])
    }

    /// Kopie bez wpisu w indeksie (np. po awarii zapisu) — tylko katalogi o nazwie UUID w `Items/`.
    private func removeOrphanedCopies() {
        let itemsDirectory = directory.appendingPathComponent(Self.itemsDirectoryName, isDirectory: true)
        let known = Set(items.map(\.id.uuidString))
        let folders = (try? fileManager.contentsOfDirectory(atPath: itemsDirectory.path)) ?? []
        for name in folders where UUID(uuidString: name) != nil && !known.contains(name) {
            try? fileManager.removeItem(at: itemsDirectory.appendingPathComponent(name, isDirectory: true))
        }
    }

    // MARK: - Odczyt

    /// Aktualne położenie elementu; nil, gdy oryginał zniknął.
    public func url(for item: ShelfItem) -> URL? {
        switch item.source {
        case .stored(let relativePath):
            guard let url = storedURL(for: item, relativePath: relativePath) else { return nil }
            return fileManager.fileExists(atPath: url.path) ? url : nil
        case .reference(let bookmark, _):
            var isStale = false
            // Bez montowania woluminów: odłączony dysk sieciowy nie zawiesza półki.
            guard let url = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting], bookmarkDataIsStale: &isStale),
                  fileManager.fileExists(atPath: url.path)
            else { return nil }
            if isStale { refreshBookmark(of: item, at: url) }
            return url
        }
    }

    public func urls(for ids: Set<UUID>) -> [URL] {
        items.filter { ids.contains($0.id) }.compactMap(url(for:))
    }

    // MARK: - Zmiany

    /// Dodaje pliki z dysku jako odnośniki; pliki już obecne na półce są pomijane.
    @discardableResult
    public func addFiles(_ urls: [URL]) throws(ShelfStoreError) -> [ShelfItem] {
        let existing = Set(items.compactMap { item -> String? in
            if case .reference(_, let path) = item.source { return path }
            return nil
        })
        var seen = existing
        let added = urls.compactMap { url -> ShelfItem? in
            let path = url.standardizedFileURL.path
            guard seen.insert(path).inserted else { return nil }
            guard let bookmark = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) else {
                log.error("Nie udało się utworzyć bookmarka dla \(path, privacy: .private)")
                return nil
            }
            return ShelfItem(name: url.lastPathComponent, source: .reference(bookmark: bookmark, lastKnownPath: path), addedAt: now())
        }
        try commit(items + added)
        return added
    }

    /// Zachowuje treść bez pliku (np. obraz z przeglądarki) jako kopię w katalogu półki.
    @discardableResult
    public func addData(_ data: Data, suggestedName: String) throws(ShelfStoreError) -> ShelfItem {
        let id = UUID()
        let name = Self.sanitizedFileName(suggestedName)
        let relative = "\(Self.itemsDirectoryName)/\(id.uuidString)/\(name)"
        let target = directory.appendingPathComponent(relative)
        do {
            try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: target, options: .atomic)
        } catch {
            throw .cannotStore(error.localizedDescription)
        }
        let item = ShelfItem(id: id, name: name, source: .stored(relativePath: relative), addedAt: now())
        try commit(items + [item])
        return item
    }

    /// Kopiuje plik tymczasowy (np. spełnioną obietnicę pliku) do katalogu półki.
    @discardableResult
    public func addCopy(of temporaryURL: URL, suggestedName: String? = nil) throws(ShelfStoreError) -> ShelfItem {
        let id = UUID()
        let name = Self.sanitizedFileName(suggestedName ?? temporaryURL.lastPathComponent)
        let relative = "\(Self.itemsDirectoryName)/\(id.uuidString)/\(name)"
        let target = directory.appendingPathComponent(relative)
        do {
            try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileManager.copyItem(at: temporaryURL, to: target)
        } catch {
            throw .cannotStore(error.localizedDescription)
        }
        let item = ShelfItem(id: id, name: name, source: .stored(relativePath: relative), addedAt: now())
        try commit(items + [item])
        return item
    }

    /// Usuwa elementy; kopie w katalogu półki są kasowane, oryginały użytkownika nietknięte.
    public func remove(_ ids: Set<UUID>) throws(ShelfStoreError) {
        let removed = items.filter { ids.contains($0.id) }
        try commit(items.filter { !ids.contains($0.id) })
        removed.forEach(deleteStoredCopy)
    }

    public func removeAll() throws(ShelfStoreError) {
        try remove(Set(items.map(\.id)))
    }

    // MARK: - Wewnętrzne

    private func commit(_ newItems: [ShelfItem]) throws(ShelfStoreError) {
        do {
            let data = try JSONEncoder().encode(newItems)
            try data.write(to: directory.appendingPathComponent(Self.indexFileName), options: .atomic)
        } catch {
            throw .cannotSave(error.localizedDescription)
        }
        items = newItems
    }

    private func refreshBookmark(of item: ShelfItem, at url: URL) {
        guard let bookmark = try? url.bookmarkData() else { return }
        let refreshed = ShelfItem(
            id: item.id, name: item.name,
            source: .reference(bookmark: bookmark, lastKnownPath: url.path), addedAt: item.addedAt
        )
        try? commit(items.map { $0.id == item.id ? refreshed : $0 })
    }

    private func deleteStoredCopy(_ item: ShelfItem) {
        guard case .stored = item.source else { return }
        let folder = copyFolder(for: item.id)
        do {
            try fileManager.removeItem(at: folder)
        } catch {
            log.error("Nie udało się usunąć kopii elementu: \(error.localizedDescription)")
        }
    }

    private static func loadIndex(from url: URL) -> [ShelfItem] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        do {
            return try JSONDecoder().decode([ShelfItem].self, from: data)
        } catch {
            Log.logger("shelf.store").error("Uszkodzony indeks półki, zaczynam od pustej: \(error.localizedDescription)")
            return []
        }
    }

    /// Nazwa pliku bez separatorów ścieżki i znaków sterujących; pusta → „Element”.
    static func sanitizedFileName(_ name: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/:\\").union(.controlCharacters)
        let cleaned = name.components(separatedBy: forbidden).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutDots = cleaned.drop { $0 == "." }
        return withoutDots.isEmpty ? "Element" : String(withoutDots.prefix(200))
    }
}
