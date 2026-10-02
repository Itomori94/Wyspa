import AppKit
import ApplicationServices
import AVFoundation
import CoreLocation
import CoreBluetooth
import EventKit

@MainActor
public final class PermissionCenter: PermissionProviding {
    private let log = Log.logger("permissions")

    public init() {}

    public func status(of permission: Permission) -> PermissionStatus {
        switch permission {
        case .accessibility:
            return AXIsProcessTrusted() ? .granted : .notDetermined
        case .calendars:
            return Self.map(EKEventStore.authorizationStatus(for: .event))
        case .reminders:
            return Self.map(EKEventStore.authorizationStatus(for: .reminder))
        case .camera:
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: return .granted
            case .notDetermined: return .notDetermined
            default: return .denied
            }
        case .bluetooth:
            switch CBManager.authorization {
            case .allowedAlways: return .granted
            case .notDetermined: return .notDetermined
            default: return .denied
            }
        case .location:
            return LocationAuthorization.status
        }
    }

    public func request(_ permission: Permission) async -> PermissionStatus {
        do {
            switch permission {
            case .accessibility:
                // System pokazuje własny dialog i odsyła do Ustawień; zgoda nadawana jest poza aplikacją.
                let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
                return AXIsProcessTrustedWithOptions(options) ? .granted : .denied
            case .calendars:
                return try await EKEventStore().requestFullAccessToEvents() ? .granted : .denied
            case .reminders:
                return try await EKEventStore().requestFullAccessToReminders() ? .granted : .denied
            case .camera:
                return await AVCaptureDevice.requestAccess(for: .video) ? .granted : .denied
            case .bluetooth:
                return await BluetoothAuthorization.request()
            case .location:
                return await LocationAuthorization.request()
            }
        } catch {
            log.error("Prośba o uprawnienie \(permission.rawValue) nie powiodła się: \(error.localizedDescription)")
            return .denied
        }
    }

    public func openSystemSettings(for permission: Permission) {
        let anchor = switch permission {
        case .accessibility: "Privacy_Accessibility"
        case .calendars: "Privacy_Calendars"
        case .reminders: "Privacy_Reminders"
        case .camera: "Privacy_Camera"
        case .bluetooth: "Privacy_Bluetooth"
        case .location: "Privacy_LocationServices"
        }
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else { return }
        NSWorkspace.shared.open(url)
    }

    private static func map(_ status: EKAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .fullAccess, .authorized: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
    }
}
