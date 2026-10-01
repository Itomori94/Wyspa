import AppKit
import WyspaCore

/// Utrzymuje globalny skrót zgodny z ustawieniami i raportuje błąd rejestracji do okna ustawień.
@MainActor
final class HotkeyController {
    private let settings: SettingsStore
    private let hotkey: GlobalHotkey
    private weak var settingsWindow: SettingsWindowController?
    private let log = Log.logger("hotkey")

    init(settings: SettingsStore, settingsWindow: SettingsWindowController, action: @escaping @MainActor () -> Void) {
        self.settings = settings
        self.settingsWindow = settingsWindow
        self.hotkey = GlobalHotkey(action: action)
        apply()
        observeChanges({ _ = settings.toggleShortcut }) { [weak self] in self?.apply() }
    }

    private func apply() {
        guard let shortcut = settings.toggleShortcut else {
            hotkey.unregister()
            settingsWindow?.hotkeyProblem = nil
            return
        }
        do {
            try hotkey.register(shortcut)
            settingsWindow?.hotkeyProblem = nil
        } catch {
            log.error("Rejestracja skrótu \(shortcut.displayString) nie powiodła się: \(error.message)")
            settingsWindow?.hotkeyProblem = error.message
        }
    }
}
