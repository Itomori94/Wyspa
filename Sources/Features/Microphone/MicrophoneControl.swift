import CoreAudio
import Foundation
import WyspaCore

/// Wyciszanie domyślnego wejścia przez CoreAudio (publiczne API, bez dostępu do dźwięku i bez zgody na mikrofon).
///
/// Najpierw właściwość `Mute` wejścia; urządzenia bez niej (np. część mikrofonów wbudowanych i USB) wycisza się,
/// ustawiając głośność wejścia na 0 i zapamiętując poprzednią. Zmiany (także z Ustawień systemowych i przełączenie
/// urządzenia) przychodzą jako powiadomienia CoreAudio — bez odpytywania.
@MainActor
final class MicrophoneControl {
    struct Reading: Equatable {
        let deviceUID: String
        let deviceName: String
        let isMuted: Bool
        let canMute: Bool
    }

    private let log = Log.logger("microphone")
    private let onChange: @MainActor () -> Void
    private var device: AudioDeviceID?
    private var systemListener: AudioObjectPropertyListenerBlock?
    private var deviceListener: AudioObjectPropertyListenerBlock?
    private var observedDeviceAddresses: [AudioObjectPropertyAddress] = []

    init(onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
    }

    func start() {
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.defaultDeviceChanged() }
        }
        var address = Self.defaultInputAddress
        if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener) == noErr {
            systemListener = listener
        }
        observe(defaultInputDevice())
    }

    func stop() {
        if let systemListener {
            var address = Self.defaultInputAddress
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, systemListener)
        }
        systemListener = nil
        observe(nil)
    }

    var reading: Reading? {
        guard let device else { return nil }
        let uid = stringProperty(kAudioDevicePropertyDeviceUID, of: device) ?? "\(device)"
        let name = stringProperty(kAudioObjectPropertyName, of: device) ?? "Mikrofon"
        let strategy = Self.strategy(for: device)
        return Reading(deviceUID: uid, deviceName: name, isMuted: isMuted(device, strategy: strategy), canMute: strategy != nil)
    }

    struct MuteOutcome: Equatable {
        let succeeded: Bool
        /// Głośność sprzed wyciszenia do zapamiętania (tylko tryb przez głośność, przy wyciszaniu).
        let volumeToRemember: Float?
    }

    /// Wycisza albo przywraca bieżące wejście. `restoreVolume` = zapamiętana głośność sprzed wyciszenia.
    func setMuted(_ muted: Bool, restoreVolume: Float?) -> MuteOutcome {
        guard let device, let strategy = Self.strategy(for: device) else {
            return MuteOutcome(succeeded: false, volumeToRemember: nil)
        }
        switch strategy {
        case .muteProperty:
            var value = UInt32(muted ? 1 : 0)
            var address = Self.inputAddress(kAudioDevicePropertyMute, element: kAudioObjectPropertyElementMain)
            let status = AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
            if status != noErr { log.error("Wyciszenie wejścia nie powiodło się: \(status)") }
            return MuteOutcome(succeeded: status == noErr, volumeToRemember: nil)
        case .volume(let elements):
            let previous = elements.compactMap { volume(of: device, element: $0) }.max()
            let target = muted ? 0 : Float32(Self.restoredVolume(restoreVolume))
            var succeeded = true
            for element in elements {
                var value = target
                var address = Self.inputAddress(kAudioDevicePropertyVolumeScalar, element: element)
                let status = AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
                if status != noErr {
                    succeeded = false
                    log.error("Głośność wejścia (element \(element)) nie ustawiona: \(status)")
                }
            }
            // Ponowne wyciszenie już wyciszonego wejścia nie nadpisuje zapamiętanej głośności zerem.
            let remember = muted ? previous.flatMap { $0 > 0.01 ? Float($0) : nil } : nil
            return MuteOutcome(succeeded: succeeded, volumeToRemember: remember)
        }
    }

    /// Głośność po zdjęciu wyciszenia: zapamiętana, a bez niej (albo prawie zero) — 75%.
    nonisolated static func restoredVolume(_ remembered: Float?) -> Float {
        guard let remembered, remembered > 0.01 else { return fallbackVolume }
        return min(remembered, 1)
    }

    // MARK: - Obserwacja urządzenia

    private func defaultDeviceChanged() {
        observe(defaultInputDevice())
        onChange()
    }

    private func observe(_ newDevice: AudioDeviceID?) {
        if let device, let deviceListener {
            for var address in observedDeviceAddresses {
                AudioObjectRemovePropertyListenerBlock(device, &address, .main, deviceListener)
            }
        }
        deviceListener = nil
        observedDeviceAddresses = []
        device = newDevice
        guard let newDevice else { return }
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.onChange() }
        }
        var addresses = [Self.inputAddress(kAudioDevicePropertyMute, element: kAudioObjectPropertyElementMain)]
        addresses += Self.volumeElements(of: newDevice).map { Self.inputAddress(kAudioDevicePropertyVolumeScalar, element: $0) }
        for var address in addresses {
            guard AudioObjectHasProperty(newDevice, &address) else { continue }
            if AudioObjectAddPropertyListenerBlock(newDevice, &address, .main, listener) == noErr {
                observedDeviceAddresses.append(address)
            }
        }
        deviceListener = listener
    }

    // MARK: - CoreAudio

    enum Strategy: Equatable {
        case muteProperty
        case volume(elements: [AudioObjectPropertyElement])
    }

    nonisolated static let fallbackVolume: Float = 0.75

    private static var defaultInputAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                   mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
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

    static func strategy(for device: AudioDeviceID) -> Strategy? {
        if isSettable(device, kAudioDevicePropertyMute, element: kAudioObjectPropertyElementMain) { return .muteProperty }
        let elements = volumeElements(of: device)
        return elements.isEmpty ? nil : .volume(elements: elements)
    }

    /// Głośność wejścia: element główny albo osobno kanały 1…n (część urządzeń ma tylko kanały).
    private static func volumeElements(of device: AudioDeviceID) -> [AudioObjectPropertyElement] {
        if isSettable(device, kAudioDevicePropertyVolumeScalar, element: kAudioObjectPropertyElementMain) {
            return [kAudioObjectPropertyElementMain]
        }
        return (1...max(inputChannelCount(device), 1)).map { AudioObjectPropertyElement($0) }
            .filter { isSettable(device, kAudioDevicePropertyVolumeScalar, element: $0) }
    }

    private static func inputChannelCount(_ device: AudioDeviceID) -> Int {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration,
                                                 mScope: kAudioDevicePropertyScopeInput,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, raw) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return min(list.reduce(0) { $0 + Int($1.mNumberChannels) }, 16)
    }

    private func isMuted(_ device: AudioDeviceID, strategy: Strategy?) -> Bool {
        switch strategy {
        case .muteProperty:
            var address = Self.inputAddress(kAudioDevicePropertyMute, element: kAudioObjectPropertyElementMain)
            var value = UInt32(0)
            var size = UInt32(MemoryLayout<UInt32>.size)
            return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr && value != 0
        case .volume(let elements):
            let volumes = elements.compactMap { volume(of: device, element: $0) }
            return !volumes.isEmpty && volumes.allSatisfy { $0 < 0.001 }
        case nil:
            return false
        }
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
        var address = Self.defaultInputAddress
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return status == noErr && device != kAudioObjectUnknown ? device : nil
    }

    private func stringProperty(_ selector: AudioObjectPropertySelector, of device: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }
}
