import AppKit
import SwiftUI
import WyspaCore
import WyspaHookKit

/// Prośba o uprawnienie czekająca na decyzję w wyspie.
public struct PendingPermission: Identifiable, Sendable {
    public let id: UUID
    public let sessionID: String
    public let event: HookEvent
    public let receivedAt: Date
    let channel: HookServer.ReplyChannel
}

/// Monitor sesji Claude Code: stan sesji, ostatnie narzędzia, zatwierdzanie uprawnień z wyspy.
@MainActor
@Observable
public final class ClaudeMonitorModule: IslandModule {
    public static let descriptor = ModuleDescriptor(
        id: "claude",
        name: "Claude Code",
        summary: "Sesje Claude Code: czy pracuje, jakiego narzędzia używa, czy czeka na Ciebie. Zatwierdzanie uprawnień z wyspy.",
        symbol: "terminal.fill",
        widgetMinWidth: 150
    )

    static let finishedDisplay: Duration = .seconds(5)
    static let decisionMinutesRange = 1...30
    private static let decisionKey = "decisionMinutes"
    private static let soundsKey = "sounds"
    private static let muteKey = "muteWhenTerminalFrontmost"

    public private(set) var store = SessionStore()
    public private(set) var pending: [PendingPermission] = []
    public private(set) var hookStatus: HookStatus = .unknown
    public private(set) var problem: String?
    /// Sesja, która przed chwilą skończyła (krótka aktywność w zwiniętej wyspie).
    public private(set) var justFinished: ClaudeSession?

    public var decisionMinutes: Int {
        didSet {
            context.settings.set(decisionMinutes, for: Self.decisionKey)
            scheduleHookUpdate()
        }
    }
    public var soundsEnabled: Bool { didSet { context.settings.set(soundsEnabled, for: Self.soundsKey) } }
    public var muteWhenTerminalFrontmost: Bool { didSet { context.settings.set(muteWhenTerminalFrontmost, for: Self.muteKey) } }

    public enum HookStatus: Equatable { case unknown, notInstalled, installed, outdatedPath }

    @ObservationIgnored private let context: ModuleContext
    @ObservationIgnored private var server: HookServer?
    @ObservationIgnored private var finishedTask: Task<Void, Never>?
    @ObservationIgnored private var hookUpdateTask: Task<Void, Never>?
    /// Obserwatory zakończenia procesów Claude Code (zdarzenia jądra, bez odpytywania).
    @ObservationIgnored private var processWatchers: [Int32: DispatchSourceProcess] = [:]
    @ObservationIgnored private let log = Log.logger("claude")

    public required init(context: ModuleContext) {
        self.context = context
        decisionMinutes = context.settings.value(Self.decisionKey, default: 5)
        soundsEnabled = context.settings.value(Self.soundsKey, default: true)
        muteWhenTerminalFrontmost = context.settings.value(Self.muteKey, default: true)
    }

    public func activate() async throws {
        let server = HookServer(
            onMessage: { [weak self] envelope, channel in
                Task { @MainActor in self?.receive(envelope, channel: channel) }
            },
            onClosed: { [weak self] (channelID: UInt64) in
                Task { @MainActor in self?.hookGaveUp(channelID) }
            }
        )
        try server.start()
        self.server = server
        refreshHookStatus()
    }

    /// Wyłączenie: czekające hooki od razu wracają do promptu w terminalu.
    public func deactivate() {
        processWatchers.values.forEach { $0.cancel() }
        processWatchers = [:]
        hookUpdateTask?.cancel()
        server?.stop()
        server = nil
        pending = []
        store = SessionStore()
        finishedTask?.cancel()
    }

    // MARK: - Widoki

