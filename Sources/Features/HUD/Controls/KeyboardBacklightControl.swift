import Foundation
import WyspaCore

/// Podświetlenie klawiatury przez prywatną klasę `KeyboardBrightnessClient` z CoreBrightness.
///
/// PRYWATNE API: metody `copyKeyboardBacklightIDs`, `brightnessForKeyboard:`, `setBrightness:forKeyboard:`.
/// Każda jest sprawdzana przez `responds(to:)`; gdy którejś brak, `make()` zwraca nil i klawisze obsługuje system.
@MainActor
final class KeyboardBacklightControl {
    private typealias Getter = @convention(c) (AnyObject, Selector, UInt64) -> Float
    private typealias Setter = @convention(c) (AnyObject, Selector, Float, UInt64) -> Bool
    private static let framework = "/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness"

    private let client: NSObject
    private let keyboardID: UInt64
    private let getter: Getter
    private let setter: Setter
    private var levelBeforeToggle: Float = 0.5

    private init(client: NSObject, keyboardID: UInt64, getter: Getter, setter: Setter) {
        self.client = client
        self.keyboardID = keyboardID
        self.getter = getter
        self.setter = setter
    }

    static func make() -> KeyboardBacklightControl? {
        guard dlopen(framework, RTLD_NOW | RTLD_LOCAL) != nil,
              let type = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type
        else { return nil }
        let client = type.init()
        let idsSelector = NSSelectorFromString("copyKeyboardBacklightIDs")
        let getSelector = NSSelectorFromString("brightnessForKeyboard:")
        let setSelector = NSSelectorFromString("setBrightness:forKeyboard:")
        guard [idsSelector, getSelector, setSelector].allSatisfy(client.responds(to:)),
              let ids = client.perform(idsSelector)?.takeRetainedValue() as? [NSNumber],
              let first = ids.first
        else { return nil }
        return KeyboardBacklightControl(
            client: client,
            keyboardID: first.uint64Value,
            getter: unsafeBitCast(client.method(for: getSelector), to: Getter.self),
            setter: unsafeBitCast(client.method(for: setSelector), to: Setter.self)
        )
    }

    func reading() -> HUDReading {
        HUDReading(kind: .keyboard, level: getter(client, NSSelectorFromString("brightnessForKeyboard:"), keyboardID))
    }

    func set(level: Float) -> HUDReading? {
        let ok = setter(client, NSSelectorFromString("setBrightness:forKeyboard:"), min(max(level, 0), 1), keyboardID)
        return ok ? reading() : nil
    }

    /// Wyłącza podświetlenie i przy kolejnym naciśnięciu przywraca poprzedni poziom.
    func toggle() -> HUDReading? {
        let current = reading().level
        if current > 0 {
            levelBeforeToggle = current
            return set(level: 0)
        }
        return set(level: levelBeforeToggle)
    }
}
