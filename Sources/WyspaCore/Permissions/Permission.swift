import Foundation

public enum Permission: String, Hashable, Sendable, CaseIterable {
    case accessibility
    case calendars
    case reminders
    case camera
    case bluetooth

    public var displayName: String {
        switch self {
        case .accessibility: "Dostępność"
        case .calendars: "Kalendarze"
        case .reminders: "Przypomnienia"
        case .camera: "Kamera"
        case .bluetooth: "Bluetooth"
        }
    }
}

public enum PermissionStatus: Equatable, Sendable {
    case granted
    case denied
    case notDetermined
}

/// Źródło stanu uprawnień. W testach podmieniane na atrapę.
@MainActor
public protocol PermissionProviding: AnyObject {
    func status(of permission: Permission) -> PermissionStatus
    /// Prosi system o uprawnienie (pokazuje dialog) i zwraca stan po odpowiedzi użytkownika.
    func request(_ permission: Permission) async -> PermissionStatus
}
