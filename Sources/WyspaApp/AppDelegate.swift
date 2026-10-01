import AppKit
import WyspaCore
import WyspaFeatures

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = SettingsStore()
    private let permissions = PermissionCenter()
    private var registry: ModuleRegistry?
    private var screens: ScreenCoordinator?
    private var statusItem: StatusItemController?
    private var settingsWindow: SettingsWindowController?
    private var hotkey: HotkeyController?
    private var terminationSignal: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        handleTerminationSignal()
        let registry = ModuleRegistry(
            catalog: ModuleCatalog.all,
            settings: settings,
            permissions: permissions,
            requestExpand: { [weak self] in self?.screens?.expandUnderPointer() }
        )
        self.registry = registry

        let settingsWindow = SettingsWindowController(
            settings: settings, registry: registry, permissions: permissions
        )
        self.settingsWindow = settingsWindow

        let screens = ScreenCoordinator(settings: settings, registry: registry) {
            settingsWindow.show()
        }
        self.screens = screens
        screens.start()

        statusItem = StatusItemController(
            toggleIsland: { screens.toggleUnderPointer() },
            openSettings: { settingsWindow.show() }
        )
        hotkey = HotkeyController(settings: settings, settingsWindow: settingsWindow) {
            screens.toggleUnderPointer()
        }

        Task { await registry.startEnabledModules() }
    }

    /// SIGTERM (np. `pkill`, wylogowanie) zamyka aplikację porządnie, żeby moduły zakończyły procesy potomne.
    private func handleTerminationSignal() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { NSApp.terminate(nil) }
        source.resume()
        terminationSignal = source
    }

    func applicationWillTerminate(_ notification: Notification) {
        registry?.stopAll()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settingsWindow?.show()
        return true
    }
}
