import Foundation

public struct DayEvent: Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let start: Date
    public let end: Date
    public let isAllDay: Bool
    public let location: String?
    public let joinURL: URL?
    /// Kolor kalendarza jako sRGB (0–1).
    public let color: [Double]

    public init(id: String, title: String, start: Date, end: Date, isAllDay: Bool = false,
                location: String? = nil, joinURL: URL? = nil, color: [Double] = [0.3, 0.6, 1]) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.location = location
        self.joinURL = joinURL
        self.color = color
    }
}

/// Kiedy pokazać wydarzenie w zwiniętej wyspie i kiedy obudzić się następnym razem (bez odpytywania).
public enum UpcomingEventPolicy {
    /// Wydarzenie pojawia się 10 minut przed startem…
    public static let leadTime: TimeInterval = 10 * 60
    /// …i znika 5 minut po starcie.
    public static let lingerAfterStart: TimeInterval = 5 * 60

    public static func activeEvent(in events: [DayEvent], at now: Date) -> DayEvent? {
        events
            .filter { !$0.isAllDay && $0.start.addingTimeInterval(-leadTime) <= now && now < $0.start.addingTimeInterval(lingerAfterStart) }
            .min { $0.start < $1.start }
    }

    /// Najbliższa chwila, w której zmieni się to, co pokazać: wejście lub wyjście z okna aktywności albo północ.
    public static func nextWake(for events: [DayEvent], after now: Date, calendar: Calendar = .current) -> Date {
        let boundaries = events.filter { !$0.isAllDay }.flatMap {
            [$0.start.addingTimeInterval(-leadTime), $0.start.addingTimeInterval(lingerAfterStart)]
        }
        let midnight = calendar.startOfDay(for: now).addingTimeInterval(24 * 3600)
        return (boundaries + [midnight]).filter { $0 > now }.min() ?? midnight
    }
}

/// Link do wideokonferencji w polach wydarzenia (URL, miejsce, notatki).
public enum MeetingLinkFinder {
    private static let pattern = #"https://[^\s<>"]*(meet\.google\.com|zoom\.us|teams\.microsoft\.com|teams\.live\.com|webex\.com|whereby\.com|meet\.jit\.si|facetime\.apple\.com)[^\s<>"]*"#
    private static let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)

    public static func find(in fields: [String?]) -> URL? {
        guard let regex else { return nil }
        for text in fields.compactMap({ $0 }) {
            let range = NSRange(text.startIndex..., in: text)
            if let match = regex.firstMatch(in: text, range: range), let swiftRange = Range(match.range, in: text) {
                return URL(string: String(text[swiftRange]))
            }
        }
        return nil
    }
}

public enum EventTimeText {
    /// „za 8 min”, „teraz”, „trwa”, „zakończone”.
    public static func countdown(to event: DayEvent, at now: Date) -> String {
        if now >= event.end { return "zakończone" }
        if now >= event.start { return now.timeIntervalSince(event.start) < 60 ? "teraz" : "trwa" }
        let minutes = Int((event.start.timeIntervalSince(now) / 60).rounded(.up))
        return minutes < 60 ? "za \(minutes) min" : "za \(minutes / 60) godz."
    }

    /// Krótka forma do skrzydła wyspy: „8 min”, „teraz”.
    public static func short(to event: DayEvent, at now: Date) -> String {
        guard now < event.start else { return "teraz" }
        return "\(Int((event.start.timeIntervalSince(now) / 60).rounded(.up))) min"
    }
}
