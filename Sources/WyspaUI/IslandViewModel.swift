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
    public var theme: IslandTheme = .classic
    /// Skrzydła schowane, bo kursor sięga do ikon paska menu pod nimi.
    public var wingsYielded = false
    public var glassTint: Double = IslandTheme.defaultGlassTint
    /// Strefa upuszczania pod kursorem podczas przeciągania.
    public var dropTarget: String?
    /// Moduł pokazywany doraźnie w rozwiniętej wyspie, bo nie ma strony w układzie (np. Claude prosi o zgodę).
    public var standaloneModuleID: String?
    /// Ramki stref upuszczania we współrzędnych wyspy.
    public var dropZoneFrames: [String: CGRect] = [:]

    @ObservationIgnored public let registry: ModuleRegistry
    @ObservationIgnored public var onSelectTab: (Int) -> Void = { _ in }
    @ObservationIgnored public var onOpenSettings: () -> Void = {}
    @ObservationIgnored public var onClick: () -> Void = {}
    /// Kliknięcie aktywności w nagłówku rozwiniętej wyspy: otwiera widok jej modułu.
    @ObservationIgnored public var onOpenActivity: () -> Void = {}
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
        IslandLayout.size(for: phase, notch: notch.size, activityWingWidth: wingsYielded ? nil : activity?.wingWidth,
                          activityDetailHeight: activity?.detail == nil ? nil : activity?.detailHeight, expanded: expandedSize)
    }
}
