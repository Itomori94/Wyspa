import Foundation

/// Protokół gniazda między `wyspa-hook` a Wyspą: jedna linia JSON w każdą stronę.
///
/// Hook → Wyspa: `{"v":1,"event":{…wejście hooka…},"claudePid":123,"bundleID":"…","termProgram":"…","wantsReply":true}`
/// Wyspa → hook (tylko gdy `wantsReply`): `{"behavior":"allow"|"deny"|"ask","message":"…"}`
public enum HookProtocol {
    public static let version = 1
    /// Największa przyjmowana wiadomość (narzędzie Write potrafi nieść duży plik).
    public static let maxMessageBytes = 8 * 1024 * 1024

    /// Gniazdo w katalogu użytkownika (dostęp tylko dla właściciela).
    ///
    /// `WYSPA_SOCKET_PATH` nadpisuje ścieżkę wyłącznie w buildzie debug (testy). W wersji wydanej zmienna środowiskowa
    /// z ustawień projektu nie może przekierować próśb o uprawnienia do cudzego gniazda.
    public static var socketURL: URL {
        #if DEBUG
        if let override = ProcessInfo.processInfo.environment["WYSPA_SOCKET_PATH"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        #endif
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Wyspa/claude.sock")
    }

    /// Potwierdzenie, że główny wątek Wyspy przyjął prośbę (hook bez niego w ~2 s wraca do terminala).
    public static let acknowledgement = Data("{\"ack\":true}\n".utf8)
    public static let acknowledgementTimeout: TimeInterval = 2

    public struct Envelope: Equatable, Sendable {
        public let event: HookEvent
        public let claudePID: Int32?
        public let bundleID: String?
        public let termProgram: String?
        public let wantsReply: Bool

        public init(event: HookEvent, claudePID: Int32?, bundleID: String?, termProgram: String?, wantsReply: Bool) {
            self.event = event
            self.claudePID = claudePID
            self.bundleID = bundleID
            self.termProgram = termProgram
            self.wantsReply = wantsReply
        }
    }

    public enum ParseError: Error, Equatable {
        case notJSON
        case unsupportedVersion(Int?)
        case missingField(String)
    }

    public static func parse(_ data: Data) throws(ParseError) -> Envelope {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw .notJSON }
        let version = object["v"] as? Int
        guard version == Self.version else { throw .unsupportedVersion(version) }
        guard let event = object["event"] as? [String: Any] else { throw .missingField("event") }
        return Envelope(
            event: try HookEvent.parse(event),
            claudePID: (object["claudePid"] as? NSNumber).map { Int32(truncatingIfNeeded: $0.intValue) },
            bundleID: object["bundleID"] as? String,
            termProgram: object["termProgram"] as? String,
            wantsReply: object["wantsReply"] as? Bool ?? false
        )
    }

    public enum Behavior: String, Codable, Sendable {
        case allow, deny
        /// Brak decyzji w wyspie: Claude Code pokaże zwykły prompt w terminalu.
        case ask
    }

    public static func reply(_ behavior: Behavior, message: String? = nil, answers: [String: String]? = nil) -> Data {
        var object: [String: Any] = ["behavior": behavior.rawValue]
        if let message { object["message"] = message }
        if let answers { object["answers"] = answers }
        let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{\"behavior\":\"ask\"}".utf8)
        return data + Data("\n".utf8)
    }

    /// Wyjście hooka dla Claude Code; nil = brak wyjścia (zwykły prompt w terminalu).
    public static func hookOutput(for behavior: Behavior, message: String?) -> String? {
        switch behavior {
        case .ask:
            return nil
        case .allow:
            return #"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}"#
        case .deny:
            let decision: [String: Any] = ["behavior": "deny", "message": message ?? "Odrzucono w Wyspie."]
            let object: [String: Any] = ["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": decision]]
            return (try? JSONSerialization.data(withJSONObject: object)).flatMap { String(data: $0, encoding: .utf8) }
        }
    }
}

