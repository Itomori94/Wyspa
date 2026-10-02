import AppKit
import SwiftUI
import WyspaCore

/// Minutnik, stoper i Pomodoro z odliczaniem w zwiniętej wyspie.
@MainActor
@Observable
public final class TimerModule: IslandModule {
    public static let descriptor = ModuleDescriptor(
        id: "timer",
        name: "Timer",
        summary: "Minutnik, stoper i Pomodoro z odliczaniem widocznym w zwiniętej wyspie.",
        symbol: "timer",
        content: .neutral,
        widgetMinWidth: 110
    )

    public enum Mode: String, CaseIterable, Codable {
        case countdown, stopwatch, pomodoro

        public var displayName: String {
            switch self {
            case .countdown: "Minutnik"
            case .stopwatch: "Stoper"
            case .pomodoro: "Pomodoro"
            }
        }
    }

    static let presets: [TimeInterval] = [1, 3, 5, 10, 15, 25, 45, 60].map { $0 * 60 }
    private static let sessionKey = "session"
    private static let durationKey = "countdownDuration"
    private static let finishedDisplay: Duration = .seconds(6)
    private static let statsKey = "focusStats"
    private static let goalKey = "dailyGoal"

    public private(set) var session: TimerSession?
    /// Krótki komunikat po zakończeniu odliczania („Koniec”, „Czas na przerwę”).
    public private(set) var finishedMessage: String?
    public var countdownDuration: TimeInterval {
        didSet { context.settings.set(countdownDuration, for: Self.durationKey) }
    }
    /// Ukończone sesje skupienia (dzisiejszy wynik w widżecie i rozwiniętym widoku).
    public private(set) var stats: FocusStats
    /// Dzienny cel sesji skupienia; 0 = bez celu.
    public var dailyGoal: Int {
        didSet { context.settings.set(dailyGoal, for: Self.goalKey) }
    }

    @ObservationIgnored private let context: ModuleContext
    @ObservationIgnored private var completionTask: Task<Void, Never>?
    @ObservationIgnored private var messageTask: Task<Void, Never>?

    public required init(context: ModuleContext) {
        self.context = context
        countdownDuration = context.settings.value(Self.durationKey, default: 5 * 60)
        stats = context.settings.value(Self.statsKey, default: FocusStats())
        dailyGoal = context.settings.value(Self.goalKey, default: FocusStats.defaultGoal)
    }

    public func activate() async throws {
        session = context.settings.value(Self.sessionKey, default: TimerSession?.none)
        // Odliczanie mogło się skończyć, gdy aplikacja nie działała.
        if let session, session.isFinished(at: Date()) {
            finish(session, at: session.endDate ?? Date(), announce: false)
        } else {
            scheduleCompletion()
        }
    }

    public func deactivate() {
        completionTask?.cancel()
        messageTask?.cancel()
        completionTask = nil
        messageTask = nil
    }

    public var mode: Mode {
        switch session?.kind {
        case .stopwatch: .stopwatch
        case .pomodoro: .pomodoro
        case .countdown, nil: .countdown
        }
    }

