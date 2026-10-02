import SwiftUI
import WyspaCore

/// Które moduły mają zakładkę w rozwiniętej wyspie i w jakiej kolejności (przeciąganie).
struct TabsSettingsView: View {
    @Bindable var settings: SettingsStore
    let registry: ModuleRegistry

    var body: some View {
        let tabs = registry.allTabs
        VStack(alignment: .leading, spacing: 0) {
            if tabs.isEmpty {
                ContentUnavailableView(
                    "Brak zakładek",
                    systemImage: "rectangle.3.group",
                    description: Text("Włącz moduły w karcie Moduły — ich zakładki pojawią się tutaj.")
                )
            } else {
                List {
                    Section {
                        ForEach(tabs) { tab in
                            TabRow(tab: tab, isVisible: !settings.hiddenTabs.contains(tab.id)) { visible in
                                settings.setTab(tab.id, visible: visible)
                            }
                        }
                        .onMove { source, destination in
                            var ids = tabs.map(\.id)
                            ids.move(fromOffsets: source, toOffset: destination)
                            settings.setTabOrder(ids)
                        }
                    } header: {
                        Text("Przeciągnij, żeby zmienić kolejność. Wyłączona zakładka znika z wyspy, a moduł działa dalej.")
                    } footer: {
                        Text(capacityText(visibleCount: tabs.filter { !settings.hiddenTabs.contains($0.id) }.count))
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: false))
            }
        }
    }

    private func capacityText(visibleCount: Int) -> String {
        let notch = ScreenInfo.current().first(where: \.notch.isPhysical)?.notch.size.width ?? 12
        let available = IslandLayout.headerSideWidth(islandWidth: settings.islandSize.expandedSize.width, notchGap: notch)
        let fits = TabStripPlan.capacity(available: available, style: .regular)
        let base = "Wyspa „\(settings.islandSize.displayName)” mieści od razu \(fits) zakładek."
        return visibleCount > fits
            ? base + " Pozostałe są w menu ⋯ w nagłówku wyspy. Większy rozmiar wyspy zmieścisz w karcie Wyspa."
            : base
    }
}

private struct TabRow: View {
    let tab: ModuleTab
    let isVisible: Bool
    let setVisible: @MainActor (Bool) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .help("Przeciągnij, żeby zmienić kolejność")
            Image(systemName: tab.symbol)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary))
            Text(tab.name)
                .foregroundStyle(isVisible ? .primary : .secondary)
            Spacer()
            Toggle("W wyspie", isOn: Binding(get: { isVisible }, set: setVisible))
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.vertical, 2)
    }
}