/// Zdarzenie hooka Claude Code (pola z dokumentacji hooków; nieznane zdarzenia są dopuszczalne).
public struct HookEvent: Equatable, Sendable {
    public let name: String
    public let sessionID: String
    public let cwd: String?
    public let toolName: String?
    public let toolUseID: String?
    public let toolInput: ToolInput?
    public let notificationType: String?
    public let message: String?
    public let lastAssistantMessage: String?
    /// Zapis sesji (JSONL); z niego wykrywamy przerwanie, po którym Claude Code nie wysyła żadnego hooka.
    public let transcriptPath: String?
    /// Limity planu — tylko w zdarzeniu „StatusLine” z linii statusu Claude Code.
    public let rateLimits: ClaudeLimits?
    /// Pytania z opcjami, gdy to PreToolUse narzędzia `AskUserQuestion`.
    public let questions: [ClaudeQuestion]

    /// Czy hook ma czekać na odpowiedź z wyspy (prośba o zgodę albo pytanie z opcjami).
    public static func wantsReply(_ event: [String: Any]) -> Bool {
        switch event["hook_event_name"] as? String {
        case "PermissionRequest": true
        case "PreToolUse": event["tool_name"] as? String == ClaudeQuestion.toolName && !ClaudeQuestion.parse(event["tool_input"]).isEmpty
        default: false
        }
    }

    /// Nazwa zdarzenia wysyłanego przez `wyspa-hook --statusline` (nie jest hookiem Claude Code).
    public static let statusLineEvent = "StatusLine"

    /// Zdarzenie bez danych narzędzia (do syntetycznych zmian stanu).
    public static func fallback(_ sessionID: String) -> HookEvent {
        HookEvent(name: "Notification", sessionID: sessionID, cwd: nil, toolName: nil, toolUseID: nil, toolInput: nil,
                  notificationType: nil, message: nil, lastAssistantMessage: nil, transcriptPath: nil, rateLimits: nil, questions: [])
    }

    public static func parse(_ object: [String: Any]) throws(HookProtocol.ParseError) -> HookEvent {
        guard let name = object["hook_event_name"] as? String else { throw .missingField("hook_event_name") }
        guard let session = object["session_id"] as? String, !session.isEmpty else { throw .missingField("session_id") }
        return HookEvent(
            name: name,
            sessionID: session,
            cwd: object["cwd"] as? String,
            toolName: object["tool_name"] as? String,
            toolUseID: object["tool_use_id"] as? String,
            toolInput: (object["tool_input"] as? [String: Any]).map(ToolInput.init),
            notificationType: object["notification_type"] as? String,
            message: object["message"] as? String,
            lastAssistantMessage: object["last_assistant_message"] as? String,
            transcriptPath: object["transcript_path"] as? String,
            rateLimits: ClaudeLimits.parse(object["rate_limits"]),
            questions: object["tool_name"] as? String == ClaudeQuestion.toolName ? ClaudeQuestion.parse(object["tool_input"]) : []
        )
    }
}

/// Wejście narzędzia w postaci potrzebnej do podglądu (polecenie, plik, diff).
public struct ToolInput: Equatable, Sendable {
    public let command: String?
    public let description: String?
    public let filePath: String?
    public let oldString: String?
    public let newString: String?
    public let content: String?
    public let edits: [(old: String, new: String)]
    public let url: String?
    public let pattern: String?

    public init(_ object: [String: Any]) {
        command = object["command"] as? String
        description = object["description"] as? String
        filePath = object["file_path"] as? String ?? object["notebook_path"] as? String
        oldString = object["old_string"] as? String
        newString = object["new_string"] as? String
        content = object["content"] as? String
        edits = (object["edits"] as? [[String: Any]] ?? []).compactMap { edit in
            guard let old = edit["old_string"] as? String, let new = edit["new_string"] as? String else { return nil }
            return (old, new)
        }
        url = object["url"] as? String
        pattern = object["pattern"] as? String
    }

    public static func == (lhs: ToolInput, rhs: ToolInput) -> Bool {
        lhs.command == rhs.command && lhs.filePath == rhs.filePath && lhs.oldString == rhs.oldString
            && lhs.newString == rhs.newString && lhs.content == rhs.content && lhs.url == rhs.url
            && lhs.pattern == rhs.pattern && lhs.description == rhs.description
            && lhs.edits.map(\.old) == rhs.edits.map(\.old) && lhs.edits.map(\.new) == rhs.edits.map(\.new)
    }

    /// Jednowierszowy opis do listy narzędzi i nagłówka prośby.
    public var summary: String? {
        command ?? filePath.map { ($0 as NSString).lastPathComponent } ?? url ?? pattern
    }
}
