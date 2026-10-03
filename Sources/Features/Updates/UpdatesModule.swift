import AppKit
import SwiftUI
import WyspaCore
import WyspaUI

/// Aktualizacje: porównanie zainstalowanej wersji z GitHubem i aktualizacja jednym przyciskiem
/// (`git pull --ff-only` + `scripts/install.sh` w katalogu, z którego zbudowano aplikację).
@MainActor
@Observable
public final class UpdatesModule: IslandModule {
    public static let descriptor = ModuleDescriptor(
        id: "updates",
        name: "Aktualizacje",
        summary: "Sprawdza, czy na GitHubie jest nowsza wersja Wyspy, pokazuje listę zmian i aktualizuje jednym przyciskiem.",
        symbol: "arrow.triangle.2.circlepath",
        content: .neutral,
        providesPage: false
    )

    public enum Status: Equatable {
        case idle
        case checking
        case upToDate
        case available(UpdateCheck)
        case updating
        case failed(String)
    }

    /// Sprawdzanie przy starcie i co 6 godzin — jedno zaplanowane zadanie, tylko gdy moduł jest włączony.
    static let checkInterval: Duration = .seconds(6 * 3600)
    static let cardDisplay: Duration = .seconds(8)
    private static let announcedKey = "announcedCommit"

    public let source: BuildSource?
    public private(set) var status: Status = .idle
    public private(set) var lastChecked: Date?
    /// Krótka karta w wyspie po znalezieniu nowej wersji (raz na wersję).
    public private(set) var announcement: UpdateCheck?

    @ObservationIgnored private let context: ModuleContext
    @ObservationIgnored private var scheduleTask: Task<Void, Never>?
    @ObservationIgnored private var cardTask: Task<Void, Never>?
    @ObservationIgnored private let session = URLSession(configuration: .ephemeral)
    @ObservationIgnored private let log = Log.logger("updates")

    public required init(context: ModuleContext) {
        self.context = context
        source = BuildSource.from(infoDictionary: Bundle.main.infoDictionary ?? [:])
    }

    public func activate() async throws {
        scheduleTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.check()
                try? await Task.sleep(for: Self.checkInterval)
            }
        }
    }

    public func deactivate() {
        scheduleTask?.cancel()
        cardTask?.cancel()
        scheduleTask = nil
        announcement = nil
    }

    public var liveActivity: LiveActivity? {
        guard let announcement else { return nil }
        return LiveActivity(id: "updates", priority: .status, accent: .blue, wingWidth: 46, detailHeight: 46) {
            Image(systemName: "arrow.down.circle.fill").font(.system(size: 14, weight: .semibold)).foregroundStyle(.blue)
        } trailing: {
            Text("\(announcement.changes.count)").font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(.blue)
        } detail: {
            UpdateCard(check: announcement)
        }
    }

    public func makeExpandedView() -> AnyView? { nil }
    public func makeSettingsView() -> AnyView? { AnyView(UpdatesSettingsView(module: self)) }

    // MARK: - Sprawdzanie

    func check() async {
        guard let source, let repository = source.repository,
              let url = repository.compareURL(from: source.commit, to: "master")
        else {
            status = .failed("Ta kopia Wyspy nie została zbudowana z repozytorium git — nie ma z czym porównać.")
            return
        }
        status = .checking
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await session.data(for: request)
            lastChecked = Date()
            guard let http = response as? HTTPURLResponse, http.statusCode == 200, let result = UpdateCheck.parse(data) else {
                status = .failed("GitHub zwrócił nieoczekiwaną odpowiedź.")
                return
            }
            status = result.isAvailable ? .available(result) : .upToDate
            if result.isAvailable { announceIfNew(result) }
        } catch {
            status = .failed("Brak połączenia z GitHubem.")
        }
    }

    /// Karta w wyspie tylko raz na nową wersję.
    private func announceIfNew(_ result: UpdateCheck) {
        guard let latest = result.latestCommit,
              context.settings.value(Self.announcedKey, default: "") != latest
        else { return }
        context.settings.set(latest, for: Self.announcedKey)
        withAnimation { announcement = result }
        cardTask?.cancel()
        cardTask = Task { [weak self] in
            try? await Task.sleep(for: Self.cardDisplay)
            guard !Task.isCancelled else { return }
            withAnimation { self?.announcement = nil }
        }
    }

    // MARK: - Aktualizacja

    /// `git pull --ff-only` i `scripts/install.sh` w katalogu źródeł. Instalacja zamyka tę kopię Wyspy i uruchamia nową;
    /// przebieg trafia do ~/Library/Logs/Wyspa/aktualizacja.log.
    func update() {
        guard let source, !source.path.isEmpty else { return }
        status = .updating
        let path = source.path
        Task.detached { [weak self] in
            let problem = Self.prepare(path: path)
            await MainActor.run {
                if let problem {
                    self?.status = .failed(problem)
                } else {
                    self?.launchInstall(path: path)
                }
            }
        }
    }

    /// Sprawdza katalog źródeł i pobiera zmiany; zwraca opis problemu albo nil.
    nonisolated static func prepare(path: String) -> String? {
        guard FileManager.default.fileExists(atPath: path + "/scripts/install.sh") else {
            return "Nie ma katalogu projektu (\(path)) — sklonuj repozytorium i zbuduj Wyspę od nowa."
        }
        let branch = run(["-C", path, "rev-parse", "--abbrev-ref", "HEAD"])
        guard branch.status == 0, branch.output == "master" else {
            return "W katalogu projektu aktywna jest gałąź „\(branch.output)”, a nie master — zaktualizuj ręcznie."
        }
        let changes = run(["-C", path, "status", "--porcelain"])
        guard changes.status == 0, changes.output.isEmpty else {
            return "W katalogu projektu są niezapisane zmiany — zapisz je albo cofnij, zanim zaktualizujesz."
        }
        let pull = run(["-C", path, "pull", "--ff-only"])
        guard pull.status == 0 else { return "Nie udało się pobrać zmian (git pull): \(pull.output)" }
        return nil
    }

    nonisolated private static func run(_ arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return (-1, error.localizedDescription)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func launchInstall(path: String) {
        let logs = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("Logs/Wyspa")
        try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        let logURL = logs.appendingPathComponent("aktualizacja.log")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path + "/scripts/install.sh")
        process.currentDirectoryURL = URL(fileURLWithPath: path)
        if let handle = try? FileHandle(forWritingTo: logURL) {
            process.standardOutput = handle
            process.standardError = handle
        }
        do {
            // Skrypt instalacji zamknie tę kopię Wyspy; proces potomny działa dalej i uruchamia nową wersję.
            try process.run()
            log.notice("Aktualizacja uruchomiona")
        } catch {
            status = .failed("Nie udało się uruchomić instalacji: \(error.localizedDescription)")
        }
    }
}
