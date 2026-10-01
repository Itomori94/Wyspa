import Foundation

/// Poziomy baterii urządzenia Bluetooth (0–100); nil = urządzenie nie podaje tej wartości.
public struct BatteryLevels: Equatable, Sendable {
    public let single: Int?
    public let left: Int?
    public let right: Int?
    public let caseLevel: Int?
    public let combined: Int?

    public init(single: Int? = nil, left: Int? = nil, right: Int? = nil, caseLevel: Int? = nil, combined: Int? = nil) {
        self.single = Self.valid(single)
        self.left = Self.valid(left)
        self.right = Self.valid(right)
        self.caseLevel = Self.valid(caseLevel)
        self.combined = Self.valid(combined)
    }

    /// Urządzenia zgłaszają 0, gdy nie znają poziomu.
    private static func valid(_ value: Int?) -> Int? {
        guard let value, (1...100).contains(value) else { return nil }
        return value
    }

    /// Jeden poziom do skrzydła wyspy: słabsza słuchawka, inaczej to, co urządzenie podaje.
    public var summary: Int? {
        switch (left, right) {
        case let (l?, r?): min(l, r)
        default: single ?? combined ?? left ?? right
        }
    }

    public var isEmpty: Bool { summary == nil && caseLevel == nil }
}

public enum DeviceKind: Equatable, Sendable {
    case airPods, airPodsPro, airPodsMax, headphones, speaker, keyboard, mouse, trackpad, gamepad, other

    /// Klasa urządzenia z Bluetooth Core Spec: główna 0x04 = audio, 0x05 = urządzenie peryferyjne.
    public static func classify(name: String, majorClass: UInt32, minorClass: UInt32) -> DeviceKind {
        let lowered = name.lowercased()
        if lowered.contains("airpods max") { return .airPodsMax }
        if lowered.contains("airpods pro") { return .airPodsPro }
        if lowered.contains("airpods") { return .airPods }
        if lowered.contains("trackpad") { return .trackpad }
        if lowered.contains("mouse") || lowered.contains("mysz") { return .mouse }
        if lowered.contains("keyboard") || lowered.contains("klawiatura") { return .keyboard }
        if lowered.contains("controller") || lowered.contains("gamepad") { return .gamepad }

        switch majorClass {
        case 0x04:
            // Podklasy audio: 0x01 zestaw słuchawkowy, 0x02 zestaw głośnomówiący, 0x06 słuchawki, 0x05 głośnik.
            return minorClass == 0x05 ? .speaker : .headphones
        case 0x05:
            let pointing = minorClass & 0x20 != 0
            let keyboard = minorClass & 0x10 != 0
            if keyboard && !pointing { return .keyboard }
            if pointing { return .mouse }
            return minorClass & 0x0F == 0x02 ? .gamepad : .other
        default:
            return .other
        }
    }

    public var symbol: String {
        switch self {
        case .airPods: "airpods"
        case .airPodsPro: "airpodspro"
        case .airPodsMax: "airpodsmax"
        case .headphones: "headphones"
        case .speaker: "hifispeaker.fill"
        case .keyboard: "keyboard"
        case .mouse: "computermouse.fill"
        case .trackpad: "rectangle.and.hand.point.up.left.fill"
        case .gamepad: "gamecontroller.fill"
        case .other: "dot.radiowaves.left.and.right"
        }
    }
}

public struct ConnectedDevice: Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let kind: DeviceKind
    public let battery: BatteryLevels

    public init(id: String, name: String, kind: DeviceKind, battery: BatteryLevels) {
        self.id = id
        self.name = name
        self.kind = kind
        self.battery = battery
    }
}

public enum BluetoothEvent: Equatable, Sendable {
    case connected(ConnectedDevice)
    case disconnected(ConnectedDevice)
}
