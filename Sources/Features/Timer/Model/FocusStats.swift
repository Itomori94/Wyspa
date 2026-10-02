import Foundation

/// Ukończone sesje skupienia Pomodoro z ostatnich dni. Niemutowalne, zapisywane w ustawieniach modułu.
public struct FocusStats: Codable, Equatable, Sendable {
    public struct Day: Codable, Equatable, Sendable {
        public let sessions: Int
        public let minutes: Int

        public static let empty = Day(sessions: 0, minutes: 0)
    }

    /// Ile dni historii trzymamy.
    public static let keptDays = 14
    public static let goalRange = 0...16
    public static let defaultGoal = 8

    /// Klucz dnia „rrrr-MM-dd” w lokalnej strefie → wynik dnia.
    public let days: [String: Day]

    public init(days: [String: Day] = [:]) {
        self.days = days
    }

    public func today(at date: Date, calendar: Calendar = .current) -> Day {
        days[Self.key(for: date, calendar: calendar)] ?? .empty
    }

    /// Dopisuje ukończoną sesję skupienia i usuwa dni starsze niż `keptDays`.
    public func recording(minutes: Int, at date: Date, calendar: Calendar = .current) -> FocusStats {
        let key = Self.key(for: date, calendar: calendar)
        let current = days[key] ?? .empty
        var next = days
        next[key] = Day(sessions: current.sessions + 1, minutes: current.minutes + max(minutes, 0))
        let oldest = calendar.date(byAdding: .day, value: -(Self.keptDays - 1), to: calendar.startOfDay(for: date)) ?? date
        let oldestKey = Self.key(for: oldest, calendar: calendar)
        return FocusStats(days: next.filter { $0.key >= oldestKey })
    }

    static func key(for date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
