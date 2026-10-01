import Foundation

/// Odtwarzacze obsługiwane w trybie awaryjnym AppleScript.
public enum ScriptablePlayer: String, CaseIterable, Sendable {
    case music = "com.apple.Music"
    case spotify = "com.spotify.client"

    public var applicationName: String {
        switch self {
        case .music: "Music"
        case .spotify: "Spotify"
        }
    }

    /// Powiadomienie rozproszone wysyłane przy każdej zmianie odtwarzania (bez odpytywania).
    public var changeNotification: Notification.Name {
        switch self {
        case .music: Notification.Name("com.apple.Music.playerInfo")
        case .spotify: Notification.Name("com.spotify.client.PlaybackStateChanged")
        }
    }

    /// Spotify podaje długość w milisekundach, Muzyka w sekundach.
    var durationDivisor: Double {
        switch self {
        case .music: 1
        case .spotify: 1000
        }
    }
}

/// Parsuje wynik skryptu statusu: pola rozdzielone `AppleScriptParser.separator`.
///
/// Kolejność: stan, tytuł, wykonawca, album, długość, pozycja, URL okładki (tylko Spotify).
public enum AppleScriptParser {
    public static let separator = "\u{1F}"

    public struct Status: Equatable, Sendable {
        public let nowPlaying: NowPlaying
        public let artworkURL: URL?
    }

    public static func parse(_ output: String, player: ScriptablePlayer, now: Date) -> Status? {
        let fields = output
            .trimmingCharacters(in: .newlines)
            .components(separatedBy: separator)
        guard fields.count >= 6 else { return nil }
        let state = fields[0]
        guard state == "playing" || state == "paused", !fields[1].isEmpty else { return nil }

        let isPlaying = state == "playing"
        let nowPlaying = NowPlaying(
            bundleIdentifier: player.rawValue,
            title: fields[1],
            artist: fields[2].isEmpty ? nil : fields[2],
            album: fields[3].isEmpty ? nil : fields[3],
            duration: number(fields[4]).map { $0 / player.durationDivisor },
            elapsedTime: number(fields[5]),
            timestamp: now,
            playbackRate: isPlaying ? 1 : 0,
            isPlaying: isPlaying
        )
        let artworkURL = fields.count > 6 ? URL(string: fields[6]).flatMap { $0.scheme == "https" ? $0 : nil } : nil
        return Status(nowPlaying: nowPlaying, artworkURL: artworkURL)
    }

    /// AppleScript formatuje liczby według ustawień regionu (np. „215,5”).
    static func number(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
    }

    /// Skrypt statusu. Uruchamiany tylko, gdy odtwarzacz już działa (inaczej `tell` by go uruchomił).
    public static func statusScript(for player: ScriptablePlayer) -> String {
        let artwork = player == .spotify ? "artwork url of current track" : "\"\""
        return """
        tell application "\(player.applicationName)"
            set s to player state as string
            if s is not "playing" and s is not "paused" then return s
            set t to current track
            set sep to (ASCII character 31)
            return s & sep & (name of t) & sep & (artist of t) & sep & (album of t) & sep & ((duration of t) as string) & sep & ((player position) as string) & sep & \(artwork)
        end tell
        """
    }

    public static func commandScript(_ command: MediaCommand, for player: ScriptablePlayer) -> String {
        let verb = switch command {
        case .togglePlayPause: "playpause"
        case .next: "next track"
        case .previous: "previous track"
        }
        return "tell application \"\(player.applicationName)\" to \(verb)"
    }

    public static func seekScript(to seconds: TimeInterval, for player: ScriptablePlayer) -> String {
        "tell application \"\(player.applicationName)\" to set player position to \(String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), seconds))"
    }

    /// Okładka z Muzyki jako surowe dane obrazu.
    public static let musicArtworkScript = """
    tell application "Music"
        if (count of artworks of current track) is 0 then return missing value
        return raw data of artwork 1 of current track
    end tell
    """
}
