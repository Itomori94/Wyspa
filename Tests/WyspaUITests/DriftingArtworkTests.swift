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

    @Test("Warstwy zakrywają całą wyspę także po obrocie")
    func coversWhenRotated() {
        let view = DriftingArtworkView(frame: CGRect(x: 0, y: 0, width: 600, height: 220))
        view.layout()
        let diagonal = hypot(600.0, 220.0)
        let largest = view.stage.sublayers?.map(\.bounds.width).max() ?? 0
        #expect(largest >= diagonal)
    }

    @Test("Zmiana ruchu tła to zmiana wartości (widok musi się odświeżyć)")
    func backdropEquality() {
        let still = IslandBackdrop(id: "media.1", color: .red)
        let moving = IslandBackdrop(id: "media.1", color: .red, isMoving: true)
        #expect(still != moving)
        #expect(still == IslandBackdrop(id: "media.1"))
    }
}
