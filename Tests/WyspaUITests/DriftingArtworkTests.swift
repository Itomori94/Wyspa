import AppKit
import SwiftUI
import Testing
@testable import WyspaCore
@testable import WyspaUI

@Suite("Rozmyta okładka w ruchu")
@MainActor
struct DriftingArtworkTests {
    private func image() throws -> CGImage {
        let context = try #require(CGContext(
            data: nil, width: 48, height: 48, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(srgbRed: 0.8, green: 0.3, blue: 0.5, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 48, height: 48))
        return try #require(context.makeImage())
    }

    @Test("Pauza zatrzymuje zegar warstw, odtwarzanie go wznawia")
    func pauseAndResume() throws {
        let view = DriftingArtworkView(frame: CGRect(x: 0, y: 0, width: 600, height: 220))
        view.layout()
        #expect(view.stage.speed == 0)
        view.update(image: try image(), isMoving: true)
        #expect(view.stage.speed == 1)
        view.update(image: try image(), isMoving: false)
        #expect(view.stage.speed == 0)
    }

    /// Kanał alfa obrazu jako funkcja (x, y) → 0…255.
    private func alphaReader(_ image: CGImage) throws -> (Int, Int) -> UInt8 {
        let width = image.width, height = image.height
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let data = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        let pixels = Array(UnsafeBufferPointer(start: data, count: width * height * 4))
        return { x, y in pixels[(y * width + x) * 4 + 3] }
    }

    @Test("Okładka pod plamami zakrywa całe tło przy każdym kącie obrotu")
    func baseCoversWhenRotated() {
        let view = DriftingArtworkView(frame: CGRect(x: 0, y: 0, width: 600, height: 220))
        view.layout()
        #expect(view.base.bounds.width >= hypot(600.0, 220.0))
        #expect(view.base.bounds.width == view.base.bounds.height)
    }

    @Test("Animowane są tylko kąty: po zmianie rozmiaru ruch trwa, a orbity pasują do nowego tła")
    func resizeKeepsMotion() throws {
        let source = try image()
        let view = DriftingArtworkView(frame: CGRect(x: 0, y: 0, width: 200, height: 40))
        view.update(image: source, isMoving: true)
        view.setFrameSize(NSSize(width: 600, height: 220))
        let radius = DriftingArtworkView.orbitRadius(for: CGSize(width: 600, height: 220))
        #expect(view.base.animation(forKey: "drift.base") != nil)
        #expect(view.orbits.count == DriftingArtworkView.blobs.count)
        for (orbit, spot) in zip(view.orbits, view.spots) {
            #expect(orbit.animation(forKey: "drift.orbit") != nil)
            #expect(spot.animation(forKey: "drift.spin") != nil)
            #expect(abs(spot.position.x - radius) < 0.001)
            #expect(spot.contents != nil)
        }
    }

    @Test("Plama ma miękki brzeg: przezroczyste rogi, kryjący środek")
    func softSpotEdges() throws {
        let source = try image()
        let spot = try #require(DriftingArtworkView.softSpot(from: source, region: CGRect(x: 0, y: 0, width: 0.5, height: 0.5)))
        let alpha = try alphaReader(spot)
        let side = spot.width
        #expect(side == DriftingArtworkView.spotSide)
        #expect(alpha(0, 0) == 0)
        #expect(alpha(side - 1, 0) == 0)
        #expect(alpha(side - 1, side - 1) == 0)
        #expect(alpha(side / 2, side / 2) > 240)
    }

    @Test("Zmiana ruchu tła to zmiana wartości (widok musi się odświeżyć)")
    func backdropEquality() {
        let still = IslandBackdrop(id: "media.1", color: .red)
        let moving = IslandBackdrop(id: "media.1", color: .red, isMoving: true)
        #expect(still != moving)
        #expect(still == IslandBackdrop(id: "media.1"))
    }
}
