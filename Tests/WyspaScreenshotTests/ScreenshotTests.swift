import AppKit
import SwiftUI
import Testing
@testable import WyspaBluetooth
@testable import WyspaClaudeMonitor
@testable import WyspaClipboard
@testable import WyspaCore
@testable import WyspaDownloads
@testable import WyspaHookKit
@testable import WyspaHUD
@testable import WyspaMedia
@testable import WyspaNotifications
@testable import WyspaQuickActions
@testable import WyspaTimer
@testable import WyspaUI
@testable import WyspaWeather

// Zrzuty ekranu do README z danymi demonstracyjnymi (żadnych prywatnych treści).
// Uruchamianie: scripts/screenshots.sh — bez zmiennej WYSPA_SCREENSHOTS_DIR test jest pomijany.

private let outputDirectory = ProcessInfo.processInfo.environment["WYSPA_SCREENSHOTS_DIR"]

@MainActor
private final class NoPermissions: PermissionProviding {
    func status(of permission: Permission) -> PermissionStatus { .granted }
    func request(_ permission: Permission) async -> PermissionStatus { .granted }
}

/// Miejsca na moduły w wyspie: każde pokazuje widok prawdziwego modułu z danymi demonstracyjnymi.
@MainActor
private enum Stage {
    static var expanded: [String: AnyView] = [:]
    static var widgets: [String: AnyView] = [:]
    static var activity: (slot: String, activity: LiveActivity)?
}

@MainActor @Observable private class SlotBase {
    required init(context: ModuleContext) {}
    func activate() async throws {}
    func deactivate() {}
    func liveActivity(for id: String) -> LiveActivity? { Stage.activity?.slot == id ? Stage.activity?.activity : nil }
}

private func slot(_ id: String, _ name: String, _ symbol: String) -> ModuleDescriptor {
    ModuleDescriptor(id: id, name: name, summary: "", symbol: symbol, content: .neutral, widgetMinWidth: 60)
}

@MainActor @Observable private final class MediaSlot: SlotBase, IslandModule {
    static let descriptor = slot("media", "Teraz odtwarzane", "music.note")
    var liveActivity: LiveActivity? { liveActivity(for: "media") }
    func makeExpandedView() -> AnyView? { Stage.expanded["media"] }
    func makeWidgetView() -> AnyView? { Stage.widgets["media"] }
}
@MainActor @Observable private final class TimerSlot: SlotBase, IslandModule {
    static let descriptor = slot("timer", "Timer", "timer")
    var liveActivity: LiveActivity? { liveActivity(for: "timer") }
    func makeExpandedView() -> AnyView? { Stage.expanded["timer"] }
    func makeWidgetView() -> AnyView? { Stage.widgets["timer"] }
}
@MainActor @Observable private final class WeatherSlot: SlotBase, IslandModule {
    static let descriptor = slot("weather", "Pogoda", "cloud.sun.fill")
    var liveActivity: LiveActivity? { liveActivity(for: "weather") }
    func makeExpandedView() -> AnyView? { Stage.expanded["weather"] }
    func makeWidgetView() -> AnyView? { Stage.widgets["weather"] }
}
@MainActor @Observable private final class ClaudeSlot: SlotBase, IslandModule {
    static let descriptor = slot("claude", "Claude Code", "terminal.fill")
    var liveActivity: LiveActivity? { liveActivity(for: "claude") }
    func makeExpandedView() -> AnyView? { Stage.expanded["claude"] }
}
@MainActor @Observable private final class ClipboardSlot: SlotBase, IslandModule {
    static let descriptor = slot("clipboard", "Historia schowka", "doc.on.clipboard")
    var liveActivity: LiveActivity? { liveActivity(for: "clipboard") }
    func makeExpandedView() -> AnyView? { Stage.expanded["clipboard"] }
}
@MainActor @Observable private final class QuickSlot: SlotBase, IslandModule {
    static let descriptor = slot("quick", "Szybkie akcje", "bolt.circle.fill")
    var liveActivity: LiveActivity? { liveActivity(for: "quick") }
    func makeExpandedView() -> AnyView? { Stage.expanded["quick"] }
    func makeWidgetView() -> AnyView? { Stage.widgets["quick"] }
}
@MainActor @Observable private final class BluetoothSlot: SlotBase, IslandModule {
    static let descriptor = slot("bluetooth", "Bluetooth", "headphones")
    var liveActivity: LiveActivity? { liveActivity(for: "bluetooth") }
    func makeExpandedView() -> AnyView? { Stage.expanded["bluetooth"] }
}
@MainActor @Observable private final class AlertSlot: SlotBase, IslandModule {
    static let descriptor = slot("alerts", "Powiadomienia", "bell.badge.fill")
    var liveActivity: LiveActivity? { liveActivity(for: "alerts") }
    func makeExpandedView() -> AnyView? { nil }
}

