import SwiftUI
import WyspaCore
import WyspaUI

struct SettingsView: View {
    @Bindable var settings: SettingsStore
    let registry: ModuleRegistry
    let permissions: PermissionCenter
    let uiState: SettingsUIState

    var body: some View {
        TabView {
            GeneralSettingsView(settings: settings, uiState: uiState)
                .tabItem { Label("Ogólne", systemImage: "gearshape") }
            IslandSettingsView(settings: settings)
                .tabItem { Label("Wyspa", systemImage: "capsule") }
            ModulesSettingsView(registry: registry, permissions: permissions)
                .tabItem { Label("Moduły", systemImage: "square.grid.2x2") }
            BoardEditorView(settings: settings, registry: registry)
                .tabItem { Label("Układ", systemImage: "rectangle.3.group") }
        }
        .frame(width: 720, height: 620)
    }
}

private struct GeneralSettingsView: View {
    @Bindable var settings: SettingsStore
    let uiState: SettingsUIState
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchProblem: String?

    var body: some View {
        Form {
            Section {
                Toggle("Uruchamiaj przy logowaniu", isOn: Binding(
                    get: { launchAtLogin },
                    set: { enabled in
                        launchProblem = LaunchAtLogin.set(enabled)
                        launchAtLogin = LaunchAtLogin.isEnabled
                    }
                ))
                if LaunchAtLogin.requiresApproval {
                    Button("Zatwierdź w Ustawieniach systemowych…", action: LaunchAtLogin.openLoginItemsSettings)
                }
                if let launchProblem {
                    ProblemText(launchProblem)
                }
            }
            Section("Skrót klawiszowy") {
                LabeledContent("Rozwiń lub zwiń wyspę") {
                    ShortcutRecorder(shortcut: $settings.toggleShortcut)
                }
                if let problem = uiState.hotkeyProblem {
                    ProblemText(problem)
                }
            }
            Section("Ekrany") {
                Picker("Pokazuj wyspę", selection: $settings.screenSelection) {
                    ForEach(ScreenSelection.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                Picker("Wirtualny notch", selection: $settings.virtualNotchMode) {
                    ForEach(VirtualNotchMode.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                Text("Na monitorach bez notcha wyspa rysuje wirtualny notch pod paskiem menu.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { launchAtLogin = LaunchAtLogin.isEnabled }
    }
}

private struct IslandSettingsView: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        Form {
            Section("Rozwijanie") {
                Toggle("Rozwijaj po najechaniu kursorem", isOn: $settings.expandOnHover)
                DelaySlider(
                    title: "Opóźnienie rozwinięcia",
                    value: $settings.hoverDelay,
                    range: SettingsStore.Limits.hoverDelay
                )
                .disabled(!settings.expandOnHover)
                DelaySlider(
                    title: "Opóźnienie zwinięcia",
                    value: $settings.collapseDelay,
                    range: SettingsStore.Limits.collapseDelay
                )
                Text("Kliknięcie albo przesunięcie dwoma palcami w dół zawsze rozwija wyspę, w górę ją zwija.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Wygląd") {
                Picker("Rozmiar rozwiniętej wyspy", selection: $settings.islandSize) {
                    ForEach(IslandSize.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Haptyka gładzika przy rozwinięciu", isOn: $settings.hapticsEnabled)
            }
        }
        .formStyle(.grouped)
    }
}

private struct DelaySlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        LabeledContent(title) {
            HStack {
                Slider(value: $value, in: range, step: 0.05)
                    .frame(width: 180)
                Text(value, format: .number.precision(.fractionLength(2)))
                    .monospacedDigit()
                    .frame(width: 36, alignment: .trailing)
                Text("s").foregroundStyle(.secondary)
            }
        }
    }
}

struct ProblemText: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.callout)
            .foregroundStyle(.orange)
    }
}
