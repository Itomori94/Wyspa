import AppKit
import SwiftUI
import WyspaCore

/// Postęp pobierania w zwiniętej wyspie; po zakończeniu plik trafia na Półkę.
///
/// Bez odpytywania: przeglądarki publikują postęp pobierania (`NSProgress`), z którego korzysta też Finder.
@MainActor
@Observable
public final class DownloadsModule: IslandModule {
    public static let descriptor = ModuleDescriptor(
        id: "downloads",
        name: "Pobierania",
        summary: "Pasek postępu pobieranego pliku w zwiniętej wyspie; po zakończeniu plik ląduje na Półce.",
        symbol: "arrow.down.circle.fill",
        widgetMinWidth: 150
    )

    static let shelfZone = "shelf.store"
    private static let shelfKey = "addToShelf"
    /// Postęp ważniejszy niż odtwarzanie, mniej ważny niż timer i prośby o uwagę.
    static let priority = ActivityPriority(55)

    public private(set) var items: [DownloadItem] = []
    public var addsToShelf: Bool { didSet { context.settings.set(addsToShelf, for: Self.shelfKey) } }

    @ObservationIgnored private let context: ModuleContext
    @ObservationIgnored private var subscriber: Any?
    @ObservationIgnored private var observations: [UUID: NSKeyValueObservation] = [:]

    public required init(context: ModuleContext) {
        self.context = context
        addsToShelf = context.settings.value(Self.shelfKey, default: true)
    }

    public func activate() async throws {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        // System może wołać te bloki z dowolnego wątku — wszystko przechodzi na główny.
        subscriber = Progress.addSubscriber(forFileURL: downloads) { [weak self] progress in
            let id = UUID()
            let box = ProgressBox(progress: progress)
            Task { @MainActor in self?.track(box.progress, id: id) }
            return { [weak self] in
                Task { @MainActor in self?.finished(id) }
            }
        }
    }

    public func deactivate() {
        if let subscriber { Progress.removeSubscriber(subscriber) }
        subscriber = nil
        observations = [:]
        items = []
    }

    public var liveActivity: LiveActivity? {
        guard !items.isEmpty else { return nil }
        let fraction = DownloadSummary.fraction(of: items)
        return LiveActivity(id: "downloads", priority: Self.priority, accent: .blue, wingWidth: 52) {
            DownloadRing(fraction: fraction)
        } trailing: {
            Text(items.count > 1 ? "\(items.count) × \(DownloadSummary.percentText(fraction))" : DownloadSummary.percentText(fraction))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.85))
        }
    }

    public func makeExpandedView() -> AnyView? { AnyView(DownloadsView(module: self)) }
    public func makeWidgetView() -> AnyView? { AnyView(DownloadsView(module: self)) }
    public func makeSettingsView() -> AnyView? { AnyView(DownloadsSettingsView(module: self)) }

    // MARK: - Postęp

    private func track(_ progress: Progress, id: UUID) {
        // U subskrybenta adres i rodzaj operacji są w `userInfo` (sprawdzone na żywo); śledzimy tylko pobierania,
        // nie np. kopiowanie w Finderze.
        let operation = progress.fileOperationKind ?? (progress.userInfo[.fileOperationKindKey] as? Progress.FileOperationKind)
        guard operation == .downloading || operation == .receiving,
              let url = progress.fileURL ?? progress.userInfo[.fileURLKey] as? URL
        else { return }
        items.append(DownloadItem(id: id, fileURL: url, fraction: Self.fraction(of: progress)))
        // Aktualizacja tylko przy zmianie o pełny procent.
        observations[id] = progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            let fraction = Self.fraction(of: progress)
            Task { @MainActor in self?.update(id, fraction: fraction) }
        }
    }

    private nonisolated static func fraction(of progress: Progress) -> Double? {
        progress.totalUnitCount > 0 ? DownloadSummary.quantized(progress.fractionCompleted) : nil
    }

    private func update(_ id: UUID, fraction: Double?) {
        guard let index = items.firstIndex(where: { $0.id == id }), items[index].fraction != fraction else { return }
        let item = items[index]
        items = items.map { $0.id == id ? DownloadItem(id: id, fileURL: item.fileURL, fraction: fraction) : $0 }
    }

    /// Przeglądarka przestała publikować postęp: pobieranie się skończyło albo zostało przerwane.
    private func finished(_ id: UUID) {
        observations[id] = nil
        guard let item = items.first(where: { $0.id == id }) else { return }
        items = items.filter { $0.id != id }
        let final = DownloadNaming.finalURL(for: item.fileURL)
        // Przerwane pobieranie nie zostawia pliku docelowego.
        guard addsToShelf, FileManager.default.fileExists(atPath: final.path),
              let provider = NSItemProvider(contentsOf: final) else { return }
        _ = context.deliver([provider], Self.shelfZone)
    }

    func reveal(_ item: DownloadItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.fileURL])
    }
}

/// `Progress` jest bezpieczny wątkowo (KVO, odczyt), ale nie jest oznaczony jako Sendable.
private struct ProgressBox: @unchecked Sendable {
    let progress: Progress
}
