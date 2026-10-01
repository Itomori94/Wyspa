import SwiftUI

struct HUDIcon: View {
    let reading: HUDReading

    var body: some View {
        Image(systemName: reading.symbol, variableValue: Double(reading.level))
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .contentTransition(.symbolEffect(.replace))
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 6)
            .accessibilityLabel(reading.kind.displayName)
    }
}

/// Cienki pasek poziomu; przy wyciszeniu przygaszony.
struct HUDLevelBar: View {
    let reading: HUDReading

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.2))
                Capsule()
                    .fill(.white.opacity(reading.isMuted ? 0.35 : 1))
                    .frame(width: max(5, proxy.size.width * CGFloat(reading.level)))
            }
        }
        .frame(height: 5)
        .padding(.leading, 6)
        .padding(.trailing, 4)
        .animation(.spring(response: 0.22, dampingFraction: 0.9), value: reading.level)
        .accessibilityElement()
        .accessibilityLabel(reading.kind.displayName)
        .accessibilityValue("\(Int((reading.level * 100).rounded())) procent")
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
