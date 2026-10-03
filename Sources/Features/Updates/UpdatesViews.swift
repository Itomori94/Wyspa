import SwiftUI
import WyspaCore
import WyspaUI

/// Karta pod notchem: nowa wersja i ostatnia zmiana.
struct UpdateCard: View {
    let check: UpdateCheck

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Nowa wersja Wyspy · \(PolishPlural.format(check.changes.count, one: "zmiana", few: "zmiany", many: "zmian"))")
                .font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.blue)
            Text(check.changes.first?.title ?? "")
                .font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.8)).lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

struct UpdatesSettingsView: View {
    let module: UpdatesModule

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let source = module.source {
                Text("Zainstalowana wersja: \(source.shortCommit)\(source.isDirty ? " (z niezapisanymi zmianami)" : "")")
                    .font(.callout).monospacedDigit()
            }
            statusView
            HStack {
                Button("Sprawdź teraz") { Task { await module.check() } }
                    .disabled(module.status == .checking || module.status == .updating)
                if case .available = module.status {
                    Button("Zaktualizuj teraz", action: module.update).buttonStyle(.borderedProminent)
                }
                if let url = module.source?.repository?.webURL {
                    Link("GitHub", destination: url)
                }
            }
            Text("Aktualizacja pobiera zmiany do katalogu projektu (git pull), buduje i instaluje Wyspę — aplikacja zamknie się "
                 + "i uruchomi ponownie. Przebieg: ~/Library/Logs/Wyspa/aktualizacja.log. Sprawdzanie: przy starcie i co 6 godzin.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var statusView: some View {
        switch module.status {
        case .idle: EmptyView()
        case .checking: Label("Sprawdzanie…", systemImage: "hourglass").foregroundStyle(.secondary)
        case .upToDate: Label("Masz najnowszą wersję", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .updating: Label("Aktualizowanie… Wyspa za chwilę uruchomi się ponownie.", systemImage: "arrow.down.circle")
        case .failed(let message): Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .available(let check):
            VStack(alignment: .leading, spacing: 4) {
                Label("Dostępna nowa wersja: \(PolishPlural.format(check.changes.count, one: "zmiana", few: "zmiany", many: "zmian"))",
                      systemImage: "arrow.down.circle.fill").foregroundStyle(.blue)
                ForEach(check.changes.prefix(8), id: \.sha) { change in
                    Text("• \(change.title)").font(.caption).lineLimit(1)
                }
                if check.changes.count > 8 {
                    Text("… i \(check.changes.count - 8) więcej").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
