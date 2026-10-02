import AppKit
import SwiftUI

/// Kontener panelu: śledzi kursor tylko nad wyspą i ogranicza zdarzenia do jej obszaru.
///
/// Wszystkie kliknięcia i przeciągania nad wyspą trafiają do SwiftUI (`IslandHostingView`).
/// Poza wyspą `hitTest` zwraca nil, a przezroczyste piksele okna przepuszczają kliknięcia do aplikacji pod spodem.
final class IslandContainerView: NSView {
    var onPointerEntered: () -> Void = {}
    var onPointerExited: () -> Void = {}

    /// Obszar wyspy we współrzędnych widoku (y w górę).
    var interactiveRect: CGRect = .zero {
        didSet {
            guard interactiveRect != oldValue else { return }
            updateTrackingAreas()
            resyncPointer()
        }
    }

    private let hostingView: NSView
    private var trackingArea: NSTrackingArea?
    private var isPointerInside = false

    init(content: some View) {
        hostingView = IslandHostingView(rootView: AnyView(content))
        super.init(frame: .zero)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: interactiveRect,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { setPointerInside(true) }
    override func mouseExited(with event: NSEvent) { setPointerInside(false) }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return interactiveRect.contains(local) ? super.hitTest(point) : nil
    }

    /// Po zmianie obszaru albo po przeciąganiu (które wstrzymuje zdarzenia śledzenia)
    /// kursor mógł zmienić położenie bez `mouseEntered`/`mouseExited`.
    func resyncPointer() {
        guard let window else { return }
        let location = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        setPointerInside(interactiveRect.contains(location))
    }

    /// Czy kursor jest teraz nad wyspą (stan faktyczny, nie z ostatniego zdarzenia).
    var isPointerOverIsland: Bool {
        guard let window else { return false }
        return interactiveRect.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil))
    }

    private func setPointerInside(_ inside: Bool) {
        guard inside != isPointerInside else { return }
        isPointerInside = inside
        inside ? onPointerEntered() : onPointerExited()
    }
}

/// Panel nigdy nie jest oknem kluczowym, więc każde kliknięcie jest „pierwszym” — musi działać od razu.
private final class IslandHostingView: NSHostingView<AnyView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
