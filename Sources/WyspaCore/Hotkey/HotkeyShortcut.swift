import Carbon.HIToolbox

public struct ShortcutModifiers: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let control = ShortcutModifiers(rawValue: 1 << 0)
    public static let option = ShortcutModifiers(rawValue: 1 << 1)
    public static let shift = ShortcutModifiers(rawValue: 1 << 2)
    public static let command = ShortcutModifiers(rawValue: 1 << 3)

    /// Kolejność symboli zgodna z konwencją macOS.
    public var symbols: String {
        var result = ""
        if contains(.control) { result += "⌃" }
        if contains(.option) { result += "⌥" }
        if contains(.shift) { result += "⇧" }
        if contains(.command) { result += "⌘" }
        return result
    }

    public var carbonFlags: UInt32 {
        var flags = 0
        if contains(.control) { flags |= controlKey }
        if contains(.option) { flags |= optionKey }
        if contains(.shift) { flags |= shiftKey }
        if contains(.command) { flags |= cmdKey }
        return UInt32(flags)
    }

    /// Skrót globalny musi zawierać ⌃, ⌥ albo ⌘, inaczej zablokowałby zwykłe pisanie.
    public var isValidForGlobalShortcut: Bool {
        !intersection([.control, .option, .command]).isEmpty
    }
}

public struct HotkeyShortcut: Codable, Hashable, Sendable {
    public static let defaultToggle = HotkeyShortcut(keyCode: UInt32(kVK_ANSI_W), modifiers: [.control, .option], keyName: "W")

    public let keyCode: UInt32
    public let modifiers: ShortcutModifiers
    /// Nazwa klawisza zapisana w chwili nagrania (zależy od układu klawiatury).
    public let keyName: String

    public init(keyCode: UInt32, modifiers: ShortcutModifiers, keyName: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyName = keyName
    }

    public var displayString: String { modifiers.symbols + keyName }
}
