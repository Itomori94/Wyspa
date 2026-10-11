import Foundation

/// Przyciemnienie przejrzystego szkła (motyw Szkło) dobrane do jasności tego, co leży pod wyspą: nad ciemnym pulpitem
/// szkło zostaje przejrzyste, nad jasnym ciemnieje na tyle, żeby biały tekst był czytelny. Suwak użytkownika to minimum.
public enum GlassContrast {
    /// Najjaśniejsze dopuszczalne tło pod białym tekstem (luminancja względna). Kontrast bieli z takim tłem to
    /// (1 + 0,05) / (0,2125 + 0,05) = 4:1 — prawie poziom WCAG AA dla zwykłego tekstu.
    static let maxBackgroundLuminance = 0.2125
    /// Najmocniejsze przyciemnienie automatyczne (wyżej szkła już prawie nie widać).
    static let maxAutomaticTint = 0.8
    /// Nieznane tło (np. okno innej aplikacji pod wyspą — jego wyglądu nie znamy bez nagrywania ekranu).
    static let unknownBackgroundTint = 0.5

    /// Krycie czarnej warstwy nad szkłem dla tła o jasności `luminance` (nil = nieznane); nigdy poniżej `minimum`.
    public static func tint(luminance: Double?, minimum: Double) -> Double {
        guard let luminance else { return max(minimum, unknownBackgroundTint) }
        // Czerń o kryciu t daje tło L · (1 − t); szukamy t, przy którym tło nie przekracza progu.
        let needed = luminance <= maxBackgroundLuminance ? 0 : 1 - maxBackgroundLuminance / luminance
        return max(minimum, min(needed, maxAutomaticTint))
    }

    /// Jasność tła pod tekstem: 80. percentyl luminancji względnej pikseli RGBA (8 bitów, sRGB). Percentyl zamiast
    /// średniej, bo tekst trafia też na jasne fragmenty — ciemna reszta nie może ich „uśrednić”.
    public static func luminance(rgba: [UInt8]) -> Double? {
        let count = rgba.count / 4
        guard count > 0 else { return nil }
        var values = [Double]()
        values.reserveCapacity(count)
        for index in 0..<count {
            let base = index * 4
            let red = linear(rgba[base]), green = linear(rgba[base + 1]), blue = linear(rgba[base + 2])
            values.append(0.2126 * red + 0.7152 * green + 0.0722 * blue)
        }
        values.sort()
        return values[min(values.count - 1, Int(Double(values.count) * 0.8))]
    }

    private static func linear(_ component: UInt8) -> Double {
        let value = Double(component) / 255
        return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }
}
