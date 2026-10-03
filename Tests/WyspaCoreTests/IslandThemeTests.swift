import Foundation
import Testing
@testable import WyspaCore

@Suite("Motyw wyspy")
@MainActor
struct IslandThemeTests {
    private func store() -> (SettingsStore, UserDefaults) {
        let defaults = UserDefaults(suiteName: "wyspa.theme.\(UUID().uuidString)")!
        return (SettingsStore(defaults: defaults), defaults)
    }

    @Test("domyślnie klasyczny, szkło przyciemnione w 60%")
    func defaults() {
        let (settings, _) = store()
        #expect(settings.islandTheme == .classic)
        #expect(settings.glassTint == IslandTheme.defaultGlassTint)
    }

    @Test("motyw i przyciemnienie zapisują się i wracają po ponownym uruchomieniu")
    func persists() {
        let (settings, defaults) = store()
        settings.islandTheme = .blackSheet
        settings.glassTint = 0.8
        let reloaded = SettingsStore(defaults: defaults)
        #expect(reloaded.islandTheme == .blackSheet)
        #expect(reloaded.glassTint == 0.8)
    }

    @Test("przyciemnienie poza zakresem jest przycinane")
    func clampsTint() {
        let (settings, defaults) = store()
        settings.glassTint = 0.05
        #expect(settings.glassTint == IslandTheme.glassTintRange.lowerBound)
        defaults.set(5.0, forKey: SettingsStore.Key.glassTint)
        #expect(SettingsStore(defaults: defaults).glassTint == IslandTheme.glassTintRange.upperBound)
    }

    @Test("nieznany motyw z ustawień: klasyczny")
    func unknownTheme() {
        let (_, defaults) = store()
        defaults.set("neon", forKey: SettingsStore.Key.islandTheme)
        #expect(SettingsStore(defaults: defaults).islandTheme == .classic)
    }

    @Test("szkło tylko w motywie Szkło i tylko poza notchem (rozwinięta albo karta)")
    func glassOnlyWhenRaised() {
        #expect(IslandTheme.glass.usesGlass(isExpanded: true, showsCard: false))
        #expect(IslandTheme.glass.usesGlass(isExpanded: false, showsCard: true))
        #expect(!IslandTheme.glass.usesGlass(isExpanded: false, showsCard: false), "przy notchu zostaje czarna")
        #expect(!IslandTheme.blackSheet.usesGlass(isExpanded: true, showsCard: true))
        #expect(!IslandTheme.classic.usesGlass(isExpanded: true, showsCard: true))
    }

    @Test("zapisane nazwy motywów są stałe")
    func rawValues() {
        #expect(IslandTheme.allCases.map(\.rawValue) == ["classic", "black-sheet", "glass"])
    }
}

@Suite("Siła haptyki")
@MainActor
struct HapticStrengthTests {
    @Test("delikatna to publiczne API, mocniejsze to impulsy silnika gładzika")
    func actuationIDs() {
        #expect(HapticStrength.gentle.actuationID == nil)
        #expect(HapticStrength.medium.actuationID == 4)
        #expect(HapticStrength.strong.actuationID == 6)
        #expect(HapticStrength.allCases.map(\.rawValue) == ["gentle", "medium", "strong"])
    }

    @Test("domyślnie delikatna; wybór zapisuje się, nieznana wartość wraca do delikatnej")
    func persists() {
        let defaults = UserDefaults(suiteName: "wyspa.haptics.\(UUID().uuidString)")!
        let settings = SettingsStore(defaults: defaults)
        #expect(settings.hapticStrength == .gentle)
        settings.hapticStrength = .strong
        #expect(SettingsStore(defaults: defaults).hapticStrength == .strong)
        defaults.set("tornado", forKey: SettingsStore.Key.hapticStrength)
        #expect(SettingsStore(defaults: defaults).hapticStrength == .gentle)
    }
}
