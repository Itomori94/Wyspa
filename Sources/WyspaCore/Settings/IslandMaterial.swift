/// Tło wyspy wybierane w ustawieniach.
public enum IslandMaterial: String, CaseIterable, Codable, Sendable {
    /// Czarne tło zlewające się z notchem.
    case black
    /// Liquid Glass (macOS 26+) w rozwiniętej wyspie i kartach; zwinięta wyspa zostaje czarna.
    case liquidGlass
    /// Własna przezroczystość bez rozmycia (suwak w ustawieniach), na każdym macOS.
    case transparent

    public var displayName: String {
        switch self {
        case .black: "Czarny"
        case .liquidGlass: "Liquid Glass"
        case .transparent: "Przezroczysty"
        }
    }

    /// Zakres suwaka: 0 = czarne tło, 1 = zupełnie przejrzyste (zostaje tylko krawędź).
    public static let transparencyRange: ClosedRange<Double> = 0...1
    public static let defaultTransparency = 0.6

    /// Liquid Glass istnieje od macOS 26; na starszych systemach wyspa zostaje czarna.
    public static var isGlassAvailable: Bool {
        if #available(macOS 26, *) { true } else { false }
    }

    /// Tło do narysowania w danej chwili. Zwinięta wyspa bez karty zawsze jest czarna, żeby zlewać się z notchem.
    public func background(phase: IslandPhase, showsCard: Bool, systemSupportsGlass: Bool,
                           transparency: Double) -> IslandBackgroundStyle {
        let showsSpecial = switch phase {
        case .expanded: true
        case .collapsed, .peek: showsCard
        case .hidden: false
        }
        guard showsSpecial else { return .black }
        switch self {
        case .black: return .black
        case .liquidGlass: return systemSupportsGlass ? .glass : .black
        case .transparent:
            let clamped = min(max(transparency, Self.transparencyRange.lowerBound), Self.transparencyRange.upperBound)
            return .tinted(blackOpacity: 1 - clamped)
        }
    }
}

public enum IslandBackgroundStyle: Equatable, Sendable {
    case black
    case glass
    /// Czarne tło o danym kryciu, bez rozmycia.
    case tinted(blackOpacity: Double)
}

/// Wariant szkła zgodny z wyborem w Ustawieniach systemowych → Wygląd → Liquid Glass.
public enum GlassVariant: Equatable, Sendable {
    /// „Przezroczyste”: szkło bez szronu.
    case clear
    /// „Zabarwione” albo brak informacji: zwykłe, zaszronione szkło.
    case regular

    /// Klucz globalnych preferencji, pod którym macOS zapisuje wybór (0 = przezroczyste). Nieudokumentowany:
    /// gdy zniknie, zostaje zwykłe szkło.
    public static let systemTintKey = "NSGlassTintAmount"

    public static func forSystemTint(_ amount: Double?) -> GlassVariant {
        guard let amount else { return .regular }
        return amount <= 0.01 ? .clear : .regular
    }
}
