import CoreGraphics

/// Rozmiar notcha: fizycznego (z safe area ekranu) albo wirtualnego na ekranach bez notcha.
public struct NotchMetrics: Equatable, Sendable {
    public static let virtualWidth: CGFloat = 190
    public static let fallbackMenuBarHeight: CGFloat = 24

    public let size: CGSize
    public let isPhysical: Bool

    public init(size: CGSize, isPhysical: Bool) {
        self.size = size
        self.isPhysical = isPhysical
    }

    /// - Parameters:
    ///   - safeAreaTop: `NSScreen.safeAreaInsets.top` (0 na ekranach bez notcha).
    ///   - leftAuxWidth/rightAuxWidth: szerokości `auxiliaryTopLeftArea` / `auxiliaryTopRightArea`.
    ///   - menuBarHeight: wysokość paska menu na tym ekranie (0, gdy pasek jest ukryty).
    public static func resolve(
        screenWidth: CGFloat,
        safeAreaTop: CGFloat,
        leftAuxWidth: CGFloat?,
        rightAuxWidth: CGFloat?,
        menuBarHeight: CGFloat
    ) -> NotchMetrics {
        if safeAreaTop > 0, let left = leftAuxWidth, let right = rightAuxWidth {
            let width = screenWidth - left - right
            if width > 0 {
                return NotchMetrics(size: CGSize(width: width, height: safeAreaTop), isPhysical: true)
            }
        }
        let height = menuBarHeight > 0 ? menuBarHeight : fallbackMenuBarHeight
        return NotchMetrics(size: CGSize(width: virtualWidth, height: height), isPhysical: false)
    }
}

public enum IslandPlacement {
    /// Prostokąt danego rozmiaru przyklejony do górnej krawędzi i wyśrodkowany (współrzędne AppKit, y w górę).
    public static func topCentered(_ size: CGSize, in frame: CGRect) -> CGRect {
        CGRect(
            x: (frame.midX - size.width / 2).rounded(),
            y: frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }
}
