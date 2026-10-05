import CoreGraphics
import Foundation
import Testing
@testable import WyspaMedia

@Suite("Wybór źródła mediów")
struct MediaSourceSelectionTests {
    @Test("Automatycznie: działający adapter")
    func automaticAdapter() {
        #expect(MediaSourceSelector.decide(preference: .automatic, adapter: .functional).kind == .adapter)
    }

    @Test("Automatycznie: zepsuty adapter przechodzi na AppleScript z powodem")
    func automaticFallback() {
        let decision = MediaSourceSelector.decide(preference: .automatic, adapter: .broken(reason: "kod 1"))
        #expect(decision.kind == .appleScript)
        #expect(decision.reason.contains("kod 1"))
    }

    @Test("Wybór ręczny jest respektowany, z ostrzeżeniem przy zepsutym adapterze")
    func manual() {
        #expect(MediaSourceSelector.decide(preference: .appleScript, adapter: .functional).kind == .appleScript)
        let forced = MediaSourceSelector.decide(preference: .adapter, adapter: .broken(reason: "x"))
        #expect(forced.kind == .adapter && forced.reason.contains("nie przeszedł"))
    }
}

@Suite("Wykrywanie milczącego adaptera")
struct SilentAdapterDetectorTests {
    let t0 = Date(timeIntervalSince1970: 0)

    @Test("Odtwarzacz gra, adapter milczy dłużej niż karencja")
    func silent() {
        var detector = SilentAdapterDetector(gracePeriod: 4)
        detector.playerReported(isPlaying: true, at: t0)
        #expect(!detector.isSilent(at: t0.addingTimeInterval(3)))
        #expect(detector.isSilent(at: t0.addingTimeInterval(4)))
    }

    @Test("Dane z adaptera kasują alarm")
    func adapterData() {
        var detector = SilentAdapterDetector(gracePeriod: 4)
        detector.playerReported(isPlaying: true, at: t0)
        detector.adapterReported(hasData: true)
        #expect(!detector.isSilent(at: t0.addingTimeInterval(10)))
    }

    @Test("Pauza w odtwarzaczu kasuje alarm")
    func playerPaused() {
        var detector = SilentAdapterDetector(gracePeriod: 4)
        detector.playerReported(isPlaying: true, at: t0)
        detector.playerReported(isPlaying: false, at: t0.addingTimeInterval(1))
        #expect(!detector.isSilent(at: t0.addingTimeInterval(10)))
    }

    @Test("Kolejne zgłoszenia odtwarzania nie przesuwają początku")
    func repeatedPlaying() {
        var detector = SilentAdapterDetector(gracePeriod: 4)
        detector.playerReported(isPlaying: true, at: t0)
        detector.playerReported(isPlaying: true, at: t0.addingTimeInterval(3))
        #expect(detector.isSilent(at: t0.addingTimeInterval(4)))
    }
}

@Suite("Kolor akcentu z okładki")
struct ArtworkPaletteTests {
    @Test("Dominujący żywy odcień wygrywa z szarościami")
    func dominantHue() throws {
        let red = RGB(red: 0.8, green: 0.1, blue: 0.1)
        let gray = RGB(red: 0.5, green: 0.5, blue: 0.5)
        let blue = RGB(red: 0.1, green: 0.2, blue: 0.9)
        let pixels = Array(repeating: gray, count: 50) + Array(repeating: red, count: 30) + Array(repeating: blue, count: 10)
        let accent = try #require(ArtworkPalette.accent(from: pixels))
        #expect(accent.red > accent.blue && accent.red > accent.green)
    }

    @Test("Ciemny kolor jest rozjaśniany do czytelności na czerni")
    func brightens() throws {
        let dark = RGB(red: 0.3, green: 0.05, blue: 0.05)
        let accent = try #require(ArtworkPalette.accent(from: Array(repeating: dark, count: 10)))
        #expect(abs(accent.maxComponent - ArtworkPalette.targetBrightness) < 0.0001)
    }

    @Test("Okładka czarno-biała nie ma akcentu")
    func monochrome() {
        let pixels = [RGB(red: 0, green: 0, blue: 0), RGB(red: 1, green: 1, blue: 1), RGB(red: 0.4, green: 0.4, blue: 0.4)]
        #expect(ArtworkPalette.accent(from: pixels) == nil)
    }

    @Test("Tło wyspy: ten sam odcień co akcent, przyciemniony pod biały tekst")
    func background() throws {
        let bright = RGB(red: 0.9, green: 0.3, blue: 0.1)
        let pixels = Array(repeating: bright, count: 10)
        let background = try #require(ArtworkPalette.background(from: pixels))
        let accent = try #require(ArtworkPalette.accent(from: pixels))
        #expect(abs(background.maxComponent - ArtworkPalette.backgroundBrightness) < 0.0001)
        #expect(abs(background.hue - accent.hue) < 0.0001)
        #expect(background.maxComponent < accent.maxComponent)
    }

    @Test("Okładka czarno-biała zostawia czarną wyspę")
    func monochromeBackground() {
        let pixels = [RGB(red: 0, green: 0, blue: 0), RGB(red: 1, green: 1, blue: 1), RGB(red: 0.4, green: 0.4, blue: 0.4)]
        #expect(ArtworkPalette.background(from: pixels) == nil)
    }

    @Test("Próbkowanie obrazu zwraca siatkę pikseli")
    func sampling() throws {
        let context = try #require(CGContext(
            data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(srgbRed: 0, green: 0.8, blue: 0.2, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        let image = try #require(context.makeImage())
        let pixels = ArtworkPalette.samplePixels(of: image, side: 4)
        #expect(pixels.count == 16)
        let accent = try #require(ArtworkPalette.accent(from: pixels))
        #expect(accent.green > accent.red)
    }
}

@Suite("Rozmyta okładka w tle odtwarzacza")
@MainActor
struct ArtworkBackdropTests {
    @Test("Okładka jest zmniejszana do małego obrazu z zachowaniem proporcji")
    func downscales() throws {
        let context = try #require(CGContext(
            data: nil, width: 600, height: 300, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(srgbRed: 0.9, green: 0.2, blue: 0.1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 600, height: 300))
        let image = try #require(context.makeImage())
        let blurred = try #require(ArtworkBackdrop.blurred(image))
        #expect(CGFloat(blurred.width) <= ArtworkBackdrop.side + 1)
        #expect(blurred.width > blurred.height)
    }

    @Test("Nazwy stylów tła są zapisane w ustawieniach — nie mogą się zmienić")
    func storedNames() {
        #expect(MediaBackdropStyle.allCases.map(\.rawValue) == ["black", "color", "blurred"])
    }
}
