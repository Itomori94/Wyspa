import CoreImage
import Foundation

/// Tło rozwiniętego odtwarzacza (wybór w ustawieniach modułu). Nazwy są zapisane w ustawieniach — nie zmieniać.
public enum MediaBackdropStyle: String, Codable, CaseIterable, Sendable {
    case black
    case color
    case blurred

    public var displayName: String {
        switch self {
        case .black: "Czarne"
        case .color: "Kolor okładki"
        case .blurred: "Rozmyta okładka"
        }
    }
}

/// Rozmyta okładka jak w Apple Music: zmniejszona, mocno rozmyta i nasycona raz na okładkę.
/// Wyspa tylko ją rozciąga — żadnego filtra liczonego przy każdej klatce.
@MainActor
enum ArtworkBackdrop {
    /// Bok zmniejszonej okładki: po rozmyciu szczegóły i tak znikają, a mały obraz rozciąga się gładko.
    static let side: CGFloat = 48
    static let blurSigma: Double = 5
    private static let context = CIContext(options: [.cacheIntermediates: false])

    static func blurred(_ image: CGImage) -> CGImage? {
        let input = CIImage(cgImage: image)
        let longest = max(input.extent.width, input.extent.height)
        guard longest > 0 else { return nil }
        let small = input.applyingFilter("CILanczosScaleTransform", parameters: [
            kCIInputScaleKey: side / longest,
            kCIInputAspectRatioKey: 1,
        ])
        let extent = small.extent.integral
        let output = small.clampedToExtent()
            .applyingGaussianBlur(sigma: blurSigma)
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.6])
            .cropped(to: extent)
        return context.createCGImage(output, from: extent)
    }
}
