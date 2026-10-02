import SwiftUI
import WyspaUI

struct ScriptProgressRing: View {
    let fraction: Double?
    let finished: Bool

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.2), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: finished ? 1 : (fraction ?? 0.25))
                .stroke(Color.green, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.3), value: fraction)
            Image(systemName: finished ? "checkmark" : "terminal")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: 16, height: 16)
    }
}

/// Karta `wyspa notify` pod notchem. Podpisana „Skrypt”, żeby nie udawała powiadomienia aplikacji.
struct ScriptNoticeCard: View {
    let notice: ScriptNotice
    let isPrivate: Bool
    let close: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "terminal.fill")
                .font(.system(size: 16))
                .foregroundStyle(.green)
                .frame(width: 30, height: 30)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 2) {
                Text("Skrypt").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.white.opacity(0.5))
                Text(isPrivate ? "Nowa wiadomość ze skryptu" : notice.title)
                    .font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                if isPrivate {
                    Label("Treść ukryta — ekran jest udostępniany", systemImage: "eye.slash")
                        .font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                } else if let body = notice.body {
                    Text(body).font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.75)).lineLimit(2)
                }
            }
        }
        .padding(.vertical, 6)
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
        .onTapGesture(perform: close)
        .help("Kliknij, żeby ukryć")
    }
}

struct ScriptsView: View {
    let module: ScriptsModule

    var body: some View {
        if module.state.progress.isEmpty {
            VStack(spacing: 6) {
                Label("Brak zadań w toku", systemImage: "terminal")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
                Text("wyspa progress 0.4 \"Build\"")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.35))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(module.state.progress) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(item.label ?? item.id).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                Spacer()
                                if item.isFinished {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                } else {
                                    Text(ScriptsState.percentText(item.fraction))
                                        .font(.system(size: 11, weight: .semibold)).monospacedDigit()
                                        .foregroundStyle(.white.opacity(0.6))
                                }
                                Button { module.dismissProgress(item.id) } label: {
                                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.white.opacity(0.5))
                                }
                                .buttonStyle(.plain)
                                .help("Ukryj")
                            }
                            if let fraction = item.isFinished ? 1 : item.fraction {
                                ProgressView(value: fraction).tint(.green)
                            } else {
                                ProgressView().progressViewStyle(.linear).tint(.green)
                            }
                        }
                        .foregroundStyle(.white)
                    }
                }
            }
        }
    }
}

struct ScriptsSettingsView: View {
    let module: ScriptsModule

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                switch module.commandStatus {
                case .installed:
                    Label("Komenda wyspa zainstalowana w ~/.local/bin", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    Spacer()
                    Button("Usuń komendę") { module.uninstallCommand() }
                case .outdated:
                    Label("Komenda wyspa jest starsza niż aplikacja", systemImage: "arrow.triangle.2.circlepath").foregroundStyle(.orange)
                    Spacer()
                    Button("Zaktualizuj") { module.installCommand() }
                case .missing:
                    Text("Komenda wyspa nie jest zainstalowana.")
                    Spacer()
                    Button("Zainstaluj w ~/.local/bin") { module.installCommand() }
                case .foreign:
                    Label("~/.local/bin/wyspa to inny program — Wyspa go nie nadpisze.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
            if let problem = module.installProblem {
                Text(problem).font(.caption).foregroundStyle(.red)
            }
            Text("Gdy powłoka nie znajduje komendy, dopisz export PATH=\"$HOME/.local/bin:$PATH\" do ~/.zshrc. "
                 + "Cron i Skróty nie czytają ~/.zshrc — tam podawaj pełną ścieżkę ~/.local/bin/wyspa.")
                .font(.caption).foregroundStyle(.secondary)
            Text("""
                 wyspa notify "Backup gotowy" "42 GB w 12 min"
                 wyspa progress 0.4 "Build" --id build
                 wyspa done build
                 open -g "wyspa://notify?title=Gotowe"
                 """)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
            Text("Gdy Wyspa nie działa, komenda kończy się po cichu z kodem 0. Adres wyspa:// może otworzyć każda aplikacja "
                 + "i strona WWW (po pytaniu przeglądarki), dlatego polecenia tylko pokazują tekst: karta jest podpisana „Skrypt”, "
                 + "teksty są przycinane, a postęp bez aktualizacji znika po 15 minutach.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onAppear { module.refreshCommandStatus() }
    }
}
