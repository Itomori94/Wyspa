import Foundation
import Testing
@testable import WyspaTimer

@Suite("Sesja timera")
struct TimerSessionTests {
    let t0 = Date(timeIntervalSince1970: 1_000)

    @Test("Minutnik odlicza z dat, bez tyknięć")
    func countdown() {
        let session = TimerSession(kind: .countdown(duration: 300)).started(at: t0)
        #expect(session.remaining(at: t0.addingTimeInterval(60)) == 240)
        #expect(session.endDate == t0.addingTimeInterval(300))
        #expect(!session.isFinished(at: t0.addingTimeInterval(299)))
        #expect(session.isFinished(at: t0.addingTimeInterval(300)))
        #expect(session.remaining(at: t0.addingTimeInterval(999)) == 0)
    }

    @Test("Skupienie trwa tylko w uruchomionej fazie skupienia Pomodoro")
    func focusing() {
        let focus = TimerSession(kind: .pomodoro(phase: .focus, completedFocus: 0, config: .standard))
        #expect(!focus.isFocusing, "nieuruchomiona")
        #expect(focus.started(at: t0).isFocusing)
        #expect(!focus.started(at: t0).paused(at: t0.addingTimeInterval(60)).isFocusing)
        let rest = focus.started(at: t0).nextPomodoroPhase(at: t0.addingTimeInterval(1500))
        #expect(rest?.isFocusing == false, "przerwa")
        #expect(!TimerSession(kind: .countdown(duration: 60)).started(at: t0).isFocusing)
    }

    @Test("Pauza zatrzymuje czas, wznowienie przesuwa koniec")
    func pauseResume() {
        let paused = TimerSession(kind: .countdown(duration: 300)).started(at: t0).paused(at: t0.addingTimeInterval(100))
        #expect(!paused.isRunning && paused.accumulated == 100)
        #expect(paused.remaining(at: t0.addingTimeInterval(500)) == 200)
        #expect(paused.endDate == nil)
        let resumed = paused.started(at: t0.addingTimeInterval(1000))
        #expect(resumed.endDate == t0.addingTimeInterval(1200))
    }

    @Test("Operacje nie zmieniają oryginału")
    func immutable() {
        let original = TimerSession(kind: .stopwatch)
        _ = original.started(at: t0)
        #expect(!original.isRunning)
    }

    @Test("Stoper liczy w górę bez końca")
    func stopwatch() {
        let session = TimerSession(kind: .stopwatch).started(at: t0)
        #expect(session.elapsed(at: t0.addingTimeInterval(4000)) == 4000)
        #expect(session.remaining(at: t0) == nil && session.endDate == nil)
        #expect(!session.isFinished(at: t0.addingTimeInterval(1e6)))
    }

    @Test("Zakończonego minutnika nie da się wystartować, reset zeruje")
    func finishedAndReset() {
        let finished = TimerSession(kind: .countdown(duration: 10), accumulated: 10)
        #expect(finished.started(at: t0) == finished)
        #expect(finished.reset() == TimerSession(kind: .countdown(duration: 10)))
    }

    @Test("Pomodoro: skupienie, krótkie przerwy, długa przerwa co 4 sesje")
    func pomodoroCycle() {
        var session = TimerSession(kind: .pomodoro(phase: .focus, completedFocus: 0, config: .standard))
        var phases: [PomodoroPhase] = []
        for _ in 0..<8 {
            session = session.nextPomodoroPhase(at: t0)!
            if case .pomodoro(let phase, _, _) = session.kind { phases.append(phase) }
        }
        #expect(phases == [.shortBreak, .focus, .shortBreak, .focus, .shortBreak, .focus, .longBreak, .focus])
        #expect(session.isRunning)
        #expect(session.duration == PomodoroConfig.standard.focus)
    }

    @Test("Następna faza istnieje tylko w Pomodoro")
    func nextPhaseOnlyForPomodoro() {
        #expect(TimerSession(kind: .stopwatch).nextPomodoroPhase(at: t0) == nil)
    }

    @Test("Sesja przetrwa zapis i odczyt (restart aplikacji)")
    func codable() throws {
        let session = TimerSession(kind: .pomodoro(phase: .longBreak, completedFocus: 4, config: .standard), startedAt: t0, accumulated: 12)
        let decoded = try JSONDecoder().decode(TimerSession.self, from: JSONEncoder().encode(session))
        #expect(decoded == session)
    }

    @Test("Formatowanie czasu")
    func format() {
        #expect(TimerText.format(245) == "4:05")
        #expect(TimerText.format(1500) == "25:00")
        #expect(TimerText.format(3723) == "1:02:03")
        #expect(TimerText.format(0.2) == "0:01")
        #expect(TimerText.formatElapsed(59.9) == "0:59")
    }
}
