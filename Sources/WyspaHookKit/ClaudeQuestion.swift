import Foundation

/// Pytanie Claude z opcjami (narzędzie `AskUserQuestion`), na które można odpowiedzieć w wyspie.
public struct ClaudeQuestion: Equatable, Sendable {
    public struct Option: Equatable, Sendable {
        public let label: String
        public let description: String?
    }

    public static let toolName = "AskUserQuestion"

    public let question: String
    public let header: String?
    public let options: [Option]
    public let multiSelect: Bool

    /// Pytania z wejścia narzędzia; puste, gdy to nie są pytania z opcjami.
    public static func parse(_ toolInput: Any?) -> [ClaudeQuestion] {
        guard let input = toolInput as? [String: Any], let questions = input["questions"] as? [[String: Any]] else { return [] }
        return questions.compactMap { entry in
            guard let question = entry["question"] as? String, !question.isEmpty else { return nil }
            let options = (entry["options"] as? [[String: Any]] ?? []).compactMap { option -> Option? in
                guard let label = option["label"] as? String, !label.isEmpty else { return nil }
                return Option(label: label, description: option["description"] as? String)
            }
            guard !options.isEmpty else { return nil }
            return ClaudeQuestion(question: question, header: entry["header"] as? String, options: options,
                                  multiSelect: entry["multiSelect"] as? Bool ?? false)
        }
    }

    /// Odpowiedź w formacie pola `answers` narzędzia: pytanie → etykieta (kilka etykiet po przecinku).
    public static func answerText(_ labels: [String]) -> String {
        labels.joined(separator: ", ")
    }

    /// Wyjście hooka PreToolUse: pozwala narzędziu działać z odpowiedziami wpisanymi w jego wejście, więc Claude Code
    /// nie pokazuje pytania w terminalu. Pozostałe pola wejścia zostają bez zmian.
    public static func hookOutput(toolInput: [String: Any], answers: [String: String]) -> String? {
        var updated = toolInput
        updated["answers"] = answers
        let object: [String: Any] = ["hookSpecificOutput": [
            "hookEventName": "PreToolUse",
            "permissionDecision": "allow",
            "permissionDecisionReason": "Odpowiedź wybrana w Wyspie.",
            "updatedInput": updated,
        ]]
        return (try? JSONSerialization.data(withJSONObject: object)).flatMap { String(data: $0, encoding: .utf8) }
    }
}
