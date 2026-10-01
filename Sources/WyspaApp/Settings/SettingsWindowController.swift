import AppKit
import SwiftUI
import WyspaCore

/// Stan okna ustawień, który nie należy do magazynu ustawień (np. błędy rejestracji skrótu).
@MainActor
@Observable
final class SettingsUIState {
    var hotkeyProblem: String?
}

@MainActor
final class SettingsWindowController {
    private static let size = NSSize(width: 560, height: 480)

    private let uiState = SettingsUIState()
    private let settings: SettingsStore
    private let registry: ModuleRegistry
    private let permissions: PermissionCenter
    private var window: NSWindow?

    var hotkeyProblem: String? {
        get { uiState.hotkeyProblem }
        set { uiState.hotkeyProblem = newValue }
    }

    init(settings: SettingsStore, registry: ModuleRegistry, permissions: PermissionCenter) {
        self.settings = settings
        self.registry = registry
        self.permissions = permissions
    }

    func show() {
        let window = window ?? makeWindow()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let root = SettingsView(settings: settings, registry: registry, permissions: permissions, uiState: uiState)
        let window = NSWindow(contentViewController: NSHostingController(rootView: root))
        window.title = "Ustawienia Wyspy"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(Self.size)
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}
