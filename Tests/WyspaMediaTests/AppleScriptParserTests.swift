import Foundation
import Testing
@testable import WyspaMedia

@Suite("Parser AppleScript")
struct AppleScriptParserTests {
    let now = Date(timeIntervalSince1970: 500)
    let sep = AppleScriptParser.separator

    @Test("Spotify: długość w milisekundach, okładka https")
    func spotify() throws {
        let output = ["playing", "Tytuł", "Artysta", "Album", "215000", "12,5", "https://i.scdn.co/image/abc"].joined(separator: sep)
        let status = try #require(AppleScriptParser.parse(output, player: .spotify, now: now))
        #expect(status.nowPlaying.duration == 215)
        #expect(status.nowPlaying.elapsedTime == 12.5)
        #expect(status.nowPlaying.isPlaying)
        #expect(status.nowPlaying.bundleIdentifier == "com.spotify.client")
        #expect(status.artworkURL?.host == "i.scdn.co")
    }

    @Test("Muzyka: długość w sekundach, pauza, puste pola jako nil")
    func music() throws {
        let output = ["paused", "Tytuł", "", "", "180.5", "3", ""].joined(separator: sep)
        let status = try #require(AppleScriptParser.parse(output, player: .music, now: now))
        #expect(status.nowPlaying.duration == 180.5)
        #expect(status.nowPlaying.isPlaying == false)
        #expect(status.nowPlaying.artist == nil && status.nowPlaying.album == nil)
        #expect(status.artworkURL == nil)
    }

    @Test("Zatrzymany odtwarzacz albo za mało pól daje nil")
    func invalid() {
        #expect(AppleScriptParser.parse("stopped", player: .music, now: now) == nil)
        #expect(AppleScriptParser.parse(["playing", "x"].joined(separator: sep), player: .music, now: now) == nil)
        #expect(AppleScriptParser.parse(["playing", "", "", "", "1", "1"].joined(separator: sep), player: .music, now: now) == nil)
    }

    @Test("Okładka spoza https jest odrzucana")
    func insecureArtwork() throws {
        let output = ["playing", "T", "A", "B", "1000", "0", "http://example.com/a.jpg"].joined(separator: sep)
        #expect(try #require(AppleScriptParser.parse(output, player: .spotify, now: now)).artworkURL == nil)
    }

    @Test("Przewijanie formatuje liczbę z kropką niezależnie od regionu")
    func seekScript() {
        #expect(AppleScriptParser.seekScript(to: 42.5, for: .music).hasSuffix("to 42.50"))
    }

    @Test("Polecenia celują we właściwą aplikację")
    func commands() {
        #expect(AppleScriptParser.commandScript(.next, for: .spotify) == #"tell application "Spotify" to next track"#)
        #expect(AppleScriptParser.commandScript(.togglePlayPause, for: .music) == #"tell application "Music" to playpause"#)
    }
}
