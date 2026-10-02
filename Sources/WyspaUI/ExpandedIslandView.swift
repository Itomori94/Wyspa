import SwiftUI
import WyspaCore

/// Rozwinięta wyspa: nagłówek (aktywność, zegar, zakładki) i zawartość wybranej zakładki.
struct ExpandedIslandView: View {
    @Bindable var model: IslandViewModel
    let namespace: Namespace.ID

    var body: some View {
        let tabs = model.registry.tabs
        VStack(alignment: .leading, spacing: 12) {
            header(tabs: tabs)
                .frame(height: max(model.notch.size.height - 8, 24))
            Group {
                if tabs.isEmpty {
                    EmptyModulesView(openSettings: model.onOpenSettings)
                } else {
                    let index = min(model.selectedTab, tabs.count - 1)
                    tabs[index].content
                        .id(tabs[index].id)
                        .transition(.opacity.combined(with: .offset(y: 6)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .animation(IslandMotion.tab, value: model.selectedTab)
        }
        .foregroundStyle(.white)
    }

    /// Nagłówek z trzech kolumn: lewa połowa, pusta przerwa pod notchem, prawa połowa.
    ///
    /// Połowy mają szerokość wynikającą z wyspy; każda wybiera pierwszy wariant, który się mieści,
    /// a ostatni wariant mieści się zawsze. Dzięki temu nagłówek nigdy nie poszerza wyspy.
    private func header(tabs: [ModuleTab]) -> some View {
        HStack(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { leadingWing; ClockLabel(style: .full) }
                HStack(spacing: 10) { leadingWing; ClockLabel(style: .timeOnly) }
                HStack(spacing: 10) { leadingWing }
                Color.clear.frame(width: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Color.clear.frame(width: notchGap)

            // Zakładki są nawigacją, prawe skrzydło aktywności ozdobą (lewe zostaje):
            // przy braku miejsca najpierw znika skrzydło, dopiero potem zakładki przechodzą w przewijanie.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { tabStrip(tabs, style: .regular); trailingWing }
                HStack(spacing: 8) { tabStrip(tabs, style: .compact); trailingWing }
                tabStrip(tabs, style: .regular)
                tabStrip(tabs, style: .compact)
                ScrollingTabStrip(model: model, tabs: tabs)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    /// Środek nagłówka pod fizycznym notchem musi pozostać pusty.
    private var notchGap: CGFloat {
        model.notch.isPhysical ? model.notch.size.width : 12
    }

    @ViewBuilder
    private var leadingWing: some View {
        if let activity = model.activity {
            activity.leading
                .matchedGeometryEffect(id: ActivityGeometryID.leading(activity), in: namespace)
                .frame(width: activity.wingWidth)
        }
    }

    @ViewBuilder
    private var trailingWing: some View {
        if let activity = model.activity {
            activity.trailing
                .matchedGeometryEffect(id: ActivityGeometryID.trailing(activity), in: namespace)
                .frame(width: activity.wingWidth)
        }
    }

    @ViewBuilder
    private func tabStrip(_ tabs: [ModuleTab], style: TabStyle) -> some View {
        if tabs.count > 1 {
            TabStrip(tabs: tabs, selected: min(model.selectedTab, tabs.count - 1), style: style, select: model.onSelectTab)
        }
    }
}

/// Ostatni wariant prawej połowy: przewijany pasek zakładek mieści się w każdej szerokości.
private struct ScrollingTabStrip: View {
    let model: IslandViewModel
    let tabs: [ModuleTab]

    var body: some View {
        if tabs.count > 1 {
            let selected = min(model.selectedTab, tabs.count - 1)
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    TabStrip(tabs: tabs, selected: selected, style: .compact, select: model.onSelectTab)
                }
                .onChange(of: selected, initial: true) { _, index in
                    withAnimation(IslandMotion.tab) { proxy.scrollTo(tabs[index].id, anchor: .center) }
                }
            }
        }
    }
}

enum TabStyle {
    case regular, compact

    var size: CGSize {
        switch self {
        case .regular: CGSize(width: 26, height: 22)
        case .compact: CGSize(width: 22, height: 22)
        }
    }

    var spacing: CGFloat {
        switch self {
        case .regular: 4
        case .compact: 2
        }
    }
}

private struct ClockLabel: View {
    enum Style { case full, timeOnly }

    let style: Style

    var body: some View {
        TimelineView(.everyMinute) { context in
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(context.date, format: .dateTime.hour().minute())
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                if style == .full {
                    Text(context.date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .fixedSize()
        }
    }
}

private struct TabStrip: View {
    let tabs: [ModuleTab]
    let selected: Int
    let style: TabStyle
    let select: (Int) -> Void

    var body: some View {
        HStack(spacing: style.spacing) {
            ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                TabButton(symbol: tab.symbol, name: tab.name, isSelected: index == selected, size: style.size) {
                    select(index)
                }
                .id(tab.id)
            }
        }
        .fixedSize()
    }
}

private struct TabButton: View {
    let symbol: String
    let name: String
    let isSelected: Bool
    let size: CGSize
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: size.width, height: size.height)
                .foregroundStyle(.white.opacity(isSelected ? 1 : 0.5))
                .background(
                    Capsule().fill(.white.opacity(isSelected ? 0.18 : (isHovered ? 0.08 : 0)))
                )
        }
        .buttonStyle(IslandPressStyle())
        .onHover { isHovered = $0 }
        .help(name)
        .accessibilityLabel(name)
        .animation(.easeOut(duration: 0.15), value: isHovered)
    }
}

/// Wyspa bez włączonych modułów: wskazówka zamiast pustego czarnego prostokąta.
private struct EmptyModulesView: View {
    let openSettings: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.white.opacity(0.35))
            VStack(alignment: .leading, spacing: 4) {
                Text("Wyspa jest gotowa")
                    .font(.system(size: 14, weight: .semibold))
                Text("Włącz moduły w ustawieniach, żeby coś tu się pojawiło.")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.55))
            }
            Spacer()
            Button("Ustawienia…", action: openSettings)
                .buttonStyle(IslandCapsuleButtonStyle())
        }
        .frame(maxHeight: .infinity)
    }
}
