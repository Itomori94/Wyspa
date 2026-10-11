import Foundation

/// Wygląd wyspy. Ikony modułów, okładki i ikony aplikacji (np. Apple Music) są takie same w każdym motywie —
/// motyw zmienia tylko tło wyspy, krawędź, pasek zakładek i karty widżetów.
public enum IslandTheme: String, CaseIterable, Codable, Sendable {
    /// Dotychczasowy wygląd: czarna wyspa, widżety rozdzielone kreskami.
    case classic
    /// Czarna tafla: cienka jasna krawędź, zakładki w kapsule, widżety na osobnych kartach z połyskiem.
    case blackSheet = "black-sheet"
    /// Szkło: rozwinięta wyspa i karty z rozmytego, przyciemnionego szkła; zwinięta wyspa zostaje czarna przy notchu.
    case glass
    /// Przezroczysty: Liquid Glass jak w Centrum sterowania (macOS 26+), bez przyciemnienia; na starszym systemie
    /// rozmyte szkło. Zwinięta wyspa zostaje czarna przy notchu, jak w Szkle.
    case clear

    public var displayName: String {
        switch self {
        case .classic: "Klasyczny"
        case .blackSheet: "Czarna tafla"
        case .glass: "Szkło"
        case .clear: "Przezroczysty"
        }
    }

    /// Motyw ze szklaną rozwiniętą wyspą (Szkło, Przezroczysty).
    public var hasGlass: Bool { self == .glass || self == .clear }

    /// Szkło tylko tam, gdzie wyspa wychodzi poza notch: rozwinięta albo z kartą pod skrzydłami.
    public func usesGlass(isExpanded: Bool, showsCard: Bool) -> Bool {
        hasGlass && (isExpanded || showsCard)
    }

    /// Przyciemnienie szkła (krycie czarnej warstwy na rozmyciu).
    public static let glassTintRange: ClosedRange<Double> = 0.35...0.9
    public static let defaultGlassTint = 0.6
}
