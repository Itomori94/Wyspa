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

@Suite("Aktualizacje — potwierdzenie po ponownym uruchomieniu")
@MainActor
struct FinishedUpdateTests {
    private let defaults = UserDefaults(suiteName: "wyspa.tests.updates.\(UUID().uuidString)")!
    private let old = String(repeating: "a", count: 40)
    private let new = String(repeating: "b", count: 40)

    private func service(commit: String) -> UpdateService {
        UpdateService(source: BuildSource(commit: commit, branch: "master", repository: nil, path: "", isDirty: false), defaults: defaults)
    }

    private func savePending(titles: [String] = ["feat: x"]) throws {
        let pending = UpdateService.PendingUpdate(fromCommit: old, titles: titles)
        defaults.set(try JSONEncoder().encode(pending), forKey: UpdateService.pendingKey)
    }

    @Test("bez rozpoczętej aktualizacji nic nie pokazuje")
    func nothingPending() {
        #expect(service(commit: new).consumeFinishedUpdate() == nil)
    }

    @Test("nowa wersja: potwierdzenie z listą zmian, tylko raz")
    func updated() throws {
        try savePending()
        let service = service(commit: new)
        #expect(service.consumeFinishedUpdate() == .updated(to: "bbbbbbb", titles: ["feat: x"]))
        #expect(service.status == .upToDate)
        #expect(service.consumeFinishedUpdate() == nil)
    }

    @Test("ta sama wersja po restarcie: aktualizacja się nie udała")
    func unchanged() throws {
        try savePending()
        #expect(service(commit: old).consumeFinishedUpdate() == .unchanged)
    }
}

/// Uruchamia proces i zwraca kod wyjścia oraz wyjście (stdout + stderr). terminationHandler zamiast waitUntilExit:
/// to drugie potrafi przegapić koniec procesu poza głównym wątkiem.
private func run(_ process: Process) async throws -> (status: Int32, output: String) {
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    let status = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int32, Error>) in
        process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
        do { try process.run() } catch { continuation.resume(throwing: error) }
    }
    return (status, String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
}

private func run(_ executable: String, _ arguments: [String], in directory: URL? = nil) async throws -> (status: Int32, output: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.currentDirectoryURL = directory
    return try await run(process)
}

@Suite("Aktualizacje — etapy instalacji")
struct UpdateStageTests {
    @Test("linia „▸ etap: opis” to etap, reszta wyjścia nie", arguments: zip(
        ["▸ build: budowanie Wyspy", "▸ restart: zamykanie Wyspy", "Compiling WyspaCore IslandShape.swift", "▸ nieznany: x",
         "  ▸ build: wcięte", "▸build: bez spacji"],
        [UpdateStage.build, .restart, nil, nil, nil, nil]
    ))
    func marker(line: String, expected: UpdateStage?) {
        #expect(UpdateStage(marker: line) == expected)
    }

    @Test("wyjście czytane po bajcie (linie i znaki UTF-8 urwane w połowie): kolejne ogłoszone etapy")
    func readsChunks() {
        var reader = InstallOutputReader()
        var seen: [UpdateStage] = []
        for byte in Array("Compiling x\n▸ build: budowanie\nLinking\n▸ install: kopiowanie\n▸ restart: zamyk".utf8) {
            reader.consume([byte])
            if let stage = reader.stage, stage != seen.last { seen.append(stage) }
        }
        // Linia „restart” bez końca jeszcze się nie liczy.
        #expect(seen == [.build, .install])
    }

    @Test("etapy mają kolejność postępu")
    func order() {
        #expect(UpdateStage.allCases.sorted() == [.fetch, .build, .install, .restart])
        #expect(UpdateStage.build < .restart)
    }
}

@Suite("Aktualizacje — skrypt instalacji")
struct InstallScriptTests {
    private static let script = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("scripts/install.sh")

    /// Linie skryptu bez komentarzy.
    private func code() throws -> [Substring] {
        try String(contentsOf: Self.script, encoding: .utf8).split(separator: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }
    }

    @Test("skrypt jest poprawnym bashem (na macOS: bash 3.2)")
    func syntax() async throws {
        let result = try await run("/bin/bash", ["-n", Self.script.path])
        #expect(result.status == 0, "\(result.output)")
    }

    @Test("skrypt ogłasza po kolei etapy znane Wyspie (pobieranie zmian robi sama Wyspa)")
    func announcesStages() throws {
        let announced = try code().compactMap { line -> String? in
            let words = line.split(separator: " ")
            return words.first == "stage" && words.count > 1 ? String(words[1]) : nil
        }
        #expect(announced == UpdateStage.allCases.filter { $0 != .fetch }.map(\.rawValue))
    }

