import AppKit
import SwiftUI

/// Kontener panelu: śledzi kursor tylko nad wyspą i przechwytuje kliknięcie w stanie zwiniętym.
///
/// Przezroczyste obszary okna przepuszczają kliknięcia do aplikacji pod spodem
/// (macOS testuje przezroczystość pikseli okien nieprzezroczystych = false).
final class IslandContainerView: NSView {
    var onPointerEntered: () -> Void = {}
    var onPointerExited: () -> Void = {}
    var onClick: () -> Void = {}
    /// Czy kliknięcia mają trafiać do SwiftUI (stan rozwinięty), czy do kontenera.
    var forwardsClicksToContent = false

    /// Obszar wyspy we współrzędnych widoku (y w górę).
    var interactiveRect: CGRect = .zero {
        didSet {
            guard interactiveRect != oldValue else { return }
            updateTrackingAreas()
            syncPointerState()
        }
    }

    private let hostingView: NSView
    private var trackingArea: NSTrackingArea?
    private var isPointerInside = false

    init(content: some View) {
        hostingView = NSHostingView(rootView: content)
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
        guard interactiveRect.contains(local) else { return nil }
        return forwardsClicksToContent ? super.hitTest(point) : self
    }

    override func mouseDown(with event: NSEvent) { onClick() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Po zmianie obszaru (np. zwinięcie) kursor mógł znaleźć się poza nim bez zdarzenia `mouseExited`.
    private func syncPointerState() {
        guard let window else { return }
        let location = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        setPointerInside(interactiveRect.contains(location))
    }

    private func setPointerInside(_ inside: Bool) {
        guard inside != isPointerInside else { return }
        isPointerInside = inside
        inside ? onPointerEntered() : onPointerExited()
    }
}
