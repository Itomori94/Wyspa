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
    static let feedbackDisplay: Duration = .seconds(3)

    public private(set) var isKeepingAwake = false
    /// Krótki komunikat po akcji („Skopiowano #1E90FF”).
    public private(set) var feedback: String?

    @ObservationIgnored private let context: ModuleContext
    @ObservationIgnored private var assertionID: IOPMAssertionID = 0
    @ObservationIgnored private var feedbackTask: Task<Void, Never>?
    @ObservationIgnored private var sampler: NSColorSampler?
    @ObservationIgnored private let log = Log.logger("quickactions")

    public required init(context: ModuleContext) {
        self.context = context
    }

    public func activate() async throws {}

    public func deactivate() {
        if isKeepingAwake { toggleKeepAwake() }
        feedbackTask?.cancel()
        sampler = nil
    }

    public var liveActivity: LiveActivity? { nil }
    public func makeExpandedView() -> AnyView? { AnyView(QuickActionsView(module: self, compact: false)) }
    public func makeWidgetView() -> AnyView? { AnyView(QuickActionsView(module: self, compact: true)) }

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
