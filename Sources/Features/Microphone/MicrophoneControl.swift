import CoreAudio
import Foundation
import WyspaCore

/// Wyciszanie wszystkich wejść przez CoreAudio (publiczne API, bez dostępu do dźwięku i bez zgody na mikrofon).
///
/// Wszystkie, bo Jabber, Zoom, Teams czy Discord mogą mieć wybrany inny mikrofon niż systemowy. Każde wejście dostaje
/// oba zabezpieczenia naraz: właściwość `Mute` i głośność wejścia 0 — programy z własnym przetwarzaniem głosu potrafią
/// pominąć samo „wycisz” (sprawdzone z wbudowanym mikrofonem MacBooka). Wyciszony = wszystkie wejścia wyciszone.
/// Zmiany (urządzenia, wyciszenie, głośność, także z Ustawień systemowych) przychodzą jako powiadomienia CoreAudio.
@MainActor
final class MicrophoneControl {
    struct Input: Equatable {
        let uid: String
        let name: String
        let isDefault: Bool
        let isMuted: Bool
        let canMute: Bool
    }

    struct Reading: Equatable {
        let inputs: [Input]

        var mutable: [Input] { inputs.filter(\.canMute) }
        /// Mikrofony bez wyciszania i bez głośności (np. iPhone przez Continuity) — nie da się ich wyciszyć.
        var unmutable: [Input] { inputs.filter { !$0.canMute } }
        var canMute: Bool { !mutable.isEmpty }
        /// Wyciszony dopiero wtedy, gdy wyciszone są wszystkie mikrofony, które da się wyciszyć.
        var isMuted: Bool { canMute && mutable.allSatisfy(\.isMuted) }
        var deviceUIDs: Set<String> { Set(mutable.map(\.uid)) }
        var defaultName: String { (inputs.first(where: \.isDefault) ?? inputs.first)?.name ?? "Mikrofon" }
    }

    struct MuteOutcome: Equatable {
        let succeeded: Bool
        /// Głośności sprzed wyciszenia do zapamiętania (UID → głośność).
        let volumesToRemember: [String: Float]
    }

    /// Co dane wejście pozwala zmienić.
    struct Controls: Equatable {
        let hasMute: Bool
        let volumeElements: [AudioObjectPropertyElement]

        var canMute: Bool { hasMute || !volumeElements.isEmpty }

        /// Z głośnością liczy się głośność (sama flaga „wycisz” bywa pomijana); bez niej — flaga.
        static func isMuted(mute: Bool?, volumes: [Float]) -> Bool {
            if !volumes.isEmpty { return volumes.allSatisfy { $0 < 0.001 } }
            return mute ?? false
        }
    }

    nonisolated static let fallbackVolume: Float = 0.75

    private let log = Log.logger("microphone")
    private let onChange: @MainActor () -> Void
    private let onDevicesChanged: @MainActor () -> Void
    private var systemListener: AudioObjectPropertyListenerBlock?
    private var deviceListener: AudioObjectPropertyListenerBlock?
    private var observed: [(AudioDeviceID, AudioObjectPropertyAddress)] = []

    init(onChange: @escaping @MainActor () -> Void, onDevicesChanged: @escaping @MainActor () -> Void = {}) {
        self.onChange = onChange
        self.onDevicesChanged = onDevicesChanged
    }

