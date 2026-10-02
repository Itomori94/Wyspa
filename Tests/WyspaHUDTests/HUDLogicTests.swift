import Testing
@testable import WyspaHUD

@Suite("Dekodowanie klawiszy multimedialnych")
struct MediaKeyTests {
    private func data1(code: Int, state: Int, repeat: Bool = false) -> Int {
        (code << 16) | (state << 8) | (`repeat` ? 1 : 0)
    }

    @Test("Wciśnięcie i puszczenie głośności w górę")
    func volumeUp() {
        #expect(MediaKeyEvent.decode(subtype: 8, data1: data1(code: 0, state: 0x0A)) == MediaKeyEvent(key: .volumeUp, isDown: true, isRepeat: false))
        #expect(MediaKeyEvent.decode(subtype: 8, data1: data1(code: 0, state: 0x0B))?.isDown == false)
    }

    @Test("Powtórzenie przy przytrzymaniu")
    func repeatFlag() {
        #expect(MediaKeyEvent.decode(subtype: 8, data1: data1(code: 3, state: 0x0A, repeat: true))?.isRepeat == true)
    }

    @Test("Inny podtyp, nieznany kod albo stan są ignorowane")
    func ignored() {
        #expect(MediaKeyEvent.decode(subtype: 7, data1: data1(code: 0, state: 0x0A)) == nil)
        #expect(MediaKeyEvent.decode(subtype: 8, data1: data1(code: 16, state: 0x0A)) == nil) // play/pauza: nie nasze
        #expect(MediaKeyEvent.decode(subtype: 8, data1: data1(code: 0, state: 0x01)) == nil)
    }
}

@Suite("Kroki poziomu")
struct LevelStepperTests {
    @Test("Krok normalny to 1/16 i trzyma się siatki")
    func normal() {
        #expect(LevelStepper.step(0.5, up: true, size: .normal) == 0.5625)
        #expect(LevelStepper.step(0.30, up: true, size: .normal) == 0.3125)
        #expect(LevelStepper.step(0.30, up: false, size: .normal) == 0.25)
    }

    @Test("Krok precyzyjny to 1/64")
    func fine() {
        #expect(LevelStepper.step(0.5, up: false, size: .fine) == 0.484375)
    }

    @Test("Granice 0 i 1")
    func clamps() {
        #expect(LevelStepper.step(1, up: true, size: .normal) == 1)
        #expect(LevelStepper.step(0, up: false, size: .normal) == 0)
        #expect(LevelStepper.step(0.99, up: true, size: .normal) == 1)
    }

    @Test("Szesnaście kroków w górę od zera daje pełny poziom")
    func sixteenSteps() {
        var level: Float = 0
        for _ in 0..<16 { level = LevelStepper.step(level, up: true, size: .normal) }
        #expect(level == 1)
    }
}

@Suite("Kierowanie klawiszy")
struct HUDKeyRouterTests {
    let all = HUDCapabilities(volume: true, brightness: true, keyboard: true)
    private func down(_ key: MediaKey, repeat: Bool = false) -> MediaKeyEvent { MediaKeyEvent(key: key, isDown: true, isRepeat: `repeat`) }

    @Test("Głośność, jasność i klawiatura")
    func adjusts() {
        #expect(HUDKeyRouter.route(down(.volumeUp), modifiers: [], capabilities: all) == .adjust(.volume, up: true, size: .normal))
        #expect(HUDKeyRouter.route(down(.brightnessDown), modifiers: [], capabilities: all) == .adjust(.brightness, up: false, size: .normal))
        #expect(HUDKeyRouter.route(down(.keyboardBacklightUp), modifiers: [], capabilities: all) == .adjust(.keyboard, up: true, size: .normal))
    }

    @Test("⇧⌥ daje krok precyzyjny, sam ⌥ zostaje dla systemu")
    func modifiers() {
        #expect(HUDKeyRouter.route(down(.volumeUp), modifiers: [.option, .shift], capabilities: all) == .adjust(.volume, up: true, size: .fine))
        #expect(HUDKeyRouter.route(down(.volumeUp), modifiers: [.option], capabilities: all) == .passThrough)
    }

    @Test("Wyłączony albo niedostępny rodzaj przechodzi do systemu")
    func disabledKinds() {
        let noBrightness = HUDCapabilities(volume: true, brightness: false, keyboard: true)
        #expect(HUDKeyRouter.route(down(.brightnessUp), modifiers: [], capabilities: noBrightness) == .passThrough)
        #expect(HUDKeyRouter.route(MediaKeyEvent(key: .brightnessUp, isDown: false, isRepeat: false), modifiers: [], capabilities: noBrightness) == .passThrough)
    }

    @Test("Puszczenie obsługiwanego klawisza jest pochłaniane")
    func keyUp() {
        #expect(HUDKeyRouter.route(MediaKeyEvent(key: .volumeDown, isDown: false, isRepeat: false), modifiers: [], capabilities: all) == .swallow)
    }

    @Test("Wyciszenie i przełącznik podświetlenia nie powtarzają się przy przytrzymaniu")
    func toggles() {
        #expect(HUDKeyRouter.route(down(.mute), modifiers: [], capabilities: all) == .toggleMute)
        #expect(HUDKeyRouter.route(down(.mute, repeat: true), modifiers: [], capabilities: all) == .swallow)
        #expect(HUDKeyRouter.route(down(.keyboardBacklightToggle), modifiers: [], capabilities: all) == .toggleKeyboardBacklight)
    }

    @Test("Symbole odczytu")
    func symbols() {
        #expect(HUDReading(kind: .volume, level: 0.5).symbol == "speaker.wave.3.fill")
        #expect(HUDReading(kind: .volume, level: 0.5, isMuted: true).symbol == "speaker.slash.fill")
        #expect(HUDReading(kind: .volume, level: 0).symbol == "speaker.slash.fill")
        #expect(HUDReading(kind: .keyboard, level: 0).symbol == "light.min")
    }
}

@Suite("Pasek HUD")
struct HUDLevelTests {
    @Test("Poziom spoza zakresu jest przycinany, procent zaokrąglony")
    func clamped() {
        #expect(HUDReading(kind: .volume, level: 1.3).clampedLevel == 1)
        #expect(HUDReading(kind: .volume, level: -0.2).clampedLevel == 0)
        #expect(HUDReading(kind: .volume, level: 0.637).percentText == "64%")
        #expect(HUDReading(kind: .volume, level: 1.3).percentText == "100%")
    }
}
