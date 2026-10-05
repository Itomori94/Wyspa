import SwiftUI
import WyspaCore

/// Korzeń wyspy: czarny kształt przy górnej krawędzi i zawartość zależna od fazy.
public struct IslandView: View {
    private static let collapsedBottomRadius: CGFloat = 10
    private static let peekBottomRadius: CGFloat = 13
    private static let expandedBottomRadius: CGFloat = 28
    private static let cardBottomRadius: CGFloat = 22

    @Bindable var model: IslandViewModel
    @Namespace private var namespace
    /// Ostatnio pokazana aktywność — ta sama po rozwinięciu i zwinięciu wyspy nie wjeżdża ponownie.
    @State private var shownActivityID: String?

    public init(model: IslandViewModel) {
        self.model = model
    }

    public var body: some View {
        let size = model.islandSize
        ZStack(alignment: .top) {
            IslandBackground(topRadius: topRadius, bottomRadius: bottomRadius, theme: model.theme,
                             isGlass: model.theme.usesGlass(isExpanded: model.phase == .expanded, showsCard: showsCard),
                             glassTint: model.glassTint, tint: model.tint, isHidden: model.phase == .hidden,
                             isRaised: isRaised)
                .contentShape(IslandShape(topRadius: topRadius, bottomRadius: bottomRadius))
                .onTapGesture {
                    // W rozwiniętej wyspie kliknięcia obsługują kontrolki modułów.
                    if model.phase != .expanded { model.onClick() }
                }

            content
                .padding(.horizontal, model.phase == .expanded ? topRadius + IslandLayout.expandedContentInset : topRadius)
                // Najpierw rama o rozmiarze wyspy, potem przycięcie do jej kształtu: cokolwiek narysuje moduł,
                // nie wyjdzie poza wyspę (clipShape bez ramy przycina do granic samej treści, które mogą urosnąć).
                .frame(width: size.width, height: size.height, alignment: .top)
                .clipShape(IslandShape(topRadius: topRadius, bottomRadius: bottomRadius))
        }
        .frame(width: size.width, height: size.height)
        .onChange(of: model.activity?.id, initial: true) { _, id in shownActivityID = id }
        .backgroundPreferenceValue(DropZoneKey.self) { anchors in
            GeometryReader { proxy in
                let frames = anchors.mapValues { proxy[$0] }
                Color.clear
                    .onAppear { model.dropZoneFrames = frames }
                    .onChange(of: frames) { _, new in model.dropZoneFrames = new }
            }
        }
        .onDrop(of: model.registry.dropTypes, delegate: IslandDropDelegate(model: model, types: model.registry.dropTypes))
        .environment(\.islandDropTarget, model.dropTarget)
        .onExitCommand(perform: model.onEscape)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
        .environment(\.islandTheme, model.theme)
    }

    /// Ukryta wyspa musi mieć niezerową przezroczystość, inaczej okno nie dostanie zdarzeń myszy.
    private static let hiddenAlpha = 0.01

    /// Karta pod skrzydłami (powiadomienie, podgląd) w zwiniętej wyspie.
    private var showsCard: Bool {
        (model.phase == .collapsed || model.phase == .peek) && model.activity?.detail != nil
    }

    /// Klasyczna wyspa ma cień tylko rozwinięta; nowe motywy także pod kartą.
    private var isRaised: Bool {
        model.phase == .expanded || (model.theme != .classic && showsCard)
    }

    private var topRadius: CGFloat {
        model.phase == .expanded ? IslandLayout.expandedTopRadius : IslandLayout.collapsedTopRadius
    }

