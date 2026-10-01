import SwiftUI

struct PowerExpandedView: View {
    let state: PowerState?

    var body: some View {
        if let state {
            HStack(spacing: 18) {
                BatteryRing(level: state.level, isCharging: state.isCharging || state.isPluggedIn)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(state.level)%")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text(state.statusText)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
                Spacer()
            }
            .frame(maxHeight: .infinity)
        } else {
            Label("Ten Mac nie ma baterii.", systemImage: "powerplug")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct BatteryRing: View {
    let level: Int
    let isCharging: Bool

    private var tint: Color {
        if isCharging { return .green }
        return level <= 10 ? .red : (level <= 20 ? .orange : .white)
    }

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.12), lineWidth: 7)
            Circle()
                .trim(from: 0, to: CGFloat(level) / 100)
                .stroke(tint, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: isCharging ? "bolt.fill" : "battery.100percent")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)
        }
        .frame(width: 68, height: 68)
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: level)
        .accessibilityElement()
        .accessibilityLabel("Bateria")
        .accessibilityValue("\(level) procent")
    }
}
