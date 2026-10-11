import Foundation
import Observation
import WyspaCore

/// Sprawdzanie i instalacja aktualizacji — wspólne dla modułu Aktualizacje i pozycji „Sprawdź aktualizacje…”
/// w menu Wyspy (działa także przy wyłączonym module).
@MainActor
@Observable
public final class UpdateService {
    public static let shared = UpdateService(source: BuildSource.from(infoDictionary: Bundle.main.infoDictionary ?? [:]))
    static let pendingKey = "updates.pending"

    /// Zapisane przed instalacją: z jakiej wersji i jakie zmiany — po ponownym uruchomieniu Wyspa potwierdza wynik.
    struct PendingUpdate: Codable, Equatable {
        let fromCommit: String
        let titles: [String]
    }

    /// Wynik aktualizacji uruchomionej w poprzedniej kopii Wyspy.
    public enum FinishedUpdate: Equatable {
        case updated(to: String, titles: [String])
        case unchanged
    }

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
    /// Etap trwającej aktualizacji i od kiedy trwa (okienko postępu); nil poza aktualizacją.
    public private(set) var stage: UpdateStage?
    public private(set) var stageStarted: Date?
    /// Przebieg ostatniej aktualizacji (wyjście scripts/install.sh).
    public let logURL: URL

    nonisolated static let defaultLogURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Logs/Wyspa/aktualizacja.log")

    @ObservationIgnored private let session = URLSession(configuration: .ephemeral)
    @ObservationIgnored private let log = Log.logger("updates")

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var installer: Process?
    @ObservationIgnored private var logWatch: DispatchSourceFileSystemObject?
    @ObservationIgnored private var logHandle: FileHandle?
    @ObservationIgnored private var output = InstallOutputReader()

    init(source: BuildSource?, defaults: UserDefaults = .standard, logURL: URL = UpdateService.defaultLogURL) {
        self.source = source
        self.defaults = defaults
        self.logURL = logURL
    }

    /// Jednorazowo po starcie: czy poprzednia kopia Wyspy zaczęła aktualizację i czy ta wersja jest już nowa.
    public func consumeFinishedUpdate() -> FinishedUpdate? {
        guard let data = defaults.data(forKey: Self.pendingKey) else { return nil }
        defaults.removeObject(forKey: Self.pendingKey)
        guard let pending = try? JSONDecoder().decode(PendingUpdate.self, from: data), let source else { return nil }
        guard source.commit != pending.fromCommit else { return .unchanged }
        status = .upToDate
        return .updated(to: source.shortCommit, titles: pending.titles)
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
    /// przebieg trafia do ~/Library/Logs/Wyspa/aktualizacja.log, a etapy do `stage` (okienko postępu).
    public func update() {
        guard !isBusy, let source, !source.path.isEmpty else { return }
        let titles: [String] = if case .available(let check) = status { check.changes.map(\.title) } else { [] }
        status = .updating
        enter(.fetch)
        let path = source.path
        Task.detached { [weak self] in
            let problem = Self.prepare(path: path)
            await MainActor.run {
                if let problem {
                    self?.fail(problem)
                } else {
                    self?.launchInstall(path: path, pending: PendingUpdate(fromCommit: source.commit, titles: titles))
                }
            }
        }
    }

    private func enter(_ stage: UpdateStage) {
        guard stage != self.stage else { return }
        self.stage = stage
        stageStarted = Date()
    }

    private func fail(_ message: String) {
        status = .failed(message)
        stage = nil
        stageStarted = nil
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

    private func launchInstall(path: String, pending: PendingUpdate) {
        try? FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let header = "Aktualizacja Wyspy \(Date().formatted(.iso8601)) z wersji \(pending.fromCommit.prefix(7))\n"
        FileManager.default.createFile(atPath: logURL.path, contents: Data(header.utf8))
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path + "/scripts/install.sh")
        // Tylko bieżąca architektura: build trwa mniej więcej o połowę krócej, a aplikacja działa i tak tylko na tym Macu.
        process.arguments = ["--native"]
        process.currentDirectoryURL = URL(fileURLWithPath: path)
        // Wyjście do pliku, nie do potoku: po zamknięciu Wyspy zapis do potoku bez czytelnika przerwałby skrypt (SIGPIPE).
        if let handle = try? FileHandle(forWritingTo: logURL) {
            _ = try? handle.seekToEnd()
            process.standardOutput = handle
            process.standardError = handle
        }
        process.terminationHandler = { [weak self] finished in
            let code = finished.terminationStatus
            Task { @MainActor in self?.installerExited(code: code) }
        }
        if let data = try? JSONEncoder().encode(pending) { defaults.set(data, forKey: Self.pendingKey) }
        do {
            // Skrypt zamknie tę kopię Wyspy; proces potomny działa dalej i uruchamia nową wersję.
            try process.run()
            installer = process
            watchLog()
            log.notice("Aktualizacja uruchomiona")
        } catch {
            defaults.removeObject(forKey: Self.pendingKey)
            fail("Nie udało się uruchomić instalacji: \(error.localizedDescription)")
        }
    }

    /// Skrypt skończył, a ta kopia Wyspy wciąż działa — udana instalacja zamyka ją wcześniej. Bez tego status
    /// zostawał „Aktualizowanie…” na zawsze.
    private func installerExited(code: Int32) {
        installer = nil
        stopWatchingLog()
        guard status == .updating else { return }
        log.error("Instalacja zakończona kodem \(code), a Wyspa nie została zamknięta")
        if code == 0 {
            // Nowa wersja jest na dysku: potwierdzenie (`updates.pending`) pokaże się po ręcznym restarcie.
            fail("Nowa wersja jest zainstalowana, ale ta kopia Wyspy się nie zamknęła — zamknij ją i uruchom ponownie.")
        } else {
            defaults.removeObject(forKey: Self.pendingKey)
            let step = stage.map { " na etapie „\($0.title)”" } ?? ""
            let path = (logURL.path as NSString).abbreviatingWithTildeInPath
            fail("Instalacja nie powiodła się\(step) — działa poprzednia wersja. Przebieg: \(path).")
        }
    }

    /// Etapy ogłaszane przez skrypt czytane z przebiegu na bieżąco (zdarzenia pliku, bez odpytywania).
    private func watchLog() {
        let descriptor = open(logURL.path, O_RDONLY | O_CLOEXEC)
        guard descriptor >= 0 else { return }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        output = InstallOutputReader()
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .extend],
                                                               queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.readLog() }
        }
        // Jeden deskryptor do zdarzeń i odczytu; zamykany tylko tutaj.
        source.setCancelHandler { close(descriptor) }
        logHandle = handle
        logWatch = source
        source.resume()
        // Zapis sprzed rejestracji źródła nie wywoła zdarzenia.
        readLog()
    }

    private func readLog() {
        guard let data = try? logHandle?.readToEnd() else { return }
        output.consume(data)
        if status == .updating, let announced = output.stage { enter(announced) }
    }

    /// Ostatni odczyt (szybko przerwany skrypt mógł zdążyć ogłosić etap), potem koniec obserwacji.
    private func stopWatchingLog() {
        readLog()
        logWatch?.cancel()
        logWatch = nil
        logHandle = nil
    }
}
