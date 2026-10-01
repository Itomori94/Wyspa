import CoreGraphics
import WyspaCore

/// Jasność wbudowanego ekranu przez prywatny framework DisplayServices.
///
/// PRYWATNE API: `DisplayServicesGetBrightness` / `DisplayServicesSetBrightness`
/// z /System/Library/PrivateFrameworks/DisplayServices.framework. Może zniknąć w kolejnej wersji macOS;
/// wtedy `make()` zwraca nil, a klawisze jasności obsługuje system.
@MainActor
final class DisplayBrightnessControl {
    private typealias Getter = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias Setter = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private static let framework = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"

    private let getter: Getter
    private let setter: Setter
    private let display: CGDirectDisplayID

    private init(getter: Getter, setter: Setter, display: CGDirectDisplayID) {
        self.getter = getter
        self.setter = setter
        self.display = display
    }

    static func make() -> DisplayBrightnessControl? {
        guard let getter = PrivateSymbol.load("DisplayServicesGetBrightness", from: framework, as: Getter.self),
              let setter = PrivateSymbol.load("DisplayServicesSetBrightness", from: framework, as: Setter.self),
              let display = builtInDisplay()
        else { return nil }
        let control = DisplayBrightnessControl(getter: getter, setter: setter, display: display)
        // Sprawdzenie, że wywołanie faktycznie działa na tym Macu.
        return control.reading() == nil ? nil : control
    }

    func reading() -> HUDReading? {
        var value: Float = 0
        guard getter(display, &value) == 0 else { return nil }
        return HUDReading(kind: .brightness, level: value)
    }

    func set(level: Float) -> HUDReading? {
        guard setter(display, min(max(level, 0), 1)) == 0 else { return nil }
        return reading()
    }

    private static func builtInDisplay() -> CGDirectDisplayID? {
        var displays = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(UInt32(displays.count), &displays, &count) == .success else { return nil }
        return displays.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 }
    }
}
