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

    @ViewBuilder
    private func header(tabs: [ModuleTab]) -> some View {
        HStack(spacing: 10) {
            if let activity = model.activity {
                activity.leading
                    .matchedGeometryEffect(id: ActivityGeometryID.leading(activity), in: namespace)
                    .frame(width: activity.wingWidth)
            }
            ClockLabel()
            // Środek nagłówka leży pod fizycznym notchem i musi pozostać pusty.
            Spacer(minLength: model.notch.isPhysical ? model.notch.size.width : 12)
            if tabs.count > 1 {
                TabStrip(tabs: tabs, selected: min(model.selectedTab, tabs.count - 1), select: model.onSelectTab)
            }
            if let activity = model.activity {
                activity.trailing
                    .matchedGeometryEffect(id: ActivityGeometryID.trailing(activity), in: namespace)
                    .frame(width: activity.wingWidth)
            }
        }
    }
}

private struct ClockLabel: View {
    var body: some View {
        TimelineView(.everyMinute) { context in
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(context.date, format: .dateTime.hour().minute())
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(context.date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .fixedSize()
        }
    }
}

private struct TabStrip: View {
    let tabs: [ModuleTab]
    let selected: Int
    let select: (Int) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                TabButton(symbol: tab.symbol, name: tab.name, isSelected: index == selected) {
                    select(index)
                }
            }
        }
    }
}

private struct TabButton: View {
    let symbol: String
    let name: String
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 26, height: 22)
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
