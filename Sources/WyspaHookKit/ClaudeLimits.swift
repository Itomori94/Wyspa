import Foundation

/// Limity planu Claude z linii statusu Claude Code (`rate_limits`): okno 5-godzinne i tygodniowe.
public struct ClaudeLimits: Equatable, Sendable {
    public struct Window: Equatable, Sendable {
        /// 0–100 (może przekroczyć 100 po przekroczeniu limitu).
        public let usedPercentage: Double
        public let resetsAt: Date
    }

    public let fiveHour: Window?
    public let sevenDay: Window?

    public init(fiveHour: Window?, sevenDay: Window?) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
    }

    /// `rate_limits` z wejścia linii statusu; `nil`, gdy nie ma żadnego okna (np. konto API bez planu).
    public static func parse(_ object: Any?) -> ClaudeLimits? {
        guard let object = object as? [String: Any] else { return nil }
        let window = { (key: String) -> Window? in
            guard let entry = object[key] as? [String: Any],
                  let used = (entry["used_percentage"] as? NSNumber)?.doubleValue,
                  let reset = (entry["resets_at"] as? NSNumber)?.doubleValue
            else { return nil }
            return Window(usedPercentage: used, resetsAt: Date(timeIntervalSince1970: reset))
        }
        let limits = ClaudeLimits(fiveHour: window("five_hour"), sevenDay: window("seven_day"))
        return limits.fiveHour == nil && limits.sevenDay == nil ? nil : limits
    }

    /// Krótki tekst do linii statusu w terminalu: „5h 23% · tydz. 41%”.
    public var statusLineText: String {
        [fiveHour.map { "5h \(Self.percent($0.usedPercentage))" }, sevenDay.map { "tydz. \(Self.percent($0.usedPercentage))" }]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    public static func percent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }
}