    func start() {
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.devicesChanged() }
        }
        for var address in [Self.systemAddress(kAudioHardwarePropertyDevices), Self.systemAddress(kAudioHardwarePropertyDefaultInputDevice)] {
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener)
        }
        systemListener = listener
        observeInputs()
    }

    func stop() {
        if let systemListener {
            for var address in [Self.systemAddress(kAudioHardwarePropertyDevices), Self.systemAddress(kAudioHardwarePropertyDefaultInputDevice)] {
                AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, systemListener)
            }
        }
        systemListener = nil
        removeDeviceListeners()
    }

    var reading: Reading? {
        let devices = inputDevices()
        guard !devices.isEmpty else { return nil }
        let defaultDevice = defaultInputDevice()
        return Reading(inputs: devices.map { device in
            let controls = Self.controls(of: device)
            return Input(uid: uid(of: device), name: Self.stringProperty(kAudioObjectPropertyName, of: device) ?? "Mikrofon",
                         isDefault: device == defaultDevice, isMuted: isMuted(device, controls), canMute: controls.canMute)
        })
    }

    /// Wycisza albo przywraca wszystkie wejścia. `restoreVolumes` = zapamiętane głośności sprzed wyciszenia (po UID).
    func setMuted(_ muted: Bool, restoreVolumes: [String: Float]) -> MuteOutcome {
        var remembered: [String: Float] = [:]
        var results: [Bool] = []
        for device in inputDevices() {
            let controls = Self.controls(of: device)
            guard controls.canMute else { continue }
            let id = uid(of: device)
            let (succeeded, remember) = apply(muted, to: device, controls: controls, restoreVolume: restoreVolumes[id])
            results.append(succeeded)
            if let remember { remembered[id] = remember }
        }
        return MuteOutcome(succeeded: !results.isEmpty && results.allSatisfy { $0 }, volumesToRemember: remembered)
    }

    /// Głośność po zdjęciu wyciszenia: zapamiętana, a bez niej (albo prawie zero) — 75%.
    nonisolated static func restoredVolume(_ remembered: Float?) -> Float {
        guard let remembered, remembered > 0.01 else { return fallbackVolume }
        return min(remembered, 1)
    }

    // MARK: - Ustawianie

    private func apply(_ muted: Bool, to device: AudioDeviceID, controls: Controls, restoreVolume: Float?) -> (Bool, Float?) {
        var succeeded = true
        if controls.hasMute {
            var value = UInt32(muted ? 1 : 0)
            var address = Self.inputAddress(kAudioDevicePropertyMute, element: kAudioObjectPropertyElementMain)
            let status = AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
            if status != noErr {
                succeeded = false
                log.error("Wyciszenie wejścia \(device) nie powiodło się: \(status)")
            }
        }
        guard !controls.volumeElements.isEmpty else { return (succeeded, nil) }
        let previous = controls.volumeElements.compactMap { volume(of: device, element: $0) }.max()
        // Włączenie podnosi głośność tylko wtedy, gdy to wyciszenie ją zgasiło — nie rusza głośności ustawionej ręcznie.
        if !muted, let previous, previous > 0.001 { return (succeeded, nil) }
        let target = muted ? Float32(0) : Float32(Self.restoredVolume(restoreVolume))
        for element in controls.volumeElements {
            var value = target
            var address = Self.inputAddress(kAudioDevicePropertyVolumeScalar, element: element)
            let status = AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
            if status != noErr {
                succeeded = false
                log.error("Głośność wejścia \(device) (element \(element)) nie ustawiona: \(status)")
            }
        }
        // Ponowne wyciszenie już wyciszonego wejścia nie nadpisuje zapamiętanej głośności zerem.
        let remember = muted ? previous.flatMap { $0 > 0.01 ? Float($0) : nil } : nil
        return (succeeded, remember)
    }

    // MARK: - Obserwacja

    private func devicesChanged() {
        observeInputs()
        onDevicesChanged()
        onChange()
    }

    /// Wyciszenie i głośność każdego wejścia — zmiana w dowolnym mikrofonie odświeża stan.
    private func observeInputs() {
        removeDeviceListeners()
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.onChange() }
        }
        for device in inputDevices() {
            let controls = Self.controls(of: device)
            var addresses = [Self.inputAddress(kAudioDevicePropertyMute, element: kAudioObjectPropertyElementMain)]
            addresses += controls.volumeElements.map { Self.inputAddress(kAudioDevicePropertyVolumeScalar, element: $0) }
            for var address in addresses where AudioObjectHasProperty(device, &address) {
                if AudioObjectAddPropertyListenerBlock(device, &address, .main, listener) == noErr {
                    observed.append((device, address))
                }
            }
        }
        deviceListener = listener
    }

    private func removeDeviceListeners() {
        if let deviceListener {
            for (device, address) in observed {
                var address = address
                AudioObjectRemovePropertyListenerBlock(device, &address, .main, deviceListener)
            }
        }
        observed = []
        deviceListener = nil
    }

    // MARK: - CoreAudio

    private static func systemAddress(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }

    private static func inputAddress(_ selector: AudioObjectPropertySelector, element: AudioObjectPropertyElement) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeInput, mElement: element)
    }

    private static func isSettable(_ device: AudioDeviceID, _ selector: AudioObjectPropertySelector, element: AudioObjectPropertyElement) -> Bool {
        var address = inputAddress(selector, element: element)
        var settable: DarwinBoolean = false
        return AudioObjectHasProperty(device, &address)
            && AudioObjectIsPropertySettable(device, &address, &settable) == noErr
            && settable.boolValue
    }

    static func controls(of device: AudioDeviceID) -> Controls {
        Controls(hasMute: isSettable(device, kAudioDevicePropertyMute, element: kAudioObjectPropertyElementMain),
                 volumeElements: volumeElements(of: device))
    }

    /// Głośność wejścia: element główny albo osobno kanały 1…n (część urządzeń ma tylko kanały).
    private static func volumeElements(of device: AudioDeviceID) -> [AudioObjectPropertyElement] {
        if isSettable(device, kAudioDevicePropertyVolumeScalar, element: kAudioObjectPropertyElementMain) {
            return [kAudioObjectPropertyElementMain]
        }
        let channels = inputChannelCount(device)
        guard channels > 0 else { return [] }
        return (1...channels).map { AudioObjectPropertyElement($0) }
            .filter { isSettable(device, kAudioDevicePropertyVolumeScalar, element: $0) }
    }

    private static func inputChannelCount(_ device: AudioDeviceID) -> Int {
        var address = inputAddress(kAudioDevicePropertyStreamConfiguration, element: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, raw) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return min(list.reduce(0) { $0 + Int($1.mNumberChannels) }, 16)
    }

    /// Wszystkie urządzenia z wejściem (wbudowany, USB, Bluetooth, iPhone, wirtualne).
    private func inputDevices() -> [AudioDeviceID] {
        var address = Self.systemAddress(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &devices) == noErr else { return [] }
        return devices.filter { Self.inputChannelCount($0) > 0 }
    }

    private func isMuted(_ device: AudioDeviceID, _ controls: Controls) -> Bool {
        var mute: Bool?
        if controls.hasMute {
            var address = Self.inputAddress(kAudioDevicePropertyMute, element: kAudioObjectPropertyElementMain)
            var value = UInt32(0)
            var size = UInt32(MemoryLayout<UInt32>.size)
            if AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr { mute = value != 0 }
        }
        let volumes = controls.volumeElements.compactMap { volume(of: device, element: $0) }.map { Float($0) }
        return Controls.isMuted(mute: mute, volumes: volumes)
    }

    private func volume(of device: AudioDeviceID, element: AudioObjectPropertyElement) -> Float32? {
        var address = Self.inputAddress(kAudioDevicePropertyVolumeScalar, element: element)
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    private func defaultInputDevice() -> AudioDeviceID? {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = Self.systemAddress(kAudioHardwarePropertyDefaultInputDevice)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return status == noErr && device != kAudioObjectUnknown ? device : nil
    }

    private func uid(of device: AudioDeviceID) -> String {
        Self.stringProperty(kAudioDevicePropertyDeviceUID, of: device) ?? "\(device)"
    }

    private static func stringProperty(_ selector: AudioObjectPropertySelector, of device: AudioDeviceID) -> String? {
        var address = systemAddress(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }
}
