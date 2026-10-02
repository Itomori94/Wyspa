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

    /// Ile kopii zapasowych `settings.json.wyspa-backup-*` zostaje (najstarsze są usuwane).
    static let keptBackups = 5

    public enum InstallError: Error, Equatable, LocalizedError {
        case unreadableSettings(String)
        case unexpectedStructure(String)
        case writeFailed(String)

        public var errorDescription: String? {
            switch self {
            case .unreadableSettings(let detail): "Nie można odczytać ~/.claude/settings.json: \(detail). Plik nie został zmieniony."
            case .unexpectedStructure(let detail):
                "Nieoczekiwana struktura ~/.claude/settings.json (\(detail)). Plik nie został zmieniony — popraw go ręcznie."
            case .writeFailed(let detail): "Nie można zapisać ~/.claude/settings.json: \(detail)"
            }
        }
    }

    /// Odrzuca ustawienia, których hooków nie da się bezpiecznie przekształcić (zamiast cicho je nadpisać).
    static func validate(_ settings: [String: Any]) throws(InstallError) {
        guard let raw = settings["hooks"] else { return }
        guard let hooks = raw as? [String: Any] else { throw .unexpectedStructure("„hooks” nie jest obiektem") }
        for (event, value) in hooks {
            guard let groups = value as? [Any] else { throw .unexpectedStructure("„hooks.\(event)” nie jest listą") }
            for group in groups {
                guard let group = group as? [String: Any] else { throw .unexpectedStructure("wpis w „hooks.\(event)” nie jest obiektem") }
                if let handlers = group["hooks"], !(handlers is [[String: Any]]) {
                    throw .unexpectedStructure("„hooks” w „hooks.\(event)” nie jest listą obiektów")
                }
            }
        }
    }

    // MARK: - Czyste przekształcenia (testowane)

    /// Ustawienia z hookami Wyspy (poprzednie wpisy Wyspy są zastępowane, cudze zostają).
    public static func installing(into settings: [String: Any], helperPath: String, decisionTimeout: Int) throws(InstallError) -> [String: Any] {
        var cleaned = try uninstalling(from: settings)
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
    public static func uninstalling(from settings: [String: Any]) throws(InstallError) -> [String: Any] {
        try validate(settings)
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

    /// Wpis Wyspy = polecenie, którego plik nazywa się dokładnie `wyspa-hook` (np. `my-wyspa-hook-logger.sh` nie jest nasz).
    static func isOurs(_ handler: [String: Any]) -> Bool {
        guard let command = handler["command"] as? String else { return false }
        return (command as NSString).lastPathComponent == marker
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
    ///
    /// Dowiązanie (np. do repozytorium dotfiles) jest zachowane — zapis trafia do pliku docelowego. Prawa pliku
    /// (np. 0600) zostają takie jak były. Kopie mają unikalne nazwy, zostaje ich najwyżej `keptBackups`.
    @discardableResult
    public static func write(_ settings: [String: Any], to url: URL = settingsURL, now: Date = Date()) throws(InstallError) -> URL? {
        let fileManager = FileManager.default
        let target = url.resolvingSymlinksInPath()
        var backup: URL?
        do {
            try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            let permissions = (try? fileManager.attributesOfItem(atPath: target.path)[.posixPermissions]) as? NSNumber
            if fileManager.fileExists(atPath: target.path) {
                let stamp = ISO8601DateFormatter().string(from: now).replacingOccurrences(of: ":", with: "-")
                let name = "settings.json.wyspa-backup-\(stamp)-\(UUID().uuidString.prefix(6))"
                let copy = url.deletingLastPathComponent().appendingPathComponent(name)
                try fileManager.copyItem(at: target, to: copy)
                backup = copy
                pruneBackups(in: url.deletingLastPathComponent())
            }
            let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            try data.write(to: target, options: .atomic)
            if let permissions {
                try fileManager.setAttributes([.posixPermissions: permissions], ofItemAtPath: target.path)
            }
        } catch {
            throw .writeFailed(error.localizedDescription)
        }
        return backup
    }

    /// Usuwa najstarsze kopie zapasowe Wyspy ponad limit (inne pliki w katalogu są nietknięte).
    static func pruneBackups(in directory: URL) {
        let fileManager = FileManager.default
        let backups = ((try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey])) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("settings.json.wyspa-backup-") }
            .sorted {
                let l = (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                let r = (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return l > r
            }
        for old in backups.dropFirst(keptBackups) {
            try? fileManager.removeItem(at: old)
        }
    }
}
