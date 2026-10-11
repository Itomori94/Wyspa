import AppKit
import SwiftUI
import WyspaCore

extension EnvironmentValues {
    /// Motyw wyspy dla nagłówka i widżetów (moduły dostają go w środowisku i mogą z niego korzystać).
    @Entry public var islandTheme: IslandTheme = .classic
    /// Przyciemnienie pod kafelkami motywu Przezroczysty (`SettingsStore.tileDimming`).
    @Entry var islandTileDimming: Double = IslandTheme.defaultTileDimming
    /// Krycie treści nad szkłem kafelków w trakcie `GlassSafeTransition` (poza przejściem 1).
    @Entry var islandContentOpacity: Double = 1
}

/// Przejście treści leżącej na kafelkach szkła (Przezroczysty) bez przenikania całości: krycie rodzica mniejsze od 1
/// wyłącza efekty tła (znane z UIVisualEffectView i NSVisualEffectView). Szkło pojawia się i znika własną animacją
/// systemu, a przenikają tylko treść nad nim (`GlassContentFade`) i przyciemnienie pod nim (`TileGlass`).
struct GlassSafeTransition: Transition {
    var scale: CGFloat = 1
    var offsetY: CGFloat = 0

    func body(content: Content, phase: TransitionPhase) -> some View {
        content
            .environment(\.islandContentOpacity, phase.isIdentity ? 1 : 0)
            .scaleEffect(phase.isIdentity ? 1 : scale, anchor: .top)
            .offset(y: phase.isIdentity ? 0 : offsetY)
    }
}

/// Treść nad szkłem kafelka przenikana przez `GlassSafeTransition` (samo szkło przenikać nie może).
struct GlassContentFade: ViewModifier {
    @Environment(\.islandContentOpacity) private var opacity

    func body(content: Content) -> some View {
        content.opacity(opacity)
    }
}

extension AnyTransition {
    /// Przejście treści wyspy: w motywie Przezroczysty `GlassSafeTransition` (bez przenikania szkła), w pozostałych
    /// przenikanie z podanym ruchem.
    static func islandContent(theme: IslandTheme, scale: CGFloat = 1, offsetY: CGFloat = 0) -> AnyTransition {
        if theme.usesGlassTiles {
            return AnyTransition(GlassSafeTransition(scale: scale, offsetY: offsetY))
        }
        return .opacity.combined(with: .scale(scale: scale, anchor: .top)).combined(with: .offset(y: offsetY))
    }
}

/// Tło wyspy według motywu. Warstwy przenikają się, więc rozwinięcie czarnej wyspy w szklaną nie przeskakuje.
struct IslandBackground: View {
    let topRadius: CGFloat
    let bottomRadius: CGFloat
    let theme: IslandTheme
    let isGlass: Bool
    let glassTint: Double
    /// Tło modułu pod treścią rozwiniętej wyspy (np. rozmyta okładka); nil = sama czerń albo szkło.
    let backdrop: IslandBackdrop?
    let isHidden: Bool
    /// Wyspa wychodzi poza notch (rozwinięta albo z kartą) — wtedy cień i wyraźniejsza krawędź.
    let isRaised: Bool
    /// Czarna belka motywu Przezroczysty: wysokość (cała zwinięta wyspa, nad kartą skrzydła, w rozwiniętej nagłówek)
    /// i promień dolnych rogów.
    var headHeight: CGFloat = 0
    var headBottomRadius: CGFloat = IslandBackground.raisedHeadRadius

    /// Dolne rogi belki pod nagłówkiem i nad kartą — jak zwinięta wyspa, tylko szersza.
    static let raisedHeadRadius: CGFloat = 16

    private var shape: IslandShape { IslandShape(topRadius: topRadius, bottomRadius: bottomRadius) }
    private var edge: IslandEdge { IslandEdge(topRadius: topRadius, bottomRadius: bottomRadius) }

    var body: some View {
        // Przenikania dotyczą tylko swoich warstw: `animation(_:value:)` na całości nadpisałoby sprężynę wyspy
        // także dla belki (zmiana fazy zmienia `isGlass`, a rozwinięcie odtwarzacza — `backdrop`).
        ZStack(alignment: .top) {
            // Szkło Liquid Glass poza grupą `compositingGroup` (spłaszczenie odcięłoby je od tego, co pod oknem).
            if theme == .glass, !isHidden, Self.hasLiquidGlass {
                // Szkło jest stale pod czarną wyspą (przy notchu zakrywa je pełna czerń), a rozwinięcie tylko
                // rozjaśnia czerń do `glassTint`. Wstawiane dopiero przy rozwinięciu włączało się z opóźnieniem
                // (system włącza nowe szkło po ok. 0,3 s), więc przez chwilę wyspa wyglądała po staremu.
                IslandGlass(shape: shape)
            }
            background
        }
    }

