import SwiftUI

struct ClaudeSettingsView: View {
    @Bindable var module: ClaudeMonitorModule
    @State private var confirmingUninstall = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                status
                Spacer()
                switch module.hookStatus {
                case .installed:
                    if confirmingUninstall {
                        Button("Usuń hooki Wyspy") { module.uninstallHooks(); confirmingUninstall = false }
                        Button("Anuluj") { confirmingUninstall = false }
                    } else {
                        Button("Odinstaluj…") { confirmingUninstall = true }
                    }
                case .outdatedPath:
                    Button("Zaktualizuj ścieżkę", action: module.installHooks)
                case .notInstalled, .unknown:
                    Button("Zainstaluj hooki", action: module.installHooks).buttonStyle(.borderedProminent)
                }
            }
            Text("Instalacja dopisuje wpisy Wyspy do ~/.claude/settings.json (z kopią zapasową obok pliku). "
                 + "Twoje inne hooki i ustawienia zostają. Gdy Wyspa nie działa, hook kończy się od razu i nic nie zmienia.")
                .font(.caption).foregroundStyle(.secondary)
            Stepper("Czas na decyzję w wyspie: \(module.decisionMinutes) min", value: $module.decisionMinutes,
                    in: ClaudeMonitorModule.decisionMinutesRange)
            Text("Po tym czasie (albo gdy Wyspa nie odpowie) decyzja wraca do zwykłego promptu w terminalu.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Dźwięk, gdy sesja czeka albo kończy", isOn: $module.soundsEnabled)
            Toggle("Bez dźwięku, gdy terminal sesji jest na wierzchu", isOn: $module.muteWhenTerminalFrontmost)
                .disabled(!module.soundsEnabled)
            if let problem = module.problem {
                Label(problem, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.callout)
            }
        }
        .onAppear(perform: module.refreshHookStatus)
    }

    @ViewBuilder
    private var status: some View {
        switch module.hookStatus {
        case .installed: Label("Hooki zainstalowane", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .outdatedPath: Label("Hooki wskazują inną kopię Wyspy", systemImage: "exclamationmark.circle.fill").foregroundStyle(.orange)
        case .notInstalled: Label("Hooki niezainstalowane", systemImage: "circle.dashed").foregroundStyle(.secondary)
        case .unknown: Label("Sprawdzanie…", systemImage: "hourglass").foregroundStyle(.secondary)
        }
    }
}
