import SwiftUI
import WyspaCore

/// Stan jednej wyspy (jeden ekran), który renderuje `IslandView`.
@MainActor
@Observable
public final class IslandViewModel {
    public var phase: IslandPhase
    public var notch: NotchMetrics
    public var expandedSize: CGSize
    public var material: IslandMaterial = .black
    public var transparency: Double = IslandMaterial.defaultTransparency
    public var selectedTab: Int
    /// Strefa upuszczania pod kursorem podczas przeciągania.
    public var dropTarget: String?
    /// Ramki stref upuszczania we współrzędnych wyspy.
    public var dropZoneFrames: [String: CGRect] = [:]

    @ObservationIgnored public let registry: ModuleRegistry
    @ObservationIgnored public var onSelectTab: (Int) -> Void = { _ in }
    @ObservationIgnored public var onOpenSettings: () -> Void = {}
    @ObservationIgnored public var onClick: () -> Void = {}
    @ObservationIgnored public var onDragEntered: () -> Void = {}
    @ObservationIgnored public var onDragExited: () -> Void = {}
    @ObservationIgnored public var onDropFinished: () -> Void = {}
    /// Esc w wyspie przyjmującej klawiaturę.
    @ObservationIgnored public var onEscape: () -> Void = {}

    public init(phase: IslandPhase, notch: NotchMetrics, expandedSize: CGSize, registry: ModuleRegistry) {
        self.phase = phase
        self.notch = notch
        self.expandedSize = expandedSize
        self.selectedTab = 0
        self.registry = registry
    }

    public var activity: LiveActivity? { registry.currentActivity }

    public var islandSize: CGSize {
        IslandLayout.size(for: phase, notch: notch.size, activityWingWidth: activity?.wingWidth,
                          activityDetailHeight: activity?.detail == nil ? nil : activity?.detailHeight, expanded: expandedSize)
    }
}
