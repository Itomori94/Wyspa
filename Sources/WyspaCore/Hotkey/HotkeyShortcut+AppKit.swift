import AppKit
import Carbon.HIToolbox

extension ShortcutModifiers {
    public init(_ flags: NSEvent.ModifierFlags) {
        var result: ShortcutModifiers = []
        if flags.contains(.control) { result.insert(.control) }
        if flags.contains(.option) { result.insert(.option) }
        if flags.contains(.shift) { result.insert(.shift) }
        if flags.contains(.command) { result.insert(.command) }
        self = result
    }
}

extension HotkeyShortcut {
    private static let specialKeyNames: [Int: String] = [
        kVK_Space: "Spacja", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫",
        kVK_Escape: "⎋", kVK_LeftArrow: "←", kVK_RightArrow: "→",
        kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]

    /// Tworzy skrót z naciśnięcia klawisza; nil, gdy brakuje modyfikatora wymaganego dla skrótu globalnego.
    public init?(event: NSEvent) {
        let modifiers = ShortcutModifiers(event.modifierFlags)
        guard event.type == .keyDown, modifiers.isValidForGlobalShortcut else { return nil }
        let code = Int(event.keyCode)
        let name = Self.specialKeyNames[code]
            ?? event.charactersIgnoringModifiers?.uppercased().nilIfEmpty
            ?? "#\(code)"
        self.init(keyCode: UInt32(code), modifiers: modifiers, keyName: name)
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
