import AppKit
import SwiftUI
import WyspaCore

/// Powiadomienia macOS w wyspie zamiast w rogu ekranu.
@MainActor
@Observable
public final class NotificationsModule: IslandModule {
    public static let descriptor = ModuleDescriptor(
        id: "notifications",
        name: "Powiadomienia",
        summary: "Pokazuje powiadomienia macOS w wyspie zamiast w rogu ekranu. Najechanie zatrzymuje kartę, kliknięcie otwiera aplikację.",
        symbol: "bell.badge.fill",
        content: .personal,
        permissions: [.accessibility],
        providesPage: false
    )

    static let durations = [3, 5, 8, 10, 15]
    static let cardHeight: CGFloat = 72
    private static let hideKey = "hideOriginal"
    private static let durationKey = "durationSeconds"

    public private(set) var queue = NotificationQueue()
    public var hidesOriginal: Bool { didSet { context.settings.set(hidesOriginal, for: Self.hideKey) } }
    public var durationSeconds: Int { didSet { context.settings.set(durationSeconds, for: Self.durationKey) } }

    @ObservationIgnored private let context: ModuleContext
    @ObservationIgnored private var watcher: NotificationBannerWatcher?
    @ObservationIgnored private var dismissTask: Task<Void, Never>?
    @ObservationIgnored private var isPaused = false

    public required init(context: ModuleContext) {
        self.context = context
        hidesOriginal = context.settings.value(Self.hideKey, default: true)
        durationSeconds = context.settings.value(Self.durationKey, default: 5)
    }

    public func activate() async throws {
        guard AXIsProcessTrusted() else { throw NotificationsError.notTrusted }
        let watcher = NotificationBannerWatcher(hidesOriginal: { [weak self] in self?.hidesOriginal ?? false }) { [weak self] card in
            self?.receive(card)
        }
        watcher.start()
        self.watcher = watcher
    }

    public func deactivate() {
        watcher?.stop()
        watcher = nil
        dismissTask?.cancel()
        queue = queue.cleared()
    }

    public var liveActivity: LiveActivity? {
        guard let card = queue.current else { return nil }
        let icon = Self.icon(forAppNamed: card.appName)
        let waiting = queue.waiting.count
        return LiveActivity(id: "notification.\(card.id)", priority: .alert, detailHeight: Self.cardHeight) {
            Image(nsImage: icon).resizable().frame(width: 18, height: 18)
        } trailing: {
            if waiting > 0 {
                Text("+\(waiting)").font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(.white.opacity(0.7))
            } else {
                Image(systemName: "bell.fill").font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
            }
        } detail: {
            NotificationCardView(card: card, icon: icon, isPrivate: false,
                                 hover: { [weak self] in self?.setPaused($0) },
                                 open: { [weak self] in self?.open(card) },
                                 close: { [weak self] in self?.next() })
        }
        .withPrivateDetail {
            NotificationCardView(card: card, icon: icon, isPrivate: true,
                                 hover: { [weak self] in self?.setPaused($0) },
                                 open: { [weak self] in self?.open(card) },
                                 close: { [weak self] in self?.next() })
        }
    }

    public func makeExpandedView() -> AnyView? { nil }
    public func makeSettingsView() -> AnyView? { AnyView(NotificationsSettingsView(module: self)) }

    // MARK: - Kolejka

    private func receive(_ card: NotificationCard) {
        context.privacy.refresh()
        let wasEmpty = queue.current == nil
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { queue = queue.enqueueing(card) }
        if wasEmpty { scheduleDismiss() }
    }

    func next() {
        // Karta znika spod kursora bez „zjechania” — inaczej następna nigdy by się sama nie schowała.
        isPaused = false
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { queue = queue.advancing() }
        if queue.current != nil { scheduleDismiss() } else { dismissTask?.cancel() }
    }

    /// Najechanie na kartę zatrzymuje odliczanie; zjechanie zaczyna je od nowa.
    func setPaused(_ paused: Bool) {
        isPaused = paused
        if paused { dismissTask?.cancel() } else if queue.current != nil { scheduleDismiss() }
    }

    func open(_ card: NotificationCard) {
        if let url = Self.appURL(named: card.appName) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
        next()
    }

    private func scheduleDismiss() {
        dismissTask?.cancel()
        guard !isPaused else { return }
        let seconds = durationSeconds
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.next()
        }
    }

    // MARK: - Aplikacja źródłowa

    /// Baner podaje tylko wyświetlaną nazwę aplikacji; szukamy jej wśród działających aplikacji.
    static func appURL(named name: String) -> URL? {
        NSWorkspace.shared.runningApplications.first { $0.localizedName == name }?.bundleURL
    }

    static func icon(forAppNamed name: String) -> NSImage {
        if let url = appURL(named: name) { return NSWorkspace.shared.icon(forFile: url.path) }
        return NSImage(systemSymbolName: "bell.fill", accessibilityDescription: nil) ?? NSImage()
    }
}

enum NotificationsError: LocalizedError {
    case notTrusted
    var errorDescription: String? { "Wyspa nie ma uprawnienia Dostępność." }
}
