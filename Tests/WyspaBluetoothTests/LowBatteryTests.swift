import Testing
@testable import WyspaBluetooth

@Suite("Ostrzeżenie o słabej baterii")
struct LowBatteryTests {
    private func device(_ id: String, _ level: Int?) -> ConnectedDevice {
        ConnectedDevice(id: id, name: id, kind: .airPods, battery: BatteryLevels(single: level))
    }

    @Test("Raz na rozładowanie, ponownie po naładowaniu powyżej progu powrotu")
    func hysteresis() {
        var tracker = LowBatteryTracker()
        var alerts: [ConnectedDevice]
        (tracker, alerts) = tracker.evaluating([device("a", 50)])
        #expect(alerts.isEmpty)
        (tracker, alerts) = tracker.evaluating([device("a", 18)])
        #expect(alerts.map(\.id) == ["a"])
        (tracker, alerts) = tracker.evaluating([device("a", 15)])
        #expect(alerts.isEmpty)
        (tracker, alerts) = tracker.evaluating([device("a", 25)])
        (tracker, alerts) = tracker.evaluating([device("a", 19)])
        #expect(alerts.isEmpty, "bez naładowania do 30% nie ostrzega drugi raz")
        (tracker, alerts) = tracker.evaluating([device("a", 80)])
        (tracker, alerts) = tracker.evaluating([device("a", 10)])
        #expect(alerts.map(\.id) == ["a"])
    }

    @Test("Bez poziomu baterii nic; odłączone urządzenie wypada ze stanu")
    func unknownAndDisconnected() {
        var (tracker, alerts) = LowBatteryTracker().evaluating([device("a", nil), device("b", 5)])
        #expect(alerts.map(\.id) == ["b"])
        (tracker, alerts) = tracker.evaluating([])
        #expect(tracker.warned.isEmpty)
        (_, alerts) = tracker.evaluating([device("b", 5)])
        #expect(alerts.map(\.id) == ["b"])
    }
}
