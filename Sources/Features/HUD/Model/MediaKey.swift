import Foundation

/// Klawisze specjalne z rodziny `NX_KEYTYPE_*` (zdarzenia `NX_SYSDEFINED`, podtyp 8).
public enum MediaKey: Int, Sendable {
    case volumeUp = 0
    case volumeDown = 1
    case brightnessUp = 2
    case brightnessDown = 3
    case mute = 7
    case keyboardBacklightUp = 21
    case keyboardBacklightDown = 22
    case keyboardBacklightToggle = 23
}

public struct MediaKeyEvent: Equatable, Sendable {
    /// Podtyp `NX_SUBTYPE_AUX_CONTROL_BUTTONS` w zdarzeniu systemowym.
    public static let auxControlSubtype: Int16 = 8
    static let keyDownState = 0x0A
    static let keyUpState = 0x0B

    public let key: MediaKey
    public let isDown: Bool
    public let isRepeat: Bool

    public init(key: MediaKey, isDown: Bool, isRepeat: Bool) {
        self.key = key
        self.isDown = isDown
        self.isRepeat = isRepeat
    }

    /// `data1`: bity 16–31 kod klawisza, 8–15 stan (0x0A wciśnięty, 0x0B puszczony), bit 0 powtórzenie.
    public static func decode(subtype: Int16, data1: Int) -> MediaKeyEvent? {
        guard subtype == auxControlSubtype else { return nil }
        let code = (data1 & 0xFFFF_0000) >> 16
        let state = (data1 & 0xFF00) >> 8
        guard let key = MediaKey(rawValue: code), state == keyDownState || state == keyUpState else { return nil }
        return MediaKeyEvent(key: key, isDown: state == keyDownState, isRepeat: data1 & 0x1 == 1)
    }
}
