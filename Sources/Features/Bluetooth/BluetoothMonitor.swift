import Foundation
import IOBluetooth
import WyspaCore

/// Powiadomienia IOBluetooth o połączeniu i rozłączeniu urządzeń (bez odpytywania).
///
/// PRYWATNE API: poziomy baterii z selektorów `batteryPercentSingle/Left/Right/Case/Combined`
/// klasy `IOBluetoothDevice`. Każdy selektor jest sprawdzany przez `responds(to:)`; brak = brak poziomu.
@MainActor
final class BluetoothMonitor: NSObject {
    private let onChange: @MainActor (BluetoothEvent?) -> Void
    private var connectNotification: IOBluetoothUserNotification?
    private var disconnectNotifications: [String: IOBluetoothUserNotification] = [:]
    private(set) var devices: [String: IOBluetoothDevice] = [:]

    init(onChange: @escaping @MainActor (BluetoothEvent?) -> Void) {
        self.onChange = onChange
    }

    func start() {
        for device in (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []) where device.isConnected() {
            track(device)
        }
        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self, selector: #selector(deviceConnected(_:device:))
        )
        onChange(nil)
    }

    func stop() {
        connectNotification?.unregister()
        connectNotification = nil
        disconnectNotifications.values.forEach { $0.unregister() }
        disconnectNotifications = [:]
        devices = [:]
    }

    func snapshot(of device: IOBluetoothDevice) -> ConnectedDevice {
        let name = device.name ?? device.addressString ?? "Urządzenie Bluetooth"
        return ConnectedDevice(
            id: device.addressString ?? name,
            name: name,
            kind: DeviceKind.classify(name: name, majorClass: device.deviceClassMajor, minorClass: device.deviceClassMinor),
            battery: Self.battery(of: device)
        )
    }

    @objc private func deviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        track(device)
        onChange(.connected(snapshot(of: device)))
    }

    @objc private func deviceDisconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        let id = device.addressString ?? ""
        let snapshot = snapshot(of: device)
        notification.unregister()
        disconnectNotifications[id] = nil
        devices[id] = nil
        onChange(.disconnected(snapshot))
    }

    private func track(_ device: IOBluetoothDevice) {
        guard let id = device.addressString, devices[id] == nil else { return }
        devices[id] = device
        disconnectNotifications[id] = device.register(
            forDisconnectNotification: self, selector: #selector(deviceDisconnected(_:device:))
        )
    }

    private static func battery(of device: IOBluetoothDevice) -> BatteryLevels {
        BatteryLevels(
            single: percent(device, "batteryPercentSingle"),
            left: percent(device, "batteryPercentLeft"),
            right: percent(device, "batteryPercentRight"),
            caseLevel: percent(device, "batteryPercentCase"),
            combined: percent(device, "batteryPercentCombined")
        )
    }

    private static func percent(_ device: IOBluetoothDevice, _ key: String) -> Int? {
        // Bez tej kontroli `value(forKey:)` rzuciłby wyjątek Objective-C przy braku selektora.
        guard device.responds(to: NSSelectorFromString(key)) else { return nil }
        return (device.value(forKey: key) as? NSNumber)?.intValue
    }
}