    /// Przejrzyste szkło Liquid Glass (macOS 26+); na starszym systemie rozmycie zza okna.
    static var hasLiquidGlass: Bool {
        if #available(macOS 26, *) { return true }
        return false
    }

    private var background: some View {
        ZStack(alignment: .top) {
            ZStack {
                if isGlass, theme == .glass, !Self.hasLiquidGlass {
                    FrostedGlass(shape: shape, edge: edge)
                        .transition(.opacity)
                }
                shape.fill(Color.black.opacity(blackOpacity))
            }
            .animation(.easeInOut(duration: 0.25), value: isGlass)
            if theme.usesGlassTiles {
                // Przezroczysty: czarna jest tylko belka przy notchu, treść leży na przyciemnionych kafelkach.
                // Jedna belka we wszystkich fazach, więc rozwinięcie poszerza czarną wyspę w nagłówek,
                // zamiast przenikać ją w przezroczystą (przez chwilę widać by było ciemną taflę).
                IslandShape(topRadius: topRadius, bottomRadius: headBottomRadius)
                    .fill(Color.black)
                    .frame(height: headHeight)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .clipShape(shape)
                    .opacity(isHidden ? 0 : 1)
            }
            ZStack {
                if let backdrop, !isHidden, !theme.usesGlassTiles {
                    // Tło modułu (np. okładka) jest nieprzezroczyste w każdym motywie, jak odtwarzacz w Apple Music:
                    // przez szkło prześwitywałoby to, co leży pod oknem, a biały tekst traciłby kontrast.
                    // W motywie Przezroczysty tło ma kafelek strony, nie cała wyspa.
                    BackdropLayer(backdrop: backdrop)
                        .clipShape(shape)
                        .id(backdrop.id)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.5), value: backdrop?.id)
            if theme == .blackSheet, !isHidden {
                edge.stroke(.white.opacity(0.28), lineWidth: 0.5)
                    .transition(.opacity)
            }
        }
        .compositingGroup()
        .shadow(color: .black.opacity(shadowOpacity), radius: 20, y: isGlass ? 16 : 10)
    }

    private var blackOpacity: Double {
        // Ukryta wyspa i przezroczyste części wyspy muszą mieć niezerowe krycie, inaczej okno nie dostanie
        // zdarzeń myszy. W motywie Przezroczysty czerń daje belka.
        if isHidden || theme.usesGlassTiles { return 0.01 }
        return isGlass ? max(glassTint, 0.01) : 1
    }

    private var shadowOpacity: Double {
        guard isRaised, !isHidden else { return 0 }
        switch theme {
        case .classic: return 0.5
        case .blackSheet: return 0.5
        // Liquid Glass ma własną głębię, a cień pod przejrzystym szkłem byłby ciemną plamą.
        case .glass: return Self.hasLiquidGlass ? 0 : 0.32
        // Przezroczysta wyspa nie rzuca cienia (to byłaby ciemna plama pod niewidocznym kształtem); kafelki mają
        // własną krawędź.
        case .clear: return 0
        }
    }
}

/// Tafla motywu Szkło jak Centrum sterowania: przejrzysty Liquid Glass (`.clear`) na całej wyspie — pulpit widać ostro,
/// z załamaniem i połyskiem na brzegu. Czytelność tekstu daje czarna warstwa `glassTint` nad szkłem.
private struct IslandGlass: View {
    let shape: IslandShape

    var body: some View {
        if #available(macOS 26, *) {
            // Przycięte do wyspy: cień i poświata szkła wychodzą poza kształt (test `IslandOverflowTests`).
            Color.clear.glassEffect(.clear, in: shape)
                .clipShape(shape)
        }
    }
}

