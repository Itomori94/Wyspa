import Foundation
import Testing
@testable import WyspaCalendar

@Suite("Najbliższe wydarzenie w zwiniętej wyspie")
struct UpcomingEventPolicyTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return calendar
    }()
    var nine: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 2, hour: 9))! }

    private func event(_ id: String, startMinutes: Double, length: Double = 30, allDay: Bool = false) -> DayEvent {
        let start = nine.addingTimeInterval(startMinutes * 60)
        return DayEvent(id: id, title: id, start: start, end: start.addingTimeInterval(length * 60), isAllDay: allDay)
    }

    @Test("Pojawia się 10 minut przed startem, znika 5 minut po")
    func window() {
        let standup = event("standup", startMinutes: 30)
        #expect(UpcomingEventPolicy.activeEvent(in: [standup], at: nine.addingTimeInterval(19 * 60)) == nil)
        #expect(UpcomingEventPolicy.activeEvent(in: [standup], at: nine.addingTimeInterval(20 * 60))?.id == "standup")
        #expect(UpcomingEventPolicy.activeEvent(in: [standup], at: nine.addingTimeInterval(34 * 60))?.id == "standup")
        #expect(UpcomingEventPolicy.activeEvent(in: [standup], at: nine.addingTimeInterval(35 * 60)) == nil)
    }

    @Test("Wydarzenia całodniowe są pomijane, wygrywa wcześniejsze")
    func allDayAndOrder() {
        let events = [event("cały dzień", startMinutes: 5, allDay: true), event("b", startMinutes: 8), event("a", startMinutes: 6)]
        #expect(UpcomingEventPolicy.activeEvent(in: events, at: nine)?.id == "a")
    }

    @Test("Wybudzenie na najbliższą granicę okna, a bez wydarzeń o północy")
    func nextWake() {
        let events = [event("x", startMinutes: 60)]
        #expect(UpcomingEventPolicy.nextWake(for: events, after: nine, calendar: calendar) == nine.addingTimeInterval(50 * 60))
        #expect(UpcomingEventPolicy.nextWake(for: events, after: nine.addingTimeInterval(55 * 60), calendar: calendar)
            == nine.addingTimeInterval(65 * 60))
        let midnight = calendar.date(from: DateComponents(year: 2026, month: 10, day: 3))!
        #expect(UpcomingEventPolicy.nextWake(for: [], after: nine, calendar: calendar) == midnight)
    }

    @Test("Teksty odliczania")
    func texts() {
        let meeting = event("m", startMinutes: 8, length: 30)
        #expect(EventTimeText.countdown(to: meeting, at: nine) == "za 8 min")
        #expect(EventTimeText.short(to: meeting, at: nine.addingTimeInterval(7.5 * 60)) == "1 min")
        #expect(EventTimeText.countdown(to: meeting, at: nine.addingTimeInterval(8 * 60 + 10)) == "teraz")
        #expect(EventTimeText.countdown(to: meeting, at: nine.addingTimeInterval(20 * 60)) == "trwa")
        #expect(EventTimeText.countdown(to: meeting, at: nine.addingTimeInterval(40 * 60)) == "zakończone")
        #expect(EventTimeText.countdown(to: event("d", startMinutes: 130), at: nine) == "za 2 godz.")
    }

    @Test("Link do spotkania w notatkach i miejscu")
    func links() {
        #expect(MeetingLinkFinder.find(in: [nil, "Sala 2", "Dołącz: https://meet.google.com/abc-defg-hij\nAgenda"])?.host
            == "meet.google.com")
        #expect(MeetingLinkFinder.find(in: ["https://us02web.zoom.us/j/1?pwd=x"])?.host == "us02web.zoom.us")
        #expect(MeetingLinkFinder.find(in: ["https://example.com", nil]) == nil)
    }
}
