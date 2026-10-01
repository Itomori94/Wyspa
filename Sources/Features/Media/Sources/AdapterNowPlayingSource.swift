import Foundation
import WyspaCore

/// Now Playing dla całego systemu przez mediaremote-adapter (`/usr/bin/perl` + MediaRemoteAdapter.framework).
///
/// Strumień `stream` działa jako jeden proces potomny; aktualizacje przychodzą tylko przy zmianach.
@MainActor
final class AdapterNowPlayingSource: NowPlayingSource {
    private static let debounceMilliseconds = 100
    private static let maxRestarts = 3

    let kind = MediaSourceKind.adapter
    private let bundle: AdapterBundle
    private let log = Log.logger("media.adapter")
    private var process: Process?
    private var isStopping = false
    private var restarts = 0
    private var onUpdate: (@MainActor (NowPlaying?) -> Void)?
    private var onFailure: (@MainActor (String) -> Void)?

    init(bundle: AdapterBundle) {
        self.bundle = bundle
    }

    func start(onUpdate: @escaping @MainActor (NowPlaying?) -> Void, onFailure: @escaping @MainActor (String) -> Void) {
        self.onUpdate = onUpdate
        self.onFailure = onFailure
        isStopping = false
        launch()
    }

    func stop() {
        isStopping = true
        process?.terminate()
        process = nil
    }

    func send(_ command: MediaCommand) {
        let bundle = bundle
        Task {
            let outcome = await AdapterRunner.run(bundle, ["send", String(command.adapterID)], timeout: AdapterRunner.commandTimeout)
            if outcome.exitCode != 0 { log.error("send \(command.adapterID) zwrócił kod \(outcome.exitCode)") }
        }
    }

    func seek(to seconds: TimeInterval) {
        let bundle = bundle
        let micros = String(Int64(max(0, seconds) * 1_000_000))
        Task {
            let outcome = await AdapterRunner.run(bundle, ["seek", micros], timeout: AdapterRunner.commandTimeout)
            if outcome.exitCode != 0 { log.error("seek zwrócił kod \(outcome.exitCode)") }
        }
    }

    private func launch() {
        let process = Process()
        let output = Pipe()
        process.executableURL = AdapterBundle.perl
        process.arguments = bundle.arguments([
            "stream", "--no-diff", "--micros", "--debounce=\(Self.debounceMilliseconds)",
        ])
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        let reader = StreamReader { [weak self] line in
            Task { @MainActor in self?.handle(line) }
        }
        output.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
            } else {
                reader.consume(chunk)
            }
        }
        process.terminationHandler = { [weak self] finished in
            let status = finished.terminationStatus
            Task { @MainActor in self?.processEnded(status: status) }
        }

        do {
            try process.run()
            self.process = process
        } catch {
            onFailure?("Nie udało się uruchomić adaptera: \(error.localizedDescription)")
        }
    }

    private func handle(_ line: Data) {
        do {
            switch try AdapterPayloadParser.parse(line: line) {
            case .nowPlaying(let nowPlaying): onUpdate?(nowPlaying)
            case .nothingPlaying: onUpdate?(nil)
            }
            restarts = 0
        } catch {
            log.error("Nieczytelna linia z adaptera: \(String(describing: error))")
        }
    }

    private func processEnded(status: Int32) {
        process = nil
        guard !isStopping else { return }
        guard restarts < Self.maxRestarts else {
            onFailure?("Adapter kończy pracę (kod \(status)) mimo \(Self.maxRestarts) ponownych uruchomień.")
            return
        }
        restarts += 1
        log.error("Adapter zakończył się kodem \(status), ponowne uruchomienie \(self.restarts)/\(Self.maxRestarts)")
        launch()
    }
}

/// Składa linie z kawałków danych czytanych na wątku potoku.
private final class StreamReader: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = LineBuffer()
    private let onLine: @Sendable (Data) -> Void

    init(onLine: @escaping @Sendable (Data) -> Void) {
        self.onLine = onLine
    }

    func consume(_ chunk: Data) {
        let lines = lock.withLock { buffer.append(chunk) }
        lines.forEach(onLine)
    }
}
