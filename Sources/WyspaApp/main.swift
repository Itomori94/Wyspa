import AppKit
import WyspaNotifications

MainActor.assumeIsolated {
    let app = NSApplication.shared
    // Tryb diagnostyczny: zrzut struktury banerów powiadomień (patrz CLAUDE.md), bez uruchamiania wyspy.
    if CommandLine.arguments.contains(NotificationAXDiagnostics.flag) {
        app.setActivationPolicy(.prohibited)
        NotificationAXDiagnostics.run()
        app.run()
        return
    }
    if CommandLine.arguments.contains(NotificationBannerProbe.flag) {
        app.setActivationPolicy(.prohibited)
        NotificationBannerProbe.run()
        app.run()
        return
    }
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) { app.run() }
}
