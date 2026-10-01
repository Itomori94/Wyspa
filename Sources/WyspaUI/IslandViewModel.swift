import SwiftUI
import WyspaCore

/// Stan jednej wyspy (jeden ekran), który renderuje `IslandView`.
@MainActor
@Observable
public final class IslandViewModel {
    public var phase: IslandPhase
    public var notch: NotchMetrics
    public var expandedSize: CGSize
    public var selectedTab: Int

    @ObservationIgnored public let registry: ModuleRegistry
    @ObservationIgnored public var onSelectTab: (Int) -> Void = { _ in }
    @ObservationIgnored public var onOpenSettings: () -> Void = {}

    public init(phase: IslandPhase, notch: NotchMetrics, expandedSize: CGSize, registry: ModuleRegistry) {
        self.phase = phase
        self.notch = notch
        self.expandedSize = expandedSize
        self.selectedTab = 0
        self.registry = registry
    }

    public var activity: LiveActivity? { registry.currentActivity }

    public var islandSize: CGSize {
        IslandLayout.size(for: phase, notch: notch.size, hasActivity: activity != nil, expanded: expandedSize)
    }
}
