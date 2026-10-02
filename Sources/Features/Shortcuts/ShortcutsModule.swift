import SwiftUI
import WyspaCore
import WyspaUI

/// Uruchamianie Skrótów macOS z wyspy.
@MainActor
@Observable
public final class ShortcutsModule: IslandModule {
    public static let descriptor = ModuleDescriptor(
        id: "shortcuts",
        name: "Skróty",
        summary: "Uruchamia wybrane Skróty macOS jednym kliknięciem z wyspy.",
        symbol: "square.stack.3d.up.fill",
        widgetMinWidth: 120
    )

    public enum RunState: Equatable { case idle, running, succeeded, failed(String) }

    private static let favoritesKey = "favorites"

    public private(set) var all: [String] = []
    public private(set) var favorites: [String]
    public private(set) var states: [String: RunState] = [:]
    public private(set) var problem: String?

    @ObservationIgnored private let context: ModuleContext

    public required init(context: ModuleContext) {
        self.context = context
        favorites = context.settings.value(Self.favoritesKey, default: [String]())
    }

    public func activate() async throws {
        await refresh()
    }

    public func deactivate() {
        states = [:]
    }

    public var liveActivity: LiveActivity? { nil }

    public func makeExpandedView() -> AnyView? { AnyView(ShortcutsView(module: self)) }
    public func makeWidgetView() -> AnyView? { AnyView(ShortcutsWidget(module: self)) }
    public func makeSettingsView() -> AnyView? { AnyView(ShortcutsSettingsView(module: self)) }

    /// W wyspie: ulubione, a gdy ich brak — wszystkie skróty.
    var visible: [String] {
        let available = favorites.filter(all.contains)
        return available.isEmpty ? all : available
    }

    func refresh() async {
        do {
            all = try await ShortcutsCLI.list()
            problem = nil
        } catch {
            problem = error.localizedDescription
        }
    }

    func toggleFavorite(_ name: String) {
        favorites = favorites.contains(name) ? favorites.filter { $0 != name } : favorites + [name]
        context.settings.set(favorites, for: Self.favoritesKey)
    }

    func run(_ name: String) {
        guard states[name] != .running else { return }
        states = states.merging([name: .running]) { _, new in new }
        Task {
            let outcome: RunState
            do {
                try await ShortcutsCLI.run(shortcut: name)
                outcome = .succeeded
            } catch {
                outcome = .failed(error.localizedDescription)
            }
            states = states.merging([name: outcome]) { _, new in new }
            try? await Task.sleep(for: .seconds(3))
            if states[name] == outcome { states = states.filter { $0.key != name } }
        }
    }
}

struct ShortcutsView: View {
    let module: ShortcutsModule

    var body: some View {
        if let problem = module.problem {
            Label(problem, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.orange)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if module.visible.isEmpty {
            Text("Nie masz jeszcze żadnych skrótów. Utwórz je w aplikacji Skróty.")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.5))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 8)], spacing: 8) {
                    ForEach(module.visible, id: \.self) { name in
                        ShortcutTile(name: name, state: module.states[name] ?? .idle) { module.run(name) }
                    }
                }
            }
        }
    }
}

private struct ShortcutTile: View {
    let name: String
    let state: ShortcutsModule.RunState
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                icon.frame(width: 16)
                Text(name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(isHovered ? 0.14 : 0.07)))
        }
        .buttonStyle(IslandPressStyle())
        .onHover { isHovered = $0 }
        .help(helpText)
        .disabled(state == .running)
    }

    @ViewBuilder
    private var icon: some View {
        switch state {
        case .idle: Image(systemName: "play.fill").foregroundStyle(.white.opacity(0.6))
        case .running: ProgressView().controlSize(.small)
        case .succeeded: Image(systemName: "checkmark").foregroundStyle(.green)
        case .failed: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
    }

    private var helpText: String {
        if case .failed(let message) = state { return message }
        return "Uruchom skrót „\(name)”"
    }
}

struct ShortcutsSettingsView: View {
    let module: ShortcutsModule

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Ulubione (pokazywane w wyspie; bez ulubionych widać wszystkie)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Odśwież") { Task { await module.refresh() } }
            }
            ForEach(module.all, id: \.self) { name in
                Toggle(name, isOn: Binding(get: { module.favorites.contains(name) }, set: { _ in module.toggleFavorite(name) }))
            }
        }
    }
}
