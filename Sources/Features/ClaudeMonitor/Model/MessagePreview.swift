import Foundation

/// Krótki, płaski podgląd ostatniej odpowiedzi Claude do karty pod notchem.
public enum MessagePreview {
    public static let limit = 180

    /// Bez znaczników Markdown i bloków kodu, białe znaki zwinięte; `nil`, gdy nic nie zostaje.
    public static func make(_ text: String?) -> String? {
        guard let text else { return nil }
        let withoutCode = text.replacingOccurrences(of: "```[\\s\\S]*?```", with: " ", options: .regularExpression)
        let plain = withoutCode
            .replacingOccurrences(of: "(?m)^\\s{0,3}(#{1,6}|>|[-*+]|\\d+\\.)\\s+", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\[([^\\]]+)\\]\\([^)]*\\)", with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "[*_`|]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !plain.isEmpty else { return nil }
        guard plain.count > limit else { return plain }
        return String(plain.prefix(limit - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }
}