    public var liveActivity: LiveActivity? {
        if let finishedMessage {
            return LiveActivity(id: "timer", priority: .attention, accent: .orange, wingWidth: 56) {
                Image(systemName: "bell.fill").foregroundStyle(.orange).symbolEffect(.bounce, value: finishedMessage)
            } trailing: {
                Text("0:00").font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(.orange)
            }
        }
        guard let session, session.hasStarted else { return nil }
        return LiveActivity(id: "timer", priority: .timer, accent: Self.tint(for: session), wingWidth: 56) {
            Image(systemName: Self.symbol(for: session))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Self.tint(for: session))
        } trailing: {
            TimerClock(session: session)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(session.isRunning ? Self.tint(for: session) : .white.opacity(0.5))
        }
    }

    public func makeSettingsView() -> AnyView? { AnyView(TimerSettingsView(module: self)) }

    public func makeExpandedView() -> AnyView? {
        AnyView(TimerExpandedView(module: self))
    }

    public func makeWidgetView() -> AnyView? {
        AnyView(TimerWidget(module: self))
    }

    // MARK: - Akcje

    func select(_ mode: Mode) {
        guard mode != self.mode || session == nil else { return }
        switch mode {
        case .countdown: update(TimerSession(kind: .countdown(duration: countdownDuration)))
        case .stopwatch: update(TimerSession(kind: .stopwatch))
        case .pomodoro: update(TimerSession(kind: .pomodoro(phase: .focus, completedFocus: 0, config: .standard)))
        }
    }

    func setCountdown(_ duration: TimeInterval) {
        countdownDuration = min(max(duration, 60), 24 * 3600)
        update(TimerSession(kind: .countdown(duration: countdownDuration)))
    }

    func toggleRunning() {
        let now = Date()
        let current = session ?? TimerSession(kind: .countdown(duration: countdownDuration))
        update(current.isRunning ? current.paused(at: now) : current.started(at: now))
    }

    func reset() {
        update(session?.reset())
    }

    func skipPomodoroPhase() {
        guard let next = session?.nextPomodoroPhase(at: Date()) else { return }
        update(next)
    }

    // MARK: - Wewnętrzne

    private func update(_ newSession: TimerSession?) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { session = newSession }
        context.settings.set(newSession, for: Self.sessionKey)
        scheduleCompletion()
    }

    /// Jedno zadanie czekające do końca odliczania — bez tyknięć co sekundę.
    private func scheduleCompletion() {
        completionTask?.cancel()
        guard let session, let end = session.endDate else { return }
        completionTask = Task { [weak self] in
            let delay = end.timeIntervalSinceNow
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard !Task.isCancelled, let self, self.session == session else { return }
            self.finish(session, at: end, announce: true)
        }
    }

    /// Spóźnienie, powyżej którego koniec uznajemy za „przegapiony” (uśpienie Maca, aplikacja wyłączona).
    static let lateFinishTolerance: TimeInterval = 2

    private func finish(_ finished: TimerSession, at end: Date, announce: Bool) {
        let message: String
        // Po przegapionym końcu kolejna faza Pomodoro startuje teraz, a nie od dawnego końca —
        // inaczej każda przespana faza kończyłaby się natychmiast z osobnym dźwiękiem.
        let now = Date()
        let start = now.timeIntervalSince(end) > Self.lateFinishTolerance ? now : end
        if case .pomodoro(.focus, _, let config) = finished.kind {
            // Liczy się tylko skupienie dobiegnięte do końca (pominięcie fazy nie trafia do statystyk).
            stats = stats.recording(minutes: Int((config.focus / 60).rounded()), at: end)
            context.settings.set(stats, for: Self.statsKey)
        }
        if let next = finished.nextPomodoroPhase(at: start) {
            message = Self.pomodoroMessage(for: next)
            update(next)
        } else {
            message = "Koniec odliczania"
            update(finished.reset())
        }
        guard announce else { return }
        NSSound(named: "Glass")?.play()
        withAnimation { finishedMessage = message }
        context.requestExpand()
        messageTask?.cancel()
        messageTask = Task { [weak self] in
            try? await Task.sleep(for: Self.finishedDisplay)
            guard !Task.isCancelled else { return }
            withAnimation { self?.finishedMessage = nil }
        }
    }

    private static func pomodoroMessage(for next: TimerSession) -> String {
        guard case .pomodoro(let phase, _, _) = next.kind else { return "Koniec" }
        return phase == .focus ? "Koniec przerwy — czas na skupienie" : "Czas na przerwę"
    }

    static func symbol(for session: TimerSession) -> String {
        switch session.kind {
        case .countdown: "timer"
        case .stopwatch: "stopwatch"
        case .pomodoro(let phase, _, _): phase == .focus ? "brain.head.profile" : "cup.and.saucer.fill"
        }
    }

    static func tint(for session: TimerSession) -> Color {
        switch session.kind {
        case .countdown: .orange
        case .stopwatch: .yellow
        case .pomodoro(let phase, _, _): phase == .focus ? .red : .green
        }
    }
}
