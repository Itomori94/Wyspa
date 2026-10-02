import CoreLocation

/// Zgoda na lokalizację: systemowy dialog po `requestWhenInUseAuthorization`, odpowiedź w delegacie.
@MainActor
enum LocationAuthorization {
    static var status: PermissionStatus {
        switch CLLocationManager().authorizationStatus {
        case .authorizedAlways, .authorized: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    static func request() async -> PermissionStatus {
        guard status == .notDetermined else { return status }
        return await withCheckedContinuation { continuation in
            Requester.enqueue { continuation.resume(returning: $0) }
        }
    }

    @MainActor
    private final class Requester: NSObject, CLLocationManagerDelegate {
        /// Jedno żądanie naraz; kolejne prośby czekają na tę samą odpowiedź użytkownika (żadna nie zostaje bez wyniku).
        private static var active: Requester?

        private let manager = CLLocationManager()
        private var completions: [(PermissionStatus) -> Void] = []

        static func enqueue(_ completion: @escaping (PermissionStatus) -> Void) {
            if let active {
                active.completions.append(completion)
                return
            }
            let requester = Requester()
            requester.completions = [completion]
            active = requester
            requester.manager.delegate = requester
            requester.manager.requestWhenInUseAuthorization()
        }

        nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
            MainActor.assumeIsolated {
                // Pierwsze wywołanie przychodzi od razu z „nierozstrzygnięte”; czekamy na odpowiedź użytkownika.
                guard LocationAuthorization.status != .notDetermined else { return }
                Requester.active = nil
                let status = LocationAuthorization.status
                completions.forEach { $0(status) }
                completions = []
            }
        }
    }
}
