import Foundation
import Testing
@testable import WyspaClaudeMonitor
@testable import WyspaHookKit

@Suite("Protokół hooka")
struct HookProtocolTests {
    private func envelope(_ event: [String: Any], wantsReply: Bool = false) -> Data {
        try! JSONSerialization.data(withJSONObject: [
            "v": 1, "event": event, "claudePid": 4242, "bundleID": "com.googlecode.iterm2", "wantsReply": wantsReply,
        ] as [String: Any])
    }

    @Test("Prośba o uprawnienie z poleceniem Bash")
    func permissionRequest() throws {
        let data = envelope([
            "hook_event_name": "PermissionRequest", "session_id": "s1", "cwd": "/Users/x/Projekty/Wyspa",
            "tool_name": "Bash", "tool_input": ["command": "rm -rf build", "description": "Czyszczenie"],
            "tool_use_id": "toolu_1",
        ], wantsReply: true)
        let parsed = try HookProtocol.parse(data)
        #expect(parsed.wantsReply && parsed.claudePID == 4242 && parsed.bundleID == "com.googlecode.iterm2")
        #expect(parsed.event.name == "PermissionRequest" && parsed.event.toolInput?.command == "rm -rf build")
        #expect(parsed.event.toolInput?.summary == "rm -rf build")
    }

    @Test("Edycja pliku i wiele edycji")
    func editInputs() throws {
        let data = envelope([
            "hook_event_name": "PreToolUse", "session_id": "s1", "tool_name": "MultiEdit",
            "tool_input": ["file_path": "/a/b/Plik.swift", "edits": [["old_string": "a", "new_string": "b"]]],
        ])
        let input = try #require(try HookProtocol.parse(data).event.toolInput)
        #expect(input.summary == "Plik.swift")
        #expect(input.edits.count == 1 && input.edits[0].new == "b")
    }

    @Test("Błędne wiadomości")
    func errors() {
        #expect(throws: HookProtocol.ParseError.notJSON) { try HookProtocol.parse(Data("x".utf8)) }
        #expect(throws: HookProtocol.ParseError.unsupportedVersion(2)) {
            try HookProtocol.parse(try JSONSerialization.data(withJSONObject: ["v": 2]))
        }
        #expect(throws: HookProtocol.ParseError.missingField("session_id")) {
            try HookProtocol.parse(envelope(["hook_event_name": "Stop"]))
        }
    }

    @Test("Wyjście hooka: allow, deny z powodem, ask bez wyjścia")
    func hookOutput() throws {
        #expect(HookProtocol.hookOutput(for: .ask, message: nil) == nil)
        let allow = try #require(HookProtocol.hookOutput(for: .allow, message: nil))
        #expect(allow.contains(#""behavior":"allow""#) && allow.contains("PermissionRequest"))
        let deny = try #require(HookProtocol.hookOutput(for: .deny, message: "Nie teraz"))
        let object = try JSONSerialization.jsonObject(with: Data(deny.utf8)) as? [String: Any]
        let decision = (object?["hookSpecificOutput"] as? [String: Any])?["decision"] as? [String: Any]
        #expect(decision?["behavior"] as? String == "deny" && decision?["message"] as? String == "Nie teraz")
    }

    @Test("Odpowiedź Wyspy to jedna linia JSON")
    func reply() {
        let data = HookProtocol.reply(.deny, message: "x")
        #expect(data.last == UInt8(ascii: "\n"))
        #expect(String(data: data, encoding: .utf8)?.contains("\"deny\"") == true)
    }
}

@Suite("Stan sesji Claude Code")
struct SessionStoreTests {
    let t0 = Date(timeIntervalSince1970: 0)

    private func envelope(_ name: String, session: String = "s1", tool: String? = nil, input: [String: Any]? = nil,
                          extra: [String: Any] = [:], pid: Int32 = 100) -> HookProtocol.Envelope {
        var event: [String: Any] = ["hook_event_name": name, "session_id": session, "cwd": "/Users/x/Projekty/Wyspa"]
        if let tool { event["tool_name"] = tool }
        if let input { event["tool_input"] = input }
        event.merge(extra) { _, new in new }
        return HookProtocol.Envelope(event: try! HookEvent.parse(event), claudePID: pid, bundleID: nil,
                                     termProgram: nil, wantsReply: name == "PermissionRequest")
    }

