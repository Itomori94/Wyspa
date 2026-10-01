import Testing
@testable import WyspaBluetooth

@Suite("Bateria urządzeń Bluetooth")
struct BatteryLevelsTests {
    @Test("Słuchawki douszne: słabsza słuchawka")
    func earbuds() {
        #expect(BatteryLevels(left: 80, right: 65, caseLevel: 40).summary == 65)
    }

    @Test("Urządzenie z jedną wartością")
    func single() {
        #expect(BatteryLevels(single: 55).summary == 55)
        #expect(BatteryLevels(combined: 70).summary == 70)
    }

    @Test("Zero i wartości spoza zakresu oznaczają brak danych")
    func unknown() {
        let levels = BatteryLevels(single: 0, left: 0, right: 120, caseLevel: 0)
        #expect(levels.summary == nil)
        #expect(levels.isEmpty)
    }

    @Test("Tylko etui")
    func caseOnly() {
        let levels = BatteryLevels(caseLevel: 30)
        #expect(levels.summary == nil && !levels.isEmpty)
    }
}

@Suite("Rodzaje urządzeń")
struct DeviceKindTests {
    @Test("AirPods po nazwie")
    func airPods() {
        #expect(DeviceKind.classify(name: "AirPods Pro użytkownika", majorClass: 0x04, minorClass: 0x06) == .airPodsPro)
        #expect(DeviceKind.classify(name: "AirPods Max", majorClass: 0x04, minorClass: 0x06) == .airPodsMax)
        #expect(DeviceKind.classify(name: "AirPods", majorClass: 0x04, minorClass: 0x06) == .airPods)
    }

    @Test("Klasa audio: słuchawki albo głośnik")
    func audioClass() {
        #expect(DeviceKind.classify(name: "WH-1000XM5", majorClass: 0x04, minorClass: 0x06) == .headphones)
        #expect(DeviceKind.classify(name: "Boom 3", majorClass: 0x04, minorClass: 0x05) == .speaker)
    }

    @Test("Urządzenia peryferyjne po klasie i nazwie")
    func peripherals() {
        #expect(DeviceKind.classify(name: "MX Keys", majorClass: 0x05, minorClass: 0x10) == .keyboard)
        #expect(DeviceKind.classify(name: "MX Master", majorClass: 0x05, minorClass: 0x20) == .mouse)
        #expect(DeviceKind.classify(name: "Magic Trackpad", majorClass: 0x05, minorClass: 0x20) == .trackpad)
        #expect(DeviceKind.classify(name: "Xbox Wireless Controller", majorClass: 0x05, minorClass: 0x08) == .gamepad)
        #expect(DeviceKind.classify(name: "Coś", majorClass: 0x01, minorClass: 0) == .other)
    }
}
