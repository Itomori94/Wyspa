// Generuje Resources/AppIcon.icns: zaokrąglony kwadrat w siatce ikon macOS z wyspą (Dynamic Island) u góry.
// Użycie: swift scripts/make-icon.swift  (wymaga sips i iconutil z systemu)
import AppKit

let canvas: CGFloat = 1024
// Siatka ikon macOS: kształt 824×824 wyśrodkowany, promień ok. 185.
let shape = CGRect(x: 100, y: 100, width: 824, height: 824)
let radius: CGFloat = 185

func render() -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(canvas), pixelsHigh: Int(canvas),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let context = NSGraphicsContext.current!.cgContext

    // Cień pod kształtem.
    context.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    let path = CGPath(roundedRect: shape, cornerWidth: radius, cornerHeight: radius, transform: nil)
    context.addPath(path)
    context.setFillColor(NSColor.black.cgColor)
    context.fillPath()
    context.setShadow(offset: .zero, blur: 0)

    // Tło: fioletowy gradient (jak tapeta ekranu z notchem).
    context.saveGState()
    context.addPath(path)
    context.clip()
    let colors = [NSColor(srgbRed: 0.55, green: 0.32, blue: 0.95, alpha: 1).cgColor,
                  NSColor(srgbRed: 0.18, green: 0.08, blue: 0.38, alpha: 1).cgColor] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: shape.minX, y: shape.maxY), end: CGPoint(x: shape.maxX, y: shape.minY), options: [])
    // Pasek menu u góry.
    context.setFillColor(NSColor.white.withAlphaComponent(0.12).cgColor)
    context.fill(CGRect(x: shape.minX, y: shape.maxY - 92, width: shape.width, height: 92))

    // Wyspa: czarna kapsuła przyklejona do górnej krawędzi, z poświatą.
    let island = CGRect(x: shape.midX - 270, y: shape.maxY - 250, width: 540, height: 200)
    context.setShadow(offset: CGSize(width: 0, height: -10), blur: 40, color: NSColor.black.withAlphaComponent(0.55).cgColor)
    context.addPath(CGPath(roundedRect: island, cornerWidth: 100, cornerHeight: 100, transform: nil))
    context.setFillColor(NSColor.black.cgColor)
    context.fillPath()
    context.setShadow(offset: .zero, blur: 0)

    // Okładka po lewej i zielony wizualizer po prawej (jak aktywność mediów).
    let artwork = CGRect(x: island.minX + 52, y: island.midY - 48, width: 96, height: 96)
    context.addPath(CGPath(roundedRect: artwork, cornerWidth: 24, cornerHeight: 24, transform: nil))
    context.setFillColor(NSColor(srgbRed: 0.98, green: 0.55, blue: 0.3, alpha: 1).cgColor)
    context.fillPath()
    let heights: [CGFloat] = [60, 104, 76, 120]
    for (index, height) in heights.enumerated() {
        let bar = CGRect(x: island.maxX - 190 + CGFloat(index) * 38, y: island.midY - height / 2, width: 22, height: height)
        context.addPath(CGPath(roundedRect: bar, cornerWidth: 11, cornerHeight: 11, transform: nil))
        context.setFillColor(NSColor(srgbRed: 0.3, green: 0.9, blue: 0.45, alpha: 1).cgColor)
        context.fillPath()
    }
    context.restoreGState()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
let master = iconset.appendingPathComponent("master.png")
try render().write(to: master)

func run(_ tool: String, _ arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: tool)
    process.arguments = arguments
    process.standardOutput = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw NSError(domain: tool, code: Int(process.terminationStatus)) }
}

for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let name = scale == 1 ? "icon_\(size)x\(size).png" : "icon_\(size)x\(size)@2x.png"
        try run("/usr/bin/sips", ["-z", "\(pixels)", "\(pixels)", master.path, "--out", iconset.appendingPathComponent(name).path])
    }
}
try FileManager.default.removeItem(at: master)
let output = root.appendingPathComponent("Resources/AppIcon.icns")
try run("/usr/bin/iconutil", ["-c", "icns", iconset.path, "-o", output.path])
print("Zapisano \(output.path)")
