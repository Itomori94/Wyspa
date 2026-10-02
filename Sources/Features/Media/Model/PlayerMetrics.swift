import CoreGraphics

/// Wymiary dużego odtwarzacza dla danej szerokości: ten sam wygląd na całej stronie i w widżecie obok innych.
struct PlayerMetrics: Equatable {
    /// Poniżej tej szerokości duży odtwarzacz się nie mieści (przyciski, okładka, tekst) — wtedy wersja kompaktowa.
    static let minimumWidth: CGFloat = 230
    /// Od tej szerokości odtwarzacz ma pełne wymiary.
    static let fullWidth: CGFloat = 340

    let artworkSize: CGFloat
    let spacing: CGFloat
    let controlSpacing: CGFloat

    static let full = PlayerMetrics(artworkSize: 92, spacing: 16, controlSpacing: 22)

    /// `nil`, gdy szerokość jest za mała na duży odtwarzacz.
    static func forWidth(_ width: CGFloat) -> PlayerMetrics? {
        guard width >= minimumWidth else { return nil }
        guard width < fullWidth else { return full }
        return PlayerMetrics(artworkSize: min(92, max(56, (width * 0.3).rounded())), spacing: 12, controlSpacing: 12)
    }
}
