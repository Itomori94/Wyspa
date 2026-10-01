import IOKit.ps
import Testing
@testable import WyspaPower

@Suite("Stan zasilania")
struct PowerStateTests {
    private func description(current: Int = 80, max: Int = 100, ac: Bool = false, charging: Bool = false,
                             charged: Bool = false, toFull: Int = -1, toEmpty: Int = -1) -> [String: Any] {
        [
            kIOPSTypeKey: kIOPSInternalBatteryType,
            kIOPSCurrentCapacityKey: current,
            kIOPSMaxCapacityKey: max,
            kIOPSPowerSourceStateKey: ac ? kIOPSACPowerValue : kIOPSBatteryPowerValue,
            kIOPSIsChargingKey: charging,
            kIOPSIsChargedKey: charged,
            kIOPSTimeToFullChargeKey: toFull,
            kIOPSTimeToEmptyKey: toEmpty,
        ]
    }

    @Test("Odczyt baterii na zasilaczu")
    func pluggedIn() throws {
        let state = try #require(PowerState.from(description: description(current: 42, ac: true, charging: true, toFull: 75)))
        #expect(state.level == 42 && state.isPluggedIn && state.isCharging)
        #expect(state.minutesToFull == 75)
        #expect(state.statusText == "Ładowanie · pełna za 1 godz. 15 min")
    }

    @Test("Czas -1 oznacza „jeszcze liczy”")
    func unknownTime() throws {
        let state = try #require(PowerState.from(description: description()))
        #expect(state.minutesToEmpty == nil)
        #expect(state.statusText == "Na baterii")
    }

    @Test("Poziom liczony względem pojemności maksymalnej")
    func relativeCapacity() throws {
        #expect(try #require(PowerState.from(description: description(current: 3000, max: 6000))).level == 50)
    }

    @Test("Źródło inne niż bateria wewnętrzna jest pomijane")
    func notInternal() {
        var ups = description()
        ups[kIOPSTypeKey] = kIOPSUPSType
        #expect(PowerState.from(description: ups) == nil)
    }

    @Test("Formatowanie czasu po polsku")
    func durations() {
        #expect(DurationText.format(minutes: 45) == "45 min")
        #expect(DurationText.format(minutes: 60) == "1 godz.")
        #expect(DurationText.format(minutes: 125) == "2 godz. 5 min")
    }
}

@Suite("Zdarzenia zasilania")
struct PowerEventDetectorTests {
    private func state(_ level: Int, plugged: Bool = false, charged: Bool = false) -> PowerState {
        PowerState(level: level, isPluggedIn: plugged, isCharging: plugged && !charged, isCharged: charged)
    }

    @Test("Pierwszy odczyt nie generuje zdarzenia")
    func initial() {
        var detector = PowerEventDetector()
        #expect(detector.update(state(50)) == nil)
    }

    @Test("Podłączenie i odłączenie ładowarki")
    func plugging() {
        var detector = PowerEventDetector()
        _ = detector.update(state(50))
        #expect(detector.update(state(50, plugged: true)) == .pluggedIn)
        #expect(detector.update(state(51, plugged: true)) == nil)
        #expect(detector.update(state(51)) == .unplugged)
    }

    @Test("Pełne naładowanie ogłaszane raz")
    func charged() {
        var detector = PowerEventDetector()
        _ = detector.update(state(99, plugged: true))
        #expect(detector.update(state(100, plugged: true, charged: true)) == .charged)
        #expect(detector.update(state(100, plugged: true, charged: true)) == nil)
    }

    @Test("Progi niskiej baterii ogłaszane raz na rozładowanie")
    func lowBattery() {
        var detector = PowerEventDetector()
        _ = detector.update(state(25))
        #expect(detector.update(state(20)) == .low(threshold: 20))
        #expect(detector.update(state(19)) == nil)
        #expect(detector.update(state(10)) == .low(threshold: 10))
        #expect(detector.update(state(9)) == nil)
    }

    @Test("Spadek o kilka progów naraz daje najniższy")
    func skipThresholds() {
        var detector = PowerEventDetector()
        _ = detector.update(state(30))
        #expect(detector.update(state(8)) == .low(threshold: 10))
        #expect(detector.update(state(7)) == nil)
    }

    @Test("Start poniżej progu nie ogłasza go, ładowanie resetuje progi")
    func startBelowAndReset() {
        var detector = PowerEventDetector()
        _ = detector.update(state(15))
        #expect(detector.update(state(14)) == nil)
        _ = detector.update(state(30, plugged: true))
        _ = detector.update(state(30))
        #expect(detector.update(state(20)) == .low(threshold: 20))
    }
}
