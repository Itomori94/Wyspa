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
    /// Domyślna szerokość jednego „skrzydła” live activity po boku notcha.
    public static let wingWidth: CGFloat = 40
    /// Górna granica szerokości skrzydła; z niej liczona jest rama panelu, więc żadna aktywność nie wyjdzie poza okno.
    public static let maxWingWidth: CGFloat = 96

    public static func clampedWingWidth(_ width: CGFloat) -> CGFloat {
        min(max(width, 0), maxWingWidth)
    }
    /// Wklęsłe górne rogi, którymi wyspa wtapia się w pasek menu.
    public static let collapsedTopRadius: CGFloat = 6
    public static let expandedTopRadius: CGFloat = 14
    /// Wewnętrzny margines treści rozwiniętej wyspy (poza promieniem rogu).
    public static let expandedContentInset: CGFloat = 20
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

    /// Szerokość jednej połowy nagłówka rozwiniętej wyspy (po odjęciu marginesów i przerwy pod notchem).
    public static func headerSideWidth(islandWidth: CGFloat, notchGap: CGFloat) -> CGFloat {
        let inner = islandWidth - 2 * (expandedTopRadius + expandedContentInset)
        return max(0, (inner - notchGap) / 2)
    }

    /// Okno musi pomieścić największy możliwy stan i cień: rozwiniętą wyspę albo podgląd
    /// z najszerszymi dopuszczalnymi skrzydłami przy tym notchu.
    public static func panelSize(expanded: CGSize, notch: CGSize, shadowMargin: CGFloat) -> CGSize {
        let widest = [IslandPhase.peek, .expanded].map {
            size(for: $0, notch: notch, activityWingWidth: maxWingWidth, expanded: expanded)
        }
        let width = widest.map(\.width).max() ?? expanded.width
        let height = widest.map(\.height).max() ?? expanded.height
        return CGSize(width: width + shadowMargin * 2, height: height + shadowMargin)
    }
}
