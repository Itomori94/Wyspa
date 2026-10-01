import AppKit
import SwiftUI
import WyspaUI

/// Mysz na kafelku półki w AppKit: klik/⌘/⇧ zaznacza, dwuklik otwiera, przeciągnięcie wyciąga
/// wszystkie zaznaczone pliki naraz (SwiftUI `onDrag` obsługuje tylko jeden element).
struct ShelfTileInteraction: NSViewRepresentable {
    let onClick: (ShelfSelection.Modifier) -> Void
    let onOpen: () -> Void
    let dragURLs: () -> [URL]
    let menu: () -> NSMenu

    func makeNSView(context: Context) -> TileMouseView {
        TileMouseView()
    }

    func updateNSView(_ view: TileMouseView, context: Context) {
        view.onClick = onClick
        view.onOpen = onOpen
        view.dragURLs = dragURLs
        view.makeMenu = menu
    }
}

final class TileMouseView: NSView, NSDraggingSource {
    private static let dragThreshold: CGFloat = 4

    var onClick: (ShelfSelection.Modifier) -> Void = { _ in }
    var onOpen: () -> Void = {}
    var dragURLs: () -> [URL] = { [] }
    var makeMenu: () -> NSMenu = { NSMenu() }
    private var mouseDownLocation: NSPoint?
    private var didDrag = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        mouseDownLocation = event.locationInWindow
        didDrag = false
        if event.clickCount == 2 {
            onOpen()
            mouseDownLocation = nil
            return
        }
        let flags = event.modifierFlags
        let modifier: ShelfSelection.Modifier = flags.contains(.shift) ? .range : (flags.contains(.command) ? .toggle : .none)
        // Klik bez modyfikatora na już zaznaczonym elemencie czeka do puszczenia, żeby dało się przeciągnąć całe zaznaczenie.
        if modifier != .none { onClick(modifier) }
    }

    override func mouseUp(with event: NSEvent) {
        let flags = event.modifierFlags
        if !didDrag, mouseDownLocation != nil, !flags.contains(.shift), !flags.contains(.command) {
            onClick(.none)
        }
        mouseDownLocation = nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownLocation, !didDrag else { return }
        let distance = hypot(event.locationInWindow.x - start.x, event.locationInWindow.y - start.y)
        guard distance >= Self.dragThreshold else { return }
        let urls = dragURLs()
        guard !urls.isEmpty else { return }
        didDrag = true
        let items = urls.enumerated().map { index, url in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            let offset = CGFloat(index) * 4
            item.setDraggingFrame(CGRect(x: offset, y: -offset, width: 48, height: 48), contents: icon)
            return item
        }
        IslandDragSession.isDraggingOut = true
        beginDraggingSession(with: items, event: event, source: self)
    }

    override func menu(for event: NSEvent) -> NSMenu? { makeMenu() }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? [.copy, .link, .generic] : []
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        IslandDragSession.isDraggingOut = false
        mouseDownLocation = nil
    }
}
