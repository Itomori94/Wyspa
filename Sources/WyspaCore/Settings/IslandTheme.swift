import Foundation

/// Wygląd wyspy. Ikony modułów, okładki i ikony aplikacji (np. Apple Music) są takie same w każdym motywie —
/// motyw zmienia tylko tło wyspy, krawędź, pasek zakładek i karty widżetów.
public enum IslandTheme: String, CaseIterable, Codable, Sendable {
    /// Dotychczasowy wygląd: czarna wyspa, widżety rozdzielone kreskami.
    case classic
    /// Czarna tafla: cienka jasna krawędź, zakładki w kapsule, widżety na osobnych kartach z połyskiem.
    case blackSheet = "black-sheet"
    /// Szkło: rozwinięta wyspa i karty z jednej tafli przejrzystego szkła Liquid Glass, jak Centrum sterowania
    /// (macOS 26+, wcześniej rozmycie); zwinięta wyspa zostaje czarna przy notchu.
    case glass
    /// Przezroczysty, jak Centrum sterowania: rozwinięta wyspa bez tła — czarna zostaje tylko belka przy notchu,
    /// a strony, widżety i karty leżą na osobnych kafelkach z przejrzystego szkła Liquid Glass (macOS 26+).
    case clear

    public var displayName: String {
        switch self {
        case .classic: "Klasyczny"
        case .blackSheet: "Czarna tafla"
        case .glass: "Szkło"
        case .clear: "Przezroczysty"
        }
    }

    /// Motyw ze szkłem w rozwiniętej wyspie (Szkło, Przezroczysty).
    public var hasGlass: Bool { self == .glass || self == .clear }

    /// Treść na osobnych szklanych kafelkach zamiast jednej tafli (Przezroczysty).
    public var usesGlassTiles: Bool { self == .clear }

    /// Tło modułu (np. rozmyta okładka) pod treścią. W Szkle nigdy: zakrywałoby szkło, a biały tekst na okładce
    /// za przejrzystym szkłem był nieczytelny (prośba użytkownika 11.10.2026).
    public var showsModuleBackdrops: Bool { self != .glass }

    /// Szkło tylko tam, gdzie wyspa wychodzi poza notch: rozwinięta albo z kartą pod skrzydłami.
    public func usesGlass(isExpanded: Bool, showsCard: Bool) -> Bool {
        hasGlass && (isExpanded || showsCard)
    }

    /// Przyciemnienie szkła (krycie czarnej warstwy pod przejrzystym szkłem). Zero = jak Centrum sterowania.
    public static let glassTintRange: ClosedRange<Double> = 0...0.9
    public static let defaultGlassTint = 0.3

    /// Przyciemnienie pod kafelkami motywu Przezroczysty (krycie czarnej warstwy pod przejrzystym szkłem). Zero = jak
    /// Centrum sterowania; więcej = czytelniejszy biały tekst nad jasnymi oknami (Apple zaleca warstwę pod `.clear`).
    public static let tileDimmingRange: ClosedRange<Double> = 0...0.6
    public static let defaultTileDimming = 0.25
}
