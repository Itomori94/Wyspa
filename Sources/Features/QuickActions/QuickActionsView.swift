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

    private func tile(_ action: QuickActionsModule.Action) -> some View {
        let spec = TileSpec.make(action, module: module, compact: compact)
        return ActionTile(spec: spec, compact: compact, tap: module.taps[action, default: 0],
                          isBusy: module.busy.contains(action)) { module.run(action) }
    }
}

/// Wygląd i animacje kafelka jednej akcji.
struct TileSpec {
    var symbol: String
    var title: String
    /// Włączony stan (tryb ciemny, nie usypiaj, nagrywanie) — jasny kafelek zamiast animacji w kółko.
    var isOn = false
    var tapEffect: TapEffect = .bounce
    var busyEffect: BusyEffect = .pulse
    /// Efekt po najechaniu (domyślnie lekki podskok; słońce się obraca).
    var hoverEffect: TapEffect = .bounce

    /// Stan potrzebny do wyglądu kafelka — z modułu albo symulowany w pokazie animacji.
    struct State {
        var isDarkMode = false
        var desktopIconsVisible = true
        var isKeepingAwake = false
        var isRecording = false
        var isDone = false
    }

    @MainActor
    static func make(_ action: QuickActionsModule.Action, module: QuickActionsModule, compact: Bool) -> TileSpec {
        make(action, state: State(isDarkMode: module.isDarkMode, desktopIconsVisible: module.desktopIconsVisible,
                                  isKeepingAwake: module.isKeepingAwake,
                                  isRecording: module.busy.contains(.record), isDone: module.confirmed.contains(action)),
             compact: compact)
    }

    static func make(_ action: QuickActionsModule.Action, state: State, compact: Bool) -> TileSpec {
        let done = state.isDone
        switch action {
        case .capture:
            return TileSpec(symbol: done ? "checkmark.circle.fill" : "camera.viewfinder",
                            title: compact ? "Zrzut" : "Zrzut na Półkę")
        case .captureScreen:
            return TileSpec(symbol: done ? "checkmark.circle.fill" : "macwindow", title: "Cały ekran")
        case .captureText:
            return TileSpec(symbol: done ? "checkmark.circle.fill" : "text.viewfinder",
                            title: compact ? "Tekst" : "Tekst ze zrzutu", busyEffect: .breathe)
        case .record:
            return TileSpec(symbol: done ? "checkmark.circle.fill" : state.isRecording ? "record.circle.fill" : "record.circle",
                            title: "Nagrywanie", isOn: state.isRecording)
        case .pickColor:
            return TileSpec(symbol: done ? "checkmark.circle.fill" : "eyedropper", title: compact ? "Pipeta" : "Pipeta koloru", tapEffect: .wiggle)
        case .password:
            return TileSpec(symbol: done ? "checkmark.circle.fill" : "key.fill", title: "Hasło", tapEffect: .rotate)
        case .darkMode:
            return TileSpec(symbol: state.isDarkMode ? "moon.fill" : "sun.max.fill",
                            title: state.isDarkMode ? "Tryb ciemny" : "Tryb jasny", isOn: state.isDarkMode,
                            hoverEffect: state.isDarkMode ? .bounce : .rotate)
        case .desktopIcons:
            return TileSpec(symbol: state.desktopIconsVisible ? "eye" : "eye.slash",
                            title: state.desktopIconsVisible ? "Ukryj biurko" : "Pokaż biurko",
                            isOn: !state.desktopIconsVisible)
        case .lock:
            return TileSpec(symbol: done ? "lock.fill" : "lock.open.fill", title: compact ? "Blokada" : "Zablokuj ekran")
        case .keepAwake:
            return TileSpec(symbol: state.isKeepingAwake ? "cup.and.heat.waves.fill" : "cup.and.saucer",
                            title: state.isKeepingAwake ? "Nie usypia" : "Nie usypiaj", isOn: state.isKeepingAwake)
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

struct ActionTile: View {
    let spec: TileSpec
    let compact: Bool
    let tap: Int
    /// Krótka akcja w toku (zaznaczanie obszaru, rozpoznawanie tekstu).
    let isBusy: Bool
    let action: () -> Void
    @State private var isHovered = false
    @State private var hoverCount = 0
    @Environment(\.tileLayout) private var layout

    var body: some View {
        Button(action: action) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(spec.isOn ? .white.opacity(isHovered ? 1 : 0.9) : .white.opacity(isHovered ? 0.14 : 0.07))
                )
        }
        .buttonStyle(IslandPressStyle())
        .onHover { inside in
            isHovered = inside
            if inside { hoverCount += 1 }
        }
        .help(spec.title)
        .accessibilityLabel(spec.title)
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
        Image(systemName: spec.symbol)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(spec.isOn ? .black : .white.opacity(0.9))
            .symbolSwapTransition()
            .tapEffect(spec.tapEffect, value: tap)
            .tapEffect(spec.hoverEffect, value: hoverCount)
            // Animacja w toku tylko dla krótkich czynności (zaznaczanie, rozpoznawanie); stan włączony to jasny kafelek.
            .busyEffect(spec.busyEffect, isActive: isBusy && !spec.isOn)
            .animation(.snappy, value: spec.symbol)
    }

    private func label(size: CGFloat) -> some View {
        Text(spec.title)
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(spec.isOn ? .black : .white.opacity(0.85))
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
