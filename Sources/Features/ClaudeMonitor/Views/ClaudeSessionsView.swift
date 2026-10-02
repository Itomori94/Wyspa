import SwiftUI
import WyspaHookKit
import WyspaUI

struct ClaudeSessionsView: View {
    let module: ClaudeMonitorModule
    let compact: Bool

    var body: some View {
        let sessions = module.store.ordered
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(module.pending.prefix(compact ? 1 : 3)) { request in
                    PermissionCard(request: request, session: module.store.sessions[request.sessionID],
                                   decisionSeconds: module.decisionMinutes * 60, compact: compact,
                                   decide: { module.decide(request, $0) })
                }
                if sessions.isEmpty && module.pending.isEmpty {
                    emptyState
                }
                ForEach(sessions.prefix(compact ? 3 : 8)) { session in
                    SessionRow(session: session, compact: compact) { module.focus(session) }
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
    let decide: (HookProtocol.Behavior) -> Void

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
            if !compact { ToolPreview(input: request.event.toolInput) }
            HStack(spacing: 6) {
                Button("Odrzuć") { decide(.deny) }
                    .buttonStyle(DecisionStyle(tint: .red.opacity(0.75)))
                if !compact {
                    Button("W terminalu") { decide(.ask) }
                        .buttonStyle(DecisionStyle(tint: .white.opacity(0.15)))
                        .help("Zostaw decyzję w terminalu Claude Code")
                }
                Spacer(minLength: 0)
                Button("Zezwól") { decide(.allow) }
                    .buttonStyle(DecisionStyle(tint: .green.opacity(0.8)))
                    .keyboardShortcut(.defaultAction)
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
