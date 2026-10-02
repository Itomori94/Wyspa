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
            Requester.start { continuation.resume(returning: $0) }
        }
    }

    @MainActor
    private final class Requester: NSObject, CLLocationManagerDelegate {
        /// Trzyma żądanie przy życiu do czasu odpowiedzi użytkownika.
        private static var active: Requester?

        private let manager = CLLocationManager()
        private let completion: (PermissionStatus) -> Void

        private init(completion: @escaping (PermissionStatus) -> Void) {
            self.completion = completion
        }

        static func start(completion: @escaping (PermissionStatus) -> Void) {
            let requester = Requester(completion: completion)
            active = requester
            requester.manager.delegate = requester
            requester.manager.requestWhenInUseAuthorization()
        }

        nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
            MainActor.assumeIsolated {
                // Pierwsze wywołanie przychodzi od razu z „nierozstrzygnięte”; czekamy na odpowiedź użytkownika.
                guard LocationAuthorization.status != .notDetermined else { return }
                Requester.active = nil
                completion(LocationAuthorization.status)
            }
        }
    }
}
