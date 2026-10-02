import Testing
@testable import WyspaCore

@Suite("Tryb prywatny")
@MainActor
struct PrivacyStateTests {
    @Test("Automatycznie: aktywny tylko przy przechwytywaniu ekranu; Zawsze i Nigdy bez wykrywania")
    func modes() {
        final class Box { var captured = false; var mode = PrivacyState.Mode.automatic; var detections = 0 }
        let box = Box()
        let state = PrivacyState(mode: { box.mode }, isScreenCaptured: { box.detections += 1; return box.captured })
        #expect(!state.refresh())
        box.captured = true
        #expect(state.refresh() && state.isActive)
        box.mode = .off
        #expect(!state.refresh())
        box.mode = .always
        box.captured = false
        #expect(state.refresh())
        #expect(box.detections == 2, "wykrywanie tylko w trybie automatycznym")
    }

    @Test("Nazwy trybów")
    func names() {
        #expect(Set(PrivacyState.Mode.allCases.map(\.displayName)).count == 3)
    }
}
