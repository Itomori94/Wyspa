import AppKit
import QuartzCore
import SwiftUI

/// Rozmyta okładka w ruchu, jak w Apple Music: miękkie plamy kolorów z okładki krążą po orbitach i obracają się
/// nad powoli obracającą się całą okładką.
///
/// Animacje wykonuje serwer okien (Core Animation), główny wątek nic nie liczy. Animowane są wyłącznie kąty —
/// rozmiary i promienie orbit to zwykły układ warstw, więc zmiana rozmiaru (np. rozwijanie wyspy) nie psuje ruchu.
/// Nic nie ma twardych krawędzi: okładka pod spodem zawsze zakrywa całość (bok ≥ przekątna), a plamy mają
/// wygaszone brzegi zapisane w samym obrazie (bez masek liczonych przy każdej klatce). Bez ruchu (pauza)
/// warstwy zatrzymują się w miejscu i ruszają z niego dalej — bez skoku.
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
    /// Plama koloru: fragment okładki z miękko wygaszonym brzegiem.
    struct Blob {
        /// Fragment okładki w układzie jednostkowym (0…1).
        let region: CGRect
        /// Bok plamy jako ułamek dłuższego boku tła.
        let size: CGFloat
        /// Środek orbity jako ułamek szerokości i wysokości tła.
        let center: CGPoint
        let opacity: Float
        /// Okres orbity i obrotu własnego w sekundach; znak to kierunek.
        let orbitPeriod: CFTimeInterval
        let spinPeriod: CFTimeInterval
        /// Faza startowa (ułamek okresu), żeby plamy nie ruszały razem.
        let phase: Double
    }

    /// Okres obrotu całej okładki pod plamami.
    static let basePeriod: CFTimeInterval = 80
    /// Bok okładki pod plamami jako krotność przekątnej tła: przy każdym kącie obrotu zakrywa całość.
    static let baseScale: CGFloat = 1.1

    static let blobs = [
        Blob(region: CGRect(x: 0, y: 0, width: 0.5, height: 0.5), size: 0.8, center: CGPoint(x: 0.2, y: 0.35),
             opacity: 0.9, orbitPeriod: 22, spinPeriod: -30, phase: 0),
        Blob(region: CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5), size: 0.75, center: CGPoint(x: 0.78, y: 0.65),
             opacity: 0.85, orbitPeriod: -26, spinPeriod: 24, phase: 0.35),
        Blob(region: CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5), size: 0.7, center: CGPoint(x: 0.45, y: 0.8),
             opacity: 0.8, orbitPeriod: 30, spinPeriod: -36, phase: 0.6),
        Blob(region: CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5), size: 0.65, center: CGPoint(x: 0.6, y: 0.15),
             opacity: 0.75, orbitPeriod: -19, spinPeriod: 28, phase: 0.85),
    ]

    /// Promień orbit plam: część krótszego boku plus odrobina dłuższego (szeroka wyspa — dłuższa droga w poziomie).
    static func orbitRadius(for size: CGSize) -> CGFloat {
        0.32 * min(size.width, size.height) + 0.06 * max(size.width, size.height)
    }

    /// Krycie plamy od środka (0) do brzegu (1): gładkie wygaszanie, na brzegu zero.
    static let edgeFade: [(location: CGFloat, alpha: CGFloat)] = [
        (0, 1), (0.1, 1), (0.3, 0.87), (0.5, 0.58), (0.7, 0.26), (0.85, 0.07), (1, 0),
    ]

    /// Bok obrazu plamy w pikselach: po rozmyciu szczegółów nie ma, mały obraz rozciąga się gładko.
    static let spotSide = 64

    /// Wspólny zegar warstw: zatrzymanie go (`speed = 0`) zamraża wszystkie animacje naraz.
    let stage = CALayer()
    /// Cała okładka pod plamami.
    let base = CALayer()
    /// Orbity (bez rozmiaru, obracane wokół środka orbity) i plamy na nich (przesunięte o promień, obracane wokół siebie).
    private(set) var orbits: [CALayer] = []
    private(set) var spots: [CALayer] = []
    private var image: CGImage?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.addSublayer(stage)
        base.contentsGravity = .resizeAspectFill
        stage.addSublayer(base)
        for blob in Self.blobs {
            let orbit = CALayer()
            let spot = CALayer()
            spot.contentsGravity = .resize
            spot.opacity = blob.opacity
            orbit.addSublayer(spot)
            stage.addSublayer(orbit)
            orbits.append(orbit)
            spots.append(spot)
        }
        CATransaction.commit()
        startAnimations()
        setMoving(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Tło nie przyjmuje kliknięć — obsługują je kontrolki modułu nad nim.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        layoutLayers()
    }

    /// Rozmiar nadaje SwiftUI ramką widoku — warstwy układamy od razu, nie czekając na przebieg `layout()`.
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutLayers()
    }

    private func layoutLayers() {
        let size = bounds.size
        let baseSide = hypot(size.width, size.height) * Self.baseScale
        let longest = max(size.width, size.height)
        let radius = Self.orbitRadius(for: size)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        stage.frame = bounds
        base.bounds = CGRect(x: 0, y: 0, width: baseSide, height: baseSide)
        base.position = CGPoint(x: bounds.midX, y: bounds.midY)
        for (index, blob) in Self.blobs.enumerated() {
            let side = longest * blob.size
            orbits[index].bounds = .zero
            orbits[index].position = CGPoint(x: size.width * blob.center.x, y: size.height * blob.center.y)
            spots[index].bounds = CGRect(x: 0, y: 0, width: side, height: side)
            spots[index].position = CGPoint(x: radius, y: 0)
        }
        CATransaction.commit()
    }

    func update(image: CGImage, isMoving: Bool) {
        if image !== self.image {
            self.image = image
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            base.contents = image
            for (index, blob) in Self.blobs.enumerated() {
                spots[index].contents = Self.softSpot(from: image, region: blob.region)
            }
            CATransaction.commit()
        }
        setMoving(isMoving)
    }

    /// Fragment okładki jako okrągła plama: brzeg wygaszony do zera, więc obracana plama nie ma krawędzi.
    static func softSpot(from image: CGImage, region: CGRect, side: Int = DriftingArtworkView.spotSide) -> CGImage? {
        let crop = CGRect(x: region.minX * CGFloat(image.width), y: region.minY * CGFloat(image.height),
                          width: region.width * CGFloat(image.width), height: region.height * CGFloat(image.height)).integral
        guard let fragment = image.cropping(to: crop),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let fade = CGGradient(colorsSpace: space,
                                    colors: edgeFade.map { CGColor(srgbRed: 1, green: 1, blue: 1, alpha: $0.alpha) } as CFArray,
                                    locations: edgeFade.map { $0.location })
        else { return nil }
        let rect = CGRect(x: 0, y: 0, width: side, height: side)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        context.interpolationQuality = .high
        context.draw(fragment, in: rect)
        // Zostaje tylko miękkie koło; poza promieniem gradient (kolor końcowy) zeruje rogi.
        context.setBlendMode(.destinationIn)
        context.drawRadialGradient(fade, startCenter: center, startRadius: 0, endCenter: center,
                                   endRadius: rect.width / 2, options: [.drawsAfterEndLocation])
        return context.makeImage()
    }

    private func startAnimations() {
        base.add(Self.rotation(period: Self.basePeriod), forKey: "drift.base")
        for (index, blob) in Self.blobs.enumerated() {
            orbits[index].add(Self.rotation(period: blob.orbitPeriod, phase: blob.phase), forKey: "drift.orbit")
            spots[index].add(Self.rotation(period: blob.spinPeriod, phase: blob.phase), forKey: "drift.spin")
        }
    }

    /// Pełny obrót bez końca, ze stałą prędkością; znak okresu to kierunek, faza przesuwa punkt startu.
    static func rotation(period: CFTimeInterval, phase: Double = 0) -> CABasicAnimation {
        let animation = CABasicAnimation(keyPath: "transform.rotation.z")
        animation.fromValue = 0
        animation.toValue = (period < 0 ? -2 : 2) * Double.pi
        animation.duration = abs(period)
        animation.timeOffset = phase * abs(period)
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        return animation
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
