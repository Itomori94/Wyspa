import SwiftUI
import WyspaUI

struct QuickActionsView: View {
    let module: QuickActionsModule
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Kratka dopasowana do szerokości i wysokości: kolumny z szerokości, a wysokość kafelków z miejsca, które
            // zostaje — nic nie jest ucinane ani przewijane, przy ciasnym miejscu kafelek przechodzi w niższy układ.
            GeometryReader { proxy in
                let tiles = module.visibleActions.count
                let columns = Self.columnCount(width: proxy.size.width, compact: compact, tiles: tiles)
                let height = Self.tileHeight(available: proxy.size.height, tiles: tiles, columns: columns)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Self.spacing), count: columns),
                          spacing: Self.spacing) {
                    ForEach(module.visibleActions, id: \.self) { action in
                        tile(action).frame(height: height)
                    }
                }
                .environment(\.tileLayout, ActionTileLayout(height: height,
                                                             width: Self.tileWidth(available: proxy.size.width, columns: columns)))
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

    nonisolated static let spacing: CGFloat = 8
    /// Większych kafelków nie robimy, nawet gdy miejsca jest dużo.
    nonisolated static let maxTileHeight: CGFloat = 76

    /// Wysokość kafelka, przy której wszystkie rzędy mieszczą się w dostępnej wysokości.
    nonisolated static func tileHeight(available: CGFloat, tiles: Int, columns: Int) -> CGFloat {
        let rows = max(1, Int((Double(tiles) / Double(max(columns, 1))).rounded(.up)))
        let fitting = (available - spacing * CGFloat(rows - 1)) / CGFloat(rows)
        return max(0, min(maxTileHeight, fitting.rounded(.down)))
    }

    nonisolated static func tileWidth(available: CGFloat, columns: Int) -> CGFloat {
        (available - spacing * CGFloat(max(columns, 1) - 1)) / CGFloat(max(columns, 1))
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

/// Układ kafelka zależny od jego wysokości: ikona nad napisem, ikona obok napisu albo sama ikona.
enum ActionTileLayout: Equatable {
    case stacked
    case inline
    case iconOnly

    /// Napis obok ikony potrzebuje szerokości; w wąskim kafelku zostaje sama ikona (nazwa w podpowiedzi).
    static let minimumInlineWidth: CGFloat = 112

    init(height: CGFloat, width: CGFloat = .infinity) {
        if height >= 54 {
            self = .stacked
        } else if height >= 30, width >= Self.minimumInlineWidth {
            self = .inline
        } else {
            self = .iconOnly
        }
    }
}

private struct TileLayoutKey: EnvironmentKey {
    static let defaultValue = ActionTileLayout.stacked
}

extension EnvironmentValues {
    var tileLayout: ActionTileLayout {
        get { self[TileLayoutKey.self] }
        set { self[TileLayoutKey.self] = newValue }
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
    @Environment(\.tileLayout) private var layout

    var body: some View {
        Button(action: action) {
            content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isOn ? tint : .white.opacity(isHovered ? 0.14 : 0.07))
            )
        }
        .buttonStyle(IslandPressStyle())
        .onHover { isHovered = $0 }
        .help(title)
        .accessibilityLabel(title)
    }

    @ViewBuilder
    private var content: some View {
        switch layout {
        case .stacked:
            VStack(spacing: compact ? 3 : 6) {
                icon(size: compact ? 15 : 20)
                label(size: compact ? 9.5 : 11)
            }
        case .inline:
            HStack(spacing: 6) {
                icon(size: compact ? 13 : 15)
                label(size: compact ? 9.5 : 11)
            }
            .padding(.horizontal, 6)
        case .iconOnly:
            icon(size: compact ? 16 : 18)
        }
    }

    private func icon(size: CGFloat) -> some View {
        Image(systemName: symbol)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(isOn ? .black : tint)
    }

    private func label(size: CGFloat) -> some View {
        Text(title)
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(isOn ? .black : .white.opacity(0.85))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
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
