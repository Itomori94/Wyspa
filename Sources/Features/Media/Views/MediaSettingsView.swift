import SwiftUI
import WyspaCore
import WyspaUI

/// Szczegóły modułu w oknie ustawień: z jakich aplikacji pokazywać dźwięk.
struct MediaSettingsView: View {
    @Bindable var module: MediaModule
    @Environment(\.islandTheme) private var theme

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
            // W Szkle wyspa nie rysuje tła modułów, więc wybór tła nic by nie zmienił.
            if theme.showsModuleBackdrops {
                Picker("Tło odtwarzacza", selection: $module.backdropStyle) {
                    ForEach(MediaBackdropStyle.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .padding(.top, 4)
                Text("Tło rozwiniętego odtwarzacza. Rozmyta okładka wygląda jak odtwarzacz w Apple Music.")
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
