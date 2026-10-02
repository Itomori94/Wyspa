import Foundation
import Testing
@testable import WyspaCore

@MainActor
@Suite("Magazyn ustawień")
struct SettingsStoreTests {
    private func makeDefaults() -> UserDefaults {
        let name = "wyspa.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test("Wartości domyślne")
    func defaults() {
        let store = SettingsStore(defaults: makeDefaults())
        #expect(store.expandOnHover)
        #expect(store.islandSize == .medium)
        #expect(store.screenSelection == .all)
        #expect(store.virtualNotchMode == .whenActive)
        #expect(store.toggleShortcut == .defaultToggle)
        #expect(store.enabledModules.isEmpty)
    }

    @Test("Zmiany przetrwają ponowne utworzenie magazynu")
    func persistence() {
        let defaults = makeDefaults()
        let store = SettingsStore(defaults: defaults)
        store.hoverDelay = 0.5
        store.islandSize = .large
        store.screenSelection = .notched
        store.setModule("media", enabled: true)

        let reloaded = SettingsStore(defaults: defaults)
        #expect(reloaded.hoverDelay == 0.5)
        #expect(reloaded.islandSize == .large)
        #expect(reloaded.screenSelection == .notched)
        #expect(reloaded.isModuleEnabled("media"))
    }

    @Test("Wyłączony skrót pozostaje wyłączony po restarcie")
    func disabledShortcutPersists() {
        let defaults = makeDefaults()
        SettingsStore(defaults: defaults).toggleShortcut = nil
        #expect(SettingsStore(defaults: defaults).toggleShortcut == nil)
    }

    @Test("Niestandardowy skrót jest zapisywany")
    func customShortcut() {
        let defaults = makeDefaults()
        let shortcut = HotkeyShortcut(keyCode: 49, modifiers: [.command, .shift], keyName: "Spacja")
        SettingsStore(defaults: defaults).toggleShortcut = shortcut
        #expect(SettingsStore(defaults: defaults).toggleShortcut == shortcut)
    }

    @Test("Wartości spoza zakresu są przycinane przy odczycie")
    func clampsInvalidValues() {
        let defaults = makeDefaults()
        defaults.set(42.0, forKey: SettingsStore.Key.hoverDelay)
        defaults.set("gigantyczna", forKey: SettingsStore.Key.islandSize)
        let store = SettingsStore(defaults: defaults)
        #expect(store.hoverDelay == SettingsStore.Limits.hoverDelay.upperBound)
        #expect(store.islandSize == .medium)
    }

    @Test("Ustawienia modułów mają osobne przestrzenie kluczy")
    func moduleNamespaces() {
        let store = SettingsStore(defaults: makeDefaults())
        let timer = store.moduleSettings(for: "timer")
        let notes = store.moduleSettings(for: "notes")
        timer.set(25, for: "minutes")
        #expect(timer.value("minutes", default: 0) == 25)
        #expect(notes.value("minutes", default: 0) == 0)
    }

    @Test("Wyłączenie modułu usuwa go z listy")
    func disableModule() {
        let store = SettingsStore(defaults: makeDefaults())
        store.setModule("shelf", enabled: true)
        store.setModule("shelf", enabled: false)
        #expect(!store.isModuleEnabled("shelf"))
    }
}

@MainActor
@Suite("Kolejność i widoczność zakładek")
struct TabOrderTests {
    private func store() -> SettingsStore {
        SettingsStore(defaults: UserDefaults(suiteName: "wyspa.tabs.\(UUID().uuidString)")!)
    }

    @Test("Bez zapisanej kolejności zostaje kolejność katalogu")
    func defaultOrder() {
        #expect(store().orderedTabs(["media", "shelf", "timer"]) == ["media", "shelf", "timer"])
    }

    @Test("Zapisana kolejność, nowe moduły na końcu")
    func savedOrder() {
        let settings = store()
        settings.setTabOrder(["timer", "media"])
        #expect(settings.orderedTabs(["media", "shelf", "timer", "notes"]) == ["timer", "media", "shelf", "notes"])
    }

    @Test("Duplikaty w kolejności są usuwane, ustawienia przetrwają restart")
    func persistence() {
        let defaults = UserDefaults(suiteName: "wyspa.tabs.\(UUID().uuidString)")!
        let settings = SettingsStore(defaults: defaults)
        settings.setTabOrder(["a", "b", "a"])
        settings.setTab("b", visible: false)
        let reloaded = SettingsStore(defaults: defaults)
        #expect(reloaded.tabOrder == ["a", "b"])
        #expect(reloaded.hiddenTabs == ["b"])
        reloaded.setTab("b", visible: true)
        #expect(reloaded.hiddenTabs.isEmpty)
    }
}

@Suite("Skróty klawiszowe")
struct HotkeyShortcutTests {
    @Test("Symbole modyfikatorów w kolejności macOS")
    func symbols() {
        let modifiers: ShortcutModifiers = [.command, .shift, .option, .control]
        #expect(modifiers.symbols == "⌃⌥⇧⌘")
        #expect(HotkeyShortcut.defaultToggle.displayString == "⌃⌥W")
    }

    @Test("Sam Shift nie wystarcza do skrótu globalnego")
    func validity() {
        #expect(!ShortcutModifiers.shift.isValidForGlobalShortcut)
        #expect(ShortcutModifiers([.shift, .command]).isValidForGlobalShortcut)
    }

    @Test("Flagi Carbon")
    func carbonFlags() {
        // cmdKey = 0x100, optionKey = 0x800
        #expect(ShortcutModifiers([.command, .option]).carbonFlags == 0x900)
    }
}
