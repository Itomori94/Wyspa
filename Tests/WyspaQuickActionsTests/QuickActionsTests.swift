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
        let names = QuickActionsModule.Action.allCases.map(\.rawValue)
        // Pod tymi nazwami są zapisane skróty i wybór widocznych akcji — nie wolno ich zmieniać.
        #expect(Set(["capture", "captureText", "pickColor", "lock", "keepAwake"]).isSubset(of: Set(names)))
        #expect(names == ["capture", "captureScreen", "captureText", "record", "pickColor", "password", "darkMode",
                          "desktopIcons", "lock", "keepAwake"])
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

@Suite("Nowe szybkie akcje i wybór widocznych")
@MainActor
struct QuickActionsSelectionTests {
    private struct SeededGenerator: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return state
        }
    }

    @Test("Hasło: długość, każda grupa znaków, bez mylących znaków, za każdym razem inne")
    func password() {
        var generator = SeededGenerator(state: 42)
        for _ in 0..<50 {
            let password = QuickActionsLogic.password(using: &generator)
            #expect(password.count == QuickActionsLogic.passwordLength)
            #expect(password.contains(where: \.isLowercase) && password.contains(where: \.isUppercase))
            #expect(password.contains(where: \.isNumber) && password.contains(where: { "!@#$%&*-_=+?".contains($0) }))
            #expect(!password.contains(where: { "0O1lI".contains($0) }))
        }
        #expect(QuickActionsLogic.password() != QuickActionsLogic.password())
    }

    @Test("Widoczne akcje: od 2 do 4, kolejność stała")
    func toggling() {
        let order = QuickActionsModule.Action.allCases
        let four: [QuickActionsModule.Action] = [.capture, .captureText, .password, .darkMode]
        #expect(QuickActionsLogic.toggling(.lock, in: four, order: order) == nil, "piąta akcja niedozwolona")
        let three = QuickActionsLogic.toggling(.password, in: four, order: order)
        #expect(three == [.capture, .captureText, .darkMode])
        let two = QuickActionsLogic.toggling(.capture, in: three!, order: order)
        #expect(two == [.captureText, .darkMode])
        #expect(QuickActionsLogic.toggling(.darkMode, in: two!, order: order) == nil, "mniej niż 2 niedozwolone")
        #expect(QuickActionsLogic.toggling(.record, in: two!, order: order) == [.captureText, .record, .darkMode])
    }

    @Test("Wybór zapisuje się; przełącznik zablokowany na granicach")
    func persisted() throws {
        let defaults = try #require(UserDefaults(suiteName: "wyspa.quick.visible.\(UUID().uuidString)"))
        let context = ModuleContext(settings: SettingsStore(defaults: defaults).moduleSettings(for: "quickactions"), requestExpand: {})
        let module = QuickActionsModule(context: context)
        #expect(module.visibleActions == QuickActionsModule.defaultVisible)
        #expect(!module.canToggle(.lock), "przy 4 widocznych nie da się włączyć piątej")
        module.setVisible(.password, false)
        module.setVisible(.lock, true)
        #expect(QuickActionsModule(context: context).visibleActions == [.capture, .captureText, .darkMode, .lock])
        module.setVisible(.capture, false)
        module.setVisible(.captureText, false)
        #expect(module.visibleActions.count == 2 && !module.canToggle(.darkMode))
    }

    @Test("Ikony na biurku: brak ustawienia znaczy widoczne")
    func desktopIcons() {
        #expect(QuickActionsLogic.desktopIconsVisible(nil))
        #expect(!QuickActionsLogic.desktopIconsVisible(false))
        #expect(!QuickActionsLogic.desktopIconsVisible(NSNumber(value: false)))
    }

    @Test("Nagranie: miejsce zrzutów z ustawień systemu, inaczej biurko")
    func recordingLocation() {
        let home = URL(fileURLWithPath: "/Users/demo")
        #expect(QuickActionsLogic.recordingDirectory(systemLocation: "/Users/demo/Movies", home: home).path == "/Users/demo/Movies")
        #expect(QuickActionsLogic.recordingDirectory(systemLocation: nil, home: home).path == "/Users/demo/Desktop")
        #expect(QuickActionsLogic.recordingDirectory(systemLocation: "", home: home).path == "/Users/demo/Desktop")
        #expect(QuickActionsLogic.recordingURL(in: home, at: Date()).pathExtension == "mov")
    }
}
