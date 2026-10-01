import Foundation

/// Zaznaczenie wielu elementów jak w Finderze: klik, ⌘-klik (przełącz), ⇧-klik (zakres).
public struct ShelfSelection: Equatable, Sendable {
    public enum Modifier: Sendable {
        case none, toggle, range
    }

    public private(set) var selected: Set<UUID> = []
    private var anchor: UUID?

    public init() {}

    public mutating func click(_ id: UUID, modifier: Modifier, order: [UUID]) {
        switch modifier {
        case .none:
            selected = [id]
            anchor = id
        case .toggle:
            if selected.contains(id) {
                selected.remove(id)
            } else {
                selected.insert(id)
                anchor = id
            }
        case .range:
            guard let anchor, let from = order.firstIndex(of: anchor), let to = order.firstIndex(of: id) else {
                click(id, modifier: .none, order: order)
                return
            }
            selected = Set(order[min(from, to)...max(from, to)])
        }
    }

    /// Elementy do przeciągnięcia: zaznaczone, jeśli chwycony należy do zaznaczenia, inaczej tylko chwycony.
    public func dragSet(grabbing id: UUID) -> Set<UUID> {
        selected.contains(id) ? selected : [id]
    }

    public mutating func selectAll(_ order: [UUID]) {
        selected = Set(order)
    }

    public mutating func clear() {
        selected = []
        anchor = nil
    }

    /// Usuwa z zaznaczenia elementy, których już nie ma na półce.
    public mutating func retain(_ existing: [UUID]) {
        selected = selected.intersection(existing)
        if let anchor, !existing.contains(anchor) { self.anchor = nil }
    }
}
