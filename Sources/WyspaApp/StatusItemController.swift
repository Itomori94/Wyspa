import AppKit
import WyspaUpdates

/// Ikona w pasku menu: jedyne stałe wejście do aplikacji typu agent.
@MainActor
final class StatusItemController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let openSettings: () -> Void
    private let checkForUpdates: () -> Void

    init(openSettings: @escaping () -> Void, checkForUpdates: @escaping () -> Void) {
        self.openSettings = openSettings
        self.checkForUpdates = checkForUpdates
        super.init()
        item.button?.image = NSImage(systemSymbolName: "capsule.fill", accessibilityDescription: "Wyspa")
        item.button?.image?.isTemplate = true
        item.menu = makeMenu()
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "Ustawienia…", action: #selector(settings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Sprawdź aktualizacje…", action: #selector(updates), keyEquivalent: "").target = self
        if let source = UpdateService.shared.source {
            // Zainstalowana wersja (commit) — po aktualizacji widać, że się zmieniła.
            let version = menu.addItem(withTitle: "Wersja \(source.shortCommit)", action: nil, keyEquivalent: "")
            version.isEnabled = false
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: SupportLink.title, action: #selector(support), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Zakończ Wyspę", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    @objc private func settings() { openSettings() }
    @objc private func updates() { checkForUpdates() }
    @objc private func support() { NSWorkspace.shared.open(SupportLink.url) }
}
