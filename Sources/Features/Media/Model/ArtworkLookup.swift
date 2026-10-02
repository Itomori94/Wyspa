import Foundation

/// Brakująca okładka z katalogu iTunes (Apple) — tylko gdy Muzyka jej nie oddaje (utwory z subskrypcji przez AirPlay).
/// Wysyłane są wyłącznie wykonawca i tytuł; bez konta i klucza.
public enum ArtworkLookup {
    public static let artworkSize = 600
    /// Odpowiedzi i obrazy ponad ten rozmiar są odrzucane.
    public static let maxBytes = 4 * 1024 * 1024

    public static func searchURL(title: String, artist: String?, country: String) -> URL? {
        var components = URLComponents(string: "https://itunes.apple.com/search")
        components?.queryItems = [
            URLQueryItem(name: "term", value: [artist, title].compactMap { $0 }.joined(separator: " ")),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "5"),
            URLQueryItem(name: "country", value: country.lowercased()),
        ]
        return components?.url
    }

    /// Adres okładki najlepiej pasującego utworu (tytuł i wykonawca bez wielkości liter), w rozmiarze `artworkSize`.
    /// Przyjmowane są tylko adresy https z serwerów obrazów Apple.
    public static func artworkURL(from data: Data, title: String, artist: String?) -> URL? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = object["results"] as? [[String: Any]], !results.isEmpty
        else { return nil }
        let wantedTitle = normalized(title)
        let wantedArtist = artist.map(normalized)
        let matches = { (result: [String: Any]) -> Bool in
            let trackTitle = normalized(result["trackName"] as? String ?? "")
            let trackArtist = normalized(result["artistName"] as? String ?? "")
            return trackTitle == wantedTitle && (wantedArtist.map { trackArtist.contains($0) || $0.contains(trackArtist) } ?? true)
        }
        guard let best = results.first(where: matches),
              let small = best["artworkUrl100"] as? String,
              let url = URL(string: small.replacingOccurrences(of: "100x100bb", with: "\(artworkSize)x\(artworkSize)bb")),
              url.scheme == "https", url.host?.hasSuffix(".mzstatic.com") == true
        else { return nil }
        return url
    }

    static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Wyszukanie i pobranie okładki; `nil` przy braku dopasowania albo błędzie sieci.
    public static func fetch(title: String, artist: String?, session: URLSession = .shared) async -> Data? {
        let country = Locale.current.region?.identifier ?? "US"
        guard let search = searchURL(title: title, artist: artist, country: country),
              let (json, _) = try? await session.data(from: search), json.count <= maxBytes,
              let artworkURL = artworkURL(from: json, title: title, artist: artist),
              let (image, response) = try? await session.data(from: artworkURL), image.count <= maxBytes,
              (response as? HTTPURLResponse)?.statusCode == 200
        else { return nil }
        return image
    }
}