@Suite("Zrzuty ekranu do README", .serialized, .enabled(if: outputDirectory != nil))
@MainActor
struct ScreenshotTests {
    static let notch = NotchMetrics(size: CGSize(width: 185, height: 38), isPhysical: true)
    static let expandedSize = IslandSize.medium.expandedSize
    static let catalog: [any IslandModule.Type] = [MediaSlot.self, TimerSlot.self, WeatherSlot.self, ClaudeSlot.self,
                                                   ClipboardSlot.self, QuickSlot.self, BluetoothSlot.self, AlertSlot.self]

    private func context(_ id: String) -> ModuleContext {
        ModuleContext(settings: SettingsStore(defaults: UserDefaults(suiteName: "wyspa.shots.\(id)")!).moduleSettings(for: id),
                      requestExpand: {})
    }

    // MARK: - Dane demonstracyjne

    private func artwork() -> Data {
        let image = NSImage(size: NSSize(width: 300, height: 300), flipped: false) { rect in
            NSGradient(colors: [NSColor(calibratedRed: 0.98, green: 0.45, blue: 0.25, alpha: 1),
                                NSColor(calibratedRed: 0.62, green: 0.18, blue: 0.75, alpha: 1)])?.draw(in: rect, angle: -45)
            let symbol = NSImage(systemSymbolName: "music.note", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 120, weight: .bold))
            symbol?.draw(in: NSRect(x: 90, y: 75, width: 120, height: 150), from: .zero, operation: .sourceOver, fraction: 0.85)
            return true
        }
        let tiff = image.tiffRepresentation!
        return NSBitmapImageRep(data: tiff)!.representation(using: .png, properties: [:])!
    }

    private func prepare() async throws {
        let media = MediaModule(context: context("media"))
        media.showDemo(NowPlaying(bundleIdentifier: "com.apple.Music", title: "Nocne miasto", artist: "Wyspa Band",
                                  album: "Notch Sessions", duration: 214, elapsedTime: 81, timestamp: Date(),
                                  playbackRate: 0, isPlaying: true), artworkData: artwork())
        Stage.expanded["media"] = media.makeExpandedView()
        Stage.widgets["media"] = media.makeWidgetView()

        let timer = TimerModule(context: context("timer"))
        let today = Date()
        var stats = FocusStats()
        for _ in 0..<3 { stats = stats.recording(minutes: 25, at: today) }
        timer.showDemo(session: TimerSession(kind: .pomodoro(phase: .focus, completedFocus: 3, config: .standard),
                                             startedAt: Date().addingTimeInterval(-9 * 60 - 12)), stats: stats, goal: 8)
        Stage.expanded["timer"] = timer.makeExpandedView()
        Stage.widgets["timer"] = timer.makeWidgetView()
        Stage.timerActivity = timer.liveActivity

        let weather = WeatherModule(context: context("weather"))
        let calendar = Calendar.current
        let days = (0..<4).map { offset in
            Forecast.Day(date: calendar.date(byAdding: .day, value: offset, to: today)!, code: [2, 61, 3, 0][offset],
                         high: [19, 15, 16, 21][offset], low: [9, 8, 7, 10][offset])
        }
        weather.showDemo(Forecast(temperature: 18.4, code: 2, isDay: true, days: days, fetchedAt: Date()))
        Stage.expanded["weather"] = weather.makeExpandedView()
        Stage.widgets["weather"] = weather.makeWidgetView()

        let claude = ClaudeMonitorModule(context: context("claude"))
        func envelope(_ event: [String: Any]) -> HookProtocol.Envelope {
            HookProtocol.Envelope(event: try! HookEvent.parse(event), claudePID: nil, bundleID: "com.apple.Terminal",
                                  termProgram: nil, wantsReply: false)
        }
        var store = SessionStore()
        let now = Date()
        (store, _) = store.applying(envelope(["hook_event_name": "UserPromptSubmit", "session_id": "a", "cwd": "/Users/demo/wyspa"]),
                                    at: now.addingTimeInterval(-7 * 60))
        for command in ["swift build", "scripts/test.sh"] {
            (store, _) = store.applying(envelope(["hook_event_name": "PreToolUse", "session_id": "a", "cwd": "/Users/demo/wyspa",
                                                  "tool_name": "Bash", "tool_input": ["command": command]]), at: now)
        }
        (store, _) = store.applying(envelope(["hook_event_name": "Stop", "session_id": "b", "cwd": "/Users/demo/strona-www",
                                              "last_assistant_message": "Gotowe! Dodałem tryb ciemny i poprawiłem menu na telefonie. Wszystkie testy przechodzą."]),
                                    at: now.addingTimeInterval(-60))
        let limits = ClaudeLimits(fiveHour: .init(usedPercentage: 34, resetsAt: now.addingTimeInterval(2 * 3600 + 600)),
                                  sevenDay: .init(usedPercentage: 58, resetsAt: now.addingTimeInterval(3 * 86_400)))
        claude.showDemo(store: store, limits: limits, finished: store.sessions["b"])
        Stage.expanded["claude"] = claude.makeExpandedView()
        Stage.claudeFinished = claude.liveActivity

        let clipboard = ClipboardModule(context: context("clipboard"))
        var history = ClipboardHistory()
        for (index, text) in ["ul. Wyspowa 12, 00-001 Warszawa", "https://github.com/Itomori94/Wyspa",
                              "Do zrobienia: zrzuty ekranu do README", "brew install --cask wyspa"].enumerated().reversed() {
            history = history.adding(ClipboardEntry(content: .text(text), copiedAt: now.addingTimeInterval(Double(-index * 300))))
        }
        clipboard.showDemo(history)
        Stage.expanded["clipboard"] = clipboard.makeExpandedView()

        let quick = QuickActionsModule(context: context("quick"))
        Stage.expanded["quick"] = quick.makeExpandedView()
        Stage.widgets["quick"] = quick.makeWidgetView()

        let bluetooth = BluetoothModule(context: context("bluetooth"))
        let airpods = ConnectedDevice(id: "1", name: "AirPods Pro", kind: .airPodsPro,
                                      battery: BatteryLevels(left: 82, right: 79, caseLevel: 55))
        let mouse = ConnectedDevice(id: "2", name: "Magic Mouse", kind: .mouse, battery: BatteryLevels(single: 64))
        bluetooth.showDemo([airpods, mouse], event: .connected(airpods))
        Stage.expanded["bluetooth"] = bluetooth.makeExpandedView()
        Stage.bluetoothActivity = bluetooth.liveActivity

        Stage.mediaActivity = media.liveActivity

        let hud = HUDModule(context: context("hud"))
        hud.showDemo(HUDReading(kind: .volume, level: 0.62))
        Stage.hudActivity = hud.liveActivity

        let notifications = NotificationsModule(context: context("alerts"))
        notifications.showDemo(NotificationQueue().enqueueing(NotificationCard(
            id: "1", appName: "Wiadomości", title: "Ola", subtitle: nil, body: "Widzimy się o 18 przy fontannie?", receivedAt: now)))
        Stage.notificationActivity = notifications.liveActivity

        let downloads = DownloadsModule(context: context("downloads"))
        downloads.showDemo([DownloadItem(id: UUID(), fileURL: URL(fileURLWithPath: "/Users/demo/Downloads/Wyspa.dmg.download"), fraction: 0.64)])
        Stage.downloadsActivity = downloads.liveActivity
    }

    // MARK: - Renderowanie

    private func board() throws -> (IslandBoard, [String: Int]) {
        var board = IslandBoard().addingModulePage("media")
        let (withWidgets, page) = board.addingWidgetPage()
        board = withWidgets
        for id in ["media", "timer", "weather"] {
            board = try board.inserting(moduleID: id, intoPage: page, at: .max, minimum: { _ in WidgetWidth(units: 30) })
        }
        for id in ["claude", "timer", "weather", "clipboard", "quick", "bluetooth"] { board = board.addingModulePage(id) }
        let (withQuick, quickPage) = board.addingWidgetPage()
        board = withQuick
        for id in ["media", "quick"] {
            board = try board.inserting(moduleID: id, intoPage: quickPage, at: .max, minimum: { _ in WidgetWidth(units: 30) })
        }
        let tabs = ["media": 0, "widgets": 1, "claude": 2, "timer": 3, "weather": 4, "clipboard": 5, "quick": 6, "bluetooth": 7,
                    "quick-widget": 8]
        return (board, tabs)
    }

    private func render(_ name: String, phase: IslandPhase, tab: String? = nil, activity: (String, LiveActivity?)? = nil) async throws {
        Stage.activity = activity.flatMap { slot, activity in activity.map { (slot, $0) } }
        let settings = SettingsStore(defaults: UserDefaults(suiteName: "wyspa.shots.registry.\(UUID())")!)
        let registry = ModuleRegistry(catalog: Self.catalog, settings: settings, permissions: NoPermissions(), requestExpand: { _ in })
        for type in Self.catalog { await registry.setEnabled(type.descriptor.id, true) }
        let (board, tabs) = try board()
        registry.setBoard(board)
        let model = IslandViewModel(phase: phase, notch: Self.notch, expandedSize: Self.expandedSize, registry: registry)
        model.selectedTab = tab.flatMap { tabs[$0] } ?? 0
        let panel = IslandLayout.panelSize(expanded: Self.expandedSize, notch: Self.notch.size, shadowMargin: 36)
        let canvas = CGSize(width: panel.width + 80, height: panel.height + 20)
        let view = ZStack(alignment: .top) {
            LinearGradient(colors: [Color(red: 0.36, green: 0.22, blue: 0.62), Color(red: 0.12, green: 0.32, blue: 0.62)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            IslandView(model: model).frame(width: panel.width, height: panel.height)
        }
        .frame(width: canvas.width, height: canvas.height)
        let host = NSHostingView(rootView: view)
        host.frame = CGRect(origin: .zero, size: canvas)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(400))
        host.layoutSubtreeIfNeeded()
        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let png = try #require(rep.representation(using: .png, properties: [:]))
        // Kadrowanie: tylko wysokość wyspy (z cieniem), żeby obrazki w README nie miały pustego tła.
        let island = model.islandSize
        let scale = CGFloat(rep.pixelsWide) / canvas.width
        let cropHeight = min(CGFloat(rep.pixelsHigh), (island.height + 30) * scale)
        let cropWidth = min(CGFloat(rep.pixelsWide), (island.width + 120) * scale)
        let image = NSImage(data: png)!.cgImage(forProposedRect: nil, context: nil, hints: nil)!
        let cropped = image.cropping(to: CGRect(x: (CGFloat(image.width) - cropWidth) / 2, y: 0, width: cropWidth, height: cropHeight))!
        let output = NSBitmapImageRep(cgImage: cropped).representation(using: .png, properties: [:])!
        try output.write(to: URL(fileURLWithPath: outputDirectory!).appendingPathComponent("\(name).png"))
    }

    @Test("Zrzuty wszystkich funkcji")
    func screenshots() async throws {
        try await prepare()
        try await render("zwinieta-muzyka", phase: .collapsed, activity: ("media", Stage.mediaActivity))
        try await render("zwinieta-glosnosc", phase: .collapsed, activity: ("media", Stage.hudActivity))
        try await render("zwinieta-powiadomienie", phase: .collapsed, activity: ("alerts", Stage.notificationActivity))
        try await render("zwinieta-claude", phase: .collapsed, activity: ("claude", Stage.claudeFinished))
        try await render("zwinieta-pobieranie", phase: .collapsed, activity: ("media", Stage.downloadsActivity))
        try await render("zwinieta-timer", phase: .collapsed, activity: ("timer", Stage.timerActivity))
        try await render("zwinieta-bluetooth", phase: .collapsed, activity: ("bluetooth", Stage.bluetoothActivity))
        try await render("odtwarzacz", phase: .expanded, tab: "media")
        try await render("widzety", phase: .expanded, tab: "widgets")
        try await render("claude-code", phase: .expanded, tab: "claude")
        try await render("pomodoro", phase: .expanded, tab: "timer")
        try await render("pogoda", phase: .expanded, tab: "weather")
        try await render("schowek", phase: .expanded, tab: "clipboard")
        try await render("szybkie-akcje", phase: .expanded, tab: "quick")
        try await render("szybkie-akcje-widzet", phase: .expanded, tab: "quick-widget")
        try await render("bluetooth", phase: .expanded, tab: "bluetooth")
    }
}

@MainActor
private extension Stage {
    static var mediaActivity: LiveActivity?
    static var hudActivity: LiveActivity?
    static var notificationActivity: LiveActivity?
    static var claudeFinished: LiveActivity?
    static var downloadsActivity: LiveActivity?
    static var timerActivity: LiveActivity?
    static var bluetoothActivity: LiveActivity?
}
