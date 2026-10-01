import Foundation

public enum MediaSourceKind: String, Codable, CaseIterable, Sendable {
    case adapter
    case appleScript

    public var displayName: String {
        switch self {
        case .adapter: "mediaremote-adapter (cały system)"
        case .appleScript: "AppleScript (Muzyka i Spotify)"
        }
    }
}

/// Wybór użytkownika w ustawieniach modułu.
public enum MediaSourcePreference: String, Codable, CaseIterable, Sendable {
    case automatic
    case adapter
    case appleScript

    public var displayName: String {
        switch self {
        case .automatic: "Automatycznie"
        case .adapter: "Tylko mediaremote-adapter"
        case .appleScript: "Tylko AppleScript"
        }
    }
}

public enum AdapterHealth: Equatable, Sendable {
    case functional
    case broken(reason: String)
}

public struct MediaSourceDecision: Equatable, Sendable {
    public let kind: MediaSourceKind
    /// Dlaczego wybrano to źródło; pokazywane w ustawieniach.
    public let reason: String
}

public enum MediaSourceSelector {
    public static func decide(preference: MediaSourcePreference, adapter: AdapterHealth) -> MediaSourceDecision {
        switch (preference, adapter) {
        case (.appleScript, _):
            return MediaSourceDecision(kind: .appleScript, reason: "Wybrane ręcznie w ustawieniach.")
        case (.adapter, .functional), (.automatic, .functional):
            return MediaSourceDecision(kind: .adapter, reason: "Adapter przeszedł test działania.")
        case (.adapter, .broken(let reason)):
            // Wymuszony adapter, mimo że test nie przeszedł: użytkownik widzi powód.
            return MediaSourceDecision(kind: .adapter, reason: "Wybrane ręcznie, ale test adaptera nie przeszedł: \(reason)")
        case (.automatic, .broken(let reason)):
            return MediaSourceDecision(kind: .appleScript, reason: "Tryb awaryjny: \(reason)")
        }
    }
}

/// Wykrywa adapter, który „milczy”: odtwarzacz zgłasza odtwarzanie, a adapter od dłuższego czasu nic nie zwraca.
public struct SilentAdapterDetector: Sendable {
    public static let defaultGracePeriod: TimeInterval = 4

    private let gracePeriod: TimeInterval
    private var playerReportedPlayingAt: Date?
    private var adapterHasData = false

    public init(gracePeriod: TimeInterval = SilentAdapterDetector.defaultGracePeriod) {
        self.gracePeriod = gracePeriod
    }

    /// Powiadomienie z Muzyki lub Spotify o stanie odtwarzania.
    public mutating func playerReported(isPlaying: Bool, at date: Date) {
        if isPlaying {
            playerReportedPlayingAt = playerReportedPlayingAt ?? date
        } else {
            playerReportedPlayingAt = nil
        }
    }

    public mutating func adapterReported(hasData: Bool) {
        adapterHasData = hasData
        if hasData { playerReportedPlayingAt = nil }
    }

    /// true, gdy odtwarzacz gra od `gracePeriod`, a adapter nadal nie ma danych.
    public func isSilent(at date: Date) -> Bool {
        guard !adapterHasData, let since = playerReportedPlayingAt else { return false }
        return date.timeIntervalSince(since) >= gracePeriod
    }
}
