import AppKit

/// Panel wyspy: bez ramki, nad paskiem menu, na wszystkich Spaces i nad aplikacjami pełnoekranowymi.
final class IslandPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        animationBehavior = .none
    }

    // Wyspa nigdy nie zabiera fokusu aktywnej aplikacji.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
