import AppKit

/// Ikona w pasku menu: jedyne stałe wejście do aplikacji typu agent.
@MainActor
final class StatusItemController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let toggleIsland: () -> Void
    private let openSettings: () -> Void

    init(toggleIsland: @escaping () -> Void, openSettings: @escaping () -> Void) {
        self.toggleIsland = toggleIsland
        self.openSettings = openSettings
        super.init()
        item.button?.image = NSImage(systemSymbolName: "capsule.fill", accessibilityDescription: "Wyspa")
        item.button?.image?.isTemplate = true
        item.menu = makeMenu()
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "Rozwiń lub zwiń wyspę", action: #selector(toggle), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Ustawienia…", action: #selector(settings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Zakończ Wyspę", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    @objc private func toggle() { toggleIsland() }
    @objc private func settings() { openSettings() }
}
