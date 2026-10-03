import Foundation

/// Łączy dane z adaptera MediaRemote z danymi aplikacji Muzyka (AppleScript).
///
/// Gdy Muzyka gra przez AirPlay (np. na Apple TV), MediaRemote zgłasza jako „teraz odtwarzane” inną aplikację
/// (np. wstrzymane wideo w Safari), a Muzyki wcale — wtedy dane bierzemy z samej Muzyki.
public enum NowPlayingMerge {
    public enum Origin: Equatable, Sendable {
        case adapter
        case music
    }

    /// Krótszy dźwięk to nie utwór (dźwięk powiadomienia z Facebooka, Messengera, przeglądarki).
    public static let minimumMediaDuration: TimeInterval = 20

    /// Czy grające z adaptera wygląda na prawdziwe odtwarzanie (utwór, film), a nie na dźwięk powiadomienia:
    /// ma tytuł, znaną długość co najmniej 20 s i jeszcze się nie skończyło. Taki dźwięk przejmuje „teraz odtwarzane”
    /// w systemie i zostaje „grający”, choć Muzyka gra dalej — wtedy wyspa nie wracała do Muzyki.
    public static func looksLikeMedia(_ item: NowPlaying, at now: Date) -> Bool {
        guard !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let duration = item.duration, duration >= minimumMediaDuration
        else { return false }
        guard let elapsedTime = item.elapsedTime, let timestamp = item.timestamp else { return true }
        let position = elapsedTime + max(0, now.timeIntervalSince(timestamp)) * item.playbackRate
        return position < duration
    }

    public static func pick(adapter: NowPlaying?, music: NowPlaying?, scope: MediaScope, now: Date = Date()) -> (NowPlaying, Origin)? {
        let adapterInScope = scope.filter(adapter)
        if let adapterInScope, adapterInScope.isPlaying {
            // Grająca Muzyka nie ustępuje dźwiękowi powiadomienia z innej aplikacji.
            let isOtherSound = adapterInScope.bundleIdentifier != ScriptablePlayer.music.rawValue
                && !looksLikeMedia(adapterInScope, at: now)
            if isOtherSound, let music, music.isPlaying { return (music, .music) }
            return (adapterInScope, .adapter)
        }
        if let music, music.isPlaying { return (music, .music) }
        if let adapterInScope { return (adapterInScope, .adapter) }
        return music.map { ($0, .music) }
    }
}
