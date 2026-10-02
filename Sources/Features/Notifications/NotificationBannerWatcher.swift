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
    private static let seenLimit = 200

    private let onBanner: @MainActor (NotificationCard) -> Void
    private let hidesOriginal: @MainActor () -> Bool
    private var observer: AXObserver?
    private var pid: pid_t = 0
    private var seen: [String] = []
    /// Okno banerów przesunięte poza ekran i jego pierwotne położenie — wraca, gdy banerów już nie ma.
    /// (Na macOS 27 to okno ma rozmiar całego ekranu i to w nim otwiera się Centrum powiadomień.)
    private var hiddenWindow: (window: AXUIElement, origin: CGPoint)?
    /// Okno dalej niż tu uznajemy za schowane przez nas (np. po awarii Wyspy) i przywracamy przy starcie.
    private static let offscreenThreshold: CGFloat = -10_000
    /// Po schowaniu: jednorazowe sprawdzenie, gdyby system nie zgłosił zniknięcia banera.
    private static let restoreCheckDelay: Duration = .seconds(8)
    private static let attachRetries = 3
    private var observedElement: AXUIElement?
    private var retryTask: Task<Void, Never>?
    private var restoreCheckTask: Task<Void, Never>?
    private static let observedNotifications = [kAXWindowCreatedNotification, kAXCreatedNotification,
                                                kAXLayoutChangedNotification, kAXUIElementDestroyedNotification]
    private var launchObserver: NSObjectProtocol?
    private let log = Log.logger("notifications")

    init(hidesOriginal: @escaping @MainActor () -> Bool, onBanner: @escaping @MainActor (NotificationCard) -> Void) {
        self.hidesOriginal = hidesOriginal
        self.onBanner = onBanner
    }

    func start() {
        attach(attempt: 1)
        let bundleID = Self.bundleID
        // Centrum powiadomień bywa restartowane przez system — podpinamy się ponownie.
        launchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let launched = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard launched?.bundleIdentifier == bundleID else { return }
            MainActor.assumeIsolated { self?.attach(attempt: 1) }
        }
    }

    func stop() {
        retryTask?.cancel()
        restoreCheckTask?.cancel()
        detach()
        if let launchObserver { NSWorkspace.shared.notificationCenter.removeObserver(launchObserver) }
        launchObserver = nil
        seen = []
    }

    /// Podpina obserwatora. Tuż po uruchomieniu Centrum powiadomień rejestracja potrafi się nie udać — wtedy
    /// kilka jednorazowych ponowień (bez stałego zegara).
    private func attach(attempt: Int) {
        detach()
        retryTask?.cancel()
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
        let registered = Self.observedNotifications.filter { name in
            AXObserverAddNotification(created, element, name as CFString, refcon) == .success
        }
        guard !registered.isEmpty else {
            log.error("Centrum powiadomień nie przyjęło obserwatora (próba \(attempt))")
            guard attempt < Self.attachRetries else { return }
            retryTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(attempt))
                guard !Task.isCancelled else { return }
                self?.attach(attempt: attempt + 1)
            }
            return
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .defaultMode)
        observer = created
        observedElement = element
        healOffscreenWindows(of: element)
    }

    /// Okno banerów zostawione poza ekranem (np. po awarii Wyspy w trakcie chowania) wraca na miejsce.
    private func healOffscreenWindows(of app: AXUIElement) {
        for window in AX.children(app, kAXWindowsAttribute) {
            guard let position = AX.position(window), position.x <= Self.offscreenThreshold else { continue }
            var origin = CGPoint.zero
            if let value = AXValueCreate(.cgPoint, &origin) {
                AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
            }
        }
    }

    private func detach() {
        restoreHiddenWindow()
        if let observer {
            if let observedElement {
                for name in Self.observedNotifications {
                    AXObserverRemoveNotification(observer, observedElement, name as CFString)
                }
            }
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observedElement = nil
        observer = nil
    }

    /// Przegląda okna Centrum powiadomień i zgłasza banery, których jeszcze nie widzieliśmy.
    private func scan() {
        let app = AXUIElementCreateApplication(pid)
        var anyBanner = false
        for window in AX.children(app, kAXWindowsAttribute) {
            let banners = findBanners(in: window, depth: 0)
            guard !banners.isEmpty else { continue }
            anyBanner = true
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
        // Banery zniknęły: okno wraca na miejsce, żeby Centrum powiadomień otwierało się normalnie.
        if !anyBanner { restoreHiddenWindow() }
    }

    /// Chowa baner, przesuwając jego okno poza ekran — powiadomienie zostaje w Centrum powiadomień.
    private func hide(_ window: AXUIElement) {
        if hiddenWindow == nil, let origin = AX.position(window), origin.x > Self.offscreenThreshold {
            hiddenWindow = (window, origin)
        }
        restoreCheckTask?.cancel()
        restoreCheckTask = Task { [weak self] in
            try? await Task.sleep(for: Self.restoreCheckDelay)
            guard !Task.isCancelled else { return }
            self?.scan()
        }
        var offscreen = CGPoint(x: -20_000, y: -20_000)
        guard let value = AXValueCreate(.cgPoint, &offscreen) else { return }
        let result = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
        if result != .success { log.error("Nie udało się schować banera: \(result.rawValue)") }
    }

    private func restoreHiddenWindow() {
        guard let (window, origin) = hiddenWindow else { return }
        hiddenWindow = nil
        var point = origin
        guard let value = AXValueCreate(.cgPoint, &point) else { return }
        let result = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
        if result != .success { log.error("Nie udało się przywrócić okna banerów: \(result.rawValue)") }
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

    static func position(_ element: AXUIElement) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(value as! AXValue, .cgPoint, &point) ? point : nil
    }
}
