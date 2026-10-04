import CoreGraphics
import Foundation
import SwiftUI

public struct RGB: Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    var maxComponent: Double { max(red, green, blue) }
    var minComponent: Double { min(red, green, blue) }
    var saturation: Double { maxComponent == 0 ? 0 : (maxComponent - minComponent) / maxComponent }

    var hue: Double {
        let delta = maxComponent - minComponent
        guard delta > 0 else { return 0 }
        var h: Double
        if maxComponent == red {
            h = (green - blue) / delta
        } else if maxComponent == green {
            h = (blue - red) / delta + 2
        } else {
            h = (red - green) / delta + 4
        }
        h /= 6
        return h < 0 ? h + 1 : h
    }
}

extension Color {
    init(_ rgb: RGB) {
        self.init(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}

/// Kolory z okładki: najliczniejszy odcień wśród żywych pikseli — rozjaśniony jako akcent (czytelny na czerni)
/// i przyciemniony jako tło rozwiniętej wyspy (jak odtwarzacz w Apple Music; biały tekst zostaje czytelny).
public enum ArtworkPalette {
    static let hueBuckets = 12
    static let minimumSaturation = 0.25
    static let minimumBrightness = 0.2
    /// Akcent ma być czytelny na czarnym tle wyspy.
    static let targetBrightness = 0.85
    /// Jasność tła: na tyle ciemne, żeby biały tekst i ikony były czytelne.
    static let backgroundBrightness = 0.4

    public static func accent(from pixels: [RGB]) -> RGB? {
        dominant(in: pixels).map(brightened)
    }

    /// Kolor tła wyspy z okładki; nil dla okładek bez wyraźnego koloru (wyspa zostaje czarna).
    public static func background(from pixels: [RGB]) -> RGB? {
        dominant(in: pixels).map(shaded)
    }

    /// Średni kolor najliczniejszego odcienia wśród żywych pikseli.
    static func dominant(in pixels: [RGB]) -> RGB? {
        let vivid = pixels.filter { $0.saturation >= minimumSaturation && $0.maxComponent >= minimumBrightness }
        guard !vivid.isEmpty else { return nil }

        var weights = [Double](repeating: 0, count: hueBuckets)
        for pixel in vivid {
            let bucket = min(Int(pixel.hue * Double(hueBuckets)), hueBuckets - 1)
            weights[bucket] += pixel.saturation * pixel.maxComponent
        }
        guard let best = weights.indices.max(by: { weights[$0] < weights[$1] }) else { return nil }

        let members = vivid.filter { min(Int($0.hue * Double(hueBuckets)), hueBuckets - 1) == best }
        let count = Double(members.count)
        let average = RGB(
            red: members.map(\.red).reduce(0, +) / count,
            green: members.map(\.green).reduce(0, +) / count,
            blue: members.map(\.blue).reduce(0, +) / count
        )
        return average
    }

    static func brightened(_ color: RGB) -> RGB {
        let peak = color.maxComponent
        guard peak > 0, peak < targetBrightness else { return color }
        let scale = targetBrightness / peak
        return RGB(red: color.red * scale, green: color.green * scale, blue: color.blue * scale)
    }

    /// Ten sam odcień z jasnością `backgroundBrightness` (przyciemniony albo rozjaśniony).
    static func shaded(_ color: RGB) -> RGB {
        let peak = color.maxComponent
        guard peak > 0 else { return color }
        let scale = backgroundBrightness / peak
        return RGB(red: color.red * scale, green: color.green * scale, blue: color.blue * scale)
    }

    /// Zmniejsza obraz do siatki `side × side` i zwraca piksele (do `accent(from:)`).
    public static func samplePixels(of image: CGImage, side: Int = 24) -> [RGB] {
        let bytesPerRow = side * 4
        var buffer = [UInt8](repeating: 0, count: side * bytesPerRow)
        let drawn = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(
                data: raw.baseAddress, width: side, height: side, bitsPerComponent: 8,
                bytesPerRow: bytesPerRow, space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return [] }
        return stride(from: 0, to: buffer.count, by: 4).map { index in
            RGB(
                red: Double(buffer[index]) / 255,
                green: Double(buffer[index + 1]) / 255,
                blue: Double(buffer[index + 2]) / 255
            )
        }
    }
}
