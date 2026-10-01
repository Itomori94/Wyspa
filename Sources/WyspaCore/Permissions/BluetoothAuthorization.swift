import CoreBluetooth

/// Systemowy dialog zgody na Bluetooth pojawia się przy utworzeniu `CBCentralManager`.
@MainActor
enum BluetoothAuthorization {
    static func request() async -> PermissionStatus {
        await withCheckedContinuation { continuation in
            Requester.start { continuation.resume(returning: $0) }
        }
    }

    @MainActor
    private final class Requester: NSObject, CBCentralManagerDelegate {
        /// Trzyma żądanie przy życiu do czasu odpowiedzi użytkownika.
        private static var active: Requester?

        private var manager: CBCentralManager?
        private let completion: (PermissionStatus) -> Void

        private init(completion: @escaping (PermissionStatus) -> Void) {
            self.completion = completion
        }

        static func start(completion: @escaping (PermissionStatus) -> Void) {
            let requester = Requester(completion: completion)
            active = requester
            requester.manager = CBCentralManager(delegate: requester, queue: .main)
        }

        nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
            MainActor.assumeIsolated {
                // Przed odpowiedzią użytkownika autoryzacja jest nierozstrzygnięta; czekamy dalej.
                guard CBManager.authorization != .notDetermined else { return }
                manager = nil
                Requester.active = nil
                completion(CBManager.authorization == .allowedAlways ? .granted : .denied)
            }
        }
    }
}
