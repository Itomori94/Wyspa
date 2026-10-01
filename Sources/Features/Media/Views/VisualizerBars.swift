import AppKit
import QuartzCore
import SwiftUI

/// Animowany wizualizer na `CALayer`: animacje skali wykonuje serwer okien, główny wątek jest wolny.
///
/// To wizualizacja rytmu odtwarzania, nie analiza dźwięku (do tego potrzebny byłby dostęp do audio).
struct VisualizerBars: NSViewRepresentable {
    let color: Color
    let isAnimating: Bool

    func makeNSView(context: Context) -> VisualizerLayerView {
        VisualizerLayerView()
    }

    func updateNSView(_ view: VisualizerLayerView, context: Context) {
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        view.update(color: NSColor(color).cgColor, animating: isAnimating && !reduceMotion)
    }
}

final class VisualizerLayerView: NSView {
    private static let barCount = 4
    private static let durations: [CFTimeInterval] = [0.42, 0.55, 0.37, 0.5]
    private static let idleScale: CGFloat = 0.3
    private static let animationKey = "visualizer.scale"

    private var bars: [CALayer] = []
    private var isAnimating = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        bars = (0..<Self.barCount).map { _ in
            let bar = CALayer()
            bar.cornerCurve = .continuous
            layer?.addSublayer(bar)
            return bar
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        let spacing: CGFloat = 2
        let count = CGFloat(Self.barCount)
        let width = (bounds.width - spacing * (count - 1)) / count
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, bar) in bars.enumerated() {
            bar.bounds = CGRect(x: 0, y: 0, width: width, height: bounds.height)
            bar.position = CGPoint(x: CGFloat(index) * (width + spacing) + width / 2, y: bounds.midY)
            bar.cornerRadius = width / 2
        }
        CATransaction.commit()
    }

    func update(color: CGColor, animating: Bool) {
        bars.forEach { $0.backgroundColor = color }
        guard animating != isAnimating else { return }
        isAnimating = animating
        animating ? start() : stop()
    }

    private func start() {
        for (index, bar) in bars.enumerated() {
            let animation = CABasicAnimation(keyPath: "transform.scale.y")
            animation.fromValue = Self.idleScale
            animation.toValue = 1.0
            animation.duration = Self.durations[index % Self.durations.count]
            animation.autoreverses = true
            animation.repeatCount = .infinity
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animation.timeOffset = Double(index) * 0.13
            bar.add(animation, forKey: Self.animationKey)
        }
    }

    private func stop() {
        bars.forEach {
            $0.removeAnimation(forKey: Self.animationKey)
            $0.transform = CATransform3DMakeScale(1, Self.idleScale, 1)
        }
    }
}
