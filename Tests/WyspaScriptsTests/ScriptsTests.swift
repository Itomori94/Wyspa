import Foundation
import Testing
import WyspaCore
@testable import WyspaScripts

@Suite("Moduł Skrypty — stan")
struct ScriptsStateTests {
    let start = Date(timeIntervalSince1970: 1_000_000)

    @Test("Karty: pierwsza od razu, kolejne czekają (limit), przejście do następnej")
    func notices() {
        var state = ScriptsState()
        for index in 0..<8 { state = state.applying(.notify(title: "t\(index)", body: nil), at: start) }
        #expect(state.notice?.title == "t0")
        #expect(state.waiting.map(\.title) == ["t3", "t4", "t5", "t6", "t7"])
        state = state.advancingNotice()
        #expect(state.notice?.title == "t3" && state.waiting.count == 4)
    }

    @Test("Postęp: aktualizacja w miejscu, opis zostaje, 100% = ukończony")
    func progressUpdates() {
        var state = ScriptsState()
            .applying(.progress(id: "a", fraction: 0.1, label: "Build"), at: start)
            .applying(.progress(id: "b", fraction: nil, label: nil), at: start)
            .applying(.progress(id: "a", fraction: 0.5, label: nil), at: start)
        #expect(state.progress.map(\.id) == ["a", "b"])
        #expect(state.progress[0].label == "Build" && state.progress[0].fraction == 0.5)
        #expect(state.overallFraction == 0.5, "nieokreślony postęp nie zaniża średniej")
        state = state.applying(.progress(id: "a", fraction: 1, label: nil), at: start)
        #expect(state.progress[0].isFinished)
    }

    @Test("Koniec: znany postęp ukończony, nieznany bez zmian")
    func done() {
        let state = ScriptsState().applying(.progress(id: "a", fraction: 0.3, label: "X"), at: start)
        #expect(state.applying(.done(id: "zzz"), at: start) == state)
        let finished = state.applying(.done(id: "a"), at: start)
        #expect(finished.progress.first?.isFinished == true && finished.progress.first?.label == "X")
    }

    @Test("Przedawnienie po 15 minutach bez aktualizacji")
    func expiry() {
        let state = ScriptsState()
            .applying(.progress(id: "old", fraction: 0.2, label: nil), at: start)
            .applying(.progress(id: "new", fraction: 0.2, label: nil), at: start.addingTimeInterval(600))
        #expect(state.nextExpiry == start.addingTimeInterval(ScriptsState.staleAfter))
        let later = state.expiring(at: start.addingTimeInterval(ScriptsState.staleAfter + 1))
        #expect(later.progress.map(\.id) == ["new"])
    }

    @Test("Limit postępów: najstarsze odpadają")
    func progressLimit() {
        var state = ScriptsState()
        for index in 0..<9 { state = state.applying(.progress(id: "p\(index)", fraction: 0, label: nil), at: start) }
        #expect(state.progress.count == ScriptsState.maxProgress && state.progress.first?.id == "p3")
    }

    @Test("Tekst procentu")
    func percent() {
        #expect(ScriptsState.percentText(0.429) == "42%")
        #expect(ScriptsState.percentText(nil) == "…")
    }
}

@Suite("Instalacja komendy wyspa")
struct CommandInstallerTests {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("wyspa-cli-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("Instaluje, wykrywa starszą wersję i usuwa tylko własny plik")
    func lifecycle() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("wyspa-source")
        let target = directory.appendingPathComponent("bin/wyspa")
        try Data("#!/bin/sh\n# wyspa-cli v1\n".utf8).write(to: source)
        #expect(CommandInstaller.status(source: source, at: target) == .missing)
        try CommandInstaller.install(source: source, at: target)
        #expect(CommandInstaller.status(source: source, at: target) == .installed)
        let mode = try FileManager.default.attributesOfItem(atPath: target.path)[.posixPermissions] as? Int
        #expect(mode == 0o755)
        try Data("#!/bin/sh\n# wyspa-cli v2\n".utf8).write(to: source)
        #expect(CommandInstaller.status(source: source, at: target) == .outdated)
        try CommandInstaller.uninstall(at: target)
        #expect(!FileManager.default.fileExists(atPath: target.path))
    }

    @Test("Cudzy plik nie jest nadpisywany ani usuwany")
    func foreignFile() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("wyspa-source")
        let target = directory.appendingPathComponent("wyspa")
        try Data("#!/bin/sh\n# wyspa-cli\n".utf8).write(to: source)
        let foreign = Data("#!/bin/sh\necho inny program\n".utf8)
        try foreign.write(to: target)
        #expect(CommandInstaller.status(source: source, at: target) == .foreign)
        #expect(throws: CommandInstaller.InstallError.foreignFile(target.path)) {
            try CommandInstaller.install(source: source, at: target)
        }
        try CommandInstaller.uninstall(at: target)
        #expect(try Data(contentsOf: target) == foreign)
    }

    @Test("Skrypt w repozytorium ma znacznik i jest poprawnym sh")
    func bundledScript() async throws {
        let script = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/wyspa")
        #expect(CommandInstaller.isOurs(try Data(contentsOf: script)))
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-n", script.path]
        let status = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int32, Error>) in
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do { try process.run() } catch { continuation.resume(throwing: error) }
        }
        #expect(status == 0)
    }
}
