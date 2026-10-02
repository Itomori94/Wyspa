import AppKit
import SwiftUI
import WyspaCore

/// Moduł „Teraz odtwarzane”: okładka, tytuł, przewijanie i sterowanie.
@MainActor
@Observable
public final class MediaModule: IslandModule {
    public static let descriptor = ModuleDescriptor(
        id: "media",
        name: "Teraz odtwarzane",
        summary: "Okładka, tytuł, pasek przewijania i sterowanie odtwarzaniem z całego systemu.",
        symbol: "music.note",
        widgetMinWidth: 150
    )

    public enum SourceStatus: Equatable {
        case starting
        case running(MediaSourceDecision)
        case failed(String)
    }

    private static let preferenceKey = "sourcePreference"
    private static let scopeKey = "scope"

    public private(set) var nowPlaying: NowPlaying?
    public private(set) var status: SourceStatus = .starting
    public private(set) var artwork: NSImage?
    public private(set) var accent: Color?
    /// Głośniki AirPlay Muzyki; odczytywane na żądanie (otwarcie odtwarzacza, zmiana wyboru), bez odpytywania.
    public private(set) var airPlayDevices: [AirPlayDevice] = []

    public var preference: MediaSourcePreference {
        didSet {
            guard preference != oldValue else { return }
            context.settings.set(preference, for: Self.preferenceKey)
            restartSource()
        }
    }

    /// Z jakich aplikacji pokazywać dźwięk.
    public var scope: MediaScope {
        didSet {
            guard scope != oldValue else { return }
            context.settings.set(scope, for: Self.scopeKey)
            if source?.kind == .appleScript {
                // AppleScript odpytuje tylko odtwarzacze z zakresu, więc trzeba go uruchomić od nowa.
                restartSource()
            } else {
                publish(latestUpdate)
            }
        }
    }

    @ObservationIgnored private let context: ModuleContext
    /// Ostatnia aktualizacja ze źródła przed filtrem zakresu.
    @ObservationIgnored private var latestUpdate: NowPlaying?
    @ObservationIgnored private var source: NowPlayingSource?
    /// Obok adaptera: sama Muzyka przez AppleScript (Muzyka grająca przez AirPlay nie trafia do MediaRemote).
    @ObservationIgnored private var musicCompanion: AppleScriptNowPlayingSource?
    @ObservationIgnored private var latestMusic: NowPlaying?
    /// Skąd pochodzi pokazywany utwór — tam trafiają polecenia (pauza, następny, przewijanie).
    @ObservationIgnored private var displayedOrigin: NowPlayingMerge.Origin = .adapter
    @ObservationIgnored private var silenceWatch: SilenceWatch?
    @ObservationIgnored private var startTask: Task<Void, Never>?
    @ObservationIgnored private var artworkData: Data?
    @ObservationIgnored private let log = Log.logger("media")
    @ObservationIgnored private let airPlayRunner = ScriptRunner()

    public required init(context: ModuleContext) {
        self.context = context
        self.preference = context.settings.value(Self.preferenceKey, default: MediaSourcePreference.automatic)
        self.scope = context.settings.value(Self.scopeKey, default: MediaScope.system)
    }

    public func activate() async throws {
        restartSource()
    }

    public func deactivate() {
        startTask?.cancel()
        startTask = nil
        stopSource()
        nowPlaying = nil
        latestUpdate = nil
        artwork = nil
        accent = nil
        artworkData = nil
    }

    public var liveActivity: LiveActivity? {
        guard let nowPlaying, nowPlaying.isPlaying else { return nil }
        let tint = accent ?? .white
        // Okładka i wizualizer tylko w zwiniętej wyspie — rozwinięty odtwarzacz ma dużą okładkę.
        return LiveActivity(id: "media", priority: .media, accent: accent, showsInExpandedHeader: false) {
            ArtworkView(image: artwork, size: 22, cornerRadius: 6)
        } trailing: {
            VisualizerBars(color: tint, isAnimating: true)
                .frame(width: 22, height: 14)
        }
    }

    public func makeExpandedView() -> AnyView? {
        AnyView(MediaExpandedView(module: self))
    }

    public func makeSettingsView() -> AnyView? {
        AnyView(MediaSettingsView(module: self))
    }

    public func makeWidgetView() -> AnyView? {
        AnyView(MediaWidget(module: self))
    }

    public func send(_ command: MediaCommand) {
        displayedOrigin == .music ? musicCompanion?.send(command) : source?.send(command)
    }

    public func seek(to seconds: TimeInterval) {
        displayedOrigin == .music ? musicCompanion?.seek(to: seconds) : source?.seek(to: seconds)
    }

    // MARK: - AirPlay

    /// Wybór głośników jest dostępny tylko dla Muzyki (inne aplikacje nie dają go przez AppleScript).
    public var supportsAirPlay: Bool { nowPlaying?.bundleIdentifier == ScriptablePlayer.music.rawValue }

