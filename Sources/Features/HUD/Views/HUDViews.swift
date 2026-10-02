import SwiftUI

/// Lewe skrzydło: ikona rodzaju (głośność, jasność, klawiatura).
struct HUDIcon: View {
    let reading: HUDReading

    var body: some View {
        Image(systemName: reading.symbol, variableValue: Double(reading.level))
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .contentTransition(.symbolEffect(.replace))
            .accessibilityLabel(reading.kind.displayName)
    }
}

/// Prawe skrzydło: poziom w procentach.
struct HUDPercent: View {
    let reading: HUDReading

    var body: some View {
        Text(reading.percentText)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white.opacity(reading.isMuted ? 0.45 : 0.85))
            .contentTransition(.numericText())
            .accessibilityHidden(true)
    }
}

/// Jeden pasek poziomu pod notchem, wyśrodkowany na ekranie; przy wyciszeniu przygaszony.
struct HUDLevelBar: View {
    let reading: HUDReading

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.2))
                Capsule()
                    .fill(.white.opacity(reading.isMuted ? 0.35 : 1))
                    .frame(width: max(5, proxy.size.width * reading.clampedLevel))
            }
        }
        .frame(height: 5)
        .padding(.horizontal, 6)
        .frame(maxHeight: .infinity)
        .animation(.spring(response: 0.22, dampingFraction: 0.9), value: reading.level)
        .accessibilityElement()
        .accessibilityLabel(reading.kind.displayName)
        .accessibilityValue(reading.percentText)
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
