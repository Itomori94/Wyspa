import AppKit
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

    @Test("Miejsca: wybór akcji zamienia z innym miejscem, najmniej 2 włączone")
    func slots() {
        typealias Slot = ActionSlot<QuickActionsModule.Action>
        let slots = QuickActionsModule.defaultSlots
        #expect(slots.count == QuickActionsLogic.slotCount && slots.allSatisfy(\.isEnabled))
        let swapped = QuickActionsLogic.choosing(.keepAwake, at: 0, in: slots)
        #expect(swapped[0].action == .keepAwake && swapped[7].action == .capture, "zamiana zamiast duplikatu")
        let fresh = QuickActionsLogic.choosing(.lock, at: 1, in: slots)
        #expect(fresh[1].action == .lock && Set(fresh.map(\.action)).count == 8)
        var current = slots
        for index in 0..<6 { current = QuickActionsLogic.setting(false, at: index, in: current)! }
        #expect(current.filter(\.isEnabled).count == 2)
        #expect(QuickActionsLogic.setting(false, at: 6, in: current) == nil, "mniej niż 2 niedozwolone")
        #expect(QuickActionsLogic.setting(true, at: 0, in: current) != nil)
    }

    @Test("Zapis miejsc i odrzucenie uszkodzonego zapisu")
    func persisted() throws {
        let defaults = try #require(UserDefaults(suiteName: "wyspa.quick.slots.\(UUID().uuidString)"))
        let context = ModuleContext(settings: SettingsStore(defaults: defaults).moduleSettings(for: "quickactions"), requestExpand: {})
        let module = QuickActionsModule(context: context)
        #expect(module.visibleActions.count == 8)
        module.chooseAction(.desktopIcons, at: 2)
        module.setSlot(false, at: 3)
        let restored = QuickActionsModule(context: context)
        #expect(restored.slots[2].action == .desktopIcons && !restored.slots[3].isEnabled)
        #expect(restored.visibleActions.count == 7 && restored.canSetSlot(true, at: 3))
        let broken = [ActionSlot(action: QuickActionsModule.Action.capture, isEnabled: true)]
        #expect(QuickActionsLogic.validated(broken, default: QuickActionsModule.defaultSlots) == QuickActionsModule.defaultSlots)
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

@Suite("Kratka szybkich akcji")
struct QuickActionsGridTests {
    @Test("Liczba kolumn rośnie z szerokością, najwyżej 4 i nie więcej niż kafelków")
    func columns() {
        #expect(QuickActionsView.columnCount(width: 150, compact: true, tiles: 8) == 2)
        #expect(QuickActionsView.columnCount(width: 230, compact: true, tiles: 8) == 3)
        #expect(QuickActionsView.columnCount(width: 600, compact: true, tiles: 8) == 4)
        #expect(QuickActionsView.columnCount(width: 600, compact: true, tiles: 2) == 2)
        #expect(QuickActionsView.columnCount(width: 40, compact: true, tiles: 8) == 1)
        #expect(QuickActionsView.columnCount(width: 532, compact: false, tiles: 8) == 4)
    }

    @Test("Wysokość kafelków: wszystkie rzędy mieszczą się w miejscu; niski kafelek zmienia układ")
    func tileHeight() {
        // Mała wyspa: ok. 116 pt na dwa rzędy po 4 — kafelki niższe, ale nic nie wystaje.
        let small = QuickActionsView.tileHeight(available: 116, tiles: 8, columns: 4)
        #expect(small * 2 + QuickActionsView.spacing <= 116 && small == 54)
        #expect(QuickActionsView.tileHeight(available: 400, tiles: 8, columns: 4) == QuickActionsView.maxTileHeight)
        #expect(QuickActionsView.tileHeight(available: 150, tiles: 8, columns: 2) * 4 + 3 * QuickActionsView.spacing <= 150)
        #expect(ActionTileLayout(height: 60) == .stacked && ActionTileLayout(height: 40) == .inline && ActionTileLayout(height: 20) == .iconOnly)
        #expect(ActionTileLayout(height: 40, width: 80) == .iconOnly, "wąski i niski kafelek: sama ikona zamiast uciętego napisu")
    }
}

@Suite("Animacje kafelków")
@MainActor
struct QuickActionsTileSpecTests {
    @Test("Włączone stany to jasny kafelek, bez animacji w kółko")
    func onStates() {
        let on = TileSpec.State(isDarkMode: true, desktopIconsVisible: false, isKeepingAwake: true, isRecording: true)
        for action in [QuickActionsModule.Action.darkMode, .desktopIcons, .keepAwake, .record] {
            #expect(TileSpec.make(action, state: on, compact: false).isOn, "\(action)")
        }
        #expect(TileSpec.make(.record, state: on, compact: false).symbol == "record.circle.fill")
        #expect(!TileSpec.make(.record, state: .init(), compact: false).isOn)
    }

    @Test("Symbole i efekty w stanie spoczynku")
    func specs() throws {
        let defaults = try #require(UserDefaults(suiteName: "wyspa.quick.tiles.\(UUID().uuidString)"))
        let module = QuickActionsModule(context: ModuleContext(settings: SettingsStore(defaults: defaults).moduleSettings(for: "quickactions"),
                                                               requestExpand: {}))
        let spec = { (action: QuickActionsModule.Action) in TileSpec.make(action, module: module, compact: false) }
        #expect(spec(.lock).symbol == "lock.open.fill", "kłódka zatrzaskuje się dopiero po kliknięciu")
        #expect(spec(.keepAwake).symbol == "cup.and.saucer" && !spec(.keepAwake).isOn)
        #expect(spec(.password).tapEffect == .rotate && spec(.pickColor).tapEffect == .wiggle)
        #expect(spec(.captureText).busyEffect == .breathe)
        #expect(["eye", "eye.slash"].contains(spec(.desktopIcons).symbol))
        #expect(QuickActionsModule.Action.allCases.allSatisfy { NSImage(systemSymbolName: spec($0).symbol, accessibilityDescription: nil) != nil },
                "każdy symbol istnieje w systemie")
        #expect(["cup.and.heat.waves.fill", "lock.fill", "checkmark.circle.fill", "moon.fill", "sun.max.fill", "mic.slash.fill"]
            .allSatisfy { NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil })
    }
}
