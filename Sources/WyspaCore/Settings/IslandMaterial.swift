/// Tło wyspy wybierane w ustawieniach.
public enum IslandMaterial: String, CaseIterable, Codable, Sendable {
    /// Czarne tło zlewające się z notchem.
    case black
    /// Liquid Glass (macOS 26+) w rozwiniętej wyspie i kartach; zwinięta wyspa zostaje czarna.
    case liquidGlass

    public var displayName: String {
        switch self {
        case .black: "Czarny"
        case .liquidGlass: "Liquid Glass"
        }
    }

    /// Liquid Glass istnieje od macOS 26; na starszych systemach wyspa zostaje czarna.
    public static var isGlassAvailable: Bool {
        if #available(macOS 26, *) { true } else { false }
    }

    /// Czy w danej chwili rysować szkło. Zwinięta wyspa bez karty zawsze jest czarna, żeby zlewać się z notchem.
    public func usesGlass(phase: IslandPhase, showsCard: Bool, systemSupportsGlass: Bool) -> Bool {
        guard self == .liquidGlass, systemSupportsGlass else { return false }
        switch phase {
        case .expanded: return true
        case .collapsed, .peek: return showsCard
        case .hidden: return false
        }
    }
}