    @Test("Cykl: start, praca, narzędzie, prośba, decyzja, koniec")
    func lifecycle() {
        var store = SessionStore()
        var alert: SessionAlert?
        (store, _) = store.applying(envelope("SessionStart"), at: t0)
        #expect(store.sessions["s1"]?.state == .idle)
        #expect(store.sessions["s1"]?.projectName == "Wyspa")
        (store, _) = store.applying(envelope("UserPromptSubmit"), at: t0)
        #expect(store.sessions["s1"]?.state == .working)
        (store, _) = store.applying(envelope("PreToolUse", tool: "Bash", input: ["command": "swift test"]), at: t0)
        #expect(store.sessions["s1"]?.state == .runningTool("Bash"))
        #expect(store.sessions["s1"]?.recentTools == ["Bash: swift test"])
        (store, alert) = store.applying(envelope("PermissionRequest", tool: "Bash"), at: t0)
        #expect(store.sessions["s1"]?.state == .waitingForPermission && alert == .needsInput)
        store = store.resolvingPermission(for: "s1", at: t0)
        #expect(store.sessions["s1"]?.state == .working)
        (store, alert) = store.applying(envelope("Stop", extra: ["last_assistant_message": "Gotowe."]), at: t0)
        #expect(store.sessions["s1"]?.state == .finished && alert == .finished)
        #expect(store.sessions["s1"]?.lastMessage == "Gotowe.")
        (store, _) = store.applying(envelope("SessionEnd"), at: t0)
        #expect(store.sessions.isEmpty)
    }

    @Test("Powiadomienie: sesja czeka na użytkownika")
    func notification() {
        let (store, alert) = SessionStore().applying(envelope("Notification", extra: ["message": "Claude czeka na odpowiedź"]), at: t0)
        #expect(store.sessions["s1"]?.state == .waitingForInput("Claude czeka na odpowiedź"))
        #expect(alert == .needsInput)
    }

    @Test("Ostatnie narzędzia z limitem, długie opisy skracane")
    func recentTools() {
        var store = SessionStore()
        for index in 0..<8 {
            (store, _) = store.applying(envelope("PreToolUse", tool: "Read", input: ["file_path": "/a/plik\(index).swift"]), at: t0)
        }
        #expect(store.sessions["s1"]?.recentTools.count == ClaudeSession.recentToolsLimit)
        #expect(store.sessions["s1"]?.recentTools.last == "Read: plik7.swift")
        (store, _) = store.applying(envelope("PreToolUse", tool: "Bash", input: ["command": String(repeating: "x", count: 100)]), at: t0)
        #expect((store.sessions["s1"]?.recentTools.last?.count ?? 0) <= "Bash: ".count + 40)
    }

    @Test("Wiele sesji: wymagające uwagi na górze, potem najświeższe")
    func ordering() {
        var store = SessionStore()
        (store, _) = store.applying(envelope("UserPromptSubmit", session: "a"), at: t0)
        (store, _) = store.applying(envelope("UserPromptSubmit", session: "b"), at: t0.addingTimeInterval(10))
        (store, _) = store.applying(envelope("Notification", session: "a"), at: t0.addingTimeInterval(5))
        #expect(store.ordered.map(\.id) == ["a", "b"])
    }

    @Test("Martwe procesy znikają, nieznany PID zostaje")
    func deadSessions() {
        var store = SessionStore()
        (store, _) = store.applying(envelope("UserPromptSubmit", session: "żywa", pid: 1), at: t0)
        (store, _) = store.applying(envelope("UserPromptSubmit", session: "martwa", pid: 2), at: t0)
        #expect(Set(store.removingDead { $0 == 1 }.sessions.keys) == ["żywa"])
    }
}

@Suite("Diff linii")
struct LineDiffTests {
    @Test("Zmiana jednej linii w środku")
    func middleChange() {
        let diff = LineDiff.lines(from: "a\nb\nc", to: "a\nB\nc")
        #expect(diff == [.same("a"), .removed("b"), .added("B"), .same("c")])
    }

