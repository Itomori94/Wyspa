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

    public static func pick(adapter: NowPlaying?, music: NowPlaying?, scope: MediaScope) -> (NowPlaying, Origin)? {
        let adapterInScope = scope.filter(adapter)
        if let adapterInScope, adapterInScope.isPlaying { return (adapterInScope, .adapter) }
        if let music, music.isPlaying { return (music, .music) }
        if let adapterInScope { return (adapterInScope, .adapter) }
        return music.map { ($0, .music) }
    }
}
