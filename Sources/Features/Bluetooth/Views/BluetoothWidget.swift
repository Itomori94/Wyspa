import SwiftUI

/// Połączone urządzenia z poziomem baterii.
struct BluetoothWidget: View {
    let devices: [ConnectedDevice]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("BLUETOOTH").font(.system(size: 9.5, weight: .bold)).foregroundStyle(.white.opacity(0.45))
            if devices.isEmpty {
                Text("Brak urządzeń").font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.45))
            }
            ForEach(devices.prefix(3)) { device in
                HStack(spacing: 7) {
                    Image(systemName: device.kind.symbol).frame(width: 16)
                    Text(device.name).font(.system(size: 11.5, weight: .medium)).lineLimit(1)
                    Spacer(minLength: 2)
                    BatteryBadge(level: device.battery.summary)
                }
                .font(.system(size: 12))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
