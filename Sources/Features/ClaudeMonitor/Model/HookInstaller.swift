import WyspaHookKit
import Foundation

/// Dopisuje i usuwa hooki Wyspy w `~/.claude/settings.json`, nie ruszając innych ustawień ani cudzych hooków.
///
/// Wpisy Wyspy rozpoznaje po ścieżce helpera zawierającej `marker`.
public enum HookInstaller {
    public static let marker = "wyspa-hook"

    /// Zdarzenia, które Wyspa obserwuje. `PermissionRequest` czeka na decyzję; reszta tylko zgłasza stan.
    public static let events = [
        "SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure",
        "PermissionRequest", "Notification", "Stop", "SubagentStop", "SessionEnd",
    ]
    /// Limit Claude Code dla zdarzeń bez decyzji (hook kończy się zwykle w milisekundach).
    static let quickTimeout = 10

    public enum InstallError: Error, Equatable, LocalizedError {
        case unreadableSettings(String)
        case writeFailed(String)

        public var errorDescription: String? {
            switch self {
            case .unreadableSettings(let detail): "Nie można odczytać ~/.claude/settings.json: \(detail). Plik nie został zmieniony."
            case .writeFailed(let detail): "Nie można zapisać ~/.claude/settings.json: \(detail)"
            }
        }
    }

    // MARK: - Czyste przekształcenia (testowane)

    /// Ustawienia z hookami Wyspy (poprzednie wpisy Wyspy są zastępowane, cudze zostają).
    public static func installing(into settings: [String: Any], helperPath: String, decisionTimeout: Int) -> [String: Any] {
        var cleaned = uninstalling(from: settings)
        var hooks = cleaned["hooks"] as? [String: Any] ?? [:]
        for event in events {
            let waits = event == "PermissionRequest"
            var handler: [String: Any] = [
                "type": "command",
                "command": helperPath,
                "args": waits ? ["--decision-timeout", String(decisionTimeout)] : [],
                // Claude Code nie może przerwać hooka, zanim minie czas decyzji (+ zapas na połączenie).
                "timeout": waits ? decisionTimeout + 15 : quickTimeout,
            ]
            if !waits { handler["async"] = false }
            let group: [String: Any] = ["matcher": "", "hooks": [handler]]
            hooks[event] = (hooks[event] as? [[String: Any]] ?? []) + [group]
        }
        cleaned["hooks"] = hooks
        return cleaned
    }

    /// Ustawienia bez hooków Wyspy; puste grupy i zdarzenia znikają, reszta bez zmian.
    public static func uninstalling(from settings: [String: Any]) -> [String: Any] {
        guard var hooks = settings["hooks"] as? [String: Any] else { return settings }
        for (event, value) in hooks {
            guard let groups = value as? [[String: Any]] else { continue }
            let kept = groups.compactMap { group -> [String: Any]? in
                guard let handlers = group["hooks"] as? [[String: Any]] else { return group }
                let others = handlers.filter { !isOurs($0) }
                guard !others.isEmpty else { return nil }
                var copy = group
                copy["hooks"] = others
                return copy
            }
            hooks[event] = kept.isEmpty ? nil : kept
        }
        var result = settings
        result["hooks"] = hooks.isEmpty ? nil : hooks
        return result
    }

    public static func isInstalled(in settings: [String: Any]) -> Bool {
        guard let hooks = settings["hooks"] as? [String: Any] else { return false }
        return events.allSatisfy { event in
            (hooks[event] as? [[String: Any]] ?? []).contains { group in
                (group["hooks"] as? [[String: Any]] ?? []).contains(where: isOurs)
            }
        }
    }

    static func isOurs(_ handler: [String: Any]) -> Bool {
        (handler["command"] as? String)?.contains(marker) ?? false
    }

    // MARK: - Plik

    public static var settingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    }

    public static func read(_ url: URL = settingsURL) throws(InstallError) -> [String: Any] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        do {
            let data = try Data(contentsOf: url)
            guard !data.isEmpty else { return [:] }
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw InstallError.unreadableSettings("to nie jest obiekt JSON")
            }
            return object
        } catch let error as InstallError {
            throw error
        } catch {
            throw .unreadableSettings(error.localizedDescription)
        }
    }

    /// Zapisuje ustawienia atomowo, po zrobieniu kopii zapasowej obecnego pliku. Zwraca ścieżkę kopii.
    @discardableResult
    public static func write(_ settings: [String: Any], to url: URL = settingsURL, now: Date = Date()) throws(InstallError) -> URL? {
        let fileManager = FileManager.default
        var backup: URL?
        do {
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: url.path) {
                let stamp = ISO8601DateFormatter().string(from: now).replacingOccurrences(of: ":", with: "-")
                let target = url.deletingLastPathComponent().appendingPathComponent("settings.json.wyspa-backup-\(stamp)")
                try fileManager.copyItem(at: url, to: target)
                backup = target
            }
            let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            try data.write(to: url, options: .atomic)
        } catch {
            throw .writeFailed(error.localizedDescription)
        }
        return backup
    }
}