    public func refreshAirPlay() {
        let musicRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: ScriptablePlayer.music.rawValue).isEmpty
        guard supportsAirPlay, musicRunning else {
            airPlayDevices = []
            return
        }
        Task {
            let output = await airPlayRunner.run(AirPlayScript.listScript)?.stringValue ?? ""
            airPlayDevices = AirPlayScript.parse(output)
        }
    }

    public func toggleAirPlay(_ device: AirPlayDevice) {
        let names = AirPlayScript.toggling(device.name, in: airPlayDevices)
        Task {
            _ = await airPlayRunner.run(AirPlayScript.selectScript(names))
            refreshAirPlay()
        }
    }

    // MARK: - Źródło

    private func restartSource() {
        startTask?.cancel()
        stopSource()
        status = .starting
        let preference = preference
        startTask = Task { [weak self] in
            let bundle = AdapterBundle.locate()
            if let bundle { await AdapterRunner.terminateOrphans(of: bundle) }
            let health: AdapterHealth = preference == .appleScript
                ? .broken(reason: "nie sprawdzano")
                : await AdapterRunner.health(of: bundle)
            guard !Task.isCancelled, let self else { return }
            let decision = MediaSourceSelector.decide(preference: preference, adapter: health)
            self.start(decision, bundle: bundle)
        }
    }

    private func start(_ decision: MediaSourceDecision, bundle: AdapterBundle?) {
        let source: NowPlayingSource
        switch decision.kind {
        case .adapter:
            guard let bundle else {
                status = .failed("Brak plików adaptera w pakiecie aplikacji.")
                return
            }
            source = AdapterNowPlayingSource(bundle: bundle)
        case .appleScript:
            source = AppleScriptNowPlayingSource(players: scope.scriptablePlayers)
        }
        self.source = source
        status = .running(decision)
        log.info("Źródło mediów: \(decision.kind.rawValue) — \(decision.reason)")

        source.start(
            onUpdate: { [weak self] in self?.apply($0) },
            onFailure: { [weak self] in self?.sourceFailed($0) }
        )
        if decision.kind == .adapter {
            let companion = AppleScriptNowPlayingSource(players: [.music])
            musicCompanion = companion
            companion.start(onUpdate: { [weak self] in self?.musicReported($0) }, onFailure: { [weak self] message in
                self?.log.error("Muzyka przez AppleScript: \(message)")
            })
        }
        if decision.kind == .adapter, preference == .automatic {
            silenceWatch = SilenceWatch { [weak self] in
                self?.fallBack(reason: "adapter nie zwraca danych, choć odtwarzacz gra")
            }
        }
    }

    private func stopSource() {
        silenceWatch?.stop()
        silenceWatch = nil
        source?.stop()
        source = nil
        musicCompanion?.stop()
        musicCompanion = nil
        latestMusic = nil
    }

    private func sourceFailed(_ message: String) {
        if source?.kind == .adapter, preference == .automatic {
            fallBack(reason: message)
        } else {
            stopSource()
            status = .failed(message)
        }
    }

    private func fallBack(reason: String) {
        log.error("Przejście na AppleScript: \(reason)")
        stopSource()
        start(MediaSourceDecision(kind: .appleScript, reason: "Tryb awaryjny: \(reason)"), bundle: nil)
    }

    private func apply(_ update: NowPlaying?) {
        silenceWatch?.adapterReported(hasData: update != nil)
        latestUpdate = update
        publish(update)
    }

    private func musicReported(_ update: NowPlaying?) {
        latestMusic = update
        publish(latestUpdate)
    }

    private func publish(_ unfiltered: NowPlaying?) {
        let picked: (NowPlaying, NowPlayingMerge.Origin)? = source?.kind == .adapter
            ? NowPlayingMerge.pick(adapter: unfiltered, music: latestMusic, scope: scope)
            : scope.filter(unfiltered).map { ($0, .adapter) }
        displayedOrigin = picked?.1 ?? .adapter
        let update = picked?.0
        if update?.artwork != artworkData {
            // Okładka dociera czasem później niż tytuł: dla tego samego utworu zostaw poprzednią.
            if update?.artwork != nil || !(update?.isSameTrack(as: nowPlaying) ?? false) {
                updateArtwork(update?.artwork)
            }
        }
        nowPlaying = update
    }

    private func updateArtwork(_ data: Data?) {
        artworkData = data
        guard let data, let image = NSImage(data: data) else {
            artwork = nil
            accent = nil
            return
        }
        artwork = image
        let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        accent = cgImage
            .flatMap { ArtworkPalette.accent(from: ArtworkPalette.samplePixels(of: $0)) }
            .map { Color(red: $0.red, green: $0.green, blue: $0.blue) }
    }
}

/// Nasłuchuje powiadomień Muzyki i Spotify; gdy grają, a adapter milczy dłużej niż okres karencji, woła `onSilent`.
@MainActor
private final class SilenceWatch {
    private var detector = SilentAdapterDetector()
    private var observers: [NSObjectProtocol] = []
    private var check: Task<Void, Never>?
    private let onSilent: @MainActor () -> Void

    init(onSilent: @escaping @MainActor () -> Void) {
        self.onSilent = onSilent
        let center = DistributedNotificationCenter.default()
        observers = ScriptablePlayer.allCases.map { player in
            center.addObserver(forName: player.changeNotification, object: nil, queue: .main) { [weak self] note in
                let state = note.userInfo?["Player State"] as? String
                MainActor.assumeIsolated { self?.playerReported(isPlaying: state == "Playing") }
            }
        }
    }

    func adapterReported(hasData: Bool) {
        detector.adapterReported(hasData: hasData)
        if hasData { check?.cancel() }
    }

    func stop() {
        check?.cancel()
        observers.forEach(DistributedNotificationCenter.default().removeObserver)
        observers = []
    }

    private func playerReported(isPlaying: Bool) {
        detector.playerReported(isPlaying: isPlaying, at: Date())
        check?.cancel()
        guard isPlaying else { return }
        check = Task { [weak self] in
            try? await Task.sleep(for: .seconds(SilentAdapterDetector.defaultGracePeriod + 0.1))
            guard !Task.isCancelled, let self, self.detector.isSilent(at: Date()) else { return }
            self.onSilent()
        }
    }
}
