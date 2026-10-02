import SwiftUI
import WyspaUI

/// Czas sesji odświeżany co sekundę tylko podczas biegu; w pauzie statyczny tekst (bez zegara w tle).
struct TimerClock: View {
    let session: TimerSession

    var body: some View {
        if session.isRunning {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(text(at: context.date))
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: session.duration != nil))
            }
        } else {
            Text(text(at: Date())).monospacedDigit()
        }
    }

    private func text(at date: Date) -> String {
        if let remaining = session.remaining(at: date) { return TimerText.format(remaining) }
        return TimerText.formatElapsed(session.elapsed(at: date))
    }
}

struct TimerExpandedView: View {
    let module: TimerModule

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                ForEach(TimerModule.Mode.allCases, id: \.self) { mode in
                    ModeChip(title: mode.displayName, isSelected: module.mode == mode) { module.select(mode) }
                }
                Spacer()
                if let message = module.finishedMessage {
                    Label(message, systemImage: "bell.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.orange)
                }
            }
            HStack(alignment: .center, spacing: 16) {
                bigClock
                Spacer()
                controls
            }
            if module.mode == .countdown, !(module.session?.hasStarted ?? false) {
                presets
            } else if case .pomodoro(let phase, let completed, let config) = module.session?.kind {
                PomodoroProgress(phase: phase, completed: completed, rounds: config.roundsBeforeLongBreak)
            }
            if module.mode == .pomodoro {
                TodayFocus(module: module)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var bigClock: some View {
        let session = module.session ?? TimerSession(kind: .countdown(duration: module.countdownDuration))
        return VStack(alignment: .leading, spacing: 2) {
            TimerClock(session: session)
                .font(.system(size: 34, weight: .bold, design: .rounded))
            if case .pomodoro(let phase, _, _) = session.kind {
                Text(phase.displayName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(TimerModule.tint(for: session))
            }
        }
    }

    private var controls: some View {
        let running = module.session?.isRunning ?? false
        return HStack(spacing: 10) {
            if module.session?.hasStarted ?? false {
                RoundButton(symbol: "arrow.counterclockwise", label: "Wyzeruj", prominent: false, action: module.reset)
            }
            if module.mode == .pomodoro, module.session?.hasStarted ?? false {
                RoundButton(symbol: "forward.end.fill", label: "Pomiń fazę", prominent: false, action: module.skipPomodoroPhase)
            }
            RoundButton(symbol: running ? "pause.fill" : "play.fill", label: running ? "Pauza" : "Start",
                        prominent: true, action: module.toggleRunning)
        }
    }

    private var presets: some View {
        HStack(spacing: 6) {
            ForEach(TimerModule.presets, id: \.self) { preset in
                ModeChip(title: "\(Int(preset / 60))", isSelected: module.countdownDuration == preset) {
                    module.setCountdown(preset)
                }
            }
            Text("min").font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
            Spacer(minLength: 4)
            Stepper("", value: Binding(
                get: { module.countdownDuration / 60 },
                set: { module.setCountdown($0 * 60) }
            ), in: 1...240, step: 1)
            .labelsHidden()
        }
    }
}

private struct PomodoroProgress: View {
    let phase: PomodoroPhase
    let completed: Int
    let rounds: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<rounds, id: \.self) { index in
                Circle()
                    .fill(index < completed % rounds || (completed > 0 && completed % rounds == 0 && phase == .longBreak)
                          ? Color.red : Color.white.opacity(0.18))
                    .frame(width: 8, height: 8)
            }
            Text("Ukończone sesje: \(completed)")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.5))
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ModeChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(.white.opacity(isSelected ? 0.22 : (isHovered ? 0.12 : 0.06))))
                .foregroundStyle(.white.opacity(isSelected ? 1 : 0.7))
        }
        .buttonStyle(IslandPressStyle())
        .onHover { isHovered = $0 }
    }
}

private struct RoundButton: View {
    let symbol: String
    let label: String
    let prominent: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: prominent ? 18 : 13, weight: .bold))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: prominent ? 46 : 34, height: prominent ? 46 : 34)
                .background(Circle().fill(prominent ? Color.orange.opacity(isHovered ? 0.95 : 0.8) : .white.opacity(isHovered ? 0.18 : 0.1)))
                .foregroundStyle(prominent ? .black : .white)
        }
        .buttonStyle(IslandPressStyle())
        .onHover { isHovered = $0 }
        .help(label)
        .accessibilityLabel(label)
    }
}

/// Dzisiejszy wynik Pomodoro: kropki ukończonych sesji (do celu) i suma minut. Odświeża się przy zmianie dnia.
struct TodayFocus: View {
    let module: TimerModule
    var compact = false

    var body: some View {
        TimelineView(.everyMinute) { context in
            let today = module.stats.today(at: context.date)
            HStack(spacing: 6) {
                if module.dailyGoal > 0 {
                    HStack(spacing: compact ? 2 : 3) {
                        ForEach(0..<max(module.dailyGoal, today.sessions), id: \.self) { index in
                            Circle()
                                .fill(index < today.sessions ? Color.red : .white.opacity(0.18))
                                .frame(width: compact ? 4 : 6, height: compact ? 4 : 6)
                        }
                    }
                }
                Text(summary(today))
                    .font(.system(size: compact ? 9.5 : 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Dziś \(today.sessions) sesji skupienia, \(today.minutes) minut")
        }
    }

    private func summary(_ today: FocusStats.Day) -> String {
        let goal = module.dailyGoal > 0 ? "/\(module.dailyGoal)" : ""
        return compact ? "\(today.sessions)\(goal)" : "Dziś \(today.sessions)\(goal) · \(today.minutes) min"
    }
}

struct TimerSettingsView: View {
    @Bindable var module: TimerModule

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Stepper(value: $module.dailyGoal, in: FocusStats.goalRange) {
                Text(module.dailyGoal == 0 ? "Dzienny cel Pomodoro: brak" : "Dzienny cel Pomodoro: \(module.dailyGoal) sesji")
            }
            Toggle("Wstrzymuj powiadomienia podczas skupienia", isOn: $module.holdsNotifications)
            Text("Gdy trwa faza skupienia Pomodoro, karty powiadomień w wyspie czekają i przychodzą po jej końcu "
                 + "z podsumowaniem. Działa z włączonym modułem Powiadomienia; systemowy baner jest wtedy chowany.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
