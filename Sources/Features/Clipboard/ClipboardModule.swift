import AppKit
import Carbon.HIToolbox
import SwiftUI
import WyspaCore

/// Historia schowka z wyszukiwaniem, przypinaniem i wklejaniem kliknięciem.
///
/// Wyjątek od zasady „bez ciągłych timerów” (zaakceptowany): system nie powiadamia o zmianie schowka,
/// więc sprawdzamy `changeCount` co 0,75 s — tylko wtedy, gdy moduł jest włączony.
@MainActor
@Observable
public final class ClipboardModule: IslandModule, IslandKeyboardHandling {
    public static let descriptor = ModuleDescriptor(
        id: "clipboard",
        name: "Historia schowka",
        summary: "Ostatnio kopiowane teksty, pliki i obrazy z wyszukiwaniem. Hasła z menedżerów haseł są pomijane. Historia jest tylko w pamięci.",
        symbol: "doc.on.clipboard",
        content: .personal,
        widgetMinWidth: 150
    )

    static let pollInterval: TimeInterval = 0.75
    static let maxImageBytes = 4 * 1024 * 1024
    private static let limitKey = "limit"
    private static let pasteKey = "pasteOnClick"
    /// Czas na zwinięcie wyspy i powrót klawiatury do aplikacji pod spodem przed ⌘V.
    static let pasteDelay: Duration = .milliseconds(180)

    public private(set) var history: ClipboardHistory
    public var query = "" {
        didSet { if query != oldValue { selectedIndex = query.isEmpty ? nil : 0 } }
    }
    /// Wpis wybrany strzałkami (indeks w wynikach wyszukiwania); Enter go wkleja.
    public private(set) var selectedIndex: Int?
    /// Kliknięcie wpisu wkleja go do aplikacji na pierwszym planie (inaczej tylko kopiuje).
    public var pastesOnClick: Bool { didSet { context.settings.set(pastesOnClick, for: Self.pasteKey) } }
    /// Krótki komunikat po kliknięciu („Wklejono”, „Skopiowano”).
    public private(set) var feedback: String?

    @ObservationIgnored private let context: ModuleContext
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var lastChangeCount = NSPasteboard.general.changeCount
    @ObservationIgnored private var pasteTask: Task<Void, Never>?
    @ObservationIgnored private var feedbackTask: Task<Void, Never>?

    public required init(context: ModuleContext) {
        self.context = context
        history = ClipboardHistory(limit: context.settings.value(Self.limitKey, default: ClipboardHistory.defaultLimit))
        pastesOnClick = context.settings.value(Self.pasteKey, default: true)
    }

    public func activate() async throws {
        lastChangeCount = NSPasteboard.general.changeCount
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer.tolerance = 0.25
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Wyłączenie zatrzymuje sprawdzanie i usuwa historię z pamięci.
    public func deactivate() {
        timer?.invalidate()
        timer = nil
        pasteTask?.cancel()
        feedbackTask?.cancel()
        history = history.clearedAll()
    }

    public var liveActivity: LiveActivity? { nil }

    public func makeExpandedView() -> AnyView? {
        AnyView(ClipboardView(module: self))
    }

    public func makeWidgetView() -> AnyView? {
        AnyView(ClipboardWidget(module: self))
    }

    public func makeSettingsView() -> AnyView? {
        AnyView(ClipboardSettingsView(module: self))
    }

    var limit: Int {
        get { history.limit }
        set {
            history = history.withLimit(newValue)
            context.settings.set(history.limit, for: Self.limitKey)
        }
    }

    /// Wkleja wpis z powrotem do schowka (trafia na górę historii).
    func copy(_ entry: ClipboardEntry) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        switch entry.content {
        case .text(let text): pasteboard.setString(text, forType: .string)
        case .files(let urls): pasteboard.writeObjects(urls as [NSURL])
        case .image(let png, _, _): pasteboard.setData(png, forType: .png)
        }
        lastChangeCount = pasteboard.changeCount
        history = history.adding(ClipboardEntry(content: entry.content, copiedAt: Date(), sourceBundleID: entry.sourceBundleID))
    }

