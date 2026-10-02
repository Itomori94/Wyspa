import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WyspaCore

/// Półka: tymczasowe miejsce na pliki, z podglądem, zaznaczaniem wielu elementów i AirDrop.
@MainActor
@Observable
public final class ShelfModule: IslandModule, IslandDropHandling {
    public static let descriptor = ModuleDescriptor(
        id: "shelf",
        name: "Półka",
        summary: "Przeciągnij plik nad notch, odłóż go na później i wyciągnij, kiedy będzie potrzebny. Z podglądem i AirDrop.",
        symbol: "tray.full",
        content: .personal,
        widgetMinWidth: 110
    )
    public static let acceptedDropTypes: [UTType] = [.fileURL, .image, .url, .plainText, .data]

    enum Zone {
        static let store = "shelf.store"
        static let airDrop = "shelf.airdrop"
    }

    public private(set) var items: [ShelfItem] = []
    /// Adresy elementów rozwiązywane raz po każdej zmianie półki (nie przy każdym przerysowaniu kafelka).
    public private(set) var resolvedURLs: [UUID: URL] = [:]
    public private(set) var selection = ShelfSelection()
    public private(set) var problem: String?

    @ObservationIgnored private var store: ShelfStore?
    @ObservationIgnored private let directory: URL
    @ObservationIgnored private let log = Log.logger("shelf")

    public required init(context: ModuleContext) {
        directory = ShelfStore.defaultDirectory
    }

    public func activate() async throws {
        let store = try ShelfStore(directory: directory)
        self.store = store
        setItems(store.items)
        Self.removeStaleTemporaryFiles()
    }

    private func setItems(_ newItems: [ShelfItem]) {
        items = newItems
        guard let store else {
            resolvedURLs = [:]
            return
        }
        resolvedURLs = Dictionary(uniqueKeysWithValues: newItems.compactMap { item in store.url(for: item).map { (item.id, $0) } })
    }

    /// Pliki tymczasowe Wyspy (AirDrop, obietnice plików) starsze niż godzina.
    private static func removeStaleTemporaryFiles() {
        let fileManager = FileManager.default
        let temporary = fileManager.temporaryDirectory
        let cutoff = Date().addingTimeInterval(-3600)
        let names = (try? fileManager.contentsOfDirectory(atPath: temporary.path)) ?? []
        for name in names where name.hasPrefix("Wyspa-") {
            let url = temporary.appendingPathComponent(name)
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantFuture
            if modified < cutoff { try? fileManager.removeItem(at: url) }
        }
    }

    /// Wyłączenie zwalnia pamięć; zawartość półki zostaje na dysku na następne włączenie.
    public func deactivate() {
        store = nil
        items = []
        resolvedURLs = [:]
        selection.clear()
    }

    public var liveActivity: LiveActivity? { nil }

    public func makeExpandedView() -> AnyView? {
        AnyView(ShelfExpandedView(module: self))
    }

    public func makeWidgetView() -> AnyView? {
        AnyView(ShelfWidget(module: self))
    }

    public func performDrop(_ providers: [NSItemProvider], zoneID: String?) -> Bool {
        Task {
            let ingested = await DropIngest.load(providers)
            guard !ingested.isEmpty else {
                problem = "Nie udało się odczytać upuszczonych elementów."
                return
            }
            zoneID == Zone.airDrop ? sendViaAirDrop(ingested) : add(ingested)
        }
        return true
    }

    // MARK: - Akcje

    func url(for item: ShelfItem) -> URL? { resolvedURLs[item.id] }

    func click(_ id: UUID, modifier: ShelfSelection.Modifier) {
        var next = selection
        next.click(id, modifier: modifier, order: items.map(\.id))
        selection = next
    }

    func selectAll() {
        var next = selection
        next.selectAll(items.map(\.id))
        selection = next
    }

    func clearSelection() {
        selection = ShelfSelection()
    }

    /// Adresy do przeciągnięcia: całe zaznaczenie, jeśli chwycony element do niego należy.
    func dragURLs(grabbing id: UUID) -> [URL] {
        urls(for: selection.dragSet(grabbing: id))
    }

    var selectedURLs: [URL] { urls(for: selection.selected) }

    private func urls(for ids: Set<UUID>) -> [URL] {
        items.filter { ids.contains($0.id) }.compactMap { resolvedURLs[$0.id] }
    }

    func open(_ id: UUID) {
        guard let item = items.first(where: { $0.id == id }), let url = url(for: item) else {
            problem = "Oryginał tego elementu został usunięty albo przeniesiony poza dysk."
            return
        }
        NSWorkspace.shared.open(url)
    }

    func quickLook(grabbing id: UUID? = nil) {
        let urls = id.map(dragURLs(grabbing:)) ?? selectedURLs
        QuickLook.shared.show(urls.isEmpty ? self.urls(for: Set(items.map(\.id))) : urls)
    }

    func airDropSelection() {
        if !AirDrop.send(selectedURLs) { problem = "AirDrop jest niedostępny. Sprawdź Wi‑Fi i Bluetooth." }
    }

    func revealInFinder(_ id: UUID) {
        let urls = dragURLs(grabbing: id)
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    func remove(_ ids: Set<UUID>) {
        mutate { try $0.remove(ids) }
    }

    func removeAll() {
        mutate { try $0.removeAll() }
    }

    func dismissProblem() {
        problem = nil
    }

    // MARK: - Wewnętrzne

    private func add(_ ingested: [IngestedItem]) {
        // Pliki tymczasowe znikają zawsze, także gdy zapis na półkę się nie uda.
        defer {
            for case .temporaryFile(let url, _) in ingested { try? FileManager.default.removeItem(at: url) }
        }
        mutate { store in
            let files = ingested.compactMap { item -> URL? in
                if case .file(let url) = item { return url }
                return nil
            }
            try store.addFiles(files)
            for item in ingested {
                switch item {
                case .file: continue
                case .data(let data, let name): try store.addData(data, suggestedName: name)
                case .temporaryFile(let url, let name):
                    try store.addCopy(of: url, suggestedName: name)
                }
            }
        }
    }

    /// AirDrop bez odkładania na półkę: treści bez pliku trafiają do katalogu tymczasowego.
    private func sendViaAirDrop(_ ingested: [IngestedItem]) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Wyspa-AirDrop-\(UUID().uuidString)")
        let urls = ingested.compactMap { item -> URL? in
            switch item {
            case .file(let url): return url
            case .temporaryFile(let url, _): return url
            case .data(let data, let name):
                let target = folder.appendingPathComponent(ShelfStore.sanitizedFileName(name))
                do {
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    try data.write(to: target)
                    return target
                } catch {
                    log.error("Nie udało się przygotować pliku do AirDrop: \(error.localizedDescription)")
                    return nil
                }
            }
        }
        if !AirDrop.send(urls) { problem = "AirDrop jest niedostępny. Sprawdź Wi‑Fi i Bluetooth." }
    }

    private func mutate(_ change: (ShelfStore) throws -> Void) {
        guard let store else { return }
        do {
            try change(store)
            problem = nil
        } catch {
            log.error("Zmiana półki nie powiodła się: \(error.localizedDescription)")
            problem = error.localizedDescription
        }
        setItems(store.items)
        var next = selection
        next.retain(items.map(\.id))
        selection = next
    }
}
