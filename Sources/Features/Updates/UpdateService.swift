import Foundation
import Observation
import WyspaCore

/// Sprawdzanie i instalacja aktualizacji — wspólne dla modułu Aktualizacje i pozycji „Sprawdź aktualizacje…”
/// w menu Wyspy (działa także przy wyłączonym module).
@MainActor
@Observable
public final class UpdateService {
    public static let shared = UpdateService(source: BuildSource.from(infoDictionary: Bundle.main.infoDictionary ?? [:]))

    public enum Status: Equatable {
        case idle
        case checking
        case upToDate
        case available(UpdateCheck)
        case updating
        case failed(String)
    }

    public let source: BuildSource?
    public private(set) var status: Status = .idle
    public private(set) var lastChecked: Date?

    @ObservationIgnored private let session = URLSession(configuration: .ephemeral)
    @ObservationIgnored private let log = Log.logger("updates")

    init(source: BuildSource?) {
        self.source = source
    }

    public var isBusy: Bool { status == .checking || status == .updating }

    /// Porównuje zainstalowany commit z `master` na GitHubie; wynik też w `status`.
    @discardableResult
    public func check() async -> Status {
        guard !isBusy else { return status }
        guard let source, let repository = source.repository,
              let url = repository.compareURL(from: source.commit, to: "master")
        else {
            status = .failed("Ta kopia Wyspy nie została zbudowana z repozytorium git — nie ma z czym porównać.")
            return status
        }
        status = .checking
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await session.data(for: request)
            lastChecked = Date()
            if let http = response as? HTTPURLResponse, http.statusCode == 200, let result = UpdateCheck.parse(data) {
                status = result.isAvailable ? .available(result) : .upToDate
            } else {
                status = .failed("GitHub zwrócił nieoczekiwaną odpowiedź.")
            }
        } catch {
            status = .failed("Brak połączenia z GitHubem.")
        }
        return status
    }

    /// `git pull --ff-only` i `scripts/install.sh` w katalogu źródeł. Instalacja zamyka tę kopię Wyspy i uruchamia nową;
    /// przebieg trafia do ~/Library/Logs/Wyspa/aktualizacja.log.
    public func update() {
        guard !isBusy, let source, !source.path.isEmpty else { return }
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
        let branch = git(["-C", path, "rev-parse", "--abbrev-ref", "HEAD"])
        guard branch.status == 0, branch.output == "master" else {
            return "W katalogu projektu aktywna jest gałąź „\(branch.output)”, a nie master — zaktualizuj ręcznie."
        }
        let changes = git(["-C", path, "status", "--porcelain"])
        guard changes.status == 0, changes.output.isEmpty else {
            return "W katalogu projektu są niezapisane zmiany — zapisz je albo cofnij, zanim zaktualizujesz."
        }
        let pull = git(["-C", path, "pull", "--ff-only"])
        guard pull.status == 0 else { return "Nie udało się pobrać zmian (git pull): \(pull.output)" }
        return nil
    }

    nonisolated private static func git(_ arguments: [String]) -> (status: Int32, output: String) {
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
