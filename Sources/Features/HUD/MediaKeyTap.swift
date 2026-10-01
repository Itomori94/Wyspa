import AppKit
import WyspaCore

public enum MediaKeyTapError: LocalizedError {
    case notTrusted
    case tapUnavailable

    public var errorDescription: String? {
        switch self {
        case .notTrusted:
            "Wyspa nie ma uprawnienia Dostępność. Włącz ją w Ustawieniach systemowych → Prywatność i ochrona → Dostępność."
        case .tapUnavailable:
            "System nie pozwolił przechwytywać klawiszy (CGEventTap). Sprawdź uprawnienie Dostępność."
        }
    }
}

/// Przechwytuje klawisze multimedialne przez `CGEventTap` na zdarzeniach `NX_SYSDEFINED`.
///
/// Wymaga uprawnienia Dostępność. Obsłużone zdarzenia są pochłaniane, więc system nie pokazuje własnego HUD.
@MainActor
final class MediaKeyTap {
    /// `NX_SYSDEFINED` — w Swift brak nazwanego przypadku `CGEventType`.
    private static let systemDefinedType: UInt32 = 14

    /// Zwraca true, gdy zdarzenie zostało obsłużone i ma być pochłonięte.
    private let handler: (MediaKeyEvent, HUDKeyRouter.Modifiers) -> Bool
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private let log = Log.logger("hud.tap")

    init(handler: @escaping (MediaKeyEvent, HUDKeyRouter.Modifiers) -> Bool) {
        self.handler = handler
    }

    func start() throws(MediaKeyTapError) {
        guard AXIsProcessTrusted() else { throw .notTrusted }
        let mask = CGEventMask(1) << CGEventMask(Self.systemDefinedType)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: mediaKeyTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { throw .tapUnavailable }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
    }

    fileprivate func reenable(after type: CGEventType) {
        // System wyłącza zbyt wolny tap; włączamy go z powrotem.
        log.error("Tap klawiszy został wyłączony przez system (\(type.rawValue)), włączam ponownie")
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
    }

    fileprivate func handle(_ event: MediaKeyEvent, modifiers: HUDKeyRouter.Modifiers) -> Bool {
        handler(event, modifiers)
    }

}

/// Callback C tapu; tap jest podpięty do głównej pętli, więc działa na głównym wątku.
/// Zdarzenie jest dekodowane tutaj, a do głównego aktora trafiają tylko wartości `Sendable`.
private func mediaKeyTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    let passThrough = Unmanaged.passUnretained(event)
    guard let userInfo else { return passThrough }
    let tap = Unmanaged<MediaKeyTap>.fromOpaque(userInfo).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        MainActor.assumeIsolated { tap.reenable(after: type) }
        return passThrough
    }
    guard type.rawValue == 14, // NX_SYSDEFINED
          let nsEvent = NSEvent(cgEvent: event),
          let mediaKey = MediaKeyEvent.decode(subtype: nsEvent.subtype.rawValue, data1: nsEvent.data1)
    else { return passThrough }

    var modifiers: HUDKeyRouter.Modifiers = []
    if nsEvent.modifierFlags.contains(.option) { modifiers.insert(.option) }
    if nsEvent.modifierFlags.contains(.shift) { modifiers.insert(.shift) }
    let consume = MainActor.assumeIsolated { tap.handle(mediaKey, modifiers: modifiers) }
    return consume ? nil : passThrough
}
