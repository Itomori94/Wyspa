import SwiftUI

/// Szczegóły modułu w oknie ustawień: wybór i aktualny stan źródła danych.
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
            Picker("Źródło danych", selection: $module.preference) {
                ForEach(MediaSourcePreference.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            .fixedSize()
            statusView
                .font(.caption)
        }
    }

    @ViewBuilder
    private var statusView: some View {
        switch module.status {
        case .starting:
            Label("Sprawdzanie adaptera…", systemImage: "hourglass")
                .foregroundStyle(.secondary)
        case .running(let decision):
            VStack(alignment: .leading, spacing: 2) {
                Label("Aktywne źródło: \(decision.kind.displayName)", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(decision.kind == .adapter ? .green : .orange)
                Text(decision.reason).foregroundStyle(.secondary)
                if decision.kind == .appleScript {
                    Text("Przy pierwszym użyciu macOS zapyta o zgodę na sterowanie Muzyką i Spotify.")
                        .foregroundStyle(.secondary)
                }
            }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }
}
