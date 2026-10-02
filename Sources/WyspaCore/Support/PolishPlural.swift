/// Odmiana liczebnika po polsku: 1 element, 2–4 elementy, 5+ elementów, 12–14 elementów, 22 elementy.
public enum PolishPlural {
    public static func format(_ n: Int, one: String, few: String, many: String) -> String {
        "\(n) \(word(for: n, one: one, few: few, many: many))"
    }

    public static func word(for n: Int, one: String, few: String, many: String) -> String {
        if n == 1 { return one }
        let lastDigit = n % 10
        let lastTwo = n % 100
        return (2...4).contains(lastDigit) && !(12...14).contains(lastTwo) ? few : many
    }
}
