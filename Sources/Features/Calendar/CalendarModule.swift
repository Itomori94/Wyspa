import AppKit
import EventKit
import SwiftUI
import WyspaCore

/// Kalendarz: plan dnia w zakładce i najbliższe wydarzenie w zwiniętej wyspie na 10 minut przed startem.
@MainActor
@Observable
public final class CalendarModule: IslandModule {
    public static let descriptor = ModuleDescriptor(
        id: "calendar",
        name: "Kalendarz",
        summary: "Plan dnia i najbliższe spotkanie w zwiniętej wyspie na 10 minut przed startem, z przyciskiem „Dołącz”.",
        symbol: "calendar",
        permissions: [.calendars]
    )

    public private(set) var events: [DayEvent] = []
    public private(set) var active: DayEvent?

    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private var observer: NSObjectProtocol?
    @ObservationIgnored private var wakeTask: Task<Void, Never>?

    public required init(context: ModuleContext) {}

    public func activate() async throws {
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
        reload()
    }

    public func deactivate() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        wakeTask?.cancel()
        wakeTask = nil
        events = []
        active = nil
    }

    public var liveActivity: LiveActivity? {
        guard let active else { return nil }
        let tint = Color(red: active.color[0], green: active.color[1], blue: active.color[2])
        return LiveActivity(id: "calendar", priority: .upcomingEvent, accent: tint, wingWidth: 56) {
            Image(systemName: active.joinURL == nil ? "calendar" : "video.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
        } trailing: {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text(EventTimeText.short(to: active, at: context.date))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tint)
            }
        }
    }

    public func makeExpandedView() -> AnyView? {
        AnyView(DayView(events: events, highlighted: active?.id))
    }

    private func reload() {
        let now = Date()
        let dayStart = Calendar.current.startOfDay(for: now)
        // Dziś oraz najbliższe 24 h (spotkanie tuż po północy też dostanie zapowiedź).
        let predicate = store.predicateForEvents(withStart: dayStart, end: now.addingTimeInterval(24 * 3600), calendars: nil)
        events = store.events(matching: predicate)
            .filter { $0.status != .canceled && $0.endDate > dayStart }
            .sorted { $0.startDate < $1.startDate }
            .map(Self.makeEvent)
        refreshActive()
    }

    /// Aktualizuje aktywność i planuje jedno wybudzenie na następną zmianę.
    private func refreshActive() {
        let now = Date()
        let next = UpcomingEventPolicy.activeEvent(in: events, at: now)
        if next != active { withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { active = next } }
        wakeTask?.cancel()
        let wake = UpcomingEventPolicy.nextWake(for: events, after: now)
        wakeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(1, wake.timeIntervalSinceNow)))
            guard !Task.isCancelled else { return }
            // Po północy plan dnia się zmienia — przeładuj całość.
            self?.reload()
        }
    }

    private static func makeEvent(_ event: EKEvent) -> DayEvent {
        let rgb = (event.calendar.color ?? .systemBlue).usingColorSpace(.sRGB) ?? .systemBlue
        return DayEvent(
            id: event.calendarItemIdentifier + "@" + String(event.startDate.timeIntervalSince1970),
            title: event.title?.isEmpty == false ? event.title : "Bez tytułu",
            start: event.startDate,
            end: event.endDate,
            isAllDay: event.isAllDay,
            location: event.location?.isEmpty == false ? event.location : nil,
            joinURL: MeetingLinkFinder.find(in: [event.url?.absoluteString, event.location, event.notes]),
            color: [rgb.redComponent, rgb.greenComponent, rgb.blueComponent]
        )
    }
}
