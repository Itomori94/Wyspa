import AppKit
import SwiftUI
import WyspaCore

/// Historia schowka z wyszukiwaniem.
///
/// Wyjątek od zasady „bez ciągłych timerów” (zaakceptowany): system nie powiadamia o zmianie schowka,
/// więc sprawdzamy `changeCount` co 0,75 s — tylko wtedy, gdy moduł jest włączony.
@MainActor
@Observable
public final class ClipboardModule: IslandModule {
    public static let descriptor = ModuleDescriptor(
        id: "clipboard",
        name: "Historia schowka",
        summary: "Ostatnio kopiowane teksty, pliki i obrazy z wyszukiwaniem. Hasła z menedżerów haseł są pomijane. Historia jest tylko w pamięci.",
        symbol: "doc.on.clipboard",
        widgetMinWidth: 150
    )

    static let pollInterval: TimeInterval = 0.75
    static let maxImageBytes = 4 * 1024 * 1024
    private static let limitKey = "limit"

    public private(set) var history: ClipboardHistory
    public var query = ""

    @ObservationIgnored private let context: ModuleContext
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var lastChangeCount = NSPasteboard.general.changeCount

    public required init(context: ModuleContext) {
        self.context = context
        history = ClipboardHistory(limit: context.settings.value(Self.limitKey, default: ClipboardHistory.defaultLimit))
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
        history = history.cleared()
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
