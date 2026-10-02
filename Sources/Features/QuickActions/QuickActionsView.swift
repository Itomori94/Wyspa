import SwiftUI
import WyspaUI

struct QuickActionsView: View {
    let module: QuickActionsModule
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Kratka dopasowana do szerokości: w wąskim widżecie 2 kolumny, w szerszym więcej (najwyżej 4).
            GeometryReader { proxy in
                let columns = Self.columnCount(width: proxy.size.width, compact: compact, tiles: module.visibleActions.count)
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columns), spacing: 8) {
                        ForEach(module.visibleActions, id: \.self) { action in
                            tile(action)
                        }
                    }
                }
                .scrollIndicators(.never)
            }
            if let feedback = module.feedback {
                Text(feedback)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear(perform: module.refreshSystemState)
    }

    /// Ile kolumn mieści się w danej szerokości (kafelek najmniej 64 pt w widżecie, 110 pt na pełnej stronie).
    /// Czysta funkcja bez stanu widoku — `nonisolated`, żeby testy mogły ją wołać poza głównym aktorem.
    nonisolated static func columnCount(width: CGFloat, compact: Bool, tiles: Int) -> Int {
        let minimum: CGFloat = compact ? 64 : 110
        let fitting = Int((width + 8) / (minimum + 8))
        return max(1, min(fitting, 4, tiles))
    }

    @ViewBuilder
    private func tile(_ action: QuickActionsModule.Action) -> some View {
        switch action {
        case .capture:
            ActionTile(symbol: "camera.viewfinder", title: compact ? "Zrzut" : "Zrzut na Półkę", tint: .blue, compact: compact,
                       action: module.captureToShelf)
        case .captureScreen:
            ActionTile(symbol: "macwindow", title: "Cały ekran", tint: .blue, compact: compact, action: module.captureScreen)
        case .captureText:
            ActionTile(symbol: "text.viewfinder", title: compact ? "Tekst" : "Tekst ze zrzutu", tint: .green, compact: compact,
                       action: module.captureText)
        case .record:
            ActionTile(symbol: "record.circle", title: "Nagrywanie", tint: .red, compact: compact, action: module.startRecording)
        case .pickColor:
            ActionTile(symbol: "eyedropper", title: compact ? "Pipeta" : "Pipeta koloru", tint: .pink, compact: compact,
                       action: module.pickColor)
        case .password:
            ActionTile(symbol: "key.fill", title: "Hasło", tint: .yellow, compact: compact, action: module.copyPassword)
        case .darkMode:
            ActionTile(symbol: module.isDarkMode ? "moon.fill" : "sun.max.fill", title: module.isDarkMode ? "Tryb ciemny" : "Tryb jasny",
                       tint: .indigo, compact: compact, isOn: module.isDarkMode, action: module.toggleDarkMode)
        case .desktopIcons:
            ActionTile(symbol: module.desktopIconsVisible ? "menubar.dock.rectangle" : "eye.slash",
                       title: module.desktopIconsVisible ? "Ukryj biurko" : "Pokaż biurko",
                       tint: .teal, compact: compact, isOn: !module.desktopIconsVisible, action: module.toggleDesktopIcons)
        case .lock:
            ActionTile(symbol: "lock.fill", title: compact ? "Blokada" : "Zablokuj ekran", tint: .gray, compact: compact,
                       action: module.lockScreen)
        case .keepAwake:
            ActionTile(symbol: module.isKeepingAwake ? "cup.and.saucer.fill" : "cup.and.saucer",
                       title: module.isKeepingAwake ? "Nie usypia" : "Nie usypiaj", tint: .orange, compact: compact,
                       isOn: module.isKeepingAwake, action: { module.toggleKeepAwake() })
        }
    }
}

private struct ActionTile: View {
    let symbol: String
    let title: String
    let tint: Color
    let compact: Bool
    var isOn = false
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: compact ? 3 : 6) {
                Image(systemName: symbol)
                    .font(.system(size: compact ? 15 : 20, weight: .semibold))
                    .foregroundStyle(isOn ? .black : tint)
                    .frame(height: compact ? 18 : 24)
                Text(title)
                    .font(.system(size: compact ? 9.5 : 11, weight: .medium))
                    .foregroundStyle(isOn ? .black : .white.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, compact ? 5 : 9)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isOn ? tint : .white.opacity(isHovered ? 0.14 : 0.07))
            )
        }
        .buttonStyle(IslandPressStyle())
        .onHover { isHovered = $0 }
        .accessibilityLabel(title)
    }
}

struct QuickActionsSettingsView: View {
    let module: QuickActionsModule

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Kafelki w wyspie").font(.headline)
            ForEach(Array(module.slots.enumerated()), id: \.offset) { index, slot in
                HStack(spacing: 10) {
                    Text("\(index + 1).").monospacedDigit().foregroundStyle(.secondary).frame(width: 20, alignment: .trailing)
                    Picker("", selection: Binding(get: { slot.action }, set: { module.chooseAction($0, at: index) })) {
                        ForEach(QuickActionsModule.Action.allCases, id: \.self) { action in
                            Label(action.displayName, systemImage: action.symbol).tag(action)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 260)
                    .disabled(!slot.isEnabled)
                    Spacer()
                    Toggle("", isOn: Binding(get: { slot.isEnabled }, set: { module.setSlot($0, at: index) }))
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .disabled(!module.canSetSlot(!slot.isEnabled, at: index))
                }
            }
            Text("Wybór akcji, która jest już w innym miejscu, zamienia je miejscami. Najmniej 2 kafelki muszą zostać włączone.")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            Text("Skróty klawiszowe").font(.headline)
            ForEach(QuickActionsModule.Action.allCases, id: \.self) { action in
                LabeledContent(action.displayName) {
                    ShortcutRecorder(shortcut: Binding(
                        get: { module.shortcuts[action] },
                        set: { module.setShortcut($0, for: action) }
                    ))
                }
            }
            if let problem = module.shortcutProblem {
                Text(problem).font(.caption).foregroundStyle(.orange)
            }
            Text("Skróty działają w całym systemie, także przy zwiniętej wyspie.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
