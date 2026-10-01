import AppKit

/// Wysyłanie przez AirDrop (publiczne `NSSharingService`).
@MainActor
enum AirDrop {
    static var service: NSSharingService? { NSSharingService(named: .sendViaAirDrop) }

    static func canSend(_ urls: [URL]) -> Bool {
        !urls.isEmpty && (service?.canPerform(withItems: urls) ?? false)
    }

    /// Zwraca false, gdy AirDrop jest niedostępny (wyłączony Wi‑Fi/Bluetooth albo brak usługi).
    @discardableResult
    static func send(_ urls: [URL]) -> Bool {
        guard let service, canSend(urls) else { return false }
        // Okno wyboru odbiorcy należy do naszej aplikacji (agent), więc musi ona przejść na pierwszy plan.
        NSApp.activate()
        service.perform(withItems: urls)
        return true
    }
}
