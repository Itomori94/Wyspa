import Testing
@testable import WyspaCore

@Suite("Tryb prywatny")
@MainActor
struct PrivacyStateTests {
    @Test("Automatycznie: aktywny tylko przy przechwytywaniu ekranu; Zawsze i Nigdy bez wykrywania")
    func modes() {
        var captured = false
        var mode = PrivacyState.Mode.automatic
        var detections = 0
        let state = PrivacyState(mode: { mode }, isScreenCaptured: { detections += 1; return captured })
        #expect(!state.refresh())
        captured = true
        #expect(state.refresh() && state.isActive)
        mode = .off
        #expect(!state.refresh())
        mode = .always
        captured = false
        #expect(state.refresh())
        #expect(detections == 2, "wykrywanie tylko w trybie automatycznym")
    }

    @Test("Nazwy trybów")
    func names() {
        #expect(Set(PrivacyState.Mode.allCases.map(\.displayName)).count == 3)
    }
}
