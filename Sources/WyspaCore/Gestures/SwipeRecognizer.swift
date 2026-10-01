import CoreGraphics

/// Faza gestu trackpada, odwzorowanie `NSEvent.Phase` bez zależności od AppKit.
public enum TrackpadPhase: Sendable {
    case began, changed, ended, cancelled
    /// Zdarzenia bez fazy (klasyczne kółko myszy) i bezwładność są ignorowane.
    case other
}

/// Rozpoznaje jeden kierunek przesunięcia na gest (od `began` do `ended`).
///
/// `dx`/`dy` to ruch palców: dodatnie `dy` oznacza palce w dół, dodatnie `dx` palce w prawo.
public struct SwipeRecognizer: Sendable {
    public static let defaultThreshold: CGFloat = 28

    private let threshold: CGFloat
    private var accumulated = CGVector.zero
    private var hasFired = false

    public init(threshold: CGFloat = SwipeRecognizer.defaultThreshold) {
        self.threshold = threshold
    }

    public mutating func handle(phase: TrackpadPhase, dx: CGFloat, dy: CGFloat) -> SwipeDirection? {
        switch phase {
        case .began:
            accumulated = CGVector(dx: dx, dy: dy)
            hasFired = false
            return detect()
        case .changed:
            accumulated = CGVector(dx: accumulated.dx + dx, dy: accumulated.dy + dy)
            return detect()
        case .ended, .cancelled:
            accumulated = .zero
            hasFired = false
            return nil
        case .other:
            return nil
        }
    }

    private mutating func detect() -> SwipeDirection? {
        guard !hasFired else { return nil }
        let horizontal = abs(accumulated.dx)
        let vertical = abs(accumulated.dy)
        guard max(horizontal, vertical) >= threshold else { return nil }
        hasFired = true
        if horizontal > vertical {
            return accumulated.dx > 0 ? .right : .left
        }
        return accumulated.dy > 0 ? .down : .up
    }
}
