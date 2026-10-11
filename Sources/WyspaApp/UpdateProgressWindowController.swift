import AppKit
import SwiftUI
import WyspaCore
import WyspaUpdates

/// Okienko postępu aktualizacji: pojawia się po „Zaktualizuj teraz” (z menu albo z ustawień modułu) i zostaje
/// z opisem błędu, gdy się nie uda. Udana aktualizacja zamyka Wyspę razem z okienkiem.
@MainActor
final class UpdateProgressWindowController {
    private let service: UpdateService
    private var window: NSWindow?

    init(service: UpdateService = .shared) {
        self.service = service
        observeChanges({ [service] in _ = service.status }) { [weak self] in self?.statusChanged() }
    }

    private func statusChanged() {
        switch service.status {
        case .updating: show()
        case .failed: break  // otwarte okienko pokazuje błąd
        case .idle, .checking, .upToDate, .available: window?.close()
        }
    }

    func show() {
        let window = window ?? makeWindow()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let root = UpdateProgressView(service: service) { [weak self] in self?.window?.close() }
        let window = NSWindow(contentViewController: NSHostingController(rootView: root))
        window.title = "Aktualizacja Wyspy"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}
