import Foundation
import Testing
@testable import WyspaCore

@Suite("Tło wyspy: Liquid Glass")
@MainActor
struct IslandMaterialTests {
    private func style(_ material: IslandMaterial, _ phase: IslandPhase, card: Bool = false,
                       glass: Bool = true, transparency: Double = 0.6) -> IslandBackgroundStyle {
        material.background(phase: phase, showsCard: card, systemSupportsGlass: glass, transparency: transparency)
    }

    @Test("Szkło po rozwinięciu i w karcie; zwinięta wyspa bez karty zostaje czarna")
    func glassPhases() {
        #expect(style(.liquidGlass, .expanded) == .glass)
        #expect(style(.liquidGlass, .collapsed, card: true) == .glass)
        #expect(style(.liquidGlass, .peek, card: true) == .glass)
        #expect(style(.liquidGlass, .collapsed) == .black)
        #expect(style(.liquidGlass, .peek) == .black)
        #expect(style(.liquidGlass, .hidden, card: true) == .black)
    }

    @Test("Czarny motyw i starszy macOS nigdy nie rysują szkła")
    func neverGlass() {
        for phase in [IslandPhase.hidden, .collapsed, .peek, .expanded] {
            #expect(style(.black, phase, card: true) == .black)
            #expect(style(.liquidGlass, phase, card: true, glass: false) == .black)
        }
    }

    @Test("Przezroczysty: krycie czerni z suwaka, przycięte do zakresu, także bez Liquid Glass")
    func transparent() {
        #expect(style(.transparent, .expanded, transparency: 0.6) == .tinted(blackOpacity: 0.4))
        #expect(style(.transparent, .expanded, glass: false, transparency: 1) == .tinted(blackOpacity: 0))
        #expect(style(.transparent, .expanded, transparency: 1.7) == .tinted(blackOpacity: 0))
        #expect(style(.transparent, .expanded, transparency: -1) == .tinted(blackOpacity: 1))
        #expect(style(.transparent, .collapsed) == .black)
    }

    @Test("Domyślnie czarny, wybór zapisuje się")
    func persisted() throws {
        let defaults = try #require(UserDefaults(suiteName: "wyspa-material-\(UUID().uuidString)"))
        #expect(SettingsStore(defaults: defaults).islandMaterial == .black)
        #expect(SettingsStore(defaults: defaults).islandTransparency == IslandMaterial.defaultTransparency)
        SettingsStore(defaults: defaults).islandMaterial = .transparent
        SettingsStore(defaults: defaults).islandTransparency = 0.8
        #expect(SettingsStore(defaults: defaults).islandMaterial == .transparent)
        #expect(SettingsStore(defaults: defaults).islandTransparency == 0.8)
    }
}

@Suite("Wariant szkła z ustawień systemu")
struct GlassVariantTests {
    @Test("Przezroczyste w systemie (0) daje szkło bez szronu, zabarwione i brak klucza — zwykłe")
    func mapping() {
        #expect(GlassVariant.forSystemTint(0) == .clear)
        #expect(GlassVariant.forSystemTint(0.5) == .regular)
        #expect(GlassVariant.forSystemTint(1) == .regular)
        #expect(GlassVariant.forSystemTint(nil) == .regular)
    }
}
