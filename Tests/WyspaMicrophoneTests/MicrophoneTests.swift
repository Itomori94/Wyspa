import Foundation
import Testing
import WyspaCore
@testable import WyspaMicrophone

@Suite("Mikrofon")
struct MicrophoneTests {
    @Test("Podpis w widżecie: jeden mikrofon z nazwy, kilka — wszystkie")
    func devicesLabel() {
        #expect(MicrophoneModule.devicesLabel(name: "MacBook", count: 1) == "MacBook")
        #expect(MicrophoneModule.devicesLabel(name: "MacBook", count: 3) == "Wszystkie mikrofony (3)")
    }

    private func input(_ uid: String, muted: Bool, canMute: Bool = true, isDefault: Bool = false) -> MicrophoneControl.Input {
        MicrophoneControl.Input(uid: uid, name: uid, isDefault: isDefault, isMuted: muted, canMute: canMute)
    }

    @Test("Wyciszony dopiero, gdy wszystkie mikrofony, które da się wyciszyć, są wyciszone")
    @MainActor
    func allInputsMuted() {
        let headphones = input("słuchawki", muted: true, isDefault: true)
        let macbook = input("macbook", muted: false)
        let iphone = input("iphone", muted: false, canMute: false)
        #expect(!MicrophoneControl.Reading(inputs: [headphones, macbook]).isMuted, "MacBook dalej słyszy — to nie jest wyciszenie")
        let all = MicrophoneControl.Reading(inputs: [headphones, input("macbook", muted: true), iphone])
        #expect(all.isMuted, "mikrofon, którego nie da się wyciszyć, nie blokuje stanu")
        #expect(all.unmutable.map(\.uid) == ["iphone"])
        #expect(all.deviceUIDs == ["słuchawki", "macbook"])
        #expect(all.defaultName == "słuchawki")
        #expect(!MicrophoneControl.Reading(inputs: [iphone]).canMute)
    }

    @Test("Z głośnością liczy się głośność — sama flaga „wycisz” nie wystarcza")
    @MainActor
    func volumeDecides() {
        #expect(!MicrophoneControl.Controls.isMuted(mute: true, volumes: [0.9]), "flaga bez zera głośności nie wycisza Jabbera")
        #expect(MicrophoneControl.Controls.isMuted(mute: false, volumes: [0]))
        #expect(MicrophoneControl.Controls.isMuted(mute: true, volumes: []))
        #expect(!MicrophoneControl.Controls.isMuted(mute: nil, volumes: []))
    }

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

@Suite("Aktywność mikrofonu w wyspie")
@MainActor
struct MicrophoneActivityTests {
    @Test("Jedna aktywność o stałym id i szerokości — ikona nie przeskakuje między stanami")
    func stableActivity() throws {
        let defaults = try #require(UserDefaults(suiteName: "wyspa.mic.activity.\(UUID().uuidString)"))
        let module = MicrophoneModule(context: ModuleContext(settings: SettingsStore(defaults: defaults).moduleSettings(for: "microphone"),
                                                             requestExpand: {}))
        module.showDemo(muted: false)
        #expect(module.liveActivity == nil, "włączony mikrofon bez komunikatu nic nie pokazuje")
        module.showDemo(muted: true)
        let muted = try #require(module.liveActivity)
        #expect(muted.id == "microphone" && muted.wingWidth == MicrophoneModule.wingWidth)
    }

    @Test("Dźwięk wyciszenia i włączenia: różne dźwięki systemowe")
    @MainActor
    func sounds() {
        #expect(MicrophoneModule.soundName(muted: true) != MicrophoneModule.soundName(muted: false))
    }
}
