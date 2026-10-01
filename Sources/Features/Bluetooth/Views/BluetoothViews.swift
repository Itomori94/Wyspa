import SwiftUI

struct BatteryBadge: View {
    let level: Int?

    var body: some View {
        if let level {
            Text("\(level)%")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(level <= 20 ? .orange : .white)
        } else {
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.green)
        }
    }
}

struct BluetoothExpandedView: View {
    let devices: [ConnectedDevice]

    var body: some View {
        if devices.isEmpty {
            Label("Brak połączonych urządzeń Bluetooth.", systemImage: "dot.radiowaves.left.and.right")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(devices) { DeviceCard(device: $0) }
                }
            }
            .frame(maxHeight: .infinity)
        }
    }
}

private struct DeviceCard: View {
    let device: ConnectedDevice

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: device.kind.symbol)
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 24)
                Text(device.name)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
            }
            if device.battery.isEmpty {
                Text("Poziom baterii niedostępny")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.45))
            } else {
                HStack(spacing: 10) {
                    if let left = device.battery.left { LevelGauge(label: "L", level: left) }
                    if let right = device.battery.right { LevelGauge(label: "P", level: right) }
                    if device.battery.left == nil, device.battery.right == nil, let level = device.battery.summary {
                        LevelGauge(label: nil, level: level)
                    }
                    if let caseLevel = device.battery.caseLevel { LevelGauge(label: "Etui", level: caseLevel) }
                }
            }
        }
        .padding(12)
        .frame(width: 170, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.07)))
    }
}

private struct LevelGauge: View {
    let label: String?
    let level: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 3) {
                if let label { Text(label).foregroundStyle(.white.opacity(0.5)) }
                Text("\(level)%").monospacedDigit()
            }
            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
            Capsule()
                .fill(.white.opacity(0.15))
                .frame(width: 34, height: 4)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(level <= 20 ? Color.orange : Color.green)
                        .frame(width: 34 * CGFloat(level) / 100, height: 4)
                }
        }
        .accessibilityElement()
        .accessibilityLabel(label.map { "Bateria \($0)" } ?? "Bateria")
        .accessibilityValue("\(level) procent")
    }
}
