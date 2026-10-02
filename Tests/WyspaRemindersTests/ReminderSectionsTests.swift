import Foundation
import Testing
@testable import WyspaReminders

@Suite("Przypomnienia na dziś")
struct ReminderSectionsTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return calendar
    }()
    var noon: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 2, hour: 12))! }

    @Test("Podział na zaległe i dzisiejsze")
    func grouping() {
        let items = [
            ReminderItem(id: "wczoraj", title: "A", due: noon.addingTimeInterval(-86_400), listName: "L"),
            ReminderItem(id: "dziś", title: "B", due: noon.addingTimeInterval(3600), listName: "L"),
            ReminderItem(id: "jutro", title: "C", due: noon.addingTimeInterval(86_400), listName: "L"),
        ]
        let grouped = ReminderSections.group(items, now: noon, calendar: calendar)
        #expect(grouped.overdue.map(\.id) == ["wczoraj"])
        #expect(grouped.today.map(\.id) == ["dziś"])
    }

    @Test("Wysoki priorytet na górze, potem wcześniejszy termin")
    func ordering() {
        let items = [
            ReminderItem(id: "zwykłe-wcześniej", title: "", due: noon, listName: "", priority: 0),
            ReminderItem(id: "pilne", title: "", due: noon.addingTimeInterval(3000), listName: "", priority: 1),
            ReminderItem(id: "zwykłe-później", title: "", due: noon.addingTimeInterval(600), listName: "", priority: 0),
        ]
        #expect(ReminderSections.group(items, now: noon, calendar: calendar).today.map(\.id)
            == ["pilne", "zwykłe-wcześniej", "zwykłe-później"])
    }
}
