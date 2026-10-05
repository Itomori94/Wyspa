import AppKit
import QuartzCore
import SwiftUI

/// Rozmyta okładka w ruchu, jak w Apple Music: trzy warstwy tego samego obrazu powoli się obracają i dryfują.
///
/// Animacje wykonuje serwer okien (Core Animation), główny wątek nic nie liczy. Bez ruchu (pauza) warstwy
/// zatrzymują się w bieżącym położeniu i ruszają z niego dalej — bez skoku.
struct DriftingArtwork: NSViewRepresentable {
    let image: CGImage
    let isMoving: Bool

    func makeNSView(context: Context) -> DriftingArtworkView {
        DriftingArtworkView()
    }

    func updateNSView(_ view: DriftingArtworkView, context: Context) {
        view.update(image: image, isMoving: isMoving)
    }
}

final class DriftingArtworkView: NSView {
    /// Warstwa: powiększenie względem przekątnej (obrót nigdy nie odsłania rogów), okres obrotu, krycie,
    /// i dryf w punktach (tam i z powrotem).
    private struct Spec {
        let scale: CGFloat
        let rotationPeriod: CFTimeInterval
        let clockwise: Bool
        let opacity: Float
        let drift: CGSize
        let driftPeriod: CFTimeInterval
    }

    private static let specs = [
        Spec(scale: 1.05, rotationPeriod: 60, clockwise: true, opacity: 1, drift: .zero, driftPeriod: 1),
        Spec(scale: 1.3, rotationPeriod: 42, clockwise: false, opacity: 0.6,
             drift: CGSize(width: 60, height: 24), driftPeriod: 17),
        Spec(scale: 0.9, rotationPeriod: 31, clockwise: true, opacity: 0.45,
             drift: CGSize(width: -50, height: 18), driftPeriod: 13),
    ]

    /// Wspólny zegar warstw: zatrzymanie go (`speed = 0`) zamraża wszystkie animacje naraz.
    let stage = CALayer()
    /// Para na warstwę: zewnętrzna dryfuje, wewnętrzna (z obrazem) się obraca.
    private var drifters: [CALayer] = []
    private var spinners: [CALayer] = []
    private var image: CGImage?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.addSublayer(stage)
        for spec in Self.specs {
            let drifter = CALayer()
            let spinner = CALayer()
            spinner.contentsGravity = .resizeAspectFill
            spinner.opacity = spec.opacity
            drifter.addSublayer(spinner)
            stage.addSublayer(drifter)
            drifters.append(drifter)
            spinners.append(spinner)
        }
        startAnimations()
        setMoving(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Tło nie przyjmuje kliknięć — obsługują je kontrolki modułu nad nim.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        let diagonal = hypot(bounds.width, bounds.height)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        stage.frame = bounds
        for (index, spec) in Self.specs.enumerated() {
            let side = diagonal * spec.scale
            drifters[index].bounds = CGRect(x: 0, y: 0, width: side, height: side)
            drifters[index].position = center
            spinners[index].frame = drifters[index].bounds
        }
        CATransaction.commit()
    }

    func update(image: CGImage, isMoving: Bool) {
        if image !== self.image {
            self.image = image
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            spinners.forEach { $0.contents = image }
            CATransaction.commit()
        }
        setMoving(isMoving)
    }

    private func startAnimations() {
        for (index, spec) in Self.specs.enumerated() {
            let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
            rotation.byValue = (spec.clockwise ? -1 : 1) * 2 * Double.pi
            rotation.duration = spec.rotationPeriod
            rotation.repeatCount = .infinity
            rotation.timingFunction = CAMediaTimingFunction(name: .linear)
            spinners[index].add(rotation, forKey: "drift.rotation")

            guard spec.drift != .zero else { continue }
            let drift = CABasicAnimation(keyPath: "transform.translation")
            drift.fromValue = NSValue(size: CGSize(width: -spec.drift.width, height: -spec.drift.height))
            drift.toValue = NSValue(size: spec.drift)
            drift.duration = spec.driftPeriod
            drift.autoreverses = true
            drift.repeatCount = .infinity
            drift.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            drifters[index].add(drift, forKey: "drift.translation")
        }
    }

    /// Pauza zapamiętuje czas warstw, wznowienie przesuwa ich początek tak, żeby ruch szedł dalej z tego miejsca.
    private func setMoving(_ moving: Bool) {
        if moving, stage.speed == 0 {
            let pausedAt = stage.timeOffset
            stage.speed = 1
            stage.timeOffset = 0
            stage.beginTime = 0
            stage.beginTime = stage.convertTime(CACurrentMediaTime(), from: nil) - pausedAt
        } else if !moving, stage.speed != 0 {
            let now = stage.convertTime(CACurrentMediaTime(), from: nil)
            stage.speed = 0
            stage.timeOffset = now
        }
    }
}
