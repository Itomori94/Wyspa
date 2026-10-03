import AppKit
import IOKit
import WyspaCore

/// Stuknięcie gładzika przy rozwinięciu wyspy.
///
/// „Delikatna” to publiczne `NSHapticFeedbackManager`. Mocniejsze impulsy dają tylko prywatne funkcje
/// `MTActuator*` z MultitouchSupport (ładowane przez `dlopen`, bez linkowania). Gdy ich nie ma, nie da się otworzyć
/// silnika albo impuls się nie uda — wraca publiczne stuknięcie (rejestr prywatnych API w CLAUDE.md).
@MainActor
final class TrackpadHaptics {
    static let shared = TrackpadHaptics()

    private typealias CreateFn = @convention(c) (UInt64) -> Unmanaged<CFTypeRef>?
    private typealias OpenFn = @convention(c) (CFTypeRef) -> Int32
    private typealias ActuateFn = @convention(c) (CFTypeRef, Int32, UInt32, Float32, Float32) -> Int32

    private struct Functions {
        let create: CreateFn
        let open: OpenFn
        let actuate: ActuateFn
    }

    private let log = Log.logger("haptics")
    private lazy var functions: Functions? = Self.loadFunctions()
    /// Otwarte silniki wszystkich gładzików z haptyką (wbudowany, Magic Trackpad); tworzone przy pierwszym użyciu.
    private var actuators: [CFTypeRef]?

    func perform(_ strength: HapticStrength) {
        guard let id = strength.actuationID, actuate(id) else {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
            return
        }
    }

    private func actuate(_ id: Int32) -> Bool {
        guard let functions else { return false }
        if actuators == nil { actuators = openActuators(functions) }
        guard let actuators, !actuators.isEmpty else { return false }
        // Parametry jak w otwartych projektach używających tego API (np. HapticKey): 0, 0, 2.
        let succeeded = actuators.map { functions.actuate($0, id, 0, 0, 2) == 0 }.contains(true)
        if !succeeded {
            // Gładzik mógł zniknąć (odłączony Magic Trackpad) — następnym razem otworzymy od nowa.
            log.error("Impuls gładzika \(id) nie powiódł się")
            self.actuators = nil
        }
        return succeeded
    }

    private func openActuators(_ functions: Functions) -> [CFTypeRef] {
        Self.multitouchDeviceIDs().compactMap { deviceID in
            guard let actuator = functions.create(deviceID)?.takeRetainedValue() else { return nil }
            guard functions.open(actuator) == 0 else {
                log.error("Nie udało się otworzyć silnika gładzika \(deviceID)")
                return nil
            }
            return actuator
        }
    }

    private static func loadFunctions() -> Functions? {
        let path = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"
        guard let handle = dlopen(path, RTLD_LAZY),
              let create = dlsym(handle, "MTActuatorCreateFromDeviceID"),
              let open = dlsym(handle, "MTActuatorOpen"),
              let actuate = dlsym(handle, "MTActuatorActuate")
        else { return nil }
        return Functions(create: unsafeBitCast(create, to: CreateFn.self),
                         open: unsafeBitCast(open, to: OpenFn.self),
                         actuate: unsafeBitCast(actuate, to: ActuateFn.self))
    }

    /// Gładziki z haptyką w rejestrze IOKit (publiczne API): „Multitouch ID” przy `ActuationSupported`.
    private static func multitouchDeviceIDs() -> [UInt64] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleMultitouchDevice"), &iterator) == KERN_SUCCESS
        else { return [] }
        defer { IOObjectRelease(iterator) }
        var ids: [UInt64] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            let supported = IORegistryEntryCreateCFProperty(service, "ActuationSupported" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? Bool ?? false
            let id = IORegistryEntryCreateCFProperty(service, "Multitouch ID" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? NSNumber
            if supported, let id { ids.append(id.uint64Value) }
        }
        return ids
    }
}
