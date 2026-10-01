import CoreGraphics

/// Rozmiar rozwiniętej wyspy wybierany w ustawieniach.
public enum IslandSize: String, CaseIterable, Codable, Sendable {
    case small, medium, large

    public var expandedSize: CGSize {
        switch self {
        case .small: CGSize(width: 520, height: 190)
        case .medium: CGSize(width: 600, height: 230)
        case .large: CGSize(width: 700, height: 280)
        }
    }

    public var displayName: String {
        switch self {
        case .small: "Mała"
        case .medium: "Średnia"
        case .large: "Duża"
        }
    }
}

/// Wymiary wyspy w każdej fazie. Czysta funkcja, testowana jednostkowo.
public enum IslandLayout {
    /// Szerokość jednego „skrzydła” live activity po boku notcha.
    public static let wingWidth: CGFloat = 40
    /// Wklęsłe górne rogi, którymi wyspa wtapia się w pasek menu.
    public static let collapsedTopRadius: CGFloat = 6
    public static let expandedTopRadius: CGFloat = 14
    public static let peekGrowth = CGSize(width: 18, height: 4)
    /// Pasek pod wirtualnym notchem, na który można najechać, gdy wyspa jest ukryta.
    public static let hiddenHotZoneHeight: CGFloat = 3

    /// - Parameter activityWingWidth: szerokość skrzydła bieżącej aktywności; nil = brak aktywności.
    public static func size(
        for phase: IslandPhase,
        notch: CGSize,
        activityWingWidth: CGFloat?,
        expanded: CGSize
    ) -> CGSize {
        let wings = (activityWingWidth ?? 0) * 2
        let collapsed = CGSize(width: notch.width + wings + collapsedTopRadius * 2, height: notch.height)
        switch phase {
        case .hidden:
            return CGSize(width: notch.width, height: hiddenHotZoneHeight)
        case .collapsed:
            return collapsed
        case .peek:
            return CGSize(width: collapsed.width + peekGrowth.width, height: collapsed.height + peekGrowth.height)
        case .expanded:
            return CGSize(width: max(expanded.width, collapsed.width), height: max(expanded.height, notch.height))
        }
    }

    /// Okno musi pomieścić największy stan i cień.
    public static func panelSize(expanded: CGSize, shadowMargin: CGFloat) -> CGSize {
        CGSize(width: expanded.width + shadowMargin * 2, height: expanded.height + shadowMargin)
    }
}
