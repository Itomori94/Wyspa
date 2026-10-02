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
    private static let slotsKey = "slots"
    public typealias Slot = ActionSlot<Action>
    static let defaultSlots: [Slot] = [Action.capture, .captureText, .password, .darkMode, .pickColor, .captureScreen, .record, .keepAwake]
        .map { Slot(action: $0, isEnabled: true) }

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

        /// Ikona na liście wyboru w ustawieniach.
        public var symbol: String {
            switch self {
            case .capture: "camera.viewfinder"
            case .captureScreen: "macwindow"
            case .captureText: "text.viewfinder"
            case .record: "record.circle"
            case .pickColor: "eyedropper"
            case .password: "key.fill"
            case .darkMode: "circle.lefthalf.filled"
            case .desktopIcons: "menubar.dock.rectangle"
            case .lock: "lock.fill"
            case .keepAwake: "cup.and.saucer"
            }
        }
    }
    static let feedbackDisplay: Duration = .seconds(3)

    public private(set) var isKeepingAwake = false
    /// 8 miejsc: w każdym akcja z listy i przełącznik (najmniej 2 włączone); skróty działają dla wszystkich akcji.
    public private(set) var slots: [Slot]
    /// Kafelki w wyspie: akcje z włączonych miejsc, w kolejności miejsc.
    public var visibleActions: [Action] { slots.filter(\.isEnabled).map(\.action) }
    public private(set) var isDarkMode = false
    public private(set) var desktopIconsVisible = true
    /// Hasło znika ze schowka po tym czasie, jeśli nic innego nie zostało skopiowane.
    static let passwordLifetime: Duration = .seconds(90)
    /// Czas na zwinięcie wyspy, zanim zrobimy zrzut całego ekranu (żeby nie było jej na zrzucie).
    static let collapseDelay: Duration = .milliseconds(450)
    /// Krótki komunikat po akcji („Skopiowano #1E90FF”).
    public var feedback: String? { message.text }
    /// Globalne skróty akcji (bez domyślnych — ustawiasz je sam); działają tylko, gdy moduł jest włączony.
    public private(set) var shortcuts: [Action: HotkeyShortcut]
    public private(set) var shortcutProblem: String?

    @ObservationIgnored private let context: ModuleContext
    @ObservationIgnored private var assertionID: IOPMAssertionID = 0
    @ObservationIgnored private let message = TransientMessage()
    @ObservationIgnored private var sampler: NSColorSampler?
    @ObservationIgnored private let log = Log.logger("quickactions")
    @ObservationIgnored private var hotkeys: [GlobalHotkey] = []
    /// Trwające zaznaczanie zrzutu (przerywane przy wyłączeniu modułu).
    @ObservationIgnored private var captureProcess: Process?

    public required init(context: ModuleContext) {
        self.context = context
        slots = QuickActionsLogic.validated(context.settings.value(Self.slotsKey, default: [Slot]?.none), default: Self.defaultSlots)
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
        message.clear()
        sampler = nil
    }

    public var liveActivity: LiveActivity? { nil }
    public func makeExpandedView() -> AnyView? { AnyView(QuickActionsView(module: self, compact: false)) }
    public func makeWidgetView() -> AnyView? { AnyView(QuickActionsView(module: self, compact: true)) }
    public func makeSettingsView() -> AnyView? { AnyView(QuickActionsSettingsView(module: self)) }

    // MARK: - Skróty

    func chooseAction(_ action: Action, at index: Int) {
        save(QuickActionsLogic.choosing(action, at: index, in: slots))
    }

    /// Czy przełącznik miejsca jest aktywny (wyłączyć można tylko, gdy zostaną najmniej 2 włączone).
    func canSetSlot(_ enabled: Bool, at index: Int) -> Bool {
        QuickActionsLogic.setting(enabled, at: index, in: slots) != nil
    }

    func setSlot(_ enabled: Bool, at index: Int) {
        guard let next = QuickActionsLogic.setting(enabled, at: index, in: slots) else { return }
        save(next)
    }

    private func save(_ next: [Slot]) {
        slots = next
        context.settings.set(next, for: Self.slotsKey)
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

    /// Nagrywanie wideo: systemowy pasek od razu w trybie nagrywania (`-J video`), z widocznymi kliknięciami.
    /// Nagranie zostaje tam, gdzie system zapisuje zrzuty (inaczej na biurku), i trafia na Półkę.
    func startRecording() {
        guard captureProcess == nil else { return }
        context.requestCollapse()
        let defaults = UserDefaults(suiteName: "com.apple.screencapture")
        let directory = QuickActionsLogic.recordingDirectory(systemLocation: defaults?.string(forKey: "location"),
                                                             home: FileManager.default.homeDirectoryForCurrentUser)
        let url = QuickActionsLogic.recordingURL(in: directory, at: Date())
        // Plik docelowy: przy wyłączeniu modułu w trakcie zostaje na dysku (to nagranie użytkownika).
        runScreencapture(["-i", "-U", "-J", "video", "-k", url.path], output: url, isTemporary: false,
                         failureMessage: "Nie udało się uruchomić nagrywania") { [weak self] url in self?.recordingFinished(url) }
    }

    /// Nagranie jest plikiem docelowym (nie tymczasowym): Półka dostaje odnośnik, plik zostaje na dysku.
    private func recordingFinished(_ url: URL) {
        // Anulowanie (Esc) nie zostawia pliku.
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        if let provider = NSItemProvider(contentsOf: url), context.deliver([provider], Self.shelfZone) {
            show("Nagranie na Półce")
        } else {
            show("Nagranie zapisane: \(url.deletingLastPathComponent().lastPathComponent)")
        }
    }

    /// Losowe hasło do schowka, oznaczone jako poufne (menedżery schowka, także historia Wyspy, je pomijają);
    /// znika po 90 s, jeśli w międzyczasie nic innego nie skopiowano.
    func copyPassword() {
        let pasteboard = NSPasteboard.general
        let concealed = NSPasteboard.PasteboardType(PasteboardPrivacy.concealed)
        // `declareTypes` czyści schowek sam.
        pasteboard.declareTypes([.string, concealed], owner: nil)
        pasteboard.setString(QuickActionsLogic.password(), forType: .string)
        pasteboard.setString("", forType: concealed)
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
        let url = QuickActionsLogic.screenshotURL(in: FileManager.default.temporaryDirectory, at: Date())
        runScreencapture(arguments + ["-x", url.path], output: url, isTemporary: true,
                         failureMessage: "Nie udało się uruchomić zrzutu ekranu", completion)
    }

    /// Jeden `screencapture` naraz. Po zakończeniu `completion` dostaje plik (może go nie być po Esc).
    /// Gdy moduł wyłączono w trakcie, nic nie przekazujemy; plik tymczasowy jest wtedy kasowany.
    private func runScreencapture(_ arguments: [String], output url: URL, isTemporary: Bool, failureMessage: String,
                                  _ completion: @escaping @MainActor @Sendable (URL) -> Void) {
        guard captureProcess == nil else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = arguments
        process.terminationHandler = { [weak self] finished in
            Task { @MainActor in
                guard let self, self.captureProcess === finished else {
                    if isTemporary { try? FileManager.default.removeItem(at: url) }
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
            show(failureMessage)
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

    private func show(_ text: String) {
        message.show(text, for: Self.feedbackDisplay)
    }
}
