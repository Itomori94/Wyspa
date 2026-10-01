import AudioToolbox
import CoreAudio
import WyspaCore

/// Głośność i wyciszenie domyślnego wyjścia przez CoreAudio (publiczne API).
///
/// Urządzenia bez sterowania głośnością (np. HDMI, część interfejsów USB) zwracają `canControl == false`,
/// a klawisze wracają wtedy do systemu.
@MainActor
final class VolumeControl {
    private let log = Log.logger("hud.volume")

    var canControl: Bool {
        guard let device = defaultOutputDevice() else { return false }
        var address = Self.volumeAddress
        var settable: DarwinBoolean = false
        return AudioObjectHasProperty(device, &address)
            && AudioObjectIsPropertySettable(device, &address, &settable) == noErr
            && settable.boolValue
    }

    func reading() -> HUDReading? {
        guard let device = defaultOutputDevice(), let volume = volume(of: device) else { return nil }
        return HUDReading(kind: .volume, level: volume, isMuted: isMuted(device) ?? false)
    }

    /// Ustawia głośność; ruch w górę zdejmuje wyciszenie, zejście do zera wycisza (jak macOS).
    func set(level: Float) -> HUDReading? {
        guard let device = defaultOutputDevice() else { return nil }
        var value = Float32(min(max(level, 0), 1))
        var address = Self.volumeAddress
        let status = AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
        guard status == noErr else {
            log.error("Ustawienie głośności nie powiodło się: \(status)")
            return nil
        }
        _ = setMuted(device, value <= 0)
        return reading()
    }

    func toggleMute() -> HUDReading? {
        guard let device = defaultOutputDevice(), let muted = isMuted(device) else { return nil }
        guard setMuted(device, !muted) else { return nil }
        return reading()
    }

    // MARK: - CoreAudio

    private static var volumeAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static var muteAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private func defaultOutputDevice() -> AudioDeviceID? {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return status == noErr && device != kAudioObjectUnknown ? device : nil
    }

    private func volume(of device: AudioDeviceID) -> Float? {
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        var address = Self.volumeAddress
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    private func isMuted(_ device: AudioDeviceID) -> Bool? {
        var address = Self.muteAddress
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr ? value != 0 : nil
    }

    private func setMuted(_ device: AudioDeviceID, _ muted: Bool) -> Bool {
        var address = Self.muteAddress
        guard AudioObjectHasProperty(device, &address) else { return false }
        var value = UInt32(muted ? 1 : 0)
        return AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value) == noErr
    }
}
