import Foundation

/// Czyste funkcje Szybkich akcji (testowane).
public enum QuickActionsLogic {
    /// Kolor jako „#RRGGBB” z komponentów 0…1 (przycinanych do zakresu).
    public static func hex(red: Double, green: Double, blue: Double) -> String {
        let byte = { (value: Double) in Int((min(max(value, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
    }

    /// Plik zrzutu w katalogu tymczasowym, z datą w nazwie (tak trafia na Półkę).
    public static func screenshotURL(in directory: URL, at date: Date) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'o' HH.mm.ss"
        return directory.appendingPathComponent("Zrzut \(formatter.string(from: date)).png")
    }
}