    private var bottomRadius: CGFloat {
        switch model.phase {
        case .hidden: 0
        case .collapsed: model.activity?.detail == nil ? Self.collapsedBottomRadius : Self.cardBottomRadius
        case .peek: model.activity?.detail == nil ? Self.peekBottomRadius : Self.cardBottomRadius
        case .expanded: Self.expandedBottomRadius
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .hidden:
            EmptyView()
        case .collapsed, .peek:
            if let activity = model.activity, !model.wingsYielded {
                VStack(spacing: 0) {
                    CollapsedActivityView(activity: activity, notchWidth: model.notch.size.width, namespace: namespace,
                                          slidesIn: activity.id != shownActivityID)
                        .frame(height: model.notch.size.height)
                    if let detail = activity.detail {
                        detail
                            .frame(height: activity.detailHeight)
                            .padding(.horizontal, 12)
                            .id(activity.id + ".detail")
                            .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
                    }
                }
            }
        case .expanded:
            ExpandedIslandView(model: model, namespace: namespace)
                .padding(.top, 8)
                .padding(.bottom, 16)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.92, anchor: .top)).animation(IslandMotion.expand.delay(0.04)),
                    removal: .opacity.animation(.easeOut(duration: 0.12))
                ))
        }
    }
}

/// Skrzydła live activity po obu stronach fizycznego notcha.
///
/// Skrzydła wypełniają bieżącą (animowaną) szerokość wyspy zamiast sztywnej `wingWidth`,
/// więc przy zmianie aktywności rosną i maleją razem z kształtem.
struct CollapsedActivityView: View {
    let activity: LiveActivity
    let notchWidth: CGFloat
    let namespace: Namespace.ID
    /// Wjazd lewego skrzydła tylko dla nowej aktywności, nie przy każdym ponownym pokazaniu tej samej.
    var slidesIn = true

    var body: some View {
        HStack(spacing: 0) {
            activity.leading
                .matchedGeometryEffect(id: ActivityGeometryID.leading(activity), in: namespace)
                .modifier(SlideInFromLeading(isEnabled: slidesIn))
                .frame(maxWidth: .infinity)
            Color.clear.frame(width: notchWidth)
            activity.trailing
                .matchedGeometryEffect(id: ActivityGeometryID.trailing(activity), in: namespace)
                .frame(maxWidth: .infinity)
        }
        // Inna aktywność = inny widok: stara wygasa, nowa się pojawia, zamiast natychmiastowej podmiany treści.
        .id(activity.id)
        .transition(.opacity)
    }
}

/// Identyfikatory dopasowania geometrii zawierają id aktywności, żeby nie łączyć różnych aktywności ze sobą.
enum ActivityGeometryID {
    static func leading(_ activity: LiveActivity) -> String { "activity.\(activity.id).leading" }
    static func trailing(_ activity: LiveActivity) -> String { "activity.\(activity.id).trailing" }
}

/// Zrzut statyczny (zrzuty ekranu do README): bez animacji wejścia. Widok renderowany poza oknem nie odtwarza
/// animacji, więc wjeżdżające skrzydło zostałoby na zrzucie niewidoczne.
public struct IslandStaticSnapshotKey: EnvironmentKey {
    public static let defaultValue = false
}

public extension EnvironmentValues {
    var islandStaticSnapshot: Bool {
        get { self[IslandStaticSnapshotKey.self] }
        set { self[IslandStaticSnapshotKey.self] = newValue }
    }
}

/// Nowa aktywność: zawartość lewego skrzydła wjeżdża z lewej do swojego miejsca przy notchu (przycina ją kształt wyspy).
public struct SlideInFromLeading: ViewModifier {
    static let distance: CGFloat = 28
    /// Wyłączony wjazd = treść od razu na miejscu (ta sama aktywność pokazana ponownie, np. po zwinięciu wyspy).
    @State private var hasAppeared: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.islandStaticSnapshot) private var isStaticSnapshot

    public init(isEnabled: Bool = true) {
        _hasAppeared = State(initialValue: !isEnabled)
    }

    public func body(content: Content) -> some View {
        let isInPlace = hasAppeared || reduceMotion || isStaticSnapshot
        content
            .offset(x: isInPlace ? 0 : -Self.distance)
            .opacity(isInPlace ? 1 : 0)
            .onAppear {
                guard !hasAppeared else { return }
                withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) { hasAppeared = true }
            }
    }
}

public extension View {
    /// Wjazd z lewej przy pojawieniu się (jak lewe skrzydło nowej aktywności).
    func slideInFromLeading() -> some View { modifier(SlideInFromLeading()) }
}
