import SwiftUI
import WyspaHookKit
import WyspaUI

struct ClaudeSessionsView: View {
    let module: ClaudeMonitorModule
    let compact: Bool
    var isPrivate = false

    var body: some View {
        let sessions = module.store.ordered
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if let limits = module.limits {
                    LimitsBar(limits: limits, compact: compact)
                }
                ForEach(module.pendingQuestions.prefix(1)) { question in
                    QuestionCard(pending: question, session: module.store.sessions[question.sessionID],
                                 isPrivate: isPrivate, answer: { module.answer(question, with: $0) })
                }
                ForEach(module.pending.prefix(compact ? 1 : 3)) { request in
                    PermissionCard(request: request, session: module.store.sessions[request.sessionID],
                                   decisionSeconds: module.decisionMinutes * 60, compact: compact, isPrivate: isPrivate,
                                   decide: { module.decide(request, $0, reason: $1) })
                }
                if sessions.isEmpty && module.pending.isEmpty {
                    emptyState
                }
                ForEach(sessions.prefix(compact ? 3 : 8)) { session in
                    SessionRow(session: session, compact: compact || isPrivate) { module.focus(session) }
                }
            }
        }
        .scrollIndicators(.never)
        .onAppear(perform: module.removeDeadSessions)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "terminal").font(.system(size: 20)).foregroundStyle(.white.opacity(0.4))
            Text(module.hookStatus == .installed ? "Brak aktywnych sesji Claude Code" : "Zainstaluj hooki w ustawieniach modułu")
                .font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 80)
    }
}

private struct SessionRow: View {
    let session: ClaudeSession
    let compact: Bool
    let focus: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: focus) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    StateDot(state: session.state)
                    Text(session.projectName).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                    Spacer(minLength: 4)
                    if let since = session.busySince {
                        // Czas pracy odświeżany przez system (styl względny), bez własnego zegara.
                        Text(since, style: .relative)
                            .font(.system(size: 10, weight: .medium)).monospacedDigit()
                            .foregroundStyle(.white.opacity(0.4)).lineLimit(1)
                    }
                    Text(stateText).font(.system(size: 10.5, weight: .medium)).foregroundStyle(stateColor).lineLimit(1)
                }
                if !compact, !session.recentTools.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(Array(session.recentTools.suffix(3).enumerated()), id: \.offset) { _, tool in
                            Text(tool)
                                .font(.system(size: 9.5, design: .monospaced))
                                .lineLimit(1)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Capsule().fill(.white.opacity(0.08)))
                        }
                    }
                    .foregroundStyle(.white.opacity(0.6))
                }
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(isHovered ? 0.1 : 0.05)))
        }
        .buttonStyle(IslandPressStyle())
        .onHover { isHovered = $0 }
        .help("Przejdź do terminala tej sesji")
    }

    private var stateText: String {
        switch session.state {
        case .idle: "gotowa"
        case .working: "pracuje…"
        case .runningTool(let tool): tool
        case .waitingForPermission: "prosi o zgodę"
        case .waitingForInput: "czeka na Ciebie"
        case .finished: "skończyła"
        }
    }

    private var stateColor: Color {
        switch session.state {
        case .waitingForPermission, .waitingForInput: .orange
        case .finished: .green
        case .working, .runningTool: .purple
        case .idle: .white.opacity(0.5)
        }
    }
}

private struct StateDot: View {
    let state: ClaudeSession.State

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .phaseAnimator([false, true], trigger: state.needsAttention) { view, phase in
                view.opacity(state.needsAttention && phase ? 0.35 : 1)
            }
    }

    private var color: Color {
        switch state {
        case .waitingForPermission, .waitingForInput: .orange
        case .finished: .green
        case .working, .runningTool: .purple
        case .idle: .gray
        }
    }
}

