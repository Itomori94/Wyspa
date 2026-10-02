import AppKit
import IOKit.pwr_mgt
import SwiftUI
import WyspaCore

/// Szybkie akcje: zrzut zaznaczenia na Półkę, pipeta koloru, blokada ekranu, „nie usypiaj Maca”.
@MainActor
@Observable
public final class QuickActionsModule: IslandModule {
    public static let descriptor = ModuleDescriptor(
        id: "quickactions",
        name: "Szybkie akcje",
        summary: "Zrzut zaznaczenia prosto na Półkę, pipeta koloru (kopiuje HEX), blokada ekranu i „nie usypiaj Maca”.",
        symbol: "bolt.circle.fill",
        widgetMinWidth: 150
    )

    static let shelfZone = "shelf.store"
    private static let shortcutsKey = "shortcuts"

    public enum Action: String, CaseIterable, Codable, Sendable {
        case capture, pickColor, lock, keepAwake

        public var displayName: String {
            switch self {
            case .capture: "Zrzut na Półkę"
            case .pickColor: "Pipeta koloru"
            case .lock: "Zablokuj ekran"
            case .keepAwake: "Nie usypiaj (przełącz)"
            }
        }
    }
    static let feedbackDisplay: Duration = .seconds(3)

    public private(set) var isKeepingAwake = false
    /// Krótki komunikat po akcji („Skopiowano #1E90FF”).
    public private(set) var feedback: String?
    /// Globalne skróty akcji (bez domyślnych — ustawiasz je sam); działają tylko, gdy moduł jest włączony.
    public private(set) var shortcuts: [Action: HotkeyShortcut]
    public private(set) var shortcutProblem: String?

    @ObservationIgnored private let context: ModuleContext
    @ObservationIgnored private var assertionID: IOPMAssertionID = 0
    @ObservationIgnored private var feedbackTask: Task<Void, Never>?
    @ObservationIgnored private var sampler: NSColorSampler?
    @ObservationIgnored private let log = Log.logger("quickactions")
    @ObservationIgnored private var hotkeys: [GlobalHotkey] = []

    public required init(context: ModuleContext) {
        self.context = context
        let stored: [String: HotkeyShortcut] = context.settings.value(Self.shortcutsKey, default: [:])
        shortcuts = Dictionary(uniqueKeysWithValues: stored.compactMap { key, value in Action(rawValue: key).map { ($0, value) } })
    }

    public func activate() async throws {
        registerHotkeys()
    }

    public func deactivate() {
        hotkeys = []
        if isKeepingAwake { toggleKeepAwake() }
        feedbackTask?.cancel()
        sampler = nil
    }

    public var liveActivity: LiveActivity? { nil }
    public func makeExpandedView() -> AnyView? { AnyView(QuickActionsView(module: self, compact: false)) }
    public func makeWidgetView() -> AnyView? { AnyView(QuickActionsView(module: self, compact: true)) }
    public func makeSettingsView() -> AnyView? { AnyView(QuickActionsSettingsView(module: self)) }

    // MARK: - Skróty

    func setShortcut(_ shortcut: HotkeyShortcut?, for action: Action) {
        var next = shortcuts
        next[action] = shortcut
        shortcuts = next
        context.settings.set(Dictionary(uniqueKeysWithValues: next.map { ($0.key.rawValue, $0.value) }), for: Self.shortcutsKey)
        registerHotkeys()
    }

    func perform(_ action: Action) {
        switch action {
        case .capture: captureToShelf()
        case .pickColor: pickColor()
        case .lock: lockScreen()
        case .keepAwake:
            toggleKeepAwake()
            show(isKeepingAwake ? "Mac nie zaśnie" : "Usypianie jak zwykle")
        }
    }

    /// Rejestruje skróty od nowa; zajęty skrót nie blokuje pozostałych, tylko trafia do komunikatu w ustawieniach.
    private func registerHotkeys() {
        hotkeys = []
        var problems: [String] = []
        for action in Action.allCases {
            guard let shortcut = shortcuts[action] else { continue }
            let hotkey = GlobalHotkey { [weak self] in self?.perform(action) }
            do {
                try hotkey.register(shortcut)
                hotkeys.append(hotkey)
            } catch {
                problems.append("\(action.displayName): \(error.message)")
            }
        }
        shortcutProblem = problems.isEmpty ? nil : problems.joined(separator: "\n")
    }

    // MARK: - Akcje

    /// Zaznaczenie obszaru systemowym `screencapture`; plik trafia na Półkę, a bez Półki — do schowka.
    func captureToShelf() {
        let url = QuickActionsLogic.screenshotURL(in: FileManager.default.temporaryDirectory, at: Date())
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-x", url.path]
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor in self?.screenshotFinished(url) }
        }
        do {
            try process.run()
        } catch {
            log.error("screencapture: \(error.localizedDescription, privacy: .public)")
            show("Nie udało się uruchomić zrzutu ekranu")
        }
    }

    private func screenshotFinished(_ url: URL) {
        // Esc w trakcie zaznaczania: pliku nie ma, nic nie robimy.
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        if let provider = NSItemProvider(contentsOf: url), context.deliver([provider], Self.shelfZone) {
            show("Zrzut na Półce")
        } else if let image = NSImage(contentsOf: url) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([image])
            show("Półka wyłączona — zrzut w schowku")
        }
    }

    /// Systemowa pipeta; HEX koloru trafia do schowka.
    func pickColor() {
        let sampler = NSColorSampler()
        self.sampler = sampler
        sampler.show { [weak self] color in
            MainActor.assumeIsolated {
                self?.sampler = nil
                guard let rgb = color?.usingColorSpace(.sRGB) else { return }
                let hex = QuickActionsLogic.hex(red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(hex, forType: .string)
                self?.show("Skopiowano \(hex)")
            }
        }
    }

    /// Blokada ekranu. Prywatne API `SACLockScreenImmediate` (login.framework); bez niego — uśpienie ekranu,
    /// które blokuje Maca, gdy hasło jest wymagane od razu po uśpieniu (ustawienie systemowe).
    func lockScreen() {
        typealias LockFunction = @convention(c) () -> Int32
        if let lock = PrivateSymbol.load("SACLockScreenImmediate",
                                         from: "/System/Library/PrivateFrameworks/login.framework/Versions/Current/login",
                                         as: LockFunction.self) {
            _ = lock()
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["displaysleepnow"]
        try? process.run()
    }

    /// Nie usypiaj Maca ani ekranu (asercja zasilania, jak `caffeinate -d`); zwalniana przy wyłączeniu modułu.
    func toggleKeepAwake() {
        if isKeepingAwake {
            IOPMAssertionRelease(assertionID)
            assertionID = 0
            isKeepingAwake = false
            return
        }
        var id: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                                 IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                 "Wyspa: nie usypiaj Maca" as CFString, &id)
        guard result == kIOReturnSuccess else {
            show("Nie udało się wyłączyć usypiania")
            return
        }
        assertionID = id
        isKeepingAwake = true
    }

    private func show(_ message: String) {
        withAnimation { feedback = message }
        feedbackTask?.cancel()
        feedbackTask = Task { [weak self] in
            try? await Task.sleep(for: Self.feedbackDisplay)
            guard !Task.isCancelled else { return }
            withAnimation { self?.feedback = nil }
        }
    }
}