    @Test("pgrep i pkill z -a: przy aktualizacji z poziomu Wyspy to ona jest przodkiem skryptu")
    func includesAncestors() throws {
        let calls = try code().filter { $0.contains("pgrep") || $0.contains("pkill") }
        #expect(calls.count >= 3)
        for call in calls { #expect(call.contains(" -a "), "\(call)") }
    }

    @Test("pgrep bez -a pomija swoich przodków — dlatego aktualizacja z menu nie zamykała Wyspy")
    func pgrepSkipsAncestors() async throws {
        // Powłoka z unikalnym znacznikiem w poleceniu jest przodkiem obu pgrep (same pgrep zawsze pomijają siebie).
        let marker = "wyspa-przodek-\(UUID().uuidString)"
        let result = try await run("/bin/sh", ["-c", "echo $$; /usr/bin/pgrep -f \(marker); echo -; /usr/bin/pgrep -a -f \(marker); echo ."])
        let lines = result.output.split(separator: "\n").map(String.init)
        let shell = try #require(lines.first)
        #expect(lines == [shell, "-", shell, "."])
    }

    // MARK: - Przebieg skryptu na atrapach poleceń macOS

    /// Działająca Wyspa to plik `state/wyspa` z jej wersją; `state/parent` = to ona uruchomiła skrypt i, jak dla
    /// prawdziwych pgrep/pkill, bez -a jej nie widać. Zamknięcie trwa chwilę, `open` przy działającej tylko ją aktywuje.
    private static let stubs = [
        "pgrep": """
            #!/bin/bash
            echo "pgrep $*" >> "$SIM/calls"
            [ -f "$SIM/state/wyspa" ] || exit 1
            case " $* " in *" -a "*) ;; *) [ -f "$SIM/state/parent" ] && exit 1 ;; esac
            echo 4242
            """,
        "pkill": """
            #!/bin/bash
            echo "pkill $*" >> "$SIM/calls"
            [ -f "$SIM/state/wyspa" ] || exit 1
            case " $* " in *" -a "*) ;; *) [ -f "$SIM/state/parent" ] && exit 1 ;; esac
            ( sleep 0.3; rm -f "$SIM/state/wyspa" "$SIM/state/parent" ) >/dev/null 2>&1 &
            """,
        "open": """
            #!/bin/bash
            echo "open $*" >> "$SIM/calls"
            [ -f "$SIM/state/wyspa" ] || cp "$1/Contents/version" "$SIM/state/wyspa"
            """,
        "ditto": "#!/bin/bash\ncp -R \"$1\" \"$2\"\n",
        "codesign": "#!/bin/bash\nexit 0\n",
    ]

    private static let buildStub = """
        #!/bin/bash
        echo "build-app.sh $*" >> "$SIM/calls"
        [ -f "$SIM/state/build_fails" ] && { echo "error: kompilacja" >&2; exit 1; }
        rm -rf build/Wyspa.app && mkdir -p build/Wyspa.app/Contents && echo new > build/Wyspa.app/Contents/version
        """

    private struct Outcome {
        let status: Int32
        let output: String
        let calls: String
        /// Wersja działającej Wyspy i zainstalowanej w (piaskownicowym) /Applications.
        let running: String?
        let installed: String?
        let stagingLeft: Bool
    }

    /// Prawdziwy install.sh w piaskownicy: docelowe katalogi podmienione, polecenia macOS zastąpione atrapami.
    private func simulate(_ state: [String]) async throws -> Outcome {
        let files = FileManager.default
        let sim = files.temporaryDirectory.appendingPathComponent("wyspa-install-\(UUID().uuidString)")
        defer { try? files.removeItem(at: sim) }
        let apps = sim.appendingPathComponent("Applications")
        for dir in ["state", "stubs", "repo/scripts", "Applications/Wyspa.app/Contents"] {
            try files.createDirectory(at: sim.appendingPathComponent(dir), withIntermediateDirectories: true)
        }
        try Data("old\n".utf8).write(to: apps.appendingPathComponent("Wyspa.app/Contents/version"))
        for flag in state { try Data((flag == "wyspa" ? "old\n" : "").utf8).write(to: sim.appendingPathComponent("state/\(flag)")) }

        var replaced = 0
        let script = try String(contentsOf: Self.script, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                if line.hasPrefix("TARGET=") { replaced += 1; return "TARGET=\"\(apps.path)/Wyspa.app\"" }
                if line.hasPrefix("STAGING=") { replaced += 1; return "STAGING=\"\(apps.path)/.Wyspa-instalacja\"" }
                return String(line)
            }
            .joined(separator: "\n")
        // Wszystkie ścieżki skryptu biorą się z tych dwóch zmiennych — bez podmiany nie wolno go uruchomić.
        try #require(replaced == 2)
        func install(_ text: String, at path: String) throws {
            let url = sim.appendingPathComponent(path)
            try Data(text.utf8).write(to: url)
            try files.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }
        try install(script, at: "repo/scripts/install.sh")
        try install(Self.buildStub, at: "repo/scripts/build-app.sh")
        for (name, text) in Self.stubs { try install(text, at: "stubs/\(name)") }

        let process = Process()
        process.executableURL = sim.appendingPathComponent("repo/scripts/install.sh")
        process.arguments = ["--native"]
        process.environment = ["PATH": sim.appendingPathComponent("stubs").path + ":/usr/bin:/bin:/usr/sbin:/sbin", "SIM": sim.path]
        let result = try await run(process)
        let read = { (path: String) in
            (try? String(contentsOf: sim.appendingPathComponent(path), encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return Outcome(status: result.status, output: result.output, calls: read("calls") ?? "", running: read("state/wyspa"),
                       installed: read("Applications/Wyspa.app/Contents/version"),
                       stagingLeft: files.fileExists(atPath: apps.appendingPathComponent(".Wyspa-instalacja").path))
    }

    @Test("aktualizacja z poziomu Wyspy: zamyka ją, choć jest przodkiem skryptu, i uruchamia nową wersję")
    func updateFromApp() async throws {
        let outcome = try await simulate(["wyspa", "parent"])
        #expect(outcome.status == 0, "\(outcome.output)")
        #expect(outcome.running == "new")
        #expect(outcome.installed == "new")
        #expect(!outcome.stagingLeft)
        #expect(outcome.calls.contains("build-app.sh --native"))
        var reader = InstallOutputReader()
        reader.consume(Array(outcome.output.utf8))
        #expect(reader.stage == .restart)
    }

    @Test("nieudany build: działająca Wyspa zostaje nietknięta")
    func failedBuildKeepsRunningCopy() async throws {
        let outcome = try await simulate(["wyspa", "parent", "build_fails"])
        #expect(outcome.status != 0)
        #expect(outcome.running == "old")
        #expect(outcome.installed == "old")
        #expect(!outcome.calls.contains("pkill"))
    }

    @Test("Wyspa wyłączona: instalacja i uruchomienie bez zamykania")
    func notRunning() async throws {
        let outcome = try await simulate([])
        #expect(outcome.status == 0, "\(outcome.output)")
        #expect(outcome.running == "new")
        #expect(!outcome.calls.contains("pkill"))
    }
}

@Suite("Aktualizacje — instalator zakończony, zanim zamknął Wyspę")
@MainActor
struct InstallerExitTests {
    private let defaults = UserDefaults(suiteName: "wyspa.tests.updates.\(UUID().uuidString)")!

    private func git(_ arguments: [String], in directory: URL) async throws {
        let result = try await run("/usr/bin/git", ["-c", "user.email=t@t", "-c", "user.name=t"] + arguments, in: directory)
        try #require(result.status == 0, "git \(arguments.joined(separator: " ")): \(result.output)")
    }

    /// Projekt na gałęzi master, która śledzi lokalny „origin” (git pull się udaje), z podanym scripts/install.sh.
    private func makeProject(installScript: String) async throws -> URL {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("wyspa-installer-\(UUID().uuidString)")
        let work = base.appendingPathComponent("work")
        try FileManager.default.createDirectory(at: work.appendingPathComponent("scripts"), withIntermediateDirectories: true)
        let script = work.appendingPathComponent("scripts/install.sh")
        try Data(installScript.utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        try await git(["init", "-q", "-b", "master"], in: work)
        try await git(["add", "."], in: work)
        try await git(["commit", "-qm", "init"], in: work)
        try await git(["clone", "-q", "--bare", work.path, "origin.git"], in: base)
        try await git(["remote", "add", "origin", base.appendingPathComponent("origin.git").path], in: work)
        try await git(["fetch", "-q", "origin"], in: work)
        try await git(["branch", "-q", "--set-upstream-to=origin/master", "master"], in: work)
        return base
    }

    private func update(installScript: String) async throws -> UpdateService {
        let base = try await makeProject(installScript: installScript)
        defer { try? FileManager.default.removeItem(at: base) }
        let source = BuildSource(commit: String(repeating: "a", count: 40), branch: "master", repository: nil,
                                 path: base.appendingPathComponent("work").path, isDirty: false)
        let service = UpdateService(source: source, defaults: defaults, logURL: base.appendingPathComponent("aktualizacja.log"))
        service.update()
        #expect(service.status == .updating)
        let deadline = Date().addingTimeInterval(20)
        while service.status == .updating, Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
        return service
    }

    @Test("błąd skryptu: komunikat z etapem, na którym przerwał; bez potwierdzenia po restarcie")
    func scriptFails() async throws {
        let service = try await update(installScript: "#!/bin/sh\necho '▸ build: budowanie Wyspy'\nexit 3\n")
        guard case .failed(let message) = service.status else {
            Issue.record("status: \(service.status)")
            return
        }
        #expect(message.contains("„Budowanie nowej wersji”"), "\(message)")
        #expect(service.stage == nil)
        #expect(defaults.data(forKey: UpdateService.pendingKey) == nil)
    }

    @Test("skrypt skończył, a Wyspa działa: prośba o ręczny restart, potwierdzenie czeka na nową kopię")
    func scriptFinishedWithoutQuitting() async throws {
        let service = try await update(installScript: "#!/bin/sh\nexit 0\n")
        guard case .failed(let message) = service.status else {
            Issue.record("status: \(service.status)")
            return
        }
        #expect(message.contains("zamknij ją i uruchom ponownie"), "\(message)")
        #expect(defaults.data(forKey: UpdateService.pendingKey) != nil)
    }
}
