import WyspaHookKit
import Foundation

/// Stan jednej sesji Claude Code wyprowadzony ze zdarzeń hooków.
public struct ClaudeSession: Equatable, Identifiable, Sendable {
    public enum State: Equatable, Sendable {
        /// Sesja otwarta, Claude nic nie robi (np. tuż po starcie).
        case idle
        case working
        case runningTool(String)
        /// Prośba o uprawnienie czeka na decyzję w wyspie.
        case waitingForPermission
        /// Claude czeka na Ciebie w terminalu (pytanie, prompt uprawnienia w terminalu, bezczynność).
        case waitingForInput(String)
        case finished

        public var needsAttention: Bool {
            switch self {
            case .waitingForPermission, .waitingForInput: true
            default: false
            }
        }
    }

    public static let recentToolsLimit = 5

    public let id: String
    public let cwd: String?
    public let state: State
    /// Ostatnie narzędzia, najnowsze na końcu.
    public let recentTools: [String]
    public let lastEventAt: Date
    public let claudePID: Int32?
    public let bundleID: String?
    public let lastMessage: String?

    public var projectName: String {
        guard let cwd, !cwd.isEmpty else { return "Claude Code" }
        return (cwd as NSString).lastPathComponent
    }

    func with(state: State? = nil, recentTools: [String]? = nil, at date: Date, envelope: HookProtocol.Envelope?,
              lastMessage: String?? = nil) -> ClaudeSession {
        ClaudeSession(
            id: id,
            cwd: envelope?.event.cwd ?? cwd,
            state: state ?? self.state,
            recentTools: recentTools ?? self.recentTools,
            lastEventAt: date,
            claudePID: envelope?.claudePID ?? claudePID,
            bundleID: envelope?.bundleID ?? bundleID,
            lastMessage: lastMessage ?? self.lastMessage
        )
    }
}

/// Sygnał dla użytkownika wynikający ze zdarzenia (dźwięk, pulsowanie, rozwinięcie wyspy).
public enum SessionAlert: Equatable, Sendable {
    case needsInput
    case finished
}

/// Zbiór sesji: czysty reducer zdarzeń hooków. Niemutowalny.
public struct SessionStore: Equatable, Sendable {
    public let sessions: [String: ClaudeSession]

    public init(sessions: [String: ClaudeSession] = [:]) {
        self.sessions = sessions
    }

    /// Sesje do wyświetlenia: najpierw wymagające uwagi, potem najświeższe.
    public var ordered: [ClaudeSession] {
        sessions.values.sorted { lhs, rhs in
            if lhs.state.needsAttention != rhs.state.needsAttention { return lhs.state.needsAttention }
            return lhs.lastEventAt > rhs.lastEventAt
        }
    }

    public func applying(_ envelope: HookProtocol.Envelope, at date: Date) -> (SessionStore, SessionAlert?) {
        let event = envelope.event
        let current = sessions[event.sessionID] ?? ClaudeSession(
            id: event.sessionID, cwd: event.cwd, state: .idle, recentTools: [], lastEventAt: date,
            claudePID: envelope.claudePID, bundleID: envelope.bundleID, lastMessage: nil
        )

        let next: ClaudeSession?
        var alert: SessionAlert?
        switch event.name {
        case "SessionEnd":
            next = nil
        case "SessionStart":
            next = current.with(state: .idle, at: date, envelope: envelope)
        case "UserPromptSubmit", "PostToolUse", "PostToolUseFailure", "SubagentStop":
            next = current.with(state: .working, at: date, envelope: envelope)
        case "PreToolUse":
            let tool = Self.toolLabel(event)
            let tools = Array((current.recentTools + [tool]).suffix(ClaudeSession.recentToolsLimit))
            next = current.with(state: .runningTool(event.toolName ?? tool), recentTools: tools, at: date, envelope: envelope)
        case "PermissionRequest":
            next = current.with(state: .waitingForPermission, at: date, envelope: envelope)
            alert = .needsInput
        case "Notification" where Self.isIdleReminder(event, current: current.state):
            // Przypomnienie o bezczynności po skończonej pracy to nie prośba o uwagę — nie zapalamy „czeka”.
            next = current.with(at: date, envelope: envelope)
        case "Notification":
            let message = event.message ?? "Claude czeka na Ciebie"
            next = current.with(state: .waitingForInput(message), at: date, envelope: envelope)
            alert = .needsInput
        case "Stop":
            next = current.with(state: .finished, at: date, envelope: envelope, lastMessage: .some(event.lastAssistantMessage))
            alert = .finished
        default:
            next = current.with(at: date, envelope: envelope)
        }

        var sessions = self.sessions
        sessions[event.sessionID] = next
        return (SessionStore(sessions: sessions), alert)
    }

    /// Claude Code ok. minutę po zakończeniu odpowiedzi przypomina „czekam na Ciebie” (`idle_prompt`).
    /// Starsze wersje nie podają typu — wtedy rozpoznajemy je po tym, że sesja już skończyła odpowiedź.
    static func isIdleReminder(_ event: HookEvent, current: ClaudeSession.State) -> Bool {
        if let type = event.notificationType { return type == "idle_prompt" }
        return current == .finished
    }

    /// Po decyzji w wyspie sesja wraca do pracy.
    public func resolvingPermission(for sessionID: String, at date: Date) -> SessionStore {
        guard let session = sessions[sessionID], session.state == .waitingForPermission else { return self }
        var sessions = self.sessions
        sessions[sessionID] = session.with(state: .working, at: date, envelope: nil)
        return SessionStore(sessions: sessions)
    }

    /// Usuwa sesje, których proces Claude Code już nie istnieje (np. zamknięty terminal bez SessionEnd).
    public func removingDead(isAlive: (Int32) -> Bool) -> SessionStore {
        SessionStore(sessions: sessions.filter { _, session in session.claudePID.map(isAlive) ?? true })
    }

    static func toolLabel(_ event: HookEvent) -> String {
        guard let tool = event.toolName else { return "narzędzie" }
        guard let summary = event.toolInput?.summary else { return tool }
        let short = summary.count > 40 ? String(summary.prefix(39)) + "…" : summary
        return "\(tool): \(short)"
    }
}
