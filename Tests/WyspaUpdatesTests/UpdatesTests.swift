import Foundation
import Testing
@testable import WyspaUpdates

@Suite("Aktualizacje — źródło buildu")
struct BuildSourceTests {
    private let commit = String(repeating: "a1", count: 20)

    @Test("odczytuje commit, gałąź, repozytorium i katalog z Info.plist")
    func readsInfoDictionary() throws {
        let source = try #require(BuildSource.from(infoDictionary: [
            "WyspaSourceCommit": commit, "WyspaSourceBranch": "master",
            "WyspaSourceRemote": "https://github.com/Itomori94/Wyspa.git",
            "WyspaSourcePath": "/Users/x/Projects/Wyspa", "WyspaSourceDirty": "0",
        ]))
        #expect(source.shortCommit == "a1a1a1a")
        #expect(source.repository == GitHubRepository(remote: "git@github.com:Itomori94/Wyspa.git"))
        #expect(source.path == "/Users/x/Projects/Wyspa")
        #expect(!source.isDirty)
    }

    @Test("bez poprawnego commitu nie ma źródła", arguments: [nil, "", "abc", String(repeating: "z", count: 40)])
    func rejectsInvalidCommit(value: String?) {
        var info: [String: Any] = ["WyspaSourceRemote": "https://github.com/a/b"]
        info["WyspaSourceCommit"] = value
        #expect(BuildSource.from(infoDictionary: info) == nil)
    }

    @Test("oznacza build z niezapisanymi zmianami")
    func dirtyFlag() {
        let source = BuildSource.from(infoDictionary: ["WyspaSourceCommit": commit, "WyspaSourceDirty": "1"])
        #expect(source?.isDirty == true)
        #expect(source?.repository == nil)
    }
}

@Suite("Aktualizacje — repozytorium GitHub")
struct GitHubRepositoryTests {
    @Test("rozpoznaje adresy https i ssh", arguments: [
        "https://github.com/Itomori94/Wyspa.git", "https://github.com/Itomori94/Wyspa",
        "git@github.com:Itomori94/Wyspa.git", "ssh://git@github.com/Itomori94/Wyspa.git",
    ])
    func parsesRemotes(remote: String) throws {
        let repo = try #require(GitHubRepository(remote: remote))
        #expect(repo.owner == "Itomori94")
        #expect(repo.name == "Wyspa")
    }

    @Test("nazwa z .github w środku zostaje nietknięta")
    func keepsDotGithubName() {
        #expect(GitHubRepository(remote: "https://github.com/acme/acme.github.io.git")?.name == "acme.github.io")
    }

    @Test("odrzuca inne hosty i dziwne ścieżki", arguments: [
        "", "https://gitlab.com/a/b", "https://github.com/a", "https://github.com/a/b/c", "https://github.com/a/b?x=1",
        "https://github.com/a%2F/b",
    ])
    func rejects(remote: String) {
        #expect(GitHubRepository(remote: remote) == nil)
    }

    @Test("adres porównania wskazuje API GitHuba")
    func compareURL() {
        let repo = GitHubRepository(remote: "https://github.com/Itomori94/Wyspa")
        #expect(repo?.compareURL(from: "abc", to: "master")?.absoluteString
                == "https://api.github.com/repos/Itomori94/Wyspa/compare/abc...master")
    }
}

@Suite("Aktualizacje — odpowiedź GitHuba")
struct UpdateCheckTests {
    private func response(status: String, titles: [String]) -> Data {
        let commits = titles.enumerated().map { index, title in
            ["sha": "sha\(index)", "commit": ["message": "\(title)\n\nopis", "committer": ["date": "2026-10-0\(index + 1)T10:00:00Z"]]]
        }
        return try! JSONSerialization.data(withJSONObject: ["status": status, "ahead_by": titles.count, "commits": commits])
    }

    @Test("nowsze commity: lista od najnowszego, tylko tytuły")
    func ahead() throws {
        let check = try #require(UpdateCheck.parse(response(status: "ahead", titles: ["feat: a", "fix: b"])))
        #expect(check.isAvailable)
        #expect(check.changes.map(\.title) == ["fix: b", "feat: a"])
        #expect(check.latestCommit == "sha1")
        #expect(check.changes.first?.date != nil)
    }

    @Test("aktualna albo nowsza lokalnie wersja: brak aktualizacji", arguments: ["identical", "behind"])
    func noUpdate(status: String) throws {
        let check = try #require(UpdateCheck.parse(response(status: status, titles: [])))
        #expect(!check.isAvailable)
    }

    @Test("rozbieżne gałęzie też pokazują zmiany z GitHuba")
    func diverged() throws {
        #expect(try #require(UpdateCheck.parse(response(status: "diverged", titles: ["x"]))).isAvailable)
    }

    @Test("nieprawidłowa odpowiedź", arguments: [Data(), Data("[]".utf8), Data("{\"message\":\"Not Found\"}".utf8)])
    func invalid(data: Data) {
        #expect(UpdateCheck.parse(data) == nil)
    }
}

@Suite("Aktualizacje — zabezpieczenia przed aktualizacją")
struct UpdateGuardTests {
    private func makeRepo(branch: String = "master", dirty: Bool = false) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("wyspa-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("scripts"), withIntermediateDirectories: true)
        try Data("#!/bin/sh\n".utf8).write(to: dir.appendingPathComponent("scripts/install.sh"))
        for args in [["init", "-q", "-b", branch], ["-c", "user.email=t@t", "-c", "user.name=t", "add", "."],
                     ["-c", "user.email=t@t", "-c", "user.name=t", "commit", "-qm", "init"]] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["-C", dir.path] + args
            try process.run()
            process.waitUntilExit()
        }
        if dirty { try Data("x".utf8).write(to: dir.appendingPathComponent("zmiana.txt")) }
        return dir
    }

    @Test("brak katalogu projektu")
    func missingDirectory() {
        #expect(UpdateService.prepare(path: "/nie/ma/takiego")?.contains("Nie ma katalogu projektu") == true)
    }

    @Test("inna gałąź niż master")
    func otherBranch() throws {
        let dir = try makeRepo(branch: "eksperyment")
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(UpdateService.prepare(path: dir.path)?.contains("eksperyment") == true)
    }

    @Test("niezapisane zmiany")
    func dirtyTree() throws {
        let dir = try makeRepo(dirty: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(UpdateService.prepare(path: dir.path)?.contains("niezapisane zmiany") == true)
    }

    @Test("czyste repozytorium bez zdalnego: błąd pobierania, nie instalacja")
    func pullFails() throws {
        let dir = try makeRepo()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(UpdateService.prepare(path: dir.path)?.contains("git pull") == true)
    }
}
