import Foundation
import Testing
@testable import WyspaMedia

@Suite("Szacowanie pozycji odtwarzania")
struct NowPlayingTests {
    let start = Date(timeIntervalSince1970: 1000)

    private func track(playing: Bool, rate: Double = 1, elapsed: TimeInterval? = 10, duration: TimeInterval? = 100) -> NowPlaying {
        NowPlaying(bundleIdentifier: "b", title: "t", duration: duration, elapsedTime: elapsed,
                   timestamp: start, playbackRate: rate, isPlaying: playing)
    }

    @Test("Podczas odtwarzania pozycja rośnie z upływem czasu")
    func advances() {
        #expect(track(playing: true).elapsed(at: start.addingTimeInterval(5)) == 15)
    }

    @Test("Prędkość odtwarzania jest uwzględniana")
    func rate() {
        #expect(track(playing: true, rate: 2).elapsed(at: start.addingTimeInterval(5)) == 20)
    }

    @Test("Pauza zatrzymuje pozycję")
    func paused() {
        #expect(track(playing: false).elapsed(at: start.addingTimeInterval(50)) == 10)
    }

    @Test("Pozycja nie przekracza długości utworu i nie jest ujemna")
    func clamps() {
        #expect(track(playing: true).elapsed(at: start.addingTimeInterval(500)) == 100)
        #expect(track(playing: false, elapsed: -3).elapsed(at: start) == 0)
    }

    @Test("Brak pozycji w źródle daje nil")
    func noElapsed() {
        #expect(track(playing: true, elapsed: nil).elapsed(at: start) == nil)
    }

    @Test("Ten sam utwór mimo innej okładki")
    func sameTrack() {
        let a = track(playing: true)
        #expect(a.isSameTrack(as: a.with(artwork: Data([1]))))
        #expect(!a.isSameTrack(as: nil))
    }

    @Test("Identyfikatory poleceń adaptera zgodne z tabelą MRCommand")
    func commandIDs() {
        #expect(MediaCommand.togglePlayPause.adapterID == 2)
        #expect(MediaCommand.next.adapterID == 4)
        #expect(MediaCommand.previous.adapterID == 5)
    }
}
