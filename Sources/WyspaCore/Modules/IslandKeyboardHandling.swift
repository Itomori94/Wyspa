import Foundation

/// Klawisz przekazywany modułowi widocznej strony (sterowanie wyspą z klawiatury po skrócie).
public enum IslandKey: Equatable, Sendable {
    case up
    case down
    case enter
    case backspace
    /// Wpisany tekst (np. wyszukiwanie w schowku bez klikania w pole).
    case text(String)
}

/// Moduł obsługujący klawiaturę, gdy jego widok jest na widocznej stronie.
@MainActor
public protocol IslandKeyboardHandling: IslandModule {
    /// Czy pisanie w rozwiniętej wyspie (poza polem tekstowym) trafia do tego modułu, np. jako wyszukiwanie.
    static var receivesTypedText: Bool { get }
    /// `true`, gdy moduł obsłużył klawisz (wtedy nie trafia on dalej). `whileEditingText` = jakieś pole tekstowe
    /// w wyspie ma klawiaturę — moduł obsługuje wtedy klawisz tylko, gdy to jego pole (np. Enter w notatce obok
    /// schowka nie może wkleić wpisu).
    func handleKey(_ key: IslandKey, whileEditingText: Bool) -> Bool
}

/// Decyzja, co zrobić z naciśniętym klawiszem w rozwiniętej wyspie z klawiaturą. Czysta funkcja (testy).
public enum IslandKeyRouter {
    public enum Action: Equatable, Sendable {
        /// Klawisz idzie dalej (pole tekstowe, skróty z ⌘, nieobsługiwane klawisze).
        case pass
        case collapse
        /// Poprzednia (-1) albo następna (+1) strona.
        case stepTab(Int)
        /// Do modułu widocznej strony; nieobsłużony idzie dalej.
        case forward(IslandKey)
        /// Przejście na stronę modułu przyjmującego pisanie i przekazanie mu tekstu.
        case typeToSearch(String)
    }

    public struct Modifiers: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let command = Modifiers(rawValue: 1 << 0)
        public static let control = Modifiers(rawValue: 1 << 1)
        public static let option = Modifiers(rawValue: 1 << 2)
        public static let shift = Modifiers(rawValue: 1 << 3)
    }

    // Kody klawiszy (Carbon, niezależne od układu klawiatury).
    static let escape: UInt16 = 53
    static let returnKey: UInt16 = 36
    static let keypadEnter: UInt16 = 76
    static let delete: UInt16 = 51
    static let left: UInt16 = 123
    static let right: UInt16 = 124
    static let down: UInt16 = 125
    static let up: UInt16 = 126

    /// `isEditingText` = pole tekstowe w wyspie ma klawiaturę: wtedy tylko ↑ ↓ Enter trafiają do modułu
    /// (lista wyników pod polem wyszukiwania), reszta należy do pola (kursor, Esc z `onExitCommand`).
    public static func route(keyCode: UInt16, characters: String?, modifiers: Modifiers, isEditingText: Bool) -> Action {
        // Skróty z ⌘ i ⌃ (⌘C, ⌘V, ⌃A) zostają dla systemu i pola tekstowego.
        if !modifiers.isDisjoint(with: [.command, .control]) { return .pass }
        switch keyCode {
        case up: return .forward(.up)
        case down: return .forward(.down)
        case returnKey, keypadEnter: return .forward(.enter)
        default: break
        }
        if isEditingText { return .pass }
        switch keyCode {
        case escape: return .collapse
        case left: return modifiers.contains(.option) ? .pass : .stepTab(-1)
        case right: return modifiers.contains(.option) ? .pass : .stepTab(1)
        case delete: return .forward(.backspace)
        default: break
        }
        guard let characters, !characters.isEmpty,
              characters.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) && $0.properties.generalCategory != .privateUse })
        else { return .pass }
        return .typeToSearch(characters)
    }
}
