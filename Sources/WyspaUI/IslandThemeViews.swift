import AppKit
import SwiftUI
import WyspaCore

extension EnvironmentValues {
    /// Motyw wyspy dla nagłówka i widżetów (moduły dostają go w środowisku i mogą z niego korzystać).
    @Entry public var islandTheme: IslandTheme = .classic
}

/// Tło wyspy według motywu. Warstwy przenikają się, więc rozwinięcie czarnej wyspy w szklaną nie przeskakuje.
struct IslandBackground: View {
    let topRadius: CGFloat
    let bottomRadius: CGFloat
    let theme: IslandTheme
    let isGlass: Bool
    let glassTint: Double
    /// Kolor modułu pod treścią rozwiniętej wyspy (np. z okładki); nil = sama czerń albo szkło.
    let tint: Color?
    let isHidden: Bool
    /// Wyspa wychodzi poza notch (rozwinięta albo z kartą) — wtedy cień i wyraźniejsza krawędź.
    let isRaised: Bool

    private var shape: IslandShape { IslandShape(topRadius: topRadius, bottomRadius: bottomRadius) }
    private var edge: IslandEdge { IslandEdge(topRadius: topRadius, bottomRadius: bottomRadius) }

    var body: some View {
        ZStack {
            if isGlass {
                BehindWindowBlur()
                    .clipShape(shape)
                    .transition(.opacity)
                // Krawędź szkła: jaśniejsza u dołu, delikatna po bokach, gaśnie ku notchowi.
                edge.stroke(LinearGradient(colors: [.white.opacity(0.06), .white.opacity(0.28)], startPoint: .top, endPoint: .bottom),
                            lineWidth: 1)
                    .transition(.opacity)
            }
            shape.fill(Color.black.opacity(blackOpacity))
            if let tint, !isHidden {
                // Ciemniej u góry, przy notchu, pełny kolor u dołu. W szkle kolor jest tak przejrzysty jak czerń.
                let strength = isGlass ? glassTint : 1
                shape.fill(LinearGradient(colors: [tint.opacity(0.55 * strength), tint.opacity(strength)],
                                          startPoint: .top, endPoint: .bottom))
                    .transition(.opacity)
            }
            if theme == .blackSheet, !isHidden {
                edge.stroke(.white.opacity(0.28), lineWidth: 0.5)
                    .transition(.opacity)
            }
        }
        .compositingGroup()
        .shadow(color: .black.opacity(shadowOpacity), radius: 20, y: isGlass ? 16 : 10)
        .animation(.easeInOut(duration: 0.25), value: isGlass)
        .animation(.easeInOut(duration: 0.5), value: tint)
    }

    private var blackOpacity: Double {
        // Ukryta wyspa musi mieć niezerowe krycie, inaczej okno nie dostanie zdarzeń myszy.
        if isHidden { return 0.01 }
        return isGlass ? glassTint : 1
    }

    private var shadowOpacity: Double {
        guard isRaised, !isHidden else { return 0 }
        switch theme {
        case .classic: return 0.5
        case .blackSheet: return 0.5
        case .glass: return 0.32
        }
    }
}

/// Obrys wyspy bez górnej krawędzi (ta styka się z górą ekranu) — do cienkiej linii motywu.
struct IslandEdge: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = IslandShape(topRadius: topRadius, bottomRadius: bottomRadius).path(in: rect)
        // Ten sam kształt, ale bez zamknięcia u góry: przycinamy pierwszy piksel, żeby linia nie biegła po krawędzi ekranu.
        path = path.intersection(Path(CGRect(x: rect.minX - 2, y: rect.minY + 0.5, width: rect.width + 4, height: rect.height + 2)))
        return path
    }
}

/// Rozmycie tego, co jest pod oknem wyspy (pulpit, okna) — jak szkło w Centrum sterowania.
struct BehindWindowBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

/// Pasek zakładek: w Czarnej tafli zakładki leżą w kapsule z połyskiem.
struct TabStripBackground: ViewModifier {
    let theme: IslandTheme

    func body(content: Content) -> some View {
        if theme == .blackSheet {
            content
                .padding(2)
                .background(
                    Capsule().fill(.white.opacity(0.09))
                        .overlay(Capsule().strokeBorder(Highlight.gradient(top: 0.3), lineWidth: 0.5))
                )
        } else {
            content
        }
    }
}

/// Wybrana zakładka: w klasycznym motywie płaska kapsuła, w nowych — jaśniejsza z połyskiem u góry.
struct TabPill: View {
    let theme: IslandTheme
    let isSelected: Bool
    let isHovered: Bool

    var body: some View {
        let fill: Double = switch theme {
        case .classic: isSelected ? 0.18 : (isHovered ? 0.08 : 0)
        case .blackSheet: isSelected ? 0.22 : (isHovered ? 0.1 : 0)
        case .glass: isSelected ? 0.2 : (isHovered ? 0.1 : 0)
        }
        Capsule()
            .fill(.white.opacity(fill))
            .overlay {
                if theme != .classic, isSelected {
                    Capsule().strokeBorder(Highlight.gradient(top: 0.4), lineWidth: 0.5)
                }
            }
    }
}

/// Karta widżetu w Czarnej tafli: lekko jaśniejsza tafla z połyskiem na górnej krawędzi.
struct WidgetCard: ViewModifier {
    static let padding: CGFloat = 10
    static let cornerRadius: CGFloat = 14

    func body(content: Content) -> some View {
        content
            .padding(Self.padding)
            .background(
                RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                    .fill(.white.opacity(0.07))
                    .overlay(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                        .strokeBorder(Highlight.gradient(top: 0.16), lineWidth: 0.5))
            )
    }
}

/// Połysk krawędzi: jasny u góry, znika ku dołowi.
enum Highlight {
    static func gradient(top: Double) -> LinearGradient {
        LinearGradient(colors: [.white.opacity(top), .white.opacity(0)], startPoint: .top, endPoint: .center)
    }
}
