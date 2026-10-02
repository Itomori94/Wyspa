import Foundation

/// Czyste funkcje Szybkich akcji (testowane).
public enum QuickActionsLogic {
    /// Kolor jako „#RRGGBB” z komponentów 0…1 (przycinanych do zakresu).
    public static func hex(red: Double, green: Double, blue: Double) -> String {
        let byte = { (value: Double) in Int((min(max(value, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
    }

    /// Tekst z OCR do schowka: wiersze bez pustych i bez spacji na brzegach; nil, gdy nic nie rozpoznano.
    public static func recognizedText(lines: [String]) -> String? {
        let cleaned = lines.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return cleaned.isEmpty ? nil : cleaned.joined(separator: "\n")
    }

    /// Komunikat po OCR: „Skopiowano 1 wiersz / 3 wiersze / 5 wierszy”.
    public static func copiedLinesMessage(_ count: Int) -> String {
        let lastTwo = count % 100
        let last = count % 10
        let noun: String
        if count == 1 {
            noun = "wiersz"
        } else if (2...4).contains(last) && !(12...14).contains(lastTwo) {
            noun = "wiersze"
        } else {
            noun = "wierszy"
        }
        return "Skopiowano tekst: \(count) \(noun)"
    }

    // MARK: - Miejsca na akcje

    /// Stałe miejsca na kafelki w wyspie; w każdym wybrana akcja i przełącznik.
    public static let slotCount = 8
    public static let minimumEnabled = 2

    /// Wybór akcji w miejscu. Gdy ta akcja jest już w innym miejscu, miejsca zamieniają się akcjami (bez duplikatów).
    public static func choosing<Action: Hashable>(_ action: Action, at index: Int, in slots: [ActionSlot<Action>]) -> [ActionSlot<Action>] {
        guard slots.indices.contains(index) else { return slots }
        let previous = slots[index].action
        return slots.enumerated().map { offset, slot in
            if offset == index { return ActionSlot(action: action, isEnabled: slot.isEnabled) }
            if slot.action == action { return ActionSlot(action: previous, isEnabled: slot.isEnabled) }
            return slot
        }
    }

    /// Włączenie albo wyłączenie miejsca; `nil`, gdy zostałoby mniej niż 2 włączone.
    public static func setting<Action: Hashable>(_ enabled: Bool, at index: Int, in slots: [ActionSlot<Action>]) -> [ActionSlot<Action>]? {
        guard slots.indices.contains(index) else { return nil }
        let next = slots.enumerated().map { offset, slot in
            offset == index ? ActionSlot(action: slot.action, isEnabled: enabled) : slot
        }
        return next.filter(\.isEnabled).count >= minimumEnabled ? next : nil
    }

    /// Zapisane miejsca albo domyślne, gdy zapis jest niepełny, ma powtórki albo za mało włączonych.
    public static func validated<Action: Hashable>(_ slots: [ActionSlot<Action>]?, default fallback: [ActionSlot<Action>]) -> [ActionSlot<Action>] {
        guard let slots, slots.count == slotCount, Set(slots.map(\.action)).count == slotCount,
              slots.filter(\.isEnabled).count >= minimumEnabled
        else { return fallback }
        return slots
    }

    // MARK: - Hasło

    /// Znaki hasła bez łatwych do pomylenia (0/O, 1/l/I) i bez znaków kłopotliwych w polach formularzy.
    static let lowercase = Array("abcdefghijkmnopqrstuvwxyz")
    static let uppercase = Array("ABCDEFGHJKLMNPQRSTUVWXYZ")
    static let digits = Array("23456789")
    static let symbols = Array("!@#$%&*-_=+?")
    public static let passwordLength = 20

    /// Losowe hasło z każdą grupą znaków przynajmniej raz (generator kryptograficzny systemu).
    public static func password<Generator: RandomNumberGenerator>(length: Int = passwordLength,
                                                                   using generator: inout Generator) -> String {
        let groups = [lowercase, uppercase, digits, symbols]
        let all = groups.flatMap { $0 }
        let required = groups.map { $0.randomElement(using: &generator)! }
        let rest = (0..<max(length - required.count, 0)).map { _ in all.randomElement(using: &generator)! }
        return String((required + rest).shuffled(using: &generator))
    }

    public static func password(length: Int = passwordLength) -> String {
        var generator = SystemRandomNumberGenerator()
        return password(length: length, using: &generator)
    }

    // MARK: - Wygląd i biurko

    /// Przełączenie trybu ciemnego przez System Events (publiczny słownik AppleScript).
    public static let toggleDarkModeScript = """
    tell application "System Events" to tell appearance preferences to set dark mode to not dark mode
    """

    /// Ikony na biurku: ustawienie Findera `CreateDesktop` (brak wpisu = ikony widoczne).
    public static func desktopIconsVisible(_ value: Any?) -> Bool {
        (value as? Bool) ?? (value as? NSNumber)?.boolValue ?? true
    }

    /// Miejsce zapisu nagrań: to samo co zrzutów w ustawieniach systemu (`com.apple.screencapture location`), inaczej biurko.
    public static func recordingDirectory(systemLocation: String?, home: URL) -> URL {
        if let systemLocation, !systemLocation.isEmpty {
            let expanded = (systemLocation as NSString).expandingTildeInPath
            if expanded.hasPrefix("/") { return URL(fileURLWithPath: expanded, isDirectory: true) }
        }
        return home.appendingPathComponent("Desktop", isDirectory: true)
    }

    public static func recordingURL(in directory: URL, at date: Date) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'o' HH.mm.ss"
        return directory.appendingPathComponent("Nagranie ekranu \(formatter.string(from: date)).mov")
    }

    /// Plik zrzutu w katalogu tymczasowym, z datą w nazwie (tak trafia na Półkę).
    public static func screenshotURL(in directory: URL, at date: Date) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'o' HH.mm.ss"
        return directory.appendingPathComponent("Zrzut \(formatter.string(from: date)).png")
    }
}

/// Miejsce na kafelek szybkiej akcji.
public struct ActionSlot<Action: Hashable>: Hashable {
    public let action: Action
    public let isEnabled: Bool

    public init(action: Action, isEnabled: Bool) {
        self.action = action
        self.isEnabled = isEnabled
    }
}

extension ActionSlot: Codable where Action: Codable {}
extension ActionSlot: Sendable where Action: Sendable {}
