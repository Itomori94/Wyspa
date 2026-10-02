import Foundation
import Testing
@testable import WyspaQuickActions
import WyspaCore

@Suite("Szybkie akcje")
struct QuickActionsTests {
    @Test("HEX koloru z komponentów, poza zakresem przycinane")
    func hex() {
        #expect(QuickActionsLogic.hex(red: 0.1176, green: 0.5647, blue: 1) == "#1E90FF")
        #expect(QuickActionsLogic.hex(red: -1, green: 2, blue: 0.5) == "#00FF80")
    }

    @Test("Tekst z OCR: bez pustych wierszy i spacji na brzegach; pusty wynik = nil")
    func recognizedText() {
        #expect(QuickActionsLogic.recognizedText(lines: ["  Zażółć gęślą ", "", "   ", "jaźń"]) == "Zażółć gęślą\njaźń")
        #expect(QuickActionsLogic.recognizedText(lines: [" ", ""]) == nil)
        #expect(QuickActionsLogic.recognizedText(lines: []) == nil)
    }

    @Test("Odmiana liczby wierszy")
    func linesMessage() {
        #expect(QuickActionsLogic.copiedLinesMessage(1).hasSuffix("1 wiersz"))
        #expect(QuickActionsLogic.copiedLinesMessage(3).hasSuffix("3 wiersze"))
        #expect(QuickActionsLogic.copiedLinesMessage(5).hasSuffix("5 wierszy"))
        #expect(QuickActionsLogic.copiedLinesMessage(12).hasSuffix("12 wierszy"))
        #expect(QuickActionsLogic.copiedLinesMessage(22).hasSuffix("22 wiersze"))
    }

    @Test("Nowa akcja nie zmienia zapisanych nazw starych akcji")
    func actionRawValues() {
        #expect(QuickActionsModule.Action.allCases.map(\.rawValue) == ["capture", "captureText", "pickColor", "lock", "keepAwake"])
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

@Suite("Skróty Szybkich akcji", .serialized)
@MainActor
struct QuickActionShortcutTests {
    @Test("Skrót akcji zapisuje się i wraca po ponownym utworzeniu modułu; usunięcie kasuje")
    func persisted() throws {
        let defaults = try #require(UserDefaults(suiteName: "wyspa.quick.\(UUID().uuidString)"))
        let context = ModuleContext(settings: SettingsStore(defaults: defaults).moduleSettings(for: "quickactions"),
                                    requestExpand: {})
        let module = QuickActionsModule(context: context)
        module.setShortcut(.defaultToggle, for: .capture)
        #expect(QuickActionsModule(context: context).shortcuts[.capture] == .defaultToggle)
        module.setShortcut(nil, for: .capture)
        #expect(QuickActionsModule(context: context).shortcuts.isEmpty)
    }
}