    public var liveActivity: LiveActivity? {
        if !pending.isEmpty || store.sessions.values.contains(where: { $0.state.needsAttention }) {
            let count = max(pending.count, store.sessions.values.filter { $0.state.needsAttention }.count)
            return LiveActivity(id: "claude.attention", priority: .attention, accent: .orange, wingWidth: 56) {
                Image(systemName: pending.isEmpty ? "ellipsis.bubble.fill" : "hand.raised.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.orange)
                    .symbolEffect(.pulse, options: .repeating)
            } trailing: {
                Text(pending.isEmpty ? "czeka" : (count > 1 ? "\(count) zgody" : "zgoda?"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.orange)
            }
        }
        if let justFinished {
            return LiveActivity(id: "claude.finished", priority: .alert, accent: .green, wingWidth: 56) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            } trailing: {
                Text(justFinished.projectName).font(.system(size: 10.5, weight: .semibold)).lineLimit(1).foregroundStyle(.green)
            }
        }
        let working = store.sessions.values.filter { $0.state == .working || $0.state.isRunningTool }.count
        guard working > 0 else { return nil }
        return LiveActivity(id: "claude.working", priority: .status, accent: .purple, wingWidth: 46) {
            Image(systemName: "sparkle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.purple)
                .symbolEffect(.pulse, options: .repeating)
        } trailing: {
            Text("\(working)").font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(.purple)
        }
    }

    public func makeExpandedView() -> AnyView? { AnyView(ClaudeSessionsView(module: self, compact: false)) }
    public func makeWidgetView() -> AnyView? { AnyView(ClaudeSessionsView(module: self, compact: true)) }
    public func makeSettingsView() -> AnyView? { AnyView(ClaudeSettingsView(module: self)) }

    // MARK: - Akcje

    public func decide(_ request: PendingPermission, _ behavior: HookProtocol.Behavior) {
        request.channel.send(behavior, message: behavior == .deny ? "Odrzucono w Wyspie." : nil)
        pending = pending.filter { $0.id != request.id }
        store = store.resolvingPermission(for: request.sessionID, at: Date())
    }

    public func focus(_ session: ClaudeSession) {
        TerminalFocus.focus(bundleID: session.bundleID, claudePID: session.claudePID, cwd: session.cwd)
    }

    public func removeDeadSessions() {
        store = store.removingDead { pid in kill(pid, 0) == 0 || errno == EPERM }
    }

    // MARK: - Hooki w ~/.claude/settings.json

    /// Ścieżka helpera w bieżącym pakiecie aplikacji.
    var helperPath: String {
        Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/wyspa-hook").path
    }

    func refreshHookStatus() {
        do {
            let settings = try HookInstaller.read()
            if HookInstaller.isInstalled(in: settings) {
                hookStatus = Self.installedPaths(in: settings).allSatisfy { $0 == helperPath } ? .installed : .outdatedPath
            } else {
                hookStatus = .notInstalled
            }
            problem = nil
        } catch {
            problem = error.localizedDescription
        }
    }

    /// Zmiana czasu decyzji aktualizuje hooki dopiero po chwili bez kolejnych kliknięć.
    private func scheduleHookUpdate() {
        hookUpdateTask?.cancel()
        guard hookStatus == .installed else { return }
        hookUpdateTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            self?.installHooks()
        }
    }

    func installHooks() {
        guard FileManager.default.isExecutableFile(atPath: helperPath) else {
            problem = "Brak programu wyspa-hook w pakiecie aplikacji. Zbuduj aplikację skryptem scripts/build-app.sh."
            return
        }
        do {
            let settings = try HookInstaller.read()
            try HookInstaller.write(try HookInstaller.installing(into: settings, helperPath: helperPath,
                                                                 decisionTimeout: decisionMinutes * 60))
            refreshHookStatus()
        } catch {
            problem = error.localizedDescription
        }
    }

    func uninstallHooks() {
        do {
            try HookInstaller.write(try HookInstaller.uninstalling(from: try HookInstaller.read()))
            refreshHookStatus()
        } catch {
            problem = error.localizedDescription
        }
    }

    private static func installedPaths(in settings: [String: Any]) -> [String] {
        let hooks = settings["hooks"] as? [String: Any] ?? [:]
        return hooks.values.compactMap { $0 as? [[String: Any]] }.joined()
            .compactMap { $0["hooks"] as? [[String: Any]] }.joined()
            .compactMap { $0["command"] as? String }
            .filter { ($0 as NSString).lastPathComponent == HookInstaller.marker }
    }

    // MARK: - Zdarzenia

    private func receive(_ envelope: HookProtocol.Envelope, channel: HookServer.ReplyChannel?) {
        let (next, alert) = store.applying(envelope, at: Date())
        store = next
        if envelope.event.name == "PermissionRequest", let channel {
            // Potwierdzenie z głównego wątku: hook wie, że Wyspa żyje i czeka na decyzję użytkownika.
            channel.acknowledge()
            pending = pending + [PendingPermission(id: UUID(), sessionID: envelope.event.sessionID,
                                                   event: envelope.event, receivedAt: Date(), channel: channel)]
            context.requestExpand()
        }
        if let pid = envelope.claudePID { watchProcess(pid) }
        guard let alert, let session = store.sessions[envelope.event.sessionID] else { return }
        if alert == .finished { showFinished(session) }
        playSound(for: alert, session: session)
    }

    /// Sesja znika, gdy jej proces Claude Code się zakończy (np. zamknięty terminal bez SessionEnd).
    private func watchProcess(_ pid: Int32) {
        guard processWatchers[pid] == nil, pid > 1 else { return }
        let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                self?.processWatchers[pid]?.cancel()
                self?.processWatchers[pid] = nil
                self?.removeDeadSessions()
            }
        }
        processWatchers[pid] = source
        source.resume()
        // Proces mógł zniknąć przed rejestracją źródła.
        if kill(pid, 0) != 0 && errno == ESRCH { removeDeadSessions() }
    }

    /// Hook zamknął połączenie bez decyzji (minął jego czas): Claude Code pokazuje prompt w terminalu.
    private func hookGaveUp(_ channelID: UInt64) {
        guard let request = pending.first(where: { $0.channel.id == channelID }) else { return }
        pending = pending.filter { $0.id != request.id }
        if let session = store.sessions[request.sessionID], session.state == .waitingForPermission {
            let (next, _) = store.applying(HookProtocol.Envelope(
                event: HookEvent.waiting(sessionID: request.sessionID), claudePID: nil, bundleID: nil,
                termProgram: nil, wantsReply: false), at: Date())
            store = next
        }
    }

    private func showFinished(_ session: ClaudeSession) {
        withAnimation { justFinished = session }
        finishedTask?.cancel()
        finishedTask = Task { [weak self] in
            try? await Task.sleep(for: Self.finishedDisplay)
            guard !Task.isCancelled else { return }
            withAnimation { self?.justFinished = nil }
        }
    }

    /// Dźwięk przy oczekiwaniu i końcu; cisza, gdy terminal tej sesji jest na wierzchu.
    private func playSound(for alert: SessionAlert, session: ClaudeSession) {
        guard soundsEnabled else { return }
        if muteWhenTerminalFrontmost, let bundleID = session.bundleID,
           NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID { return }
        NSSound(named: alert == .finished ? "Glass" : "Funk")?.play()
    }
}

extension ClaudeSession.State {
    var isRunningTool: Bool {
        if case .runningTool = self { return true }
        return false
    }
}

extension HookEvent {
    /// Syntetyczne „czeka na Ciebie” po wygaśnięciu decyzji w wyspie.
    static func waiting(sessionID: String) -> HookEvent {
        // `parse` z minimalnym słownikiem nie może się nie udać (oba wymagane pola są podane).
        (try? HookEvent.parse([
            "hook_event_name": "Notification", "session_id": sessionID,
            "message": "Czeka na decyzję w terminalu",
        ])) ?? HookEvent.fallback(sessionID)
    }
}
