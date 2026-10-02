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
        // Klawiatura tylko po kliknięciu w pole tekstowe; przyciski nie zabierają fokusu innej aplikacji.
        becomesKeyOnlyIfNeeded = true
    }

    /// Ustawiane przez kontroler: tylko rozwinięta wyspa może przyjąć klawiaturę (notatka, wyszukiwanie).
    var acceptsKeyboard = false

    override var canBecomeKey: Bool { acceptsKeyboard }
    override var canBecomeMain: Bool { false }
}
