import Testing
@testable import WyspaMedia

@Suite("Łączenie adaptera z Muzyką (AirPlay)")
struct NowPlayingMergeTests {
    let safariPaused = NowPlaying(bundleIdentifier: "com.apple.WebKit.GPU", title: "Film", isPlaying: false)
    let safariPlaying = NowPlaying(bundleIdentifier: "com.apple.WebKit.GPU", title: "Film", isPlaying: true)
    let musicAirPlay = NowPlaying(bundleIdentifier: "com.apple.Music", title: "Savages", isPlaying: true)
    let musicPaused = NowPlaying(bundleIdentifier: "com.apple.Music", title: "Savages", isPlaying: false)

    @Test("Muzyka przez AirPlay: adapter zgłasza wstrzymane Safari, pokazujemy Muzykę (oba zakresy)")
    func airPlay() {
        for scope in MediaScope.allCases {
            let picked = NowPlayingMerge.pick(adapter: safariPaused, music: musicAirPlay, scope: scope)
            #expect(picked?.0 == musicAirPlay && picked?.1 == .music)
        }
    }

    @Test("Grający adapter wygrywa w całym systemie; w trybie Apple Music liczy się tylko Muzyka")
    func adapterPlaying() {
        #expect(NowPlayingMerge.pick(adapter: safariPlaying, music: musicAirPlay, scope: .system)?.1 == .adapter)
        #expect(NowPlayingMerge.pick(adapter: safariPlaying, music: musicAirPlay, scope: .appleMusic)?.1 == .music)
        #expect(NowPlayingMerge.pick(adapter: safariPlaying, music: nil, scope: .appleMusic) == nil)
    }

    @Test("Nic nie gra: wstrzymane z adaptera przed wstrzymaną Muzyką")
    func nothingPlaying() {
        #expect(NowPlayingMerge.pick(adapter: safariPaused, music: musicPaused, scope: .system)?.1 == .adapter)
        #expect(NowPlayingMerge.pick(adapter: nil, music: musicPaused, scope: .system)?.1 == .music)
        #expect(NowPlayingMerge.pick(adapter: nil, music: nil, scope: .system) == nil)
    }
}
