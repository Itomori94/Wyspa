import AppKit
import SwiftUI
import WyspaQuickActions

/// Okno „Pokaz animacji” (menu Wyspy albo `wyspa://pokaz-animacji`). Animacje działają tylko, gdy jest otwarte.
@MainActor
final class ShowcaseWindowController {
    static let urlHost = "pokaz-animacji"
    private var window: NSWindow?

    func show() {
        if window == nil {
            let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Pokaz animacji Wyspy"
            window.contentView = NSHostingView(rootView: AnimationShowcaseView())
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
