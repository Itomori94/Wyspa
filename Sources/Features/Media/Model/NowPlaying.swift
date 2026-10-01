import Foundation

/// Stan odtwarzania niezależny od źródła danych (adapter MediaRemote albo AppleScript).
public struct NowPlaying: Equatable, Sendable {
    public let bundleIdentifier: String
    public let title: String
    public let artist: String?
    public let album: String?
    public let duration: TimeInterval?
    /// Pozycja odtwarzania w chwili `timestamp`.
    public let elapsedTime: TimeInterval?
    public let timestamp: Date?
    public let playbackRate: Double
    public let isPlaying: Bool
    public let artwork: Data?

    public init(
        bundleIdentifier: String,
        title: String,
        artist: String? = nil,
        album: String? = nil,
        duration: TimeInterval? = nil,
        elapsedTime: TimeInterval? = nil,
        timestamp: Date? = nil,
        playbackRate: Double = 1,
        isPlaying: Bool,
        artwork: Data? = nil
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.elapsedTime = elapsedTime
        self.timestamp = timestamp
        self.playbackRate = playbackRate
        self.isPlaying = isPlaying
        self.artwork = artwork
    }

    /// Szacowana pozycja w chwili `now`, bez odpytywania źródła: elapsed + upływ czasu × prędkość.
    public func elapsed(at now: Date) -> TimeInterval? {
        guard let elapsedTime else { return nil }
        guard isPlaying, let timestamp else { return clamp(elapsedTime) }
        let advanced = elapsedTime + max(0, now.timeIntervalSince(timestamp)) * playbackRate
        return clamp(advanced)
    }

    /// Ta sama pozycja utworu, inne metadane (np. okładka dociągnięta później).
    public func isSameTrack(as other: NowPlaying?) -> Bool {
        guard let other else { return false }
        return bundleIdentifier == other.bundleIdentifier && title == other.title
            && artist == other.artist && album == other.album
    }

    public func with(artwork: Data?) -> NowPlaying {
        NowPlaying(
            bundleIdentifier: bundleIdentifier, title: title, artist: artist, album: album,
            duration: duration, elapsedTime: elapsedTime, timestamp: timestamp,
            playbackRate: playbackRate, isPlaying: isPlaying, artwork: artwork
        )
    }

    private func clamp(_ value: TimeInterval) -> TimeInterval {
        let lower = max(0, value)
        guard let duration, duration > 0 else { return lower }
        return min(lower, duration)
    }
}

public enum MediaCommand: Sendable, Equatable {
    case togglePlayPause
    case next
    case previous

    /// Identyfikator polecenia `send` w mediaremote-adapter (tabela MRCommand).
    var adapterID: Int {
        switch self {
        case .togglePlayPause: 2
        case .next: 4
        case .previous: 5
        }
    }
}
