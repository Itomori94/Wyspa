import Foundation

/// Głośnik AirPlay widoczny w aplikacji Muzyka (MacBook, Apple TV, HomePod…).
public struct AirPlayDevice: Equatable, Identifiable, Sendable {
    public let name: String
    public let kind: String
    public let isSelected: Bool
    public let isAvailable: Bool

    public var id: String { name }

    /// Symbol SF według rodzaju zgłaszanego przez Muzykę.
    public var symbol: String {
        switch kind.lowercased() {
        case "computer": "laptopcomputer"
        case "apple tv": "appletv.fill"
        case "homepod": "homepod.fill"
        case "bluetooth device": "headphones"
        default: "hifispeaker.fill"
        }
    }
}

/// Lista i wybór głośników AirPlay w Muzyce przez AppleScript (czyste funkcje, testowane).
public enum AirPlayScript {
    static let fieldSeparator: Character = "\u{1F}"
    static let recordSeparator: Character = "\u{1E}"

    /// Wszystkie głośniki: nazwa, rodzaj, zaznaczony, dostępny. Uruchamiać tylko, gdy Muzyka działa.
    public static let listScript = """
    tell application "Music"
        set fs to (ASCII character 31)
        set rs to (ASCII character 30)
        set out to ""
        repeat with d in AirPlay devices
            set out to out & (name of d) & fs & ((kind of d) as string) & fs & ((selected of d) as string) & fs & ((available of d) as string) & rs
        end repeat
        return out
    end tell
    """

    public static func parse(_ output: String) -> [AirPlayDevice] {
        output.split(separator: recordSeparator).compactMap { record in
            let fields = record.split(separator: fieldSeparator, omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 4, !fields[0].isEmpty else { return nil }
            return AirPlayDevice(name: fields[0], kind: fields[1], isSelected: fields[2] == "true", isAvailable: fields[3] == "true")
        }
    }

    /// Nowy zestaw zaznaczonych po kliknięciu głośnika: przełącza go, ale nigdy nie zostawia pustego wyboru.
    public static func toggling(_ name: String, in devices: [AirPlayDevice]) -> [String] {
        let selected = devices.filter(\.isSelected).map(\.name)
        let next = selected.contains(name) ? selected.filter { $0 != name } : selected + [name]
        return next.isEmpty ? selected : next
    }

    /// Ustawia zaznaczone głośniki. Nazwy są cytowane bezpiecznie (cudzysłów i ukośnik wsteczny).
    public static func selectScript(_ names: [String]) -> String {
        let list = names.map { "AirPlay device \"\(escape($0))\"" }.joined(separator: ", ")
        return "tell application \"Music\" to set current AirPlay devices to {\(list)}"
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}
