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
    private static var nextID: UInt32 = 1

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: @MainActor () -> Void
    /// Każdy skrót ma własny identyfikator: obsługa reaguje tylko na swój (przy kilku skrótach naraz).
    private let hotkeyID: UInt32

    public init(action: @escaping @MainActor () -> Void) {
        self.action = action
        hotkeyID = Self.nextID
        Self.nextID += 1
    }

    isolated deinit {
        unregister()
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }

    public func register(_ shortcut: HotkeyShortcut) throws(GlobalHotkeyError) {
        unregister()
        try installHandlerIfNeeded()
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: Self.signature, id: hotkeyID)
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
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let userData, let event else { return OSStatus(eventNotHandledErr) }
            var pressed = EventHotKeyID()
            let read = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                         nil, MemoryLayout<EventHotKeyID>.size, nil, &pressed)
            let hotkey = Unmanaged<GlobalHotkey>.fromOpaque(userData).takeUnretainedValue()
            // Carbon dostarcza zdarzenia skrótów na głównym wątku. Cudzy skrót przekazujemy dalej.
            return MainActor.assumeIsolated {
                guard read == noErr, pressed.signature == GlobalHotkey.signature, pressed.id == hotkey.hotkeyID else {
                    return OSStatus(eventNotHandledErr)
                }
                hotkey.action()
                return noErr
            }
        }, 1, &spec, context, &handlerRef)
        guard status == noErr else { throw .handlerInstallFailed(status) }
    }
}
