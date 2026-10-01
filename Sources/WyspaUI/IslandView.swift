import SwiftUI
import WyspaCore

/// Korzeń wyspy: czarny kształt przy górnej krawędzi i zawartość zależna od fazy.
public struct IslandView: View {
    private static let collapsedBottomRadius: CGFloat = 10
    private static let peekBottomRadius: CGFloat = 13
    private static let expandedBottomRadius: CGFloat = 28
    private static let contentInset: CGFloat = 20

    @Bindable var model: IslandViewModel
    @Namespace private var namespace

    public init(model: IslandViewModel) {
        self.model = model
    }

    public var body: some View {
        let size = model.islandSize
        ZStack(alignment: .top) {
            IslandShape(topRadius: topRadius, bottomRadius: bottomRadius)
                .fill(Color.black.opacity(model.phase == .hidden ? Self.hiddenAlpha : 1))
                .shadow(color: .black.opacity(model.phase == .expanded ? 0.5 : 0), radius: 20, y: 10)
                .contentShape(IslandShape(topRadius: topRadius, bottomRadius: bottomRadius))
                .onTapGesture {
                    // W rozwiniętej wyspie kliknięcia obsługują kontrolki modułów.
                    if model.phase != .expanded { model.onClick() }
                }

            content
                .padding(.horizontal, model.phase == .expanded ? topRadius + Self.contentInset : topRadius)
        }
        .frame(width: size.width, height: size.height)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
    }

    /// Ukryta wyspa musi mieć niezerową przezroczystość, inaczej okno nie dostanie zdarzeń myszy.
    private static let hiddenAlpha = 0.01

    private var topRadius: CGFloat {
        model.phase == .expanded ? IslandLayout.expandedTopRadius : IslandLayout.collapsedTopRadius
    }

    private var bottomRadius: CGFloat {
        switch model.phase {
        case .hidden: 0
        case .collapsed: Self.collapsedBottomRadius
        case .peek: Self.peekBottomRadius
        case .expanded: Self.expandedBottomRadius
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .hidden:
            EmptyView()
        case .collapsed, .peek:
            if let activity = model.activity {
                CollapsedActivityView(activity: activity, notchWidth: model.notch.size.width, namespace: namespace)
                    .frame(height: model.notch.size.height)
                    .transition(.opacity)
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
struct CollapsedActivityView: View {
    let activity: LiveActivity
    let notchWidth: CGFloat
    let namespace: Namespace.ID

    var body: some View {
        HStack(spacing: 0) {
            activity.leading
                .matchedGeometryEffect(id: "activity.leading", in: namespace)
                .frame(width: activity.wingWidth)
            Color.clear.frame(width: notchWidth)
            activity.trailing
                .matchedGeometryEffect(id: "activity.trailing", in: namespace)
                .frame(width: activity.wingWidth)
        }
    }
}
