import Foundation
import Testing
@testable import WyspaQuickActions

@Suite("Szybkie akcje")
struct QuickActionsTests {
    @Test("HEX koloru z komponentów, poza zakresem przycinane")
    func hex() {
        #expect(QuickActionsLogic.hex(red: 0.1176, green: 0.5647, blue: 1) == "#1E90FF")
        #expect(QuickActionsLogic.hex(red: -1, green: 2, blue: 0.5) == "#00FF80")
    }

    @Test("Nazwa pliku zrzutu z datą, w podanym katalogu")
    func screenshotName() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 2, hour: 9, minute: 5, second: 7))!
        let url = QuickActionsLogic.screenshotURL(in: URL(fileURLWithPath: "/tmp"), at: date)
        #expect(url.path == "/tmp/Zrzut 2026-10-02 o 09.05.07.png")
    }
}
