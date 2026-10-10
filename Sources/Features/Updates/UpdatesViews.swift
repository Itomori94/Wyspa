import AppKit
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
    private var service: UpdateService { module.service }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let source = service.source {
                Text("Zainstalowana wersja: \(source.shortCommit)\(source.isDirty ? " (z niezapisanymi zmianami)" : "")")
                    .font(.callout).monospacedDigit()
            }
            statusView
            HStack {
                Button("Sprawdź teraz") { Task { await module.check() } }
                    .disabled(service.isBusy)
                if case .available = service.status {
                    Button("Zaktualizuj teraz", action: service.update).buttonStyle(.borderedProminent)
                }
                if let url = service.source?.repository?.webURL {
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
        switch service.status {
        case .idle: EmptyView()
        case .checking: Label("Sprawdzanie…", systemImage: "hourglass").foregroundStyle(.secondary)
        case .upToDate: Label("Masz najnowszą wersję", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .updating:
            Label("\(service.stage?.title ?? "Aktualizowanie")… Wyspa uruchomi się ponownie sama.", systemImage: "arrow.down.circle")
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

/// Okienko aktualizacji: etapy z czasem trwania bieżącego, a po błędzie opis i przebieg. Budowanie trwa kilka minut —
/// bez okienka po „Zaktualizuj teraz” wyglądało, jakby nic się nie działo.
public struct UpdateProgressView: View {
    private let service: UpdateService
    private let close: @MainActor () -> Void

    public init(service: UpdateService, close: @escaping @MainActor () -> Void) {
        self.service = service
        self.close = close
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 4) {
                    Text(failure == nil ? "Aktualizowanie Wyspy" : "Aktualizacja się nie udała").font(.headline)
                    Text(failure ?? "Wyspa zbuduje nową wersję, zamknie się i uruchomi ponownie sama — nie trzeba jej "
                         + "wyłączać. Budowanie trwa zwykle kilka minut.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if failure == nil {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(UpdateStage.allCases, id: \.self) { row($0) }
                }
                .padding(.leading, 62)
            } else {
                HStack {
                    Button("Pokaż przebieg") { NSWorkspace.shared.open(service.logURL) }
                    Spacer()
                    Button("Zamknij") { close() }.keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(20)
        .frame(width: 400, alignment: .leading)
    }

    private var failure: String? {
        if case .failed(let message) = service.status { message } else { nil }
    }

    private func row(_ stage: UpdateStage) -> some View {
        let current = service.stage
        return HStack(spacing: 8) {
            Group {
                if let current, stage < current {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                } else if stage == current {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "circle").foregroundStyle(.tertiary)
                }
            }
            .frame(width: 16, height: 16)
            Text(stage.title).foregroundStyle(stage == current ? HierarchicalShapeStyle.primary : .secondary)
            Spacer()
            if stage == current, let started = service.stageStarted {
                Text(started, style: .timer).monospacedDigit().foregroundStyle(.secondary)
            }
        }
    }
}
