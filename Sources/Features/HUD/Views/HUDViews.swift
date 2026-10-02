import SwiftUI

/// Lewe skrzydło: ikona i lewa połowa paska. Razem z prawym skrzydłem pasek biegnie symetrycznie przez notch,
/// więc jego środek wypada na środku ekranu.
struct HUDLeadingWing: View {
    let reading: HUDReading

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: reading.symbol, variableValue: Double(reading.level))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: HUDWing.labelWidth)
            HalfBar(fill: reading.halfFills.left, isMuted: reading.isMuted)
        }
        .padding(.leading, 2)
        .accessibilityElement()
        .accessibilityLabel(reading.kind.displayName)
        .accessibilityValue("\(reading.percentText)")
    }
}

/// Prawe skrzydło: prawa połowa paska i procent.
struct HUDTrailingWing: View {
    let reading: HUDReading

    var body: some View {
        HStack(spacing: 6) {
            HalfBar(fill: reading.halfFills.right, isMuted: reading.isMuted)
            Text(reading.percentText)
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(reading.isMuted ? 0.45 : 0.85))
                .contentTransition(.numericText())
                .frame(width: HUDWing.labelWidth, alignment: .trailing)
        }
        .padding(.trailing, 2)
        .accessibilityHidden(true)
    }
}

enum HUDWing {
    /// Ikona i procent mają tę samą szerokość, żeby obie połowy paska były równe.
    static let labelWidth: CGFloat = 30
}

/// Połowa paska; przy wyciszeniu przygaszona.
private struct HalfBar: View {
    let fill: CGFloat
    let isMuted: Bool

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.2))
                Capsule()
                    .fill(.white.opacity(isMuted ? 0.35 : 1))
                    .frame(width: proxy.size.width * fill)
            }
        }
        .frame(height: 5)
        .animation(.spring(response: 0.22, dampingFraction: 0.9), value: fill)
    }
}

struct HUDSettingsView: View {
    @Bindable var module: HUDModule

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(HUDKind.allCases, id: \.self) { kind in
                Toggle(kind.displayName, isOn: Binding(
                    get: { module.enabledKinds.contains(kind) },
                    set: { enabled in
                        module.enabledKinds = enabled ? module.enabledKinds.union([kind]) : module.enabledKinds.subtracting([kind])
                    }
                ))
                .disabled(!isAvailable(kind))
                if !isAvailable(kind) {
                    Text(unavailableReason(kind))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text("⇧⌥ z klawiszem zmienia poziom drobniejszymi krokami. Sam ⌥ otwiera ustawienia systemowe.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func isAvailable(_ kind: HUDKind) -> Bool {
        switch kind {
        case .volume: true
        case .brightness: module.hasBrightnessControl
        case .keyboard: module.hasKeyboardControl
        }
    }

    private func unavailableReason(_ kind: HUDKind) -> String {
        switch kind {
        case .volume: ""
        case .brightness: "Niedostępne: brak wbudowanego ekranu albo DisplayServices w tej wersji macOS."
        case .keyboard: "Niedostępne: brak podświetlanej klawiatury albo CoreBrightness w tej wersji macOS."
        }
    }
}
