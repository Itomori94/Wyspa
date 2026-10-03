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
    private var accessibilityObserver: NSObjectProtocol?
    /// Zmiana aktywnej aplikacji (np. start udostępniania w Zoomie) — moment na sprawdzenie trybu prywatnego.
    private var privacyObserver: NSObjectProtocol?
    private var showcase: ShowcaseWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        handleTerminationSignal()
        let registry = ModuleRegistry(
            catalog: ModuleCatalog.all,
            settings: settings,
            permissions: permissions,
            requestExpand: { [weak self] moduleID in self?.screens?.expandUnderPointer(opening: moduleID) },
            requestCollapse: { [weak self] in self?.screens?.collapseAll() }
        )
        self.registry = registry
        let privacy = registry.privacy
        registry.startPrivacyObservation()
        privacy.refresh()
        privacyObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { _ in MainActor.assumeIsolated { _ = privacy.refresh() } }
        observeChanges({ [settings] in _ = settings.privacyMode }) { _ = privacy.refresh() }

        let settingsWindow = SettingsWindowController(
            settings: settings, registry: registry, permissions: permissions
        )
        self.settingsWindow = settingsWindow

        let screens = ScreenCoordinator(settings: settings, registry: registry) {
            settingsWindow.show()
        }
        self.screens = screens
        screens.start()

        let showcase = ShowcaseWindowController()
        self.showcase = showcase
        statusItem = StatusItemController(
            toggleIsland: { screens.toggleUnderPointer() },
            openSettings: { settingsWindow.show() },
            openShowcase: { showcase.show() }
        )
        hotkey = HotkeyController(settings: settings, settingsWindow: settingsWindow) {
            screens.toggleWithKeyboardUnderPointer()
        }

        Task { await registry.startEnabledModules() }
        observeAccessibilityChanges(registry)
    }

    /// System ogłasza zmianę zaufania Dostępności; moduły czekające na nią startują bez ponownego włączania.
    private func observeAccessibilityChanges(_ registry: ModuleRegistry) {
        accessibilityObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.accessibility.api"), object: nil, queue: .main
        ) { _ in
            Task { @MainActor in
                // Powiadomienie przychodzi chwilę przed faktyczną zmianą stanu zaufania.
                try? await Task.sleep(for: .milliseconds(500))
                await registry.retryInactiveModules()
            }
        }
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

    /// Adresy `wyspa://` (komenda `wyspa`, Skróty, cron) trafiają do modułu Skrypty.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            // Pokaz animacji tylko otwiera okno — bez skutków ubocznych, więc może go otworzyć każdy adres.
            if url.scheme == ScriptCommand.scheme, url.host == ShowcaseWindowController.urlHost {
                showcase?.show()
                continue
            }
            guard let command = ScriptCommand(url: url) else {
                Log.logger("scripts").error("Nieznany adres wyspa://: \(url.host ?? url.path, privacy: .public)")
                continue
            }
            ScriptCommandCenter.shared.post(command)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settingsWindow?.show()
        return true
    }
}
