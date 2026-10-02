import Foundation

public enum PomodoroPhase: String, Codable, Sendable {
    case focus, shortBreak, longBreak

    public var displayName: String {
        switch self {
        case .focus: "Skupienie"
        case .shortBreak: "Krótka przerwa"
        case .longBreak: "Długa przerwa"
        }
    }
}

public struct PomodoroConfig: Codable, Equatable, Sendable {
    public var focus: TimeInterval
    public var shortBreak: TimeInterval
    public var longBreak: TimeInterval
    /// Po tylu sesjach skupienia przychodzi długa przerwa.
    public var roundsBeforeLongBreak: Int

    public static let standard = PomodoroConfig(focus: 25 * 60, shortBreak: 5 * 60, longBreak: 15 * 60, roundsBeforeLongBreak: 4)

    public init(focus: TimeInterval, shortBreak: TimeInterval, longBreak: TimeInterval, roundsBeforeLongBreak: Int) {
        self.focus = focus
        self.shortBreak = shortBreak
        self.longBreak = longBreak
        self.roundsBeforeLongBreak = max(1, roundsBeforeLongBreak)
    }

    func duration(of phase: PomodoroPhase) -> TimeInterval {
        switch phase {
        case .focus: focus
        case .shortBreak: shortBreak
        case .longBreak: longBreak
        }
    }
}

/// Sesja timera. Niemutowalna: każda operacja zwraca nową sesję.
///
/// Czas nie jest odliczany tyknięciami — wynika z `startedAt` i `accumulated`, więc sesja przetrwa restart aplikacji.
public struct TimerSession: Codable, Equatable, Sendable {
    public enum Kind: Codable, Equatable, Sendable {
        case countdown(duration: TimeInterval)
        case stopwatch
        case pomodoro(phase: PomodoroPhase, completedFocus: Int, config: PomodoroConfig)
    }

    public let kind: Kind
    /// Początek bieżącego biegu; nil = pauza albo jeszcze nie wystartowano.
    public let startedAt: Date?
    /// Czas z poprzednich biegów (przed ostatnią pauzą).
    public let accumulated: TimeInterval

    public init(kind: Kind, startedAt: Date? = nil, accumulated: TimeInterval = 0) {
        self.kind = kind
        self.startedAt = startedAt
        self.accumulated = accumulated
    }

    public var isRunning: Bool { startedAt != nil }
    public var hasStarted: Bool { isRunning || accumulated > 0 }

    /// Długość odliczania; nil dla stopera.
    public var duration: TimeInterval? {
        switch kind {
        case .countdown(let duration): duration
        case .stopwatch: nil
        case .pomodoro(let phase, _, let config): config.duration(of: phase)
        }
    }

    public func elapsed(at now: Date) -> TimeInterval {
        let running = startedAt.map { max(0, now.timeIntervalSince($0)) } ?? 0
        let total = accumulated + running
        return duration.map { min(total, $0) } ?? total
    }

    public func remaining(at now: Date) -> TimeInterval? {
        duration.map { max(0, $0 - elapsed(at: now)) }
    }

    /// Chwila zakończenia odliczania przy nieprzerwanym biegu; nil dla stopera i pauzy.
    public var endDate: Date? {
        guard let startedAt, let duration else { return nil }
        return startedAt.addingTimeInterval(duration - accumulated)
    }

    public func isFinished(at now: Date) -> Bool {
        guard let remaining = remaining(at: now) else { return false }
        return remaining <= 0
    }

    public func started(at now: Date) -> TimerSession {
        guard !isRunning, !isFinished(at: now) else { return self }
        return TimerSession(kind: kind, startedAt: now, accumulated: accumulated)
    }

    public func paused(at now: Date) -> TimerSession {
        guard isRunning else { return self }
        return TimerSession(kind: kind, startedAt: nil, accumulated: elapsed(at: now))
    }

    public func reset() -> TimerSession {
        TimerSession(kind: kind)
    }

    /// Kolejna faza Pomodoro po zakończeniu bieżącej, od razu uruchomiona w chwili `now`.
    public func nextPomodoroPhase(at now: Date) -> TimerSession? {
        guard case .pomodoro(let phase, let completed, let config) = kind else { return nil }
        let next: Kind
        switch phase {
        case .focus:
            let done = completed + 1
            let isLong = done % config.roundsBeforeLongBreak == 0
            next = .pomodoro(phase: isLong ? .longBreak : .shortBreak, completedFocus: done, config: config)
        case .shortBreak, .longBreak:
            next = .pomodoro(phase: .focus, completedFocus: completed, config: config)
        }
        return TimerSession(kind: next, startedAt: now)
    }
}

public enum TimerText {
    /// „4:05”, „25:00”, „1:02:03”.
    public static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }

    /// Stoper pokazuje czas w dół (bez zaokrąglania w górę).
    public static func formatElapsed(_ seconds: TimeInterval) -> String {
        format(seconds.rounded(.down))
    }
}
