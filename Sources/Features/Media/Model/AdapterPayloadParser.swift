import Foundation

/// Parsuje linie JSON z `mediaremote-adapter.pl … stream --no-diff --micros`.
///
/// Format linii: `{"type":"data","diff":false,"payload":{…}}`. Pusty `payload` oznacza, że nic nie gra.
public enum AdapterPayloadParser {
    public enum Line: Equatable, Sendable {
        case nowPlaying(NowPlaying)
        case nothingPlaying
    }

    public enum ParseError: Error, Equatable {
        case notJSON
        case unexpectedType(String?)
        case missingPayload
    }

    private static let microsPerSecond = 1_000_000.0

    public static func parse(line: Data) throws(ParseError) -> Line {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
            throw .notJSON
        }
        let type = object["type"] as? String
        guard type == "data" else { throw .unexpectedType(type) }
        guard let payload = object["payload"] as? [String: Any] else { throw .missingPayload }
        return nowPlaying(from: payload).map(Line.nowPlaying) ?? .nothingPlaying
    }

    /// Payload bez wymaganych kluczy (bundleIdentifier, title, playing) traktujemy jak „nic nie gra”.
    static func nowPlaying(from payload: [String: Any]) -> NowPlaying? {
        guard let bundle = nonEmpty(payload["parentApplicationBundleIdentifier"]) ?? nonEmpty(payload["bundleIdentifier"]),
              let title = nonEmpty(payload["title"]),
              let playing = payload["playing"] as? Bool
        else { return nil }

        return NowPlaying(
            bundleIdentifier: bundle,
            title: title,
            artist: nonEmpty(payload["artist"]),
            album: nonEmpty(payload["album"]),
            duration: seconds(payload["durationMicros"]),
            elapsedTime: seconds(payload["elapsedTimeMicros"]),
            timestamp: seconds(payload["timestampEpochMicros"]).map(Date.init(timeIntervalSince1970:)),
            playbackRate: (payload["playbackRate"] as? NSNumber)?.doubleValue ?? (playing ? 1 : 0),
            isPlaying: playing,
            artwork: (payload["artworkData"] as? String).flatMap { Data(base64Encoded: $0) }
        )
    }

    private static func nonEmpty(_ value: Any?) -> String? {
        guard let string = value as? String, !string.isEmpty else { return nil }
        return string
    }

    private static func seconds(_ micros: Any?) -> TimeInterval? {
        (micros as? NSNumber).map { $0.doubleValue / microsPerSecond }
    }
}

/// Dzieli strumień bajtów na linie zakończone `\n` (dane z potoku przychodzą w dowolnych kawałkach).
public struct LineBuffer: Sendable {
    private var pending = Data()

    public init() {}

    public mutating func append(_ chunk: Data) -> [Data] {
        pending.append(chunk)
        var lines: [Data] = []
        while let newline = pending.firstIndex(of: UInt8(ascii: "\n")) {
            let line = pending[pending.startIndex..<newline]
            if !line.isEmpty { lines.append(Data(line)) }
            pending = Data(pending[pending.index(after: newline)...])
        }
        return lines
    }
}
