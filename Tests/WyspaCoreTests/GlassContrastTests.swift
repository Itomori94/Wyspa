import Testing
@testable import WyspaCore

@Suite("Przyciemnienie szkła dobrane do tła")
struct GlassContrastTests {
    @Test("ciemne tło: szkło przejrzyste (zostaje minimum z suwaka)")
    func darkBackground() {
        #expect(GlassContrast.tint(luminance: 0.05, minimum: 0) == 0)
        #expect(GlassContrast.tint(luminance: 0.05, minimum: 0.3) == 0.3)
    }

    @Test("jasne tło: przyciemnienie daje biel z kontrastem 4:1", arguments: [0.3, 0.5, 0.7])
    func brightBackground(luminance: Double) {
        let tint = GlassContrast.tint(luminance: luminance, minimum: 0)
        let background = luminance * (1 - tint)
        #expect(abs(background - GlassContrast.maxBackgroundLuminance) < 0.0001)
    }

    @Test("białe tło: przyciemnienie ograniczone, suwak może dać więcej")
    func whiteBackground() {
        #expect(GlassContrast.tint(luminance: 1, minimum: 0) == GlassContrast.maxAutomaticTint)
        #expect(GlassContrast.tint(luminance: 1, minimum: 0.9) == 0.9)
    }

    @Test("nieznane tło: bezpieczne przyciemnienie")
    func unknownBackground() {
        #expect(GlassContrast.tint(luminance: nil, minimum: 0.2) == GlassContrast.unknownBackgroundTint)
        #expect(GlassContrast.tint(luminance: nil, minimum: 0.7) == 0.7)
    }

    @Test("jasność pikseli: 80. percentyl, nie średnia")
    func percentile() {
        // 7 czarnych i 3 białe piksele: średnia byłaby 0,3, percentyl trafia w biel.
        let pixels = Array(repeating: [UInt8(0), 0, 0, 255], count: 7) + Array(repeating: [UInt8(255), 255, 255, 255], count: 3)
        #expect(GlassContrast.luminance(rgba: pixels.flatMap { $0 }) == 1)
        #expect(GlassContrast.luminance(rgba: Array(repeating: 0, count: 40)) == 0)
        #expect(GlassContrast.luminance(rgba: []) == nil)
    }
}
