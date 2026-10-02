import AppKit
import WyspaCore

/// Utrzymuje po jednej wyspie na każdym wybranym ekranie i reaguje na zmiany konfiguracji w locie.
@MainActor
final class ScreenCoordinator {
    private let settings: SettingsStore
    private let registry: ModuleRegistry
    private let openSettings: () -> Void
    private var islands: [UInt32: IslandWindowController] = [:]
    private var screenObserver: NSObjectProtocol?
    private let log = Log.logger("screens")

    init(settings: SettingsStore, registry: ModuleRegistry, openSettings: @escaping () -> Void) {
        self.settings = settings
        self.registry = registry
        self.openSettings = openSettings
    }

    func start() {
        rebuild()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuild() }
        }
        observeChanges({ [weak self] in
            guard let settings = self?.settings else { return }
            _ = settings.screenSelection
            _ = settings.virtualNotchMode
            _ = settings.islandSize
            _ = settings.islandMaterial
        }) { [weak self] in self?.rebuild() }
    }

    func toggleUnderPointer() {
        islandUnderPointer()?.send(.toggleRequested)
    }

    func expandUnderPointer() {
        islandUnderPointer()?.send(.clicked)
    }

    private func islandUnderPointer() -> IslandWindowController? {
        let pointer = NSEvent.mouseLocation
        return islands.values.first { $0.screen.frame.contains(pointer) } ?? islands.values.first
    }

    private func rebuild() {
        let wanted = settings.screenSelection.select(from: ScreenInfo.current())
        let wantedIDs = Set(wanted.map(\.id))

        for (id, island) in islands where !wantedIDs.contains(id) {
            island.close()
        }
        islands = islands.filter { wantedIDs.contains($0.key) }

        for screen in wanted {
            if let island = islands[screen.id] {
                island.update(screen: screen)
            } else {
                islands = islands.merging([screen.id: makeIsland(for: screen)]) { _, new in new }
            }
        }
        log.info("Wyspy aktywne na \(wanted.count) ekranach")
    }

    private func makeIsland(for screen: ScreenInfo) -> IslandWindowController {
        IslandWindowController(screen: screen, settings: settings, registry: registry, openSettings: openSettings)
    }
}
