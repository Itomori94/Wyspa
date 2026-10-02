import SwiftUI

/// Poziom baterii i stan ładowania.
struct PowerWidget: View {
    let state: PowerState?

    var body: some View {
        VStack(spacing: 4) {
            if let state {
                Image(systemName: state.symbol)
                    .font(.system(size: 22))
                    .foregroundStyle(state.isCharging || state.isPluggedIn ? .green : (state.level <= 20 ? .orange : .white))
                Text("\(state.level)%").font(.system(size: 20, weight: .bold, design: .rounded)).monospacedDigit()
                Text(state.isCharging ? "Ładowanie" : (state.isPluggedIn ? "Zasilacz" : "Bateria"))
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
            } else {
                Image(systemName: "powerplug").font(.system(size: 20)).foregroundStyle(.white.opacity(0.5))
                Text("Bez baterii").font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
