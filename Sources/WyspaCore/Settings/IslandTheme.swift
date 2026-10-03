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

    public var displayName: String {
        switch self {
        case .classic: "Klasyczny"
        case .blackSheet: "Czarna tafla"
        case .glass: "Szkło"
        }
    }

    /// Szkło tylko tam, gdzie wyspa wychodzi poza notch: rozwinięta albo z kartą pod skrzydłami.
    public func usesGlass(isExpanded: Bool, showsCard: Bool) -> Bool {
        self == .glass && (isExpanded || showsCard)
    }

    /// Przyciemnienie szkła (krycie czarnej warstwy na rozmyciu).
    public static let glassTintRange: ClosedRange<Double> = 0.35...0.9
    public static let defaultGlassTint = 0.6
}