/// Prośba o uprawnienie: narzędzie, podgląd (polecenie, diff, treść) i decyzja.
private struct PermissionCard: View {
    let request: PendingPermission
    let session: ClaudeSession?
    let decisionSeconds: Int
    let compact: Bool
    /// Tryb prywatny: sama nazwa narzędzia, bez polecenia, diffu i treści pliku.
    var isPrivate = false
    let decide: (HookProtocol.Behavior, String?) -> Void
    @State private var reason = ""
    @State private var askingReason = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: "hand.raised.fill").foregroundStyle(.orange)
                Text("\(session?.projectName ?? "Claude Code") chce użyć: \(request.event.toolName ?? "narzędzia")")
                    .font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 4)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let left = max(0, decisionSeconds - Int(context.date.timeIntervalSince(request.receivedAt)))
                    Text(String(format: "%d:%02d", left / 60, left % 60))
                        .font(.system(size: 10, weight: .medium, design: .rounded)).monospacedDigit()
                        .foregroundStyle(.white.opacity(0.45))
                        .help("Po tym czasie decyzja wróci do terminala")
                }
            }
            if isPrivate {
                Label("Szczegóły ukryte — ekran jest udostępniany", systemImage: "eye.slash")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
            } else if !compact {
                ToolPreview(input: request.event.toolInput)
            }
            HStack(spacing: 6) {
                Button("Odrzuć") { decide(.deny, nil) }
                    .buttonStyle(DecisionStyle(tint: .red.opacity(0.75)))
                if !compact {
                    Button("Z powodem…") { askingReason.toggle() }
                        .buttonStyle(DecisionStyle(tint: .red.opacity(0.35)))
                        .help("Odrzuć i napisz Claude, dlaczego — bez wracania do terminala")
                    Button("W terminalu") { decide(.ask, nil) }
                        .buttonStyle(DecisionStyle(tint: .white.opacity(0.15)))
                        .help("Zostaw decyzję w terminalu Claude Code")
                }
                Spacer(minLength: 0)
                Button("Zezwól") { decide(.allow, nil) }
                    .buttonStyle(DecisionStyle(tint: .green.opacity(0.8)))
                    .keyboardShortcut(.defaultAction)
            }
            if askingReason {
                HStack(spacing: 6) {
                    TextField("Dlaczego? (Claude dostanie ten powód)", text: $reason)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11.5))
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 7).fill(.white.opacity(0.08)))
                        .onSubmit { decide(.deny, reason) }
                    Button("Odrzuć") { decide(.deny, reason) }
                        .buttonStyle(DecisionStyle(tint: .red.opacity(0.75)))
                        .disabled(reason.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.orange.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.orange.opacity(0.45), lineWidth: 1))
    }
}

private struct DecisionStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11.5, weight: .semibold))
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(Capsule().fill(tint.opacity(configuration.isPressed ? 0.7 : 1)))
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
    }
}

/// Podgląd wejścia narzędzia: polecenie, diff edycji albo początek nowego pliku.
private struct ToolPreview: View {
    static let maxLines = 14

    let input: ToolInput?

    var body: some View {
        if let input {
            VStack(alignment: .leading, spacing: 4) {
                if let path = input.filePath {
                    Text(path).font(.system(size: 9.5, design: .monospaced)).foregroundStyle(.white.opacity(0.5)).lineLimit(1).truncationMode(.head)
                }
                if let command = input.command {
                    code(command, color: .white)
                } else if let old = input.oldString, let new = input.newString {
                    DiffLines(lines: LineDiff.lines(from: old, to: new))
                } else if !input.edits.isEmpty {
                    DiffLines(lines: input.edits.flatMap { LineDiff.lines(from: $0.old, to: $0.new) })
                } else if let content = input.content {
                    DiffLines(lines: LineDiff.lines(from: "", to: content))
                } else if let summary = input.summary {
                    code(summary, color: .white)
                }
            }
        }
    }

    private func code(_ text: String, color: Color) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(text).font(.system(size: 11, design: .monospaced)).foregroundStyle(color).lineLimit(4).textSelection(.enabled)
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 6).fill(.black.opacity(0.35)))
    }
}

private struct DiffLines: View {
    let lines: [LineDiff.Line]

    var body: some View {
        let visible = Array(lines.prefix(ToolPreview.maxLines))
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(visible.enumerated()), id: \.offset) { _, line in
                switch line {
                case .same(let text): row(" ", text, color: .white.opacity(0.55), background: .clear)
                case .removed(let text): row("−", text, color: Color(red: 1, green: 0.6, blue: 0.6), background: .red.opacity(0.18))
                case .added(let text): row("+", text, color: Color(red: 0.6, green: 1, blue: 0.7), background: .green.opacity(0.16))
                }
            }
            if lines.count > visible.count {
                Text("… i \(lines.count - visible.count) linii więcej").font(.system(size: 9.5)).foregroundStyle(.white.opacity(0.4)).padding(.top, 2)
            }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 6).fill(.black.opacity(0.35)))
    }

    private func row(_ sign: String, _ text: String, color: Color, background: Color) -> some View {
        HStack(alignment: .top, spacing: 4) {
            Text(sign).frame(width: 8)
            Text(text.isEmpty ? " " : text).lineLimit(1).truncationMode(.tail)
        }
        .font(.system(size: 10.5, design: .monospaced))
        .foregroundStyle(color)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background)
    }
}

