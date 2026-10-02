import Foundation

/// Ostrzeżenia o słabej baterii: raz na rozładowanie, ponownie dopiero po naładowaniu powyżej progu powrotu.
public struct LowBatteryTracker: Equatable, Sendable {
    public static let threshold = 20
    /// Histereza: ostrzeżenie wraca dopiero po naładowaniu do tego poziomu (bez migania przy 19–21%).
    public static let rearmLevel = 30

    /// Urządzenia, przed którymi już ostrzegliśmy w tym rozładowaniu.
    public let warned: Set<String>

    public init(warned: Set<String> = []) {
        self.warned = warned
    }

    /// Nowy stan i urządzenia, przed którymi trzeba teraz ostrzec.
    public func evaluating(_ devices: [ConnectedDevice]) -> (tracker: LowBatteryTracker, alerts: [ConnectedDevice]) {
        var warned = warned.intersection(devices.map(\.id))
        var alerts: [ConnectedDevice] = []
        for device in devices {
            guard let level = device.battery.summary else { continue }
            if level >= Self.rearmLevel {
                warned.remove(device.id)
            } else if level <= Self.threshold, !warned.contains(device.id) {
                warned.insert(device.id)
                alerts.append(device)
            }
        }
        return (LowBatteryTracker(warned: warned), alerts)
    }
}
