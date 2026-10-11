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
            QuickActionsTab(registry: registry)
                .tabItem { Label("Szybkie akcje", systemImage: "bolt.circle") }
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
                Toggle("Skrzydła ustępują ikonom paska menu", isOn: $settings.wingsYield)
                Text("Najechanie na skrzydło wyspy (obok notcha) chowa je, żeby odsłonić ikony paska menu pod spodem; "
                     + "wracają, gdy kursor zjedzie z paska. Najechanie na sam notch dalej rozwija wyspę.")
                    .font(.caption).foregroundStyle(.secondary)
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
                Picker("Motyw", selection: $settings.islandTheme) {
                    ForEach(IslandTheme.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                if settings.islandTheme == .glass {
                    LabeledContent("Przyciemnienie szkła") {
                        Slider(value: $settings.glassTint, in: IslandTheme.glassTintRange)
                            .frame(maxWidth: 220)
                    }
                }
                Text(themeHint).font(.caption).foregroundStyle(.secondary)
                Toggle("Haptyka gładzika przy rozwinięciu", isOn: $settings.hapticsEnabled)
                if settings.hapticsEnabled {
                    Picker("Siła stuknięcia", selection: $settings.hapticStrength) {
                        ForEach(HapticStrength.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: settings.hapticStrength) { _, strength in TrackpadHaptics.shared.perform(strength) }
                    Text("Stuknięcie czuć, gdy palec dotyka gładzika. Średnia i Mocna korzystają z nieoficjalnego "
                         + "interfejsu macOS — gdyby przestał działać, Wyspa stuknie delikatnie.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Tryb prywatny") {
                Picker("Ukrywaj powiadomienia, schowek i odpowiedzi Claude", selection: $settings.privacyMode) {
                    ForEach(PrivacyState.Mode.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                if !ScreenCaptureDetector.isAvailable {
                    Label("Ta wersja macOS nie pozwala wykryć udostępniania ekranu (brak SLSIsScreenWatcherPresent) — działa tylko tryb „Zawsze”.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange)
                } else if !ScreenCaptureDetector.isObservable {
                    Label("Wyspa wykrywa udostępnianie dopiero przy rozwinięciu albo nowej karcie (brak zdarzeń serwera okien).",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange)
                }
                Text("Przy udostępnianiu albo nagrywaniu ekranu (Zoom, Teams, Meet, nagranie) wyspa od razu chowa treść modułów osobistych.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Wsparcie") {
                Link(destination: SupportLink.url) {
                    Label("Wesprzyj autora na Suppi", systemImage: "heart.fill")
                }
                Text("Wyspa jest darmowa i open source. Jeśli się przydaje, możesz postawić autorowi kawę.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var themeHint: String {
        switch settings.islandTheme {
        case .classic: "Czarna wyspa, widżety rozdzielone kreskami."
        case .blackSheet: "Czarna wyspa z cienką jasną krawędzią, zakładki w kapsule, widżety na osobnych kartach."
        case .glass: "Rozwinięta wyspa i karty z rozmytego szkła; przy samym notchu wyspa zostaje czarna."
        case .clear: Self.clearThemeHint
        }
    }

    private static var clearThemeHint: String {
        if #available(macOS 26, *) {
            return "Rozwinięta wyspa i karty z przezroczystego szkła Liquid Glass, jak Centrum sterowania; przy samym "
                + "notchu wyspa zostaje czarna."
        }
        return "Liquid Glass wymaga macOS 26 — na tym systemie rozwinięta wyspa i karty są z rozmytego szkła "
            + "bez przyciemnienia; przy samym notchu wyspa zostaje czarna."
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

/// Osobna karta dla Szybkich akcji: kafelki (8 miejsc) i skróty klawiszowe.
private struct QuickActionsTab: View {
    static let moduleID = "quickactions"
    let registry: ModuleRegistry

    var body: some View {
        if registry.isActive(Self.moduleID), let view = registry.settingsView(for: Self.moduleID) {
            ScrollView { view.padding(20).frame(maxWidth: .infinity, alignment: .leading) }
        } else {
            ContentUnavailableView("Szybkie akcje są wyłączone", systemImage: "bolt.circle",
                                   description: Text("Włącz moduł „Szybkie akcje” w karcie Moduły."))
        }
    }
}
