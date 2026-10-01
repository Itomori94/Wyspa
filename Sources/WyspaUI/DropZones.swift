import SwiftUI
import UniformTypeIdentifiers
import WyspaCore

/// Strefy upuszczania zgłaszane przez widoki modułów (id strefy → kotwica ramki).
struct DropZoneKey: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]

    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

private struct DropTargetKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    /// Strefa, nad którą jest teraz przeciągany element (do podświetlenia).
    public var islandDropTarget: String? {
        get { self[DropTargetKey.self] }
        set { self[DropTargetKey.self] = newValue }
    }
}

extension View {
    /// Oznacza widok jako strefę upuszczania wyspy. Id musi mieć prefiks `<id modułu>.`.
    public func islandDropZone(_ id: String) -> some View {
        anchorPreference(key: DropZoneKey.self, value: .bounds) { [id: $0] }
    }
}

/// Przeciąganie elementów z wyspy na zewnątrz: wyspa nie przyjmuje wtedy własnych elementów z powrotem.
@MainActor
public enum IslandDragSession {
    public static var isDraggingOut = false
}

enum DropZoneHitTest {
    /// Najmniejsza strefa zawierająca punkt (strefy mogą się zagnieżdżać).
    static func zone(at point: CGPoint, in frames: [String: CGRect]) -> String? {
        frames
            .filter { $0.value.contains(point) }
            .min { $0.value.width * $0.value.height < $1.value.width * $1.value.height }?
            .key
    }
}

/// Jeden cel upuszczania na całej wyspie; przejścia między strefami nie generują wyjścia z wyspy.
struct IslandDropDelegate: DropDelegate {
    let model: IslandViewModel
    let types: [UTType]

    func validateDrop(info: DropInfo) -> Bool {
        !IslandDragSession.isDraggingOut && info.hasItemsConforming(to: types)
    }

    func dropEntered(info: DropInfo) {
        model.dropTarget = DropZoneHitTest.zone(at: info.location, in: model.dropZoneFrames)
        model.onDragEntered()
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        let zone = DropZoneHitTest.zone(at: info.location, in: model.dropZoneFrames)
        if zone != model.dropTarget { model.dropTarget = zone }
        return DropProposal(operation: .copy)
    }

    func dropExited(info: DropInfo) {
        model.dropTarget = nil
        model.onDragExited()
    }

    func performDrop(info: DropInfo) -> Bool {
        let zone = DropZoneHitTest.zone(at: info.location, in: model.dropZoneFrames)
        model.dropTarget = nil
        let accepted = model.registry.performDrop(info.itemProviders(for: types), zoneID: zone)
        model.onDropFinished()
        return accepted
    }
}