/// Kafelek motywu Przezroczysty: przyciemniona przezroczysta powierzchnia (`TileSurface`) albo — gdy moduł podaje
/// tło (np. okładkę) — to tło na kafelku.
struct GlassTile: View {
    static let pageCornerRadius: CGFloat = 20
    static let widgetCornerRadius: CGFloat = 16
    static let cardCornerRadius: CGFloat = 18
    /// Kafelek strony wychodzi poza ramę treści na boki i w dół (w margines wyspy), więc treść zostaje na swoim
    /// miejscu; od górnej krawędzi kafelka odsuwa się o `innerTop`.
    static let outset: CGFloat = 12
    static let bottomOutset: CGFloat = 8
    static let innerTop: CGFloat = 10
    /// Odstęp między kafelkami widżetów.
    static let gap: CGFloat = 8

    var cornerRadius: CGFloat = GlassTile.pageCornerRadius
    var backdrop: IslandBackdrop?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            if let backdrop {
                BackdropLayer(backdrop: backdrop)
                    .clipShape(shape)
                    .id(backdrop.id)
                    .transition(.opacity)
            } else {
                TileSurface(shape: shape)
            }
        }
        .animation(.easeInOut(duration: 0.5), value: backdrop?.id)
    }
}

/// Kafelek bez szkła: samo przyciemnienie (`islandTileDimming`) i cienka krawędź — pulpit widać przez kafelek bez
/// rozmycia i załamania. Szkło (Liquid Glass, wcześniej rozmycie) zostało tylko w motywie Szkło: tutaj włączało się
/// z opóźnieniem, a użytkownik chce w Przezroczystym samej przezroczystości (11.10.2026).
private struct TileSurface: View {
    let shape: RoundedRectangle
    @Environment(\.islandTileDimming) private var dimming
    /// Kafelek przenika z treścią (`GlassSafeTransition`), więc przy rozwijaniu nie widać pustych prostokątów.
    @Environment(\.islandContentOpacity) private var contentOpacity

    var body: some View {
        ZStack {
            shape.fill(Color.black.opacity(dimming))
            shape.strokeBorder(Highlight.gradient(top: 0.3), lineWidth: 0.5)
        }
        .opacity(contentOpacity)
    }
}

/// Motyw Przezroczysty: strona modułu na jednym kafelku. Inne motywy bez zmian.
struct PageTile: ViewModifier {
    let backdrop: IslandBackdrop?
    @Environment(\.islandTheme) private var theme

    func body(content: Content) -> some View {
        if theme.usesGlassTiles {
            content
                .modifier(GlassContentFade())
                .padding(.top, GlassTile.innerTop)
                .background {
                    GlassTile(backdrop: backdrop)
                        .padding(.horizontal, -GlassTile.outset)
                        .padding(.bottom, -GlassTile.bottomOutset)
                }
        } else {
            content
        }
    }
}

/// Rozmyte szkło: to, co pod oknem, rozmyte jak w dawnym Centrum sterowania, z jaśniejącą ku dołowi krawędzią.
struct FrostedGlass: View {
    let shape: IslandShape
    let edge: IslandEdge

    var body: some View {
        BehindWindowBlur()
            .clipShape(shape)
        // Krawędź szkła: jaśniejsza u dołu, delikatna po bokach, gaśnie ku notchowi.
        edge.stroke(LinearGradient(colors: [.white.opacity(0.06), .white.opacity(0.28)], startPoint: .top, endPoint: .bottom),
                    lineWidth: 1)
    }
}

/// Tło modułu: obraz rozciągnięty na całą wyspę (przyciemniony pod biały tekst) albo kolor.
/// Ciemniej u góry, przy notchu — wyspa łagodnie przechodzi w czarny notch.
struct BackdropLayer: View {
    let backdrop: IslandBackdrop
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.islandStaticSnapshot) private var isStaticSnapshot

    var body: some View {
        if let image = backdrop.image {
            // Obraz w nakładce na pustym kolorze: `scaledToFill` nie może wtedy poszerzyć wyspy.
            Color.clear
                .overlay {
                    // „Ogranicz ruch” i zrzuty ekranu: nieruchomy obraz (warstw Core Animation nie widać na zrzucie).
                    if reduceMotion || isStaticSnapshot {
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFill()
                    } else {
                        DriftingArtwork(image: image, isMoving: backdrop.isMoving)
                    }
                }
                .overlay {
                    LinearGradient(colors: [.black.opacity(0.6), .black.opacity(0.3)], startPoint: .top, endPoint: .bottom)
                }
                .clipped()
        } else if let color = backdrop.color {
            LinearGradient(colors: [color.opacity(0.55), color], startPoint: .top, endPoint: .bottom)
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
        case .glass, .clear: isSelected ? 0.2 : (isHovered ? 0.1 : 0)
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
