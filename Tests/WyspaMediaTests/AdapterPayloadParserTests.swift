import Foundation
import Testing
@testable import WyspaMedia

@Suite("Parser strumienia mediaremote-adapter")
struct AdapterPayloadParserTests {
    private func line(_ json: String) -> Data { Data(json.utf8) }

    @Test("Pełny payload z mikrosekundami i okładką")
    func fullPayload() throws {
        let artwork = Data([0xFF, 0xD8, 0xFF]).base64EncodedString()
        let json = """
        {"type":"data","diff":false,"payload":{"bundleIdentifier":"com.spotify.client","playing":true,\
        "title":"Utwór","artist":"Wykonawca","album":"Album","durationMicros":215000000,\
        "elapsedTimeMicros":30500000,"timestampEpochMicros":1790000000000000,"playbackRate":1,\
        "artworkData":"\(artwork)","artworkMimeType":"image/jpeg"}}
        """
        guard case .nowPlaying(let np) = try AdapterPayloadParser.parse(line: line(json)) else {
            Issue.record("oczekiwano .nowPlaying")
            return
        }
        #expect(np.bundleIdentifier == "com.spotify.client")
        #expect(np.title == "Utwór" && np.artist == "Wykonawca" && np.album == "Album")
        #expect(np.duration == 215 && np.elapsedTime == 30.5)
        #expect(np.timestamp == Date(timeIntervalSince1970: 1_790_000_000))
        #expect(np.isPlaying)
        #expect(np.artwork == Data([0xFF, 0xD8, 0xFF]))
    }

    @Test("Przeglądarka: identyfikator aplikacji nadrzędnej ma pierwszeństwo")
    func parentBundle() throws {
        let json = """
        {"type":"data","diff":false,"payload":{"bundleIdentifier":"com.apple.WebKit.GPU",\
        "parentApplicationBundleIdentifier":"com.apple.Safari","playing":false,"title":"Film"}}
        """
        guard case .nowPlaying(let np) = try AdapterPayloadParser.parse(line: line(json)) else {
            Issue.record("oczekiwano .nowPlaying")
            return
        }
        #expect(np.bundleIdentifier == "com.apple.Safari")
        #expect(np.isPlaying == false && np.playbackRate == 0)
    }

    @Test("Pusty payload oznacza, że nic nie gra")
    func emptyPayload() throws {
        #expect(try AdapterPayloadParser.parse(line: line(#"{"type":"data","diff":false,"payload":{}}"#)) == .nothingPlaying)
    }

    @Test("Brak tytułu traktujemy jak brak odtwarzania")
    func missingTitle() throws {
        let json = #"{"type":"data","diff":false,"payload":{"bundleIdentifier":"x","playing":true,"title":""}}"#
        #expect(try AdapterPayloadParser.parse(line: line(json)) == .nothingPlaying)
    }

    @Test("Błędne dane zgłaszają konkretny błąd")
    func errors() {
        #expect(throws: AdapterPayloadParser.ParseError.notJSON) { try AdapterPayloadParser.parse(line: line("nie json")) }
        #expect(throws: AdapterPayloadParser.ParseError.unexpectedType("log")) {
            try AdapterPayloadParser.parse(line: line(#"{"type":"log"}"#))
        }
        #expect(throws: AdapterPayloadParser.ParseError.missingPayload) {
            try AdapterPayloadParser.parse(line: line(#"{"type":"data"}"#))
        }
    }
}

@Suite("Bufor linii")
struct LineBufferTests {
    @Test("Składa linie z kawałków i pomija puste")
    func chunks() {
        var buffer = LineBuffer()
        #expect(buffer.append(Data("ab".utf8)).isEmpty)
        #expect(buffer.append(Data("c\n\nde".utf8)) == [Data("abc".utf8)])
        #expect(buffer.append(Data("f\ng\n".utf8)) == [Data("def".utf8), Data("g".utf8)])
    }
}
