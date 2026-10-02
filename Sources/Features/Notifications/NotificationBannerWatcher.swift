import AppKit
import ApplicationServices
import WyspaCore

/// Obserwuje banery powiadomień macOS przez Dostępność (zdarzenia `AXObserver`, bez odpytywania).
///
/// Wymaga uprawnienia Dostępność. Struktura banerów jest nieudokumentowana — gdy macOS ją zmieni, obserwator
/// po prostu nie znajdzie banerów, a powiadomienia działają jak zwykle.
@MainActor
final class NotificationBannerWatcher {
    static let bundleID = "com.apple.notificationcenterui"
    /// Okno banera jest niskie; wysokie okno to otwarte Centrum powiadomień — tego nigdy nie chowamy.
    static let maxBannerWindowHeight: CGFloat = 400
    private static let seenLimit = 200

    private let onBanner: @MainActor (NotificationCard) -> Void
    private let hidesOriginal: @MainActor () -> Bool
    private var observer: AXObserver?
    private var pid: pid_t = 0
    private var seen: [String] = []
    private var launchObserver: NSObjectProtocol?
    private let log = Log.logger("notifications")

    init(hidesOriginal: @escaping @MainActor () -> Bool, onBanner: @escaping @MainActor (NotificationCard) -> Void) {
        self.hidesOriginal = hidesOriginal
        self.onBanner = onBanner
    }

    func start() {
        attach()
        let bundleID = Self.bundleID
        // Centrum powiadomień bywa restartowane przez system — podpinamy się ponownie.
        launchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let launched = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard launched?.bundleIdentifier == bundleID else { return }
            MainActor.assumeIsolated { self?.attach() }
        }
    }

    func stop() {
        detach()
        if let launchObserver { NSWorkspace.shared.notificationCenter.removeObserver(launchObserver) }
        launchObserver = nil
        seen = []
    }

    private func attach() {
        detach()
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).first else {
            log.error("Brak procesu Centrum powiadomień")
            return
        }
        pid = app.processIdentifier
        var created: AXObserver?
        guard AXObserverCreate(pid, { _, _, _, refcon in
            guard let refcon else { return }
            let watcher = Unmanaged<NotificationBannerWatcher>.fromOpaque(refcon).takeUnretainedValue()
            MainActor.assumeIsolated { watcher.scan() }
        }, &created) == .success, let created else {
            log.error("Nie udało się utworzyć obserwatora Dostępności")
            return
        }
        let element = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for name in [kAXWindowCreatedNotification, kAXCreatedNotification, kAXLayoutChangedNotification] {
            AXObserverAddNotification(created, element, name as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .defaultMode)
        observer = created
    }

    private func detach() {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observer = nil
    }

    /// Przegląda okna Centrum powiadomień i zgłasza banery, których jeszcze nie widzieliśmy.
    private func scan() {
        let app = AXUIElementCreateApplication(pid)
        for window in AX.children(app, kAXWindowsAttribute) {
            let banners = findBanners(in: window, depth: 0)
            guard !banners.isEmpty else { continue }
            var foundNew = false
            for banner in banners {
                let identifier = AX.string(banner, kAXIdentifierAttribute)
                let texts = Dictionary(AX.children(banner, kAXChildrenAttribute).compactMap { child -> (String, String)? in
                    guard let key = AX.string(child, kAXIdentifierAttribute), let value = AX.string(child, kAXValueAttribute) else { return nil }
                    return (key, value)
                }, uniquingKeysWith: { first, _ in first })
                guard let card = BannerParser.card(identifier: identifier, description: AX.string(banner, kAXDescriptionAttribute),
                                                   texts: texts, at: Date()),
                      !seen.contains(card.id)
                else { continue }
                seen = Array((seen + [card.id]).suffix(Self.seenLimit))
                foundNew = true
                onBanner(card)
            }
            if foundNew, hidesOriginal() { hide(window) }
        }
    }

    /// Chowa baner, przesuwając jego okno poza ekran — powiadomienie zostaje w Centrum powiadomień.
    private func hide(_ window: AXUIElement) {
        guard let size = AX.size(window), size.height <= Self.maxBannerWindowHeight else { return }
        var offscreen = CGPoint(x: -20_000, y: -20_000)
        guard let value = AXValueCreate(.cgPoint, &offscreen) else { return }
        let result = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
        if result != .success { log.error("Nie udało się schować banera: \(result.rawValue)") }
    }

    private func findBanners(in element: AXUIElement, depth: Int) -> [AXUIElement] {
        guard depth < 8 else { return [] }
        if AX.string(element, kAXSubroleAttribute) == BannerParser.bannerSubrole { return [element] }
        return AX.children(element, kAXChildrenAttribute).flatMap { findBanners(in: $0, depth: depth + 1) }
    }
}

/// Odczyt atrybutów Dostępności.
enum AX {
    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    static func children(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return [] }
        return (value as? [AXUIElement]) ?? []
    }

    static func size(_ element: AXUIElement) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(value as! AXValue, .cgSize, &size) ? size : nil
    }
}
