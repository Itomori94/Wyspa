import CoreGraphics
import Foundation

public enum HUDKind: String, Codable, CaseIterable, Sendable {
    case volume
    case brightness
    case keyboard

    public var displayName: String {
        switch self {
        case .volume: "Głośność"
        case .brightness: "Jasność ekranu"
        case .keyboard: "Podświetlenie klawiatury"
        }
    }
}

public struct HUDReading: Equatable, Sendable {
    public let kind: HUDKind
    public let level: Float
    public let isMuted: Bool

    public init(kind: HUDKind, level: Float, isMuted: Bool = false) {
        self.kind = kind
        self.level = level
        self.isMuted = isMuted
    }

    /// Poziom przycięty do 0…1 (szerokość wypełnienia paska).
    public var clampedLevel: CGFloat { CGFloat(min(max(level, 0), 1)) }

    public var percentText: String { "\(Int((clampedLevel * 100).rounded()))%" }

    /// Symbol SF z wartością zmienną (wypełnienie fal/promieni zależy od poziomu).
    public var symbol: String {
        switch kind {
        case .volume: isMuted || level <= 0 ? "speaker.slash.fill" : "speaker.wave.3.fill"
        case .brightness: "sun.max.fill"
        case .keyboard: level <= 0 ? "light.min" : "light.max"
        }
    }
}

public enum StepSize: Sendable {
    /// 1/16 skali, jak systemowe klawisze.
    case normal
    /// 1/64 skali, z ⇧⌥ jak w macOS.
    case fine

    var fraction: Float {
        switch self {
        case .normal: 1 / 16
        case .fine: 1 / 64
        }
    }
}

public enum LevelStepper {
    /// Następny poziom na siatce kroków (jak w macOS: 0,30 + krok w górę = 0,3125, nie 0,3625).
    public static func step(_ level: Float, up: Bool, size: StepSize) -> Float {
        let step = size.fraction
        let position = level / step
        let tolerance: Float = 0.001
        let next = up ? (position + tolerance).rounded(.down) + 1 : (position - tolerance).rounded(.up) - 1
        return min(max(next * step, 0), 1)
    }
}

public enum HUDAction: Equatable, Sendable {
    /// Przepuść zdarzenie do systemu (pokaże własny HUD).
    case passThrough
    /// Pochłoń bez akcji (puszczenie klawisza obsłużonego przy wciśnięciu).
    case swallow
    case adjust(HUDKind, up: Bool, size: StepSize)
    case toggleMute
    case toggleKeyboardBacklight
}

/// Które rodzaje HUD są włączone i możliwe (sterowanie dostępne na tym Macu).
public struct HUDCapabilities: Equatable, Sendable {
    public var volume: Bool
    public var brightness: Bool
    public var keyboard: Bool

    public init(volume: Bool, brightness: Bool, keyboard: Bool) {
        self.volume = volume
        self.brightness = brightness
        self.keyboard = keyboard
    }

    func allows(_ kind: HUDKind) -> Bool {
        switch kind {
        case .volume: volume
        case .brightness: brightness
        case .keyboard: keyboard
        }
    }
}

public enum HUDKeyRouter {
    public struct Modifiers: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let option = Modifiers(rawValue: 1 << 0)
        public static let shift = Modifiers(rawValue: 1 << 1)
    }

    public static func route(_ event: MediaKeyEvent, modifiers: Modifiers, capabilities: HUDCapabilities) -> HUDAction {
        // Sam ⌥ z klawiszem multimedialnym otwiera ustawienia systemowe — zostawiamy to systemowi.
        if modifiers.contains(.option) && !modifiers.contains(.shift) { return .passThrough }
        guard let kind = kind(of: event.key), capabilities.allows(kind) else { return .passThrough }
        guard event.isDown else { return .swallow }
        let size: StepSize = modifiers.contains([.option, .shift]) ? .fine : .normal

        switch event.key {
        case .volumeUp: return .adjust(.volume, up: true, size: size)
        case .volumeDown: return .adjust(.volume, up: false, size: size)
        case .mute: return event.isRepeat ? .swallow : .toggleMute
        case .brightnessUp: return .adjust(.brightness, up: true, size: size)
        case .brightnessDown: return .adjust(.brightness, up: false, size: size)
        case .keyboardBacklightUp: return .adjust(.keyboard, up: true, size: size)
        case .keyboardBacklightDown: return .adjust(.keyboard, up: false, size: size)
        case .keyboardBacklightToggle: return event.isRepeat ? .swallow : .toggleKeyboardBacklight
        }
    }

    static func kind(of key: MediaKey) -> HUDKind? {
        switch key {
        case .volumeUp, .volumeDown, .mute: .volume
        case .brightnessUp, .brightnessDown: .brightness
        case .keyboardBacklightUp, .keyboardBacklightDown, .keyboardBacklightToggle: .keyboard
        }
    }
}
