import AppKit
import IOKit.pwr_mgt
import SwiftUI
import UniformTypeIdentifiers
import WyspaCore

/// Szybkie akcje: zrzut zaznaczenia na Półkę, tekst ze zrzutu (OCR), pipeta koloru, blokada ekranu, „nie usypiaj Maca”.
@MainActor
@Observable
public final class QuickActionsModule: IslandModule {
    public static let descriptor = ModuleDescriptor(
        id: "quickactions",
        name: "Szybkie akcje",
        summary: "Zrzut zaznaczenia prosto na Półkę, tekst ze zrzutu do schowka, pipeta koloru (kopiuje HEX), blokada ekranu i „nie usypiaj Maca”.",
        symbol: "bolt.circle.fill",
        content: .neutral,
        widgetMinWidth: 150
    )

    static let shelfZone = "shelf.store"
    private static let shortcutsKey = "shortcuts"
    private static let visibleKey = "visibleActions"
    static let defaultVisible: [Action] = [.capture, .captureText, .password, .darkMode]

    public enum Action: String, CaseIterable, Codable, Sendable {
        case capture, captureScreen, captureText, record, pickColor, password, darkMode, desktopIcons, lock, keepAwake

        public var displayName: String {
            switch self {
            case .capture: "Zrzut na Półkę"
            case .captureScreen: "Zrzut całego ekranu"
            case .captureText: "Tekst ze zrzutu"
            case .record: "Nagrywanie ekranu"
            case .pickColor: "Pipeta koloru"
            case .password: "Generator hasła"
            case .darkMode: "Tryb ciemny (przełącz)"
            case .desktopIcons: "Ikony na biurku (przełącz)"
            case .lock: "Zablokuj ekran"
            case .keepAwake: "Nie usypiaj (przełącz)"
            }
        }
    }
    static let feedbackDisplay: Duration = .seconds(3)

    public private(set) var isKeepingAwake = false
    /// Kafelki w wyspie (2–4, w kolejności z `Action.allCases`); skróty działają dla wszystkich akcji.
    public private(set) var visibleActions: [Action]
    public private(set) var isDarkMode = false
    public private(set) var desktopIconsVisible = true
    /// Hasło znika ze schowka po tym czasie, jeśli nic innego nie zostało skopiowane.
    static let passwordLifetime: Duration = .seconds(90)
    /// Czas na zwinięcie wyspy, zanim zrobimy zrzut całego ekranu (żeby nie było jej na zrzucie).
    static let collapseDelay: Duration = .milliseconds(450)
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
    /// Trwające zaznaczanie zrzutu (przerywane przy wyłączeniu modułu).
    @ObservationIgnored private var captureProcess: Process?

    public required init(context: ModuleContext) {
        self.context = context
        let storedVisible: [String] = context.settings.value(Self.visibleKey, default: Self.defaultVisible.map(\.rawValue))
        let restored = Action.allCases.filter { storedVisible.contains($0.rawValue) }
        visibleActions = QuickActionsLogic.visibleRange.contains(restored.count) ? restored : Self.defaultVisible
        let stored: [String: HotkeyShortcut] = context.settings.value(Self.shortcutsKey, default: [:])
        shortcuts = Dictionary(uniqueKeysWithValues: stored.compactMap { key, value in Action(rawValue: key).map { ($0, value) } })
    }

    public func activate() async throws {
        registerHotkeys()
    }

    public func deactivate() {
        hotkeys = []
        captureProcess?.terminate()
        captureProcess = nil
        if isKeepingAwake { toggleKeepAwake() }
        feedbackTask?.cancel()
        sampler = nil
    }

    public var liveActivity: LiveActivity? { nil }
    public func makeExpandedView() -> AnyView? { AnyView(QuickActionsView(module: self, compact: false)) }
    public func makeWidgetView() -> AnyView? { AnyView(QuickActionsView(module: self, compact: true)) }
    public func makeSettingsView() -> AnyView? { AnyView(QuickActionsSettingsView(module: self)) }

    // MARK: - Skróty

    func isVisible(_ action: Action) -> Bool { visibleActions.contains(action) }

