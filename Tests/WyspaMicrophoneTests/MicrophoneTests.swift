import Foundation
import Testing
import WyspaCore
@testable import WyspaMicrophone

@Suite("Mikrofon")
struct MicrophoneTests {
    @Test("Przywracana głośność: zapamiętana, a bez niej albo przy zerze — 75%")
    func restoredVolume() {
        #expect(MicrophoneControl.restoredVolume(0.42) == 0.42)
        #expect(MicrophoneControl.restoredVolume(nil) == MicrophoneControl.fallbackVolume)
        #expect(MicrophoneControl.restoredVolume(0) == MicrophoneControl.fallbackVolume)
        #expect(MicrophoneControl.restoredVolume(3) == 1)
    }

    @Test("Zapis skrótu odróżnia „bez skrótu” od domyślnego")
    func storedShortcut() throws {
        let cleared = try JSONDecoder().decode(StoredShortcut.self, from: JSONEncoder().encode(StoredShortcut(shortcut: nil)))
        #expect(cleared.shortcut == nil)
        let custom = HotkeyShortcut(keyCode: 46, modifiers: [.command, .shift], keyName: "M")
        let stored = try JSONDecoder().decode(StoredShortcut.self, from: JSONEncoder().encode(StoredShortcut(shortcut: custom)))
        #expect(stored.shortcut == custom)
    }

    @Test("Domyślny skrót ⌃⌥M jest poprawnym skrótem globalnym")
    @MainActor
    func defaultShortcut() {
        #expect(MicrophoneModule.defaultShortcut.modifiers.isValidForGlobalShortcut)
        #expect(MicrophoneModule.defaultShortcut.displayString == "⌃⌥M")
    }
}
