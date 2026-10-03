import AppKit
import WyspaCore

/// Tryb awaryjny: Muzyka i Spotify przez AppleScript.
///
/// Nie odpytuje w pętli: odświeża stan po powiadomieniach rozproszonych odtwarzaczy
/// i po uruchomieniu lub zamknięciu aplikacji. Wymaga zgody na automatyzację (system pyta przy pierwszym użyciu).
@MainActor
final class AppleScriptNowPlayingSource: NowPlayingSource {
    let kind = MediaSourceKind.appleScript
    private let players: [ScriptablePlayer]
    private let runner = ScriptRunner()
    private let log = Log.logger("media.applescript")
    private var distributedObservers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var onUpdate: (@MainActor (NowPlaying?) -> Void)?
    private var current: NowPlaying?
    private var activePlayer: ScriptablePlayer?
    private var artworkCache: (key: String, data: Data?)?
    private var refreshGeneration = 0
    /// Po `stop()` zaległe zadania (polecenia, odświeżenia) niczego już nie publikują.
    private var isStopped = false

    init(players: [ScriptablePlayer] = ScriptablePlayer.allCases) {
        self.players = players
    }

    func start(onUpdate: @escaping @MainActor (NowPlaying?) -> Void, onFailure: @escaping @MainActor (String) -> Void) {
        self.onUpdate = onUpdate
        let distributed = DistributedNotificationCenter.default()
        for player in players {
            distributedObservers.append(distributed.addObserver(forName: player.changeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            workspaceObservers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
        refresh()
    }

    func stop() {
        isStopped = true
        distributedObservers.forEach(DistributedNotificationCenter.default().removeObserver)
        workspaceObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        distributedObservers = []
        workspaceObservers = []
        refreshGeneration += 1
    }

    func send(_ command: MediaCommand) {
        guard let player = activePlayer else { return }
        let source = AppleScriptParser.commandScript(command, for: player)
        Task {
            _ = await runner.run(source)
            refresh()
        }
    }

    func seek(to seconds: TimeInterval) {
        guard let player = activePlayer else { return }
        let source = AppleScriptParser.seekScript(to: seconds, for: player)
        Task {
            _ = await runner.run(source)
            refresh()
        }
    }

    private func refresh() {
        guard !isStopped else { return }
        refreshGeneration += 1
        let generation = refreshGeneration
        let running = players.filter { player in
            !NSRunningApplication.runningApplications(withBundleIdentifier: player.rawValue).isEmpty
        }
        Task {
            var statuses: [(ScriptablePlayer, AppleScriptParser.Status)] = []
            for player in running {
                guard let output = await runner.run(AppleScriptParser.statusScript(for: player))?.stringValue,
                      let status = AppleScriptParser.parse(output, player: player, now: Date())
                else { continue }
                statuses.append((player, status))
            }
            guard generation == refreshGeneration else { return }
            let chosen = statuses.first { $0.1.nowPlaying.isPlaying } ?? statuses.first
            activePlayer = chosen?.0
            await publish(chosen, generation: generation)
        }
    }

    private func publish(_ chosen: (ScriptablePlayer, AppleScriptParser.Status)?, generation: Int) async {
        guard let (player, status) = chosen else {
            current = nil
            onUpdate?(nil)
            return
        }
        let artwork = await artwork(for: status, player: player)
        // Pobieranie okładki trwa: w tym czasie mogło przyjść nowsze odświeżenie (np. przeskok utworu).
        guard generation == refreshGeneration, !isStopped else { return }
        let nowPlaying = status.nowPlaying.with(artwork: artwork)
        current = nowPlaying
        onUpdate?(nowPlaying)
    }

    /// Okładka jest pobierana raz na utwór.
    private func artwork(for status: AppleScriptParser.Status, player: ScriptablePlayer) async -> Data? {
        let track = status.nowPlaying
        let key = [player.rawValue, track.title, track.artist ?? "", track.album ?? ""].joined(separator: "|")
        if let artworkCache, artworkCache.key == key { return artworkCache.data }

        let data: Data?
        switch player {
        case .music:
            data = await runner.run(AppleScriptParser.musicArtworkScript)?.data
        case .spotify:
            data = await download(status.artworkURL)
        }
        artworkCache = (key, data)
        return data
    }

    private func download(_ url: URL?) async -> Data? {
        // Adres okładki przychodzi z AppleScriptu Spotify: tylko https (żadnych file://, http ani innych schematów).
        guard let url, url.scheme?.lowercased() == "https" else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return data
        } catch {
            log.error("Nie udało się pobrać okładki Spotify: \(error.localizedDescription)")
            return nil
        }
    }
}

/// NSAppleScript nie jest bezpieczny wątkowo: wszystkie skrypty idą przez jedną kolejkę szeregową.
final class ScriptRunner: @unchecked Sendable {
    private let queue = DispatchQueue(label: "pl.net.kurant.wyspa.applescript", qos: .utility)
    private let log = Log.logger("media.applescript")

    struct Result: @unchecked Sendable {
        let descriptor: NSAppleEventDescriptor

        var stringValue: String? { descriptor.stringValue }
        var data: Data? {
            let data = descriptor.data
            return data.isEmpty ? nil : data
        }
    }

    func run(_ source: String) async -> Result? {
        await withCheckedContinuation { continuation in
            queue.async { [log] in
                var error: NSDictionary?
                let descriptor = NSAppleScript(source: source)?.executeAndReturnError(&error)
                if let error {
                    let code = error[NSAppleScript.errorNumber] as? Int ?? 0
                    // -1743: brak zgody na automatyzację; -600: aplikacja zamknięta w trakcie.
                    log.error("AppleScript zakończył się błędem \(code)")
                    continuation.resume(returning: nil)
                } else {
                    continuation.resume(returning: descriptor.map(Result.init))
                }
            }
        }
    }
}