    /// Czy przełącznik akcji jest aktywny (nie da się zejść poniżej 2 ani przekroczyć 4).
    func canToggle(_ action: Action) -> Bool {
        QuickActionsLogic.toggling(action, in: visibleActions, order: Action.allCases) != nil
    }

    func setVisible(_ action: Action, _ visible: Bool) {
        guard visible != isVisible(action),
              let next = QuickActionsLogic.toggling(action, in: visibleActions, order: Action.allCases) else { return }
        visibleActions = next
        context.settings.set(next.map(\.rawValue), for: Self.visibleKey)
    }

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
        case .captureScreen: captureScreen()
        case .captureText: captureText()
        case .record: startRecording()
        case .password: copyPassword()
        case .darkMode: toggleDarkMode()
        case .desktopIcons: toggleDesktopIcons()
        case .pickColor: pickColor()
        case .lock: lockScreen()
        case .keepAwake:
            if toggleKeepAwake() { show(isKeepingAwake ? "Mac nie zaśnie" : "Usypianie jak zwykle") }
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
        startCapture { [weak self] url in self?.screenshotFinished(url) }
    }

    /// Zaznaczenie obszaru → tekst rozpoznany na urządzeniu (Vision, polski i angielski) → schowek.
    func captureText() {
        startCapture { [weak self] url in self?.recognizeText(in: url) }
    }

    /// Cały ekran główny na Półkę (albo do schowka): wyspa najpierw się zwija, żeby nie było jej na zrzucie.
    func captureScreen() {
        context.requestCollapse()
        Task { [weak self] in
            try? await Task.sleep(for: Self.collapseDelay)
            self?.startCapture(arguments: ["-m"]) { [weak self] url in self?.screenshotFinished(url) }
        }
    }

    /// Systemowy pasek zrzutów i nagrywania (jak ⇧⌘5): wybór obszaru, nagrywanie, zapis jak w ustawieniach systemu.
    func startRecording() {
        context.requestCollapse()
        let screenshotApp = URL(fileURLWithPath: "/System/Applications/Utilities/Screenshot.app")
        NSWorkspace.shared.openApplication(at: screenshotApp, configuration: NSWorkspace.OpenConfiguration()) { [weak self] _, error in
            guard error != nil else { return }
            Task { @MainActor in self?.show("Nie udało się otworzyć paska nagrywania") }
        }
    }

    /// Losowe hasło do schowka, oznaczone jako poufne (menedżery schowka, także historia Wyspy, je pomijają);
    /// znika po 90 s, jeśli w międzyczasie nic innego nie skopiowano.
    func copyPassword() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.declareTypes([.string, NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")], owner: nil)
        pasteboard.setString(QuickActionsLogic.password(), forType: .string)
        pasteboard.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        let change = pasteboard.changeCount
        show("Hasło w schowku — zniknie za 90 s")
        Task {
            try? await Task.sleep(for: Self.passwordLifetime)
            if NSPasteboard.general.changeCount == change { NSPasteboard.general.clearContents() }
        }
    }

    /// Przełącza tryb ciemny całego systemu przez System Events (przy pierwszym razie macOS pyta o zgodę).
    func toggleDarkMode() {
        let source = QuickActionsLogic.toggleDarkModeScript
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var error: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&error)
            let code = error?[NSAppleScript.errorNumber] as? Int
            Task { @MainActor in
                guard let self else { return }
                self.refreshSystemState()
                if code == -1743 {
                    self.show("Zezwól Wyspie na sterowanie „System Events” (Ustawienia systemowe → Prywatność → Automatyzacja)")
                } else if code != nil {
                    self.show("Nie udało się przełączyć trybu ciemnego")
                }
            }
        }
    }

    /// Chowa albo pokazuje pliki na biurku (ustawienie Findera) i przeładowuje Findera, żeby zadziałało od razu.
    func toggleDesktopIcons() {
        let show = !QuickActionsLogic.desktopIconsVisible(CFPreferencesCopyAppValue("CreateDesktop" as CFString, "com.apple.finder" as CFString))
        CFPreferencesSetAppValue("CreateDesktop" as CFString, show as CFBoolean, "com.apple.finder" as CFString)
        CFPreferencesAppSynchronize("com.apple.finder" as CFString)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["Finder"]
        do {
            try process.run()
        } catch {
            log.error("killall Finder: \(error.localizedDescription, privacy: .public)")
        }
        desktopIconsVisible = show
        self.show(show ? "Ikony na biurku widoczne" : "Ikony na biurku ukryte")
    }

    /// Stan przełączników systemowych (tryb ciemny, ikony na biurku) — przy otwarciu widoku i po zmianie.
    func refreshSystemState() {
        isDarkMode = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
        desktopIconsVisible = QuickActionsLogic.desktopIconsVisible(
            CFPreferencesCopyAppValue("CreateDesktop" as CFString, "com.apple.finder" as CFString))
    }

    /// Zrzut ekranu (domyślnie zaznaczenie obszaru); `completion` dostaje plik (może go nie być po Esc)
    /// i odpowiada za jego usunięcie.
    private func startCapture(arguments: [String] = ["-i"], _ completion: @escaping @MainActor @Sendable (URL) -> Void) {
        guard captureProcess == nil else { return }
        let url = QuickActionsLogic.screenshotURL(in: FileManager.default.temporaryDirectory, at: Date())
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = arguments + ["-x", url.path]
        process.terminationHandler = { [weak self] finished in
            Task { @MainActor in
                // Moduł wyłączony w trakcie zaznaczania: nic nie przekazujemy, tylko sprzątamy.
                guard let self, self.captureProcess === finished else {
                    try? FileManager.default.removeItem(at: url)
                    return
                }
                self.captureProcess = nil
                completion(url)
            }
        }
        do {
            try process.run()
            captureProcess = process
        } catch {
            log.error("screencapture: \(error.localizedDescription, privacy: .public)")
            show("Nie udało się uruchomić zrzutu ekranu")
        }
    }

    /// Zrzut trafia na Półkę jako dane (Półka trzyma własną kopię), plik tymczasowy znika od razu.
    private func screenshotFinished(_ url: URL) {
        defer { try? FileManager.default.removeItem(at: url) }
        // Esc w trakcie zaznaczania: pliku nie ma, nic nie robimy.
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return }
        let provider = NSItemProvider(item: data as NSData, typeIdentifier: UTType.png.identifier)
        provider.suggestedName = url.deletingPathExtension().lastPathComponent
        if context.deliver([provider], Self.shelfZone) {
            show("Zrzut na Półce")
        } else if let image = NSImage(data: data) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([image])
            show("Półka wyłączona — zrzut w schowku")
        }
    }

    private func recognizeText(in url: URL) {
        // Esc w trakcie zaznaczania: pliku nie ma, nic nie robimy.
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        show("Rozpoznawanie tekstu…")
        Task { [weak self] in
            defer { try? FileManager.default.removeItem(at: url) }
            do {
                let lines = try await TextRecognition.lines(inImageAt: url)
                guard let self else { return }
                guard let text = QuickActionsLogic.recognizedText(lines: lines) else {
                    self.show("Nie znaleziono tekstu")
                    return
                }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                self.show(QuickActionsLogic.copiedLinesMessage(text.split(separator: "\n").count))
            } catch {
                self?.log.error("OCR: \(error.localizedDescription, privacy: .public)")
                self?.show("Nie udało się rozpoznać tekstu")
            }
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
        do {
            try process.run()
        } catch {
            log.error("pmset displaysleepnow: \(error.localizedDescription, privacy: .public)")
            show("Nie udało się zablokować ekranu")
        }
    }

    /// Nie usypiaj Maca ani ekranu (asercja zasilania, jak `caffeinate -d`); zwalniana przy wyłączeniu modułu.
    /// `false`, gdy system odmówił (komunikat już pokazany).
    @discardableResult
    func toggleKeepAwake() -> Bool {
        if isKeepingAwake {
            IOPMAssertionRelease(assertionID)
            assertionID = 0
            isKeepingAwake = false
            return true
        }
        var id: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                                 IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                 "Wyspa: nie usypiaj Maca" as CFString, &id)
        guard result == kIOReturnSuccess else {
            show("Nie udało się wyłączyć usypiania")
            return false
        }
        assertionID = id
        isKeepingAwake = true
        return true
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
