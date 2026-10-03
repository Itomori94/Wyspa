import Foundation

/// Skąd pochodzi zainstalowana Wyspa (zapisane przy budowaniu przez scripts/build-app.sh).
public struct BuildSource: Equatable, Sendable {
    public let commit: String
    public let branch: String
    public let repository: GitHubRepository?
    public let path: String
    /// Build z niezapisanymi zmianami — porównanie z GitHubem jest wtedy tylko przybliżone.
    public let isDirty: Bool

    public var shortCommit: String { String(commit.prefix(7)) }

    public init(commit: String, branch: String, repository: GitHubRepository?, path: String, isDirty: Bool) {
        self.commit = commit
        self.branch = branch
        self.repository = repository
        self.path = path
        self.isDirty = isDirty
    }

    /// Z Info.plist; nil, gdy aplikację zbudowano bez gita (wtedy moduł tylko to mówi).
    public static func from(infoDictionary: [String: Any]) -> BuildSource? {
        guard let commit = infoDictionary["WyspaSourceCommit"] as? String, commit.count == 40,
              commit.allSatisfy(\.isHexDigit)
        else { return nil }
        return BuildSource(commit: commit, branch: infoDictionary["WyspaSourceBranch"] as? String ?? "",
                           repository: GitHubRepository(remote: infoDictionary["WyspaSourceRemote"] as? String ?? ""),
                           path: infoDictionary["WyspaSourcePath"] as? String ?? "",
                           isDirty: infoDictionary["WyspaSourceDirty"] as? String == "1")
    }
}

/// Repozytorium na GitHubie z adresu `origin` (https albo ssh).
public struct GitHubRepository: Equatable, Sendable {
    public let owner: String
    public let name: String

    public init?(remote: String) {
        let trimmed = remote.trimmingCharacters(in: .whitespacesAndNewlines)
        let path: Substring
        if let range = trimmed.range(of: "github.com/") {
            path = trimmed[range.upperBound...]
        } else if let range = trimmed.range(of: "github.com:") {
            path = trimmed[range.upperBound...]
        } else {
            return nil
        }
        let bare = path.hasSuffix(".git") ? path.dropLast(4) : path
        let parts = bare.split(separator: "/")
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        guard parts.count == 2, parts.allSatisfy({ !$0.isEmpty && $0.unicodeScalars.allSatisfy(allowed.contains) }) else { return nil }
        owner = String(parts[0])
        name = String(parts[1])
    }

    /// Porównanie zainstalowanego commitu z gałęzią na GitHubie.
    public func compareURL(from commit: String, to branch: String) -> URL? {
        URL(string: "https://api.github.com/repos/\(owner)/\(name)/compare/\(commit)...\(branch)")
    }

    public var webURL: URL? { URL(string: "https://github.com/\(owner)/\(name)") }
}

/// Wynik sprawdzenia: ile commitów jest nowszych i jakie.
public struct UpdateCheck: Equatable, Sendable {
    public struct Change: Equatable, Sendable {
        public let sha: String
        public let title: String
        public let date: Date?
    }

    public let changes: [Change]
    public let latestCommit: String?

    public var isAvailable: Bool { !changes.isEmpty }

    /// Odpowiedź GitHub `compare`: `ahead_by` i lista commitów (najnowszy ostatni). Lista zmian od najnowszej.
    public static func parse(_ data: Data) -> UpdateCheck? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = object["status"] as? String
        else { return nil }
        let commits = object["commits"] as? [[String: Any]] ?? []
        let formatter = ISO8601DateFormatter()
        let changes = commits.compactMap { entry -> Change? in
            guard let sha = entry["sha"] as? String, let commit = entry["commit"] as? [String: Any],
                  let message = commit["message"] as? String
            else { return nil }
            let date = ((commit["committer"] as? [String: Any])?["date"] as? String).flatMap(formatter.date(from:))
            let title = message.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? message
            return Change(sha: sha, title: title, date: date)
        }
        // „behind” = zainstalowana wersja jest nowsza niż GitHub (lokalne commity), „identical” = aktualna.
        guard status == "ahead" || status == "diverged" else { return UpdateCheck(changes: [], latestCommit: commits.last?["sha"] as? String) }
        return UpdateCheck(changes: changes.reversed(), latestCommit: changes.last?.sha)
    }
}
