import Foundation
import IOKit.ps

/// Stan zasilania odczytany z IOKit Power Sources.
public struct PowerState: Equatable, Sendable {
    public let level: Int
    public let isPluggedIn: Bool
    public let isCharging: Bool
    public let isCharged: Bool
    /// Minuty do pełnego naładowania / do rozładowania; nil, gdy system jeszcze liczy.
    public let minutesToFull: Int?
    public let minutesToEmpty: Int?

    public init(level: Int, isPluggedIn: Bool, isCharging: Bool, isCharged: Bool,
                minutesToFull: Int? = nil, minutesToEmpty: Int? = nil) {
        self.level = level
        self.isPluggedIn = isPluggedIn
        self.isCharging = isCharging
        self.isCharged = isCharged
        self.minutesToFull = minutesToFull
        self.minutesToEmpty = minutesToEmpty
    }

    /// Opis źródła z `IOPSGetPowerSourceDescription`; nil dla źródeł bez baterii wewnętrznej.
    public static func from(description: [String: Any]) -> PowerState? {
        guard description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
              let current = description[kIOPSCurrentCapacityKey] as? Int
        else { return nil }
        let maximum = max(description[kIOPSMaxCapacityKey] as? Int ?? 100, 1)
        let level = Int((Double(current) / Double(maximum) * 100).rounded())
        return PowerState(
            level: min(max(level, 0), 100),
            isPluggedIn: description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue,
            isCharging: description[kIOPSIsChargingKey] as? Bool ?? false,
            isCharged: description[kIOPSIsChargedKey] as? Bool ?? false,
            minutesToFull: positive(description[kIOPSTimeToFullChargeKey]),
            minutesToEmpty: positive(description[kIOPSTimeToEmptyKey])
        )
    }

    /// IOKit zwraca -1, gdy czas jest jeszcze liczony.
    private static func positive(_ value: Any?) -> Int? {
        guard let minutes = value as? Int, minutes > 0 else { return nil }
        return minutes
    }

    /// Bieżący stan baterii wewnętrznej; nil na Macach bez baterii.
    public static func current() -> PowerState? {
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(info).takeRetainedValue() as [CFTypeRef]
        return sources.lazy
            .compactMap { IOPSGetPowerSourceDescription(info, $0)?.takeUnretainedValue() as? [String: Any] }
            .compactMap(from(description:))
            .first
    }
}

public enum PowerEvent: Equatable, Sendable {
    case pluggedIn
    case unplugged
    case charged
    case low(threshold: Int)
}

/// Zamienia kolejne stany w zdarzenia warte pokazania w wyspie.
public struct PowerEventDetector: Sendable {
    public static let lowThresholds = [20, 10]

    private var previous: PowerState?
    private var announcedThresholds: Set<Int> = []

    public init() {}

    public mutating func update(_ state: PowerState) -> PowerEvent? {
        defer { previous = state }
        guard let previous else {
            // Stan początkowy: nie ogłaszamy progów, poniżej których już jesteśmy.
            announcedThresholds = Set(Self.lowThresholds.filter { state.level <= $0 })
            return nil
        }
        if state.isPluggedIn != previous.isPluggedIn {
            if state.isPluggedIn { announcedThresholds = [] }
            return state.isPluggedIn ? .pluggedIn : .unplugged
        }
        if state.isPluggedIn {
            return state.isCharged && !previous.isCharged ? .charged : nil
        }
        // Najniższy nowo przekroczony próg.
        let crossed = Self.lowThresholds
            .filter { state.level <= $0 && !announcedThresholds.contains($0) }
            .min()
        guard let crossed else { return nil }
        announcedThresholds.formUnion(Self.lowThresholds.filter { $0 >= crossed })
        return .low(threshold: crossed)
    }
}

public enum DurationText {
    /// „45 min”, „1 godz.”, „2 godz. 5 min”.
    public static func format(minutes: Int) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        switch (hours, rest) {
        case (0, _): return "\(rest) min"
        case (_, 0): return "\(hours) godz."
        default: return "\(hours) godz. \(rest) min"
        }
    }
}

extension PowerState {
    /// Opis stanu do rozwiniętej wyspy.
    public var statusText: String {
        if isCharged || (isPluggedIn && level >= 100) { return "Naładowana" }
        if isCharging {
            return minutesToFull.map { "Ładowanie · pełna za \(DurationText.format(minutes: $0))" } ?? "Ładowanie"
        }
        if isPluggedIn { return "Podłączona, nie ładuje" }
        return minutesToEmpty.map { "Na baterii · zostało \(DurationText.format(minutes: $0))" } ?? "Na baterii"
    }

    public var symbol: String {
        if isCharging || isPluggedIn { return "battery.100percent.bolt" }
        switch level {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}
