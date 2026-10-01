import ServiceManagement
import WyspaCore

/// Start przy logowaniu przez `SMAppService.mainApp` (publiczne API od macOS 13).
@MainActor
enum LaunchAtLogin {
    private static let log = Log.logger("launch-at-login")

    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static var requiresApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    /// Zwraca komunikat błędu dla użytkownika albo nil przy powodzeniu.
    static func set(_ enabled: Bool) -> String? {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            log.error("Zmiana startu przy logowaniu nie powiodła się: \(error.localizedDescription)")
            return "Nie udało się zmienić ustawienia: \(error.localizedDescription)"
        }
    }

    static func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
