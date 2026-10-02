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

            RightHeader(model: model, tabs: tabs, plan: plan(for: tabs)) { trailingWing }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    /// Ile zakładek się mieści przy bieżącej szerokości wyspy (czysta funkcja, testowana w Core).
    private func plan(for tabs: [ModuleTab]) -> TabStripPlan {
        TabStripPlan.make(
            tabCount: tabs.count,
            selected: model.selectedTab,
            available: IslandLayout.headerSideWidth(islandWidth: model.islandSize.width, notchGap: notchGap),
            wingWidth: model.activity?.wingWidth
        )
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

}

/// Prawa połowa nagłówka według planu: zakładki, menu „⋯” z pozostałymi i skrzydło aktywności.
private struct RightHeader<Wing: View>: View {
    let model: IslandViewModel
    let tabs: [ModuleTab]
    let plan: TabStripPlan
    @ViewBuilder let wing: () -> Wing

    var body: some View {
        let selected = min(model.selectedTab, max(tabs.count - 1, 0))
        HStack(spacing: plan.style.spacing) {
            ForEach(plan.visible, id: \.self) { index in
                TabButton(symbol: tabs[index].symbol, name: tabs[index].name, isSelected: index == selected,
                          width: plan.style.buttonWidth) {
                    model.onSelectTab(index)
                }
            }
            if !plan.overflow.isEmpty {
                OverflowMenu(tabs: tabs, indices: plan.overflow, select: model.onSelectTab)
            }
            if plan.showsWing {
                wing().padding(.leading, TabStripPlan.wingSpacing - plan.style.spacing)
            }
        }
        .fixedSize()
    }
}

/// Zakładki, które nie zmieściły się w pasku.
private struct OverflowMenu: View {
    let tabs: [ModuleTab]
    let indices: [Int]
    let select: (Int) -> Void

    var body: some View {
        Menu {
            ForEach(indices, id: \.self) { index in
                Button { select(index) } label: { Label(tabs[index].name, systemImage: tabs[index].symbol) }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: TabStripPlan.overflowButtonWidth, height: 22)
                .foregroundStyle(.white.opacity(0.6))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Więcej zakładek")
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

private struct TabButton: View {
    let symbol: String
    let name: String
    let isSelected: Bool
    let width: CGFloat
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: width, height: 22)
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
