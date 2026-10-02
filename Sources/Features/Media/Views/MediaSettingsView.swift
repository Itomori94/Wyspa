import SwiftUI

/// Szczegóły modułu w oknie ustawień: z jakich aplikacji pokazywać dźwięk.
struct MediaSettingsView: View {
    @Bindable var module: MediaModule

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Pokazuj dźwięk z", selection: $module.scope) {
                ForEach(MediaScope.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)
            .fixedSize()
            if module.scope == .appleMusic {
                Text("Muzyka, filmy i podcasty z innych aplikacji nie będą pokazywane w wyspie.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            // Źródło danych wybiera się samo (adapter, a awaryjnie AppleScript); komunikat tylko, gdy nic nie działa.
            if case .failed(let message) = module.status {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }
}
