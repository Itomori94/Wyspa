import SwiftUI
import WyspaUI

/// Duży czas i start/pauza; tryb z ostatniej sesji.
struct TimerWidget: View {
    let module: TimerModule

    var body: some View {
        let session = module.session ?? TimerSession(kind: .countdown(duration: module.countdownDuration))
        let tint = TimerModule.tint(for: session)
        VStack(spacing: 6) {
            Label(module.mode.displayName, systemImage: TimerModule.symbol(for: session))
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(tint)
            TimerClock(session: session)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            HStack(spacing: 8) {
                Button(action: module.toggleRunning) {
                    Image(systemName: session.isRunning ? "pause.fill" : "play.fill")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 34, height: 26)
                        .background(Capsule().fill(tint.opacity(0.85)))
                        .foregroundStyle(.black)
                }
                .buttonStyle(IslandPressStyle())
                if session.hasStarted {
                    Button(action: module.reset) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 11, weight: .bold))
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(.white.opacity(0.12)))
                    }
                    .buttonStyle(IslandPressStyle())
                }
            }
            if module.mode == .pomodoro {
                TodayFocus(module: module, compact: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
