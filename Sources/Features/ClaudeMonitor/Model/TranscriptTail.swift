import Foundation

/// Odczyt końca zapisu sesji Claude Code (JSONL, jedna wiadomość w wierszu).
public enum TranscriptTail {
    /// Ile bajtów od końca czytamy: kilka ostatnich wierszy wystarcza, plik może mieć wiele MB.
    public static let tailBytes = 32 * 1024
    static let interruptMarker = "[Request interrupted by user"

    /// Czy ostatnia wiadomość rozmowy to przerwanie przez użytkownika.
    /// Wiersze pomocnicze (załączniki, wpisy systemowe) są pomijane; ostatni, niedopisany wiersz też.
    public static func endsWithInterrupt(_ data: Data) -> Bool {
        let text = String(decoding: data, as: UTF8.self)
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        if !text.hasSuffix("\n") { lines = lines.dropLast() }
        for line in lines.reversed() where !line.isEmpty {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let type = object["type"] as? String
            else { continue }
            switch type {
            case "assistant": return false
            case "user": return isInterrupt(object)
            default: continue
            }
        }
        return false
    }

    private static func isInterrupt(_ object: [String: Any]) -> Bool {
        guard let message = object["message"] as? [String: Any] else { return false }
        if let content = message["content"] as? String { return content.hasPrefix(interruptMarker) }
        let parts = message["content"] as? [[String: Any]] ?? []
        return parts.contains { ($0["text"] as? String)?.hasPrefix(interruptMarker) == true }
    }

    /// Ścieżka z hooka musi wskazywać plik zapisu (bezwzględna, `.jsonl`), żeby nie otwierać przypadkowych plików.
    public static func isAcceptablePath(_ path: String) -> Bool {
        path.hasPrefix("/") && path.hasSuffix(".jsonl") && !path.split(separator: "/").contains("..")
    }

    /// Ostatnie bajty pliku.
    static func readTail(of handle: FileHandle) -> Data? {
        guard let size = try? handle.seekToEnd() else { return nil }
        try? handle.seek(toOffset: size > UInt64(tailBytes) ? size - UInt64(tailBytes) : 0)
        return try? handle.readToEnd()
    }
}
