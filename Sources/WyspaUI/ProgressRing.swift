import SwiftUI

/// Pierścień postępu do skrzydła zwiniętej wyspy (pobierania, skrypty). `fraction == nil` = postęp nieokreślony.
public struct ProgressRing: View {
    let fraction: Double?
    let tint: Color
    let symbol: String

    public init(fraction: Double?, tint: Color, symbol: String) {
        self.fraction = fraction
        self.tint = tint
        self.symbol = symbol
    }

    public var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.2), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: fraction ?? 0.25)
                .stroke(tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.3), value: fraction)
            Image(systemName: symbol).font(.system(size: 7.5, weight: .bold)).foregroundStyle(.white)
        }
        .frame(width: 16, height: 16)
    }
}
