import Foundation
import Testing
@testable import WyspaMedia

@Suite("Zakres dźwięku")
struct MediaScopeTests {
    private func track(_ bundle: String) -> NowPlaying {
        NowPlaying(bundleIdentifier: bundle, title: "t", isPlaying: true)
    }

    @Test("Cały system przepuszcza każdą aplikację")
    func system() {
        #expect(MediaScope.system.filter(track("com.spotify.client")) != nil)
        #expect(MediaScope.system.filter(track("com.apple.Safari")) != nil)
    }

    @Test("Tylko Apple Music odrzuca inne aplikacje")
    func appleMusic() {
        #expect(MediaScope.appleMusic.filter(track("com.apple.Music")) != nil)
        #expect(MediaScope.appleMusic.filter(track("com.spotify.client")) == nil)
        #expect(MediaScope.appleMusic.filter(track("com.apple.Safari")) == nil)
        #expect(MediaScope.appleMusic.filter(nil) == nil)
    }

    @Test("AppleScript odpytuje tylko odtwarzacze z zakresu")
    func scriptablePlayers() {
        #expect(MediaScope.appleMusic.scriptablePlayers == [.music])
        #expect(MediaScope.system.scriptablePlayers == ScriptablePlayer.allCases)
    }
}
