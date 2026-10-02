import Foundation
import Testing
@testable import WyspaMedia

@Suite("Okładka z katalogu iTunes")
struct ArtworkLookupTests {
    let response = Data("""
    {"results":[
      {"trackName":"diament (bedroom version)","artistName":"Zalia","artworkUrl100":"https://is1-ssl.mzstatic.com/a/100x100bb.jpg"},
      {"trackName":"Diament","artistName":"Zalia","artworkUrl100":"https://is1-ssl.mzstatic.com/b/100x100bb.jpg"}
    ]}
    """.utf8)

    @Test("Dokładne dopasowanie tytułu i wykonawcy, okładka w dużym rozmiarze")
    func match() {
        let url = ArtworkLookup.artworkURL(from: response, title: "diament", artist: "Zalia")
        #expect(url?.absoluteString == "https://is1-ssl.mzstatic.com/b/600x600bb.jpg")
    }

    @Test("Brak dopasowania, zły JSON albo obcy serwer — bez okładki")
    func rejects() {
        #expect(ArtworkLookup.artworkURL(from: response, title: "inny utwór", artist: "Zalia") == nil)
        #expect(ArtworkLookup.artworkURL(from: Data("x".utf8), title: "diament", artist: nil) == nil)
        let foreign = Data(#"{"results":[{"trackName":"a","artistName":"b","artworkUrl100":"https://evil.example/100x100bb.jpg"}]}"#.utf8)
        #expect(ArtworkLookup.artworkURL(from: foreign, title: "a", artist: "b") == nil)
        let plain = Data(#"{"results":[{"trackName":"a","artistName":"b","artworkUrl100":"http://is1.mzstatic.com/100x100bb.jpg"}]}"#.utf8)
        #expect(ArtworkLookup.artworkURL(from: plain, title: "a", artist: "b") == nil)
    }

    @Test("Zapytanie: wykonawca i tytuł, kraj, tylko utwory")
    func query() throws {
        let url = try #require(ArtworkLookup.searchURL(title: "diament", artist: "Zalia", country: "PL"))
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(url.host == "itunes.apple.com" && url.scheme == "https")
        #expect(items.contains(URLQueryItem(name: "term", value: "Zalia diament")))
        #expect(items.contains(URLQueryItem(name: "country", value: "pl")) && items.contains(URLQueryItem(name: "entity", value: "song")))
    }

    @Test("Kilku wykonawców zapisanych różnie w Muzyce i iTunes")
    func multipleArtists() {
        let data = Data(#"{"results":[{"trackName":"Alibi","artistName":"Sevdaliza, Pabllo Vittar & Yseult","artworkUrl100":"https://is1-ssl.mzstatic.com/c/100x100bb.jpg"}]}"#.utf8)
        #expect(ArtworkLookup.artworkURL(from: data, title: "Alibi", artist: "Sevdaliza, Pabllo Vittar, Yseult") != nil)
        #expect(ArtworkLookup.artworkURL(from: data, title: "Alibi", artist: "Ktoś Inny") == nil)
        #expect(ArtworkLookup.primaryArtist("Drake feat. Rihanna") == "drake")
    }
}
