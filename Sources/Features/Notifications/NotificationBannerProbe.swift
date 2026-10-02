import AppKit
import ApplicationServices
import WyspaCore

/// Diagnostyka zachowania banerów: które zdarzenia Dostępności przychodzą i czy okno banera da się przesunąć.
///
/// Uruchamiana ręcznie: `open -n Wyspa.app --args --probe-notification-banner`. Zapisuje do pliku tylko nazwy zdarzeń,
/// kody błędów i liczbę banerów — bez treści powiadomień.
public enum NotificationBannerProbe {
    public static let flag = "--probe-notification-banner"
    static let duration: TimeInterval = 60

    @MainActor
    public static func run() {
        let output = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/Wyspa/notification-probe.txt")
        try? FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.notificationcenterui").first else {
            write(["Brak procesu Centrum powiadomień"], to: output)
            NSApp.terminate(nil)
            return
        }
        let session = ProbeSession(pid: app.processIdentifier, output: output)
        session.start()
        Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { _ in
            MainActor.assumeIsolated { session.finish() }
        }
    }

    static func write(_ lines: [String], to url: URL) {
        FileManager.default.createFile(atPath: url.path, contents: Data(lines.joined(separator: "\n").utf8),
                                       attributes: [.posixPermissions: 0o600])
    }

    @MainActor
    final class ProbeSession {
        let pid: pid_t
        let output: URL
        var lines: [String] = []
        var observer: AXObserver?
        var moved = Set<String>()

        init(pid: pid_t, output: URL) {
            self.pid = pid
            self.output = output
            lines.append("Zaufanie Dostępności: \(AXIsProcessTrusted()), pid \(pid)")
        }

        func start() {
            var observer: AXObserver?
            let status = AXObserverCreate(pid, { _, element, name, refcon in
                guard let refcon else { return }
                let session = Unmanaged<ProbeSession>.fromOpaque(refcon).takeUnretainedValue()
                let notification = name as String
                MainActor.assumeIsolated { session.handle(notification) }
                _ = element
            }, &observer)
            lines.append("AXObserverCreate: \(status.rawValue)")
            guard let observer else { return }
            self.observer = observer
            let app = AXUIElementCreateApplication(pid)
            let refcon = Unmanaged.passUnretained(self).toOpaque()
            for name in [kAXWindowCreatedNotification, kAXCreatedNotification, kAXUIElementDestroyedNotification,
                         kAXLayoutChangedNotification, kAXFocusedWindowChangedNotification] {
                let result = AXObserverAddNotification(observer, app, name as CFString, refcon)
                lines.append("rejestracja \(name): \(result.rawValue)")
            }
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }

        func handle(_ notification: String) {
            let banners = currentBanners()
            lines.append("\(Date().formatted(.dateTime.hour().minute().second())) zdarzenie \(notification), banery: \(banners.count)")
            for (identifier, window) in banners where !moved.contains(identifier) {
                moved.insert(identifier)
                // Próba schowania: przesunięcie okna banera poza ekran.
                var point = CGPoint(x: -10_000, y: -10_000)
                let value = AXValueCreate(.cgPoint, &point)!
                let result = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
                lines.append("  przesunięcie okna banera: kod \(result.rawValue)")
            }
        }

        /// Banery (identyfikator → okno) w oknach Centrum powiadomień.
        func currentBanners() -> [(String, AXUIElement)] {
            let app = AXUIElementCreateApplication(pid)
            return NotificationAXDiagnostics.children(of: app, attribute: kAXWindowsAttribute).flatMap { window in
                bannerIdentifiers(in: window, depth: 0).map { ($0, window) }
            }
        }

        func bannerIdentifiers(in element: AXUIElement, depth: Int) -> [String] {
            guard depth < 8 else { return [] }
            if NotificationAXDiagnostics.string(element, kAXSubroleAttribute) == "AXNotificationCenterBanner" {
                return [NotificationAXDiagnostics.string(element, kAXIdentifierAttribute) ?? "?"]
            }
            return NotificationAXDiagnostics.children(of: element, attribute: kAXChildrenAttribute)
                .flatMap { bannerIdentifiers(in: $0, depth: depth + 1) }
        }

        func finish() {
            write(lines, to: output)
            NSApp.terminate(nil)
        }
    }
}