    @Test("Nowy plik i usunięcie całości")
    func edges() {
        #expect(LineDiff.lines(from: "", to: "x\ny") == [.added("x"), .added("y")])
        #expect(LineDiff.lines(from: "x", to: "") == [.removed("x")])
    }

    @Test("Bardzo duże wejście nie liczy pełnej macierzy")
    func large() {
        let big = (0..<1000).map(String.init).joined(separator: "\n")
        let diff = LineDiff.lines(from: big, to: big + "\nx")
        #expect(diff.count == 2001)
    }
}

@Suite("Instalator hooków")
struct HookInstallerTests {
    let helper = "/Applications/Wyspa.app/Contents/Helpers/wyspa-hook"

    /// Ustawienia jak u użytkownika: inne klucze i cudze hooki na tych samych zdarzeniach.
    var existing: [String: Any] {
        [
            "model": "opus",
            "permissions": ["allow": ["Bash(git status)"]],
            "hooks": [
                "PreToolUse": [["matcher": "Bash", "hooks": [["type": "command", "command": "~/.claude/inne/guard.sh"]]]],
                "Stop": [["matcher": "", "hooks": [["type": "command", "command": "pnpm build"]]]],
            ],
        ]
    }

    @Test("Instalacja dopisuje wszystkie zdarzenia i nie rusza cudzych hooków ani innych kluczy")
    func install() {
        let installed = HookInstaller.installing(into: existing, helperPath: helper, decisionTimeout: 300)
        #expect(HookInstaller.isInstalled(in: installed))
        #expect(installed["model"] as? String == "opus")
        let hooks = installed["hooks"] as? [String: Any]
        let pre = hooks?["PreToolUse"] as? [[String: Any]]
        #expect(pre?.count == 2)
        #expect((pre?[0]["hooks"] as? [[String: Any]])?[0]["command"] as? String == "~/.claude/inne/guard.sh")
        let permission = (hooks?["PermissionRequest"] as? [[String: Any]])?[0]["hooks"] as? [[String: Any]]
        #expect(permission?[0]["args"] as? [String] == ["--decision-timeout", "300"])
        #expect(permission?[0]["timeout"] as? Int == 315)
    }

    @Test("Ponowna instalacja nie dubluje wpisów")
    func idempotent() {
        let once = HookInstaller.installing(into: existing, helperPath: helper, decisionTimeout: 300)
        let twice = HookInstaller.installing(into: once, helperPath: helper, decisionTimeout: 600)
        let pre = (twice["hooks"] as? [String: Any])?["PreToolUse"] as? [[String: Any]]
        #expect(pre?.count == 2)
    }

    @Test("Deinstalacja przywraca stan sprzed instalacji")
    func uninstallRestores() {
        let installed = HookInstaller.installing(into: existing, helperPath: helper, decisionTimeout: 300)
        let removed = HookInstaller.uninstalling(from: installed)
        #expect(!HookInstaller.isInstalled(in: removed))
        #expect(NSDictionary(dictionary: removed).isEqual(to: existing))
    }

    @Test("Deinstalacja z pustych ustawień usuwa klucz hooks")
    func uninstallEmpty() {
        let installed = HookInstaller.installing(into: [:], helperPath: helper, decisionTimeout: 300)
        #expect(HookInstaller.uninstalling(from: installed).isEmpty)
    }

    @Test("Zapis robi kopię zapasową, nieczytelny plik nie jest nadpisywany")
    func fileHandling() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("wyspa-hooks-\(UUID().uuidString)")
        let url = dir.appendingPathComponent("settings.json")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("{\"model\":\"opus\"}".utf8).write(to: url)
        let backup = try HookInstaller.write(HookInstaller.installing(into: try HookInstaller.read(url), helperPath: helper, decisionTimeout: 300), to: url)
        #expect(backup.map { FileManager.default.fileExists(atPath: $0.path) } == true)
        #expect(HookInstaller.isInstalled(in: try HookInstaller.read(url)))

        try Data("{nie json".utf8).write(to: url)
        #expect(throws: HookInstaller.InstallError.self) { try HookInstaller.read(url) }
        #expect(try Data(contentsOf: url) == Data("{nie json".utf8))
    }
}
