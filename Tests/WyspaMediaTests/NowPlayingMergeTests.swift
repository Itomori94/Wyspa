import Foundation
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

@Suite("Wybór źródła mediów i wykrywanie milczącego adaptera")
struct MediaSourceSelectionEdgeTests {
    @Test("Każda kombinacja preferencji i stanu adaptera")
    func decisions() {
        let broken = AdapterHealth.broken(reason: "brak Perla")
        #expect(MediaSourceSelector.decide(preference: .appleScript, adapter: .functional).kind == .appleScript)
        #expect(MediaSourceSelector.decide(preference: .automatic, adapter: .functional).kind == .adapter)
        #expect(MediaSourceSelector.decide(preference: .adapter, adapter: broken).kind == .adapter)
        let fallback = MediaSourceSelector.decide(preference: .automatic, adapter: broken)
        #expect(fallback.kind == .appleScript && fallback.reason.contains("brak Perla"))
        #expect(MediaSourcePreference.allCases.allSatisfy { !$0.displayName.isEmpty })
        #expect(MediaSourceKind.allCases.allSatisfy { !$0.displayName.isEmpty })
    }

    @Test("Adapter milczy dopiero po okresie karencji; dane albo pauza kasują alarm")
    func silence() {
        let start = Date(timeIntervalSince1970: 0)
        var detector = SilentAdapterDetector(gracePeriod: 4)
        detector.playerReported(isPlaying: true, at: start)
        #expect(!detector.isSilent(at: start.addingTimeInterval(3)))
        #expect(detector.isSilent(at: start.addingTimeInterval(4)))
        detector.adapterReported(hasData: true)
        #expect(!detector.isSilent(at: start.addingTimeInterval(10)))
        detector.adapterReported(hasData: false)
        detector.playerReported(isPlaying: true, at: start.addingTimeInterval(10))
        detector.playerReported(isPlaying: false, at: start.addingTimeInterval(11))
        #expect(!detector.isSilent(at: start.addingTimeInterval(20)))
    }
}
