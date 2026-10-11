import AppKit
import ImageIO
import WyspaCore

/// Jasność tego, co leży pod rozwiniętą wyspą — bez nagrywania ekranu (zgoda zapalałaby w pasku menu wskaźnik
/// nagrywania przy każdym rozwinięciu). Źródło: plik tapety ekranu. Gdy pod wyspą jest okno innej aplikacji, jego
/// wyglądu nie znamy — wynik nil (`GlassContrast` przyjmuje wtedy bezpieczne przyciemnienie).
@MainActor
enum BackdropBrightness {
    /// Pomniejszona tapeta (najwyżej 512 px), wczytywana raz na plik.
    private static var wallpaper: (url: URL, image: CGImage)?
    private static let thumbnailSize = 512
    private static let sampleSize = (width: 64, height: 24)

    /// `rect` w globalnych współrzędnych AppKit (y w górę), `windowNumber` — okno wyspy (liczą się okna pod nim).
    static func luminance(of rect: CGRect, on screen: NSScreen, below windowNumber: Int) -> Double? {
        guard !hasWindowBelow(windowNumber, intersecting: rect) else { return nil }
        guard let image = wallpaperImage(for: screen) else { return nil }
        return luminance(of: image, cropping: wallpaperRect(for: rect, on: screen, image: image))
    }

    /// Zwykłe okno (poziom 0) pod panelem wyspy, które zachodzi na jej obszar.
    private static func hasWindowBelow(_ windowNumber: Int, intersecting rect: CGRect) -> Bool {
        let options: CGWindowListOption = [.optionOnScreenBelowWindow, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, CGWindowID(windowNumber)) as? [[String: Any]] else {
            return false
        }
        // Ramy okien są w układzie z początkiem w lewym górnym rogu ekranu głównego.
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        let target = CGRect(x: rect.minX, y: mainHeight - rect.maxY, width: rect.width, height: rect.height)
        return windows.contains { info in
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds) else { return false }
            return frame.intersects(target)
        }
    }

    private static func wallpaperImage(for screen: NSScreen) -> CGImage? {
        guard let url = NSWorkspace.shared.desktopImageURL(for: screen) else { return nil }
        if let wallpaper, wallpaper.url == url { return wallpaper.image }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: thumbnailSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        wallpaper = (url, image)
        return image
    }

    /// Obszar wyspy przeniesiony na piksele tapety rozciągniętej jak na pulpicie: wypełnia ekran z zachowaniem proporcji,
    /// nadmiar przycięty po równo (domyślne ustawienie macOS).
    private static func wallpaperRect(for rect: CGRect, on screen: NSScreen, image: CGImage) -> CGRect {
        let frame = screen.frame
        let imageSize = CGSize(width: image.width, height: image.height)
        let scale = max(frame.width / imageSize.width, frame.height / imageSize.height)
        let shown = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let origin = CGPoint(x: (frame.width - shown.width) / 2, y: (frame.height - shown.height) / 2)
        // Względem lewego górnego rogu ekranu (obraz też liczy wiersze od góry).
        let local = CGRect(x: rect.minX - frame.minX, y: frame.maxY - rect.maxY, width: rect.width, height: rect.height)
        return CGRect(x: (local.minX - origin.x) / scale, y: (local.minY - origin.y) / scale,
                      width: local.width / scale, height: local.height / scale)
            .intersection(CGRect(origin: .zero, size: imageSize))
    }

    private static func luminance(of image: CGImage, cropping rect: CGRect) -> Double? {
        guard !rect.isEmpty, let cropped = image.cropping(to: rect.integral) else { return nil }
        let (width, height) = sampleSize
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(cropped, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? GlassContrast.luminance(rgba: pixels) : nil
    }
}
