import SwiftUI
import WyspaCore

/// Rozwinięta wyspa: nagłówek (aktywność, zegar, strony) i zawartość wybranej strony.
struct ExpandedIslandView: View {
    @Bindable var model: IslandViewModel
    let namespace: Namespace.ID

    var body: some View {
        let tabs = model.registry.pages
        VStack(alignment: .leading, spacing: 12) {
            header(tabs: tabs)
                .frame(height: max(model.notch.size.height - 8, 24))
            Group {
                if let standalone = model.standaloneModuleID, let view = model.registry.standaloneView(for: standalone) {
                    view
                        .id("standalone." + standalone)
                        .transition(.opacity.combined(with: .offset(y: 6)))
                } else if tabs.isEmpty {
                    EmptyModulesView(openSettings: model.onOpenSettings)
                } else {
                    let index = min(model.selectedTab, tabs.count - 1)
                    PageContentView(page: tabs[index])
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
    private func header(tabs: [IslandPage]) -> some View {
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
    private func plan(for tabs: [IslandPage]) -> TabStripPlan {
        TabStripPlan.make(
            tabCount: tabs.count,
            selected: model.selectedTab,
            available: IslandLayout.headerSideWidth(islandWidth: model.islandSize.width, notchGap: notchGap),
            wingWidth: headerActivity?.wingWidth
        )
    }

    /// Środek nagłówka pod fizycznym notchem musi pozostać pusty.
    private var notchGap: CGFloat {
        model.notch.isPhysical ? model.notch.size.width : 12
    }

    /// Aktywność pokazywana w nagłówku: nie ta, której treść dubluje widoczną stronę (np. timer obok widżetu timera).
    private var headerActivity: LiveActivity? {
        guard let current = model.registry.currentActivityWithSource else { return nil }
        let pages = model.registry.pages
        let pageModuleIDs = model.standaloneModuleID.map { [$0] }
            ?? (pages.isEmpty ? [] : pages[min(model.selectedTab, pages.count - 1)].moduleIDs)
        return ModuleRegistry.showsInHeader(current.activity, from: current.moduleID, pageModuleIDs: pageModuleIDs)
            ? current.activity : nil
    }

    @ViewBuilder
    private var leadingWing: some View {
        if let activity = headerActivity {
            activity.leading
                .matchedGeometryEffect(id: ActivityGeometryID.leading(activity), in: namespace)
                .frame(width: activity.wingWidth)
                .contentShape(Rectangle())
                .onTapGesture(perform: model.onOpenActivity)
                .help("Otwórz moduł")
        }
    }

    @ViewBuilder
    private var trailingWing: some View {
        if let activity = headerActivity {
            activity.trailing
                .matchedGeometryEffect(id: ActivityGeometryID.trailing(activity), in: namespace)
                .frame(width: activity.wingWidth)
                .contentShape(Rectangle())
                .onTapGesture(perform: model.onOpenActivity)
                .help("Otwórz moduł")
        }
    }

}

/// Prawa połowa nagłówka według planu: zakładki, menu „⋯” z pozostałymi i skrzydło aktywności.
private struct RightHeader<Wing: View>: View {
    let model: IslandViewModel
    let tabs: [IslandPage]
    let plan: TabStripPlan
    @ViewBuilder let wing: () -> Wing

    var body: some View {
        let selected = min(model.selectedTab, max(tabs.count - 1, 0))
        HStack(spacing: plan.style.spacing) {
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
            }
            .modifier(TabStripBackground(theme: model.theme))
            if plan.showsWing {
                wing().padding(.leading, TabStripPlan.wingSpacing - plan.style.spacing)
            }
        }
        .fixedSize()
    }
}

/// Zakładki, które nie zmieściły się w pasku.
private struct OverflowMenu: View {
    let tabs: [IslandPage]
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

/// Zawartość strony: pełny widok modułu albo widżety obok siebie z cienkimi dzielnikami.
public struct PageContentView: View {
    let page: IslandPage

    public init(page: IslandPage) {
        self.page = page
    }

    public var body: some View {
        switch page.content {
        case .module(let view):
            view
        case .widgets(let widgets):
            WidgetRow(widgets: widgets)
        }
    }
}

/// Widżety według ich szerokości, zawsze na całą szerokość strony (proporcjonalnie),
/// także gdy któryś moduł jest chwilowo wyłączony.
public struct WidgetRow: View {
    public static let dividerSpacing: CGFloat = 14

    let widgets: [IslandPage.Widget]
    @Environment(\.islandTheme) private var theme

    /// Czarna tafla: każdy widżet na własnej karcie, z odstępem zamiast kreski.
    private var gap: CGFloat { theme == .blackSheet ? 8 : Self.dividerSpacing }

    public var body: some View {
        GeometryReader { proxy in
            let gaps = CGFloat(max(widgets.count - 1, 0)) * gap
            let totalUnits = max(widgets.map(\.width.units).reduce(0, +), 1)
            let unit = max(0, proxy.size.width - gaps) / CGFloat(totalUnits)
            HStack(spacing: 0) {
                ForEach(Array(widgets.enumerated()), id: \.element.id) { index, widget in
                    if index > 0 {
                        if theme == .blackSheet {
                            Color.clear.frame(width: gap)
                        } else {
                            Rectangle()
                                .fill(.white.opacity(theme == .glass ? 0.18 : 0.1))
                                .frame(width: 1)
                                .padding(.vertical, 6)
                                .frame(width: gap)
                        }
                    }
                    widgetView(widget.content, backdrop: widget.backdrop, width: unit * CGFloat(widget.width.units),
                               isFirst: index == 0, isLast: index == widgets.count - 1)
                }
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder
    private func widgetView(_ content: AnyView, backdrop: IslandBackdrop?, width: CGFloat, isFirst: Bool,
                            isLast: Bool) -> some View {
        if theme == .blackSheet {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .clipped()
                .modifier(WidgetCard())
                .background { WidgetBackdrop(backdrop: backdrop) }
                .frame(width: width)
        } else if backdrop != nil {
            // Widżet z tłem (np. rozmyta okładka): na własnej karcie, jak w Czarnej tafli.
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(WidgetCard.padding)
                .background { WidgetBackdrop(backdrop: backdrop) }
                .frame(width: width)
        } else {
            content
                .frame(width: width, alignment: .topLeading)
                .frame(maxHeight: .infinity, alignment: .top)
                // Przycięcie z zapasem tam, gdzie obok nie ma innego widżetu (góra, dół, brzegi wyspy): poświata
                // okładki i cienie wygasają płynnie zamiast kończyć się prostą linią. Między widżetami — bez zapasu.
                .clipShape(OutsetRectangle(top: Self.glowRoom, leading: isFirst ? Self.glowRoom : 0,
                                           bottom: Self.glowRoom, trailing: isLast ? Self.glowRoom : 0))
        }
    }

    /// Ile poświaty może wyjść poza widżet (cień okładki: promień 14 + przesunięcie 4).
    static let glowRoom: CGFloat = 20
}

/// Tło widżetu na karcie o zaokrąglonych rogach, z przenikaniem przy zmianie (np. nowy utwór).
private struct WidgetBackdrop: View {
    let backdrop: IslandBackdrop?

    var body: some View {
        ZStack {
            if let backdrop {
                BackdropLayer(backdrop: backdrop)
                    .id(backdrop.id)
                    .transition(.opacity)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: WidgetCard.cornerRadius, style: .continuous))
        .animation(.easeInOut(duration: 0.5), value: backdrop?.id)
    }
}

/// Prostokąt powiększony o zapas z każdej strony — do przycinania z miejscem na cienie.
public struct OutsetRectangle: Shape {
    let top: CGFloat
    let leading: CGFloat
    let bottom: CGFloat
    let trailing: CGFloat

    public init(top: CGFloat = 0, leading: CGFloat = 0, bottom: CGFloat = 0, trailing: CGFloat = 0) {
        self.top = top
        self.leading = leading
        self.bottom = bottom
        self.trailing = trailing
    }

    public func path(in rect: CGRect) -> Path {
        Path(CGRect(x: rect.minX - leading, y: rect.minY - top,
                    width: rect.width + leading + trailing, height: rect.height + top + bottom))
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
    @Environment(\.islandTheme) private var theme

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: width, height: theme == .blackSheet ? 20 : 22)
                .foregroundStyle(.white.opacity(isSelected ? 1 : (theme == .classic ? 0.5 : 0.6)))
                .background(TabPill(theme: theme, isSelected: isSelected, isHovered: isHovered))
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
