import Foundation

/// Z jakich aplikacji wyspa pokazuje odtwarzanie (wybór użytkownika, niezależny od źródła danych).
public enum MediaScope: String, Codable, CaseIterable, Sendable {
    case system
    case appleMusic

    public var displayName: String {
        switch self {
        case .system: "Cały system"
        case .appleMusic: "Tylko Apple Music"
        }
    }

    /// Odtwarzanie z innej aplikacji niż dozwolona jest traktowane jak „nic nie gra”.
    public func filter(_ nowPlaying: NowPlaying?) -> NowPlaying? {
        guard let nowPlaying else { return nil }
        switch self {
        case .system: return nowPlaying
        case .appleMusic: return nowPlaying.bundleIdentifier == ScriptablePlayer.music.rawValue ? nowPlaying : nil
        }
    }

    /// Odtwarzacze odpytywane w trybie AppleScript.
    public var scriptablePlayers: [ScriptablePlayer] {
        switch self {
        case .system: ScriptablePlayer.allCases
        case .appleMusic: [.music]
        }
    }
}
