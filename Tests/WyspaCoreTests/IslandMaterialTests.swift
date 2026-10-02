import Foundation
import Testing
@testable import WyspaCore

@Suite("Tło wyspy: Liquid Glass")
@MainActor
struct IslandMaterialTests {
    @Test("Szkło po rozwinięciu i w karcie; zwinięta wyspa bez karty zostaje czarna")
    func glassPhases() {
        let glass = IslandMaterial.liquidGlass
        #expect(glass.usesGlass(phase: .expanded, showsCard: false, systemSupportsGlass: true))
        #expect(glass.usesGlass(phase: .collapsed, showsCard: true, systemSupportsGlass: true))
        #expect(glass.usesGlass(phase: .peek, showsCard: true, systemSupportsGlass: true))
        #expect(!glass.usesGlass(phase: .collapsed, showsCard: false, systemSupportsGlass: true))
        #expect(!glass.usesGlass(phase: .peek, showsCard: false, systemSupportsGlass: true))
        #expect(!glass.usesGlass(phase: .hidden, showsCard: true, systemSupportsGlass: true))
    }

    @Test("Czarny motyw i starszy macOS nigdy nie rysują szkła")
    func neverGlass() {
        for phase in [IslandPhase.hidden, .collapsed, .peek, .expanded] {
            #expect(!IslandMaterial.black.usesGlass(phase: phase, showsCard: true, systemSupportsGlass: true))
            #expect(!IslandMaterial.liquidGlass.usesGlass(phase: phase, showsCard: true, systemSupportsGlass: false))
        }
    }

    @Test("Domyślnie czarny, wybór zapisuje się")
    func persisted() throws {
        let defaults = try #require(UserDefaults(suiteName: "wyspa-material-\(UUID().uuidString)"))
        #expect(SettingsStore(defaults: defaults).islandMaterial == .black)
        SettingsStore(defaults: defaults).islandMaterial = .liquidGlass
        #expect(SettingsStore(defaults: defaults).islandMaterial == .liquidGlass)
    }
}