/// Karta pod notchem po zakończeniu pracy: początek ostatniej odpowiedzi Claude.
struct FinishedCard: View {
    let session: ClaudeSession
    let preview: String
    let open: () -> Void
    let hover: (Bool) -> Void
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Claude skończył · \(session.projectName)")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.green.opacity(0.85))
            Text(preview)
                .font(.system(size: 11.5))
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(2)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
        .onHover { inside in
            isHovered = inside
            hover(inside)
        }
        .onTapGesture(perform: open)
        .help("Kliknij, żeby przejść do terminala")
    }
}

/// Zużycie limitów planu Claude z odliczaniem do resetu (odświeżane przez system, bez własnego zegara).
struct LimitsBar: View {
    let limits: ClaudeLimits
    let compact: Bool

    var body: some View {
        HStack(spacing: 12) {
            if let window = limits.fiveHour { gauge("5 h", window) }
            if let window = limits.sevenDay { gauge("Tydzień", window) }
        }
        .padding(.horizontal, 2)
    }

    private func gauge(_ title: String, _ window: ClaudeLimits.Window) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(title).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
                Text(ClaudeLimits.percent(window.usedPercentage))
                    .font(.system(size: 10.5, weight: .bold)).monospacedDigit()
                    .foregroundStyle(Self.tint(window.usedPercentage))
                Spacer(minLength: 2)
                if !compact {
                    (Text("reset ") + Text(window.resetsAt, style: .relative))
                        .font(.system(size: 9.5)).foregroundStyle(.white.opacity(0.45)).lineLimit(1)
                }
            }
            ProgressView(value: min(window.usedPercentage, 100), total: 100)
                .tint(Self.tint(window.usedPercentage))
                .controlSize(.mini)
        }
        .help("Reset: \(window.resetsAt.formatted(date: .abbreviated, time: .shortened))")
    }

    static func tint(_ used: Double) -> Color {
        used >= 90 ? .red : used >= 70 ? .orange : .green
    }
}

/// Pytanie Claude z opcjami: klik w opcję odpowiada (przy kilku pytaniach — po kolei), „W terminalu” zostawia
/// pytanie w Claude Code. W trybie prywatnym treść pytania i opcji jest ukryta.
private struct QuestionCard: View {
    let pending: PendingQuestion
    let session: ClaudeSession?
    let isPrivate: Bool
    let answer: ([String: [String]]?) -> Void
    @State private var index = 0
    @State private var chosen: [String: [String]] = [:]
    @State private var selection: Set<String> = []

    var body: some View {
        let question = pending.questions[min(index, pending.questions.count - 1)]
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: "questionmark.bubble.fill").foregroundStyle(.blue)
                Text("\(session?.projectName ?? "Claude") pyta" + (pending.questions.count > 1 ? " (\(index + 1)/\(pending.questions.count))" : ""))
                    .font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 4)
                Button("W terminalu") { answer(nil) }
                    .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                    .help("Odpowiedz w terminalu Claude Code")
            }
            if isPrivate {
                Label("Treść pytania ukryta — ekran jest udostępniany", systemImage: "eye.slash")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
            } else {
                Text(question.question).font(.system(size: 12)).foregroundStyle(.white.opacity(0.9)).lineLimit(3)
                ForEach(question.options, id: \.label) { option in
                    Button { pick(option.label, in: question) } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            if question.multiSelect {
                                Image(systemName: selection.contains(option.label) ? "checkmark.square.fill" : "square")
                            }
                            VStack(alignment: .leading, spacing: 1) {
                                Text(option.label).font(.system(size: 11.5, weight: .semibold))
                                if let description = option.description, !description.isEmpty {
                                    Text(description).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.55)).lineLimit(2)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(selection.contains(option.label) ? 0.18 : 0.08)))
                    }
                    .buttonStyle(.plain)
                }
                if question.multiSelect {
                    Button("Dalej") { commit(Array(selection), for: question) }
                        .buttonStyle(.plain).font(.system(size: 11.5, weight: .semibold))
                        .disabled(selection.isEmpty)
                }
            }
        }
        .foregroundStyle(.white)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.blue.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.blue.opacity(0.45), lineWidth: 1))
    }

    private func pick(_ label: String, in question: ClaudeQuestion) {
        guard question.multiSelect else { return commit([label], for: question) }
        if selection.contains(label) { selection.remove(label) } else { selection.insert(label) }
    }

    private func commit(_ labels: [String], for question: ClaudeQuestion) {
        chosen[question.question] = labels
        selection = []
        if index + 1 < pending.questions.count {
            index += 1
        } else {
            answer(chosen)
        }
    }
}
