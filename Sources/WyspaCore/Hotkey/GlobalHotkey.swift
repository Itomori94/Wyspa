import Carbon.HIToolbox

public enum GlobalHotkeyError: Error, Equatable {
    case handlerInstallFailed(OSStatus)
    case registrationFailed(OSStatus)

    public var message: String {
        switch self {
        case .handlerInstallFailed(let status):
            "Nie udało się zainstalować obsługi skrótu (kod \(status))."
        case .registrationFailed(let status):
            status == OSStatus(eventHotKeyExistsErr)
                ? "Ten skrót jest już zajęty przez inną aplikację."
                : "Nie udało się zarejestrować skrótu (kod \(status))."
        }
    }
}

/// Globalny skrót przez Carbon `RegisterEventHotKey` (publiczne API, bez uprawnienia Accessibility).
@MainActor
public final class GlobalHotkey {
    private static let signature: OSType = 0x5759_5350 // "WYSP"

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: @MainActor () -> Void

    public init(action: @escaping @MainActor () -> Void) {
        self.action = action
    }

    public func register(_ shortcut: HotkeyShortcut) throws(GlobalHotkeyError) {
        unregister()
        try installHandlerIfNeeded()
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(
            shortcut.keyCode, shortcut.modifiers.carbonFlags, id,
            GetApplicationEventTarget(), 0, &ref
        )
        guard status == noErr else { throw .registrationFailed(status) }
        hotKeyRef = ref
    }

    public func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRef = nil
    }

    private func installHandlerIfNeeded() throws(GlobalHotkeyError) {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            let hotkey = Unmanaged<GlobalHotkey>.fromOpaque(userData).takeUnretainedValue()
            // Carbon dostarcza zdarzenia skrótów na głównym wątku.
            MainActor.assumeIsolated { hotkey.action() }
            return noErr
        }, 1, &spec, context, &handlerRef)
        guard status == noErr else { throw .handlerInstallFailed(status) }
    }
}