    /// Kliknięcie wpisu: wklejenie do aplikacji pod spodem albo samo skopiowanie (ustawienie, brak Dostępności).
    func choose(_ entry: ClipboardEntry) {
        copy(entry)
        guard pastesOnClick else {
            show("Skopiowano")
            return
        }
        // Symulowanie ⌘V w innej aplikacji wymaga Dostępności; bez niej zostaje skopiowanie.
        guard AXIsProcessTrusted() else {
            show("Skopiowano — wklejanie wymaga Dostępności")
            return
        }
        query = ""
        selectedIndex = nil
        context.requestCollapse()
        pasteTask?.cancel()
        pasteTask = Task { [weak self] in
            try? await Task.sleep(for: Self.pasteDelay)
            guard !Task.isCancelled, self != nil else { return }
            Self.postPaste()
        }
    }

    /// ⌘V do aplikacji z klawiaturą (panel wyspy nie aktywuje Wyspy, więc to wciąż aplikacja pod spodem).
    private static func postPaste() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let key = CGKeyCode(kVK_ANSI_V)
        for isDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: isDown)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }

    // MARK: - Klawiatura (po skrócie wyspy)

    public static let receivesTypedText = true

    /// Czy pole wyszukiwania ma klawiaturę (ustawiane przez widok).
    @ObservationIgnored var isSearchFocused = false

    public func handleKey(_ key: IslandKey, whileEditingText: Bool) -> Bool {
        // Pisanie w innym polu (np. notatka na tej samej stronie) nie należy do schowka.
        if whileEditingText && !isSearchFocused { return false }
        let results = history.matching(query)
        switch key {
        case .text(let text):
            query += text
            return true
        case .backspace:
            guard !query.isEmpty else { return false }
            query.removeLast()
            return true
        case .down:
            guard !results.isEmpty else { return false }
            selectedIndex = ClipboardSelection.moved(selectedIndex, by: 1, count: results.count)
            return true
        case .up:
            guard !results.isEmpty else { return false }
            selectedIndex = ClipboardSelection.moved(selectedIndex, by: -1, count: results.count)
            return true
        case .enter:
            guard let index = ClipboardSelection.chosen(selectedIndex, count: results.count) else { return false }
            choose(results[index])
            return true
        }
    }

    func togglePin(_ entry: ClipboardEntry) {
        withAnimation(.snappy) { history = history.togglingPin(entry.id) }
    }

    private func show(_ message: String) {
        withAnimation { feedback = message }
        feedbackTask?.cancel()
        feedbackTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            withAnimation { self?.feedback = nil }
        }
    }

    func remove(_ entry: ClipboardEntry) {
        history = history.removing(entry.id)
    }

    func clear() {
        history = history.cleared()
    }

    private func poll() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        let types = pasteboard.types?.map(\.rawValue) ?? []
        guard !PasteboardPrivacy.shouldIgnore(types: types), let content = Self.read(pasteboard) else { return }
        let source = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        history = history.adding(ClipboardEntry(content: content, copiedAt: Date(), sourceBundleID: source))
    }

    private static func read(_ pasteboard: NSPasteboard) -> ClipboardEntry.Content? {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            return .files(urls)
        }
        if let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff),
           data.count <= maxImageBytes,
           let image = NSBitmapImageRep(data: data),
           let png = image.representation(using: .png, properties: [:]) {
            return .image(png: png, width: image.pixelsWide, height: image.pixelsHigh)
        }
        if let text = pasteboard.string(forType: .string), text.utf8.count <= ClipboardHistory.maxTextBytes,
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .text(text)
        }
        return nil
    }
}

#if DEBUG
extension ClipboardModule {
    /// Dane demonstracyjne do zrzutów ekranu w README (tylko build debug).
    func showDemo(_ demo: ClipboardHistory) {
        history = demo
    }
}
#endif
