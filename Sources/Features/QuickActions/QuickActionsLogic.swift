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

    /// Plik zrzutu w katalogu tymczasowym, z datą w nazwie (tak trafia na Półkę).
    public static func screenshotURL(in directory: URL, at date: Date) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'o' HH.mm.ss"
        return directory.appendingPathComponent("Zrzut \(formatter.string(from: date)).png")
    }
}
