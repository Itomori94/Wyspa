import Foundation
import Testing
@testable import WyspaTimer

@Suite("Statystyki skupienia Pomodoro")
struct FocusStatsTests {
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return calendar
    }
    func date(_ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    @Test("Sesje i minuty sumują się w ramach dnia, nowy dzień zaczyna od zera")
    func sums() {
        let stats = FocusStats().recording(minutes: 25, at: date(2, 9), calendar: calendar)
            .recording(minutes: 25, at: date(2, 23), calendar: calendar)
        #expect(stats.today(at: date(2), calendar: calendar) == .init(sessions: 2, minutes: 50))
        #expect(stats.today(at: date(3, 0), calendar: calendar) == .empty)
    }

    @Test("Historia trzyma ostatnie dni, starsze znikają; oryginał bez zmian")
    func pruning() {
        let old = FocusStats().recording(minutes: 25, at: date(1), calendar: calendar)
        let later = old.recording(minutes: 25, at: date(1 + FocusStats.keptDays), calendar: calendar)
        #expect(later.days.count == 1)
        #expect(old.days.count == 1 && old.today(at: date(1), calendar: calendar).sessions == 1)
    }
}
