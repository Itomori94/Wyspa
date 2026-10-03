import Foundation

/// Siła stuknięcia gładzika przy rozwinięciu wyspy.
public enum HapticStrength: String, CaseIterable, Codable, Sendable {
    /// Publiczne `NSHapticFeedbackManager` (`.levelChange`) — najdelikatniejsze, zawsze dostępne.
    case gentle
    /// Prywatne `MTActuatorActuate` (MultitouchSupport) — mocniejsze impulsy; bez niego wraca `gentle`.
    case medium
    case strong

    public var displayName: String {
        switch self {
        case .gentle: "Delikatna"
        case .medium: "Średnia"
        case .strong: "Mocna"
        }
    }

    /// Identyfikator impulsu silnika gładzika (`MTActuatorActuate`); nil = publiczne API.
    public var actuationID: Int32? {
        switch self {
        case .gentle: nil
        case .medium: 4
        case .strong: 6
        }
    }
}
