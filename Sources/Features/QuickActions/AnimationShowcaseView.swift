import SwiftUI
import WyspaUI

/// Pokaz animacji: wszystkie animacje ikon odgrywane w kółko na prawdziwych kafelkach, bez wykonywania akcji
/// (mikrofon, schowek, tryb ciemny ani ekran się nie zmieniają). Zegar działa tylko, gdy okno pokazu jest otwarte.
public struct AnimationShowcaseView: View {
    static let stepDuration: Duration = .milliseconds(1600)
    static let steps = 4
    @State private var step = 0

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Pokaz animacji").font(.title2.bold())
            Text("Animacje odgrywają się same, w kółko. Nic się przy tym naprawdę nie dzieje.")
                .font(.callout).foregroundStyle(.secondary)

            section("Szybkie akcje") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                    ForEach(QuickActionsModule.Action.allCases, id: \.self) { action in
                        ActionTile(spec: TileSpec.make(action, state: tileState(action), compact: false), compact: false,
                                   tap: tapCount(action), isBusy: isBusy(action)) {}
                            .frame(height: 70)
                    }
                }
                .environment(\.tileLayout, .stacked)
            }

            HStack(alignment: .top, spacing: 18) {
                section("Mikrofon (⌃⌥M)") {
                    islandStrip(id: "mic") {
                        ToggleSymbol(on: "mic.slash.fill", off: "mic.fill", isOn: step % 2 == 0)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(step % 2 == 0 ? .red : .green)
                    } trailing: {
                        Text(step % 2 == 0 ? "Wyciszony" : "Włączony")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(step % 2 == 0 ? .red : .green)
                    }
                }
                section("Wjazd z lewej (nowa aktywność)") {
                    islandStrip(id: "slide-\(step)") {
                        Image(systemName: ["music.note", "timer", "bell.fill", "sparkle"][step % 4])
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .slideInFromLeading()
                    } trailing: {
                        Text(["Muzyka", "12:30", "Wiadomość", "Claude"][step % 4])
                            .font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.8))
                    }
                }
            }
        }
        .padding(24)
        .frame(width: 720)
        .background(Color(white: 0.08))
        .environment(\.colorScheme, .dark)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.stepDuration)
                withAnimation(.snappy) { step += 1 }
            }
        }
    }

    // MARK: - Scenariusz (4 kroki, w kółko)

    private func phase() -> Int { step % Self.steps }

    private func tapCount(_ action: QuickActionsModule.Action) -> Int {
        switch action {
        case .capture, .captureScreen, .pickColor, .password: step
        default: 0
        }
    }

    private func isBusy(_ action: QuickActionsModule.Action) -> Bool {
        switch action {
        case .capture: phase() == 1
        case .captureText, .record: phase() < 2
        default: false
        }
    }

    private func tileState(_ action: QuickActionsModule.Action) -> TileSpec.State {
        let even = step % 2 == 0
        var state = TileSpec.State()
        switch action {
        case .capture, .captureText, .record: state.isDone = phase() == 2
        case .captureScreen, .pickColor, .password: state.isDone = phase() == 1
        case .lock: state.isDone = !even
        case .darkMode: state.isDarkMode = !even
        case .desktopIcons: state.desktopIconsVisible = even
        case .keepAwake: state.isKeepingAwake = !even
        }
        return state
    }

    // MARK: - Układ

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
        }
    }

    /// Mała zwinięta wyspa: lewe skrzydło, notch, prawe skrzydło.
    private func islandStrip<Leading: View, Trailing: View>(id: String, @ViewBuilder leading: () -> Leading,
                                                            @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 0) {
            leading().frame(width: 80)
            Color.clear.frame(width: 120)
            trailing().frame(width: 80)
        }
        .frame(height: 34)
        .background(Capsule().fill(.black))
        .clipShape(Capsule())
        .overlay(Capsule().fill(Color(white: 0.02)).frame(width: 110, height: 26))
        .id(id)
    }
}
