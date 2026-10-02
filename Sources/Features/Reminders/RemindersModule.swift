import EventKit
import SwiftUI
import WyspaCore
import WyspaUI

/// Przypomnienia na dziś i zaległe, z odhaczaniem w wyspie.
@MainActor
@Observable
public final class RemindersModule: IslandModule {
    public static let descriptor = ModuleDescriptor(
        id: "reminders",
        name: "Przypomnienia",
        summary: "Przypomnienia na dziś i zaległe; odhaczasz je jednym kliknięciem.",
        symbol: "checklist",
        content: .personal,
        permissions: [.reminders],
        widgetMinWidth: 140
    )

    public private(set) var sections = ReminderSections.Grouped(overdue: [], today: [])
    public private(set) var problem: String?

    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private var observer: NSObjectProtocol?
    @ObservationIgnored private var midnightTask: Task<Void, Never>?
    @ObservationIgnored private var reminders: [String: EKReminder] = [:]

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
        midnightTask?.cancel()
        reminders = [:]
        sections = ReminderSections.Grouped(overdue: [], today: [])
    }

    public var liveActivity: LiveActivity? { nil }

    public func makeExpandedView() -> AnyView? { AnyView(RemindersView(module: self)) }
    public func makeWidgetView() -> AnyView? { AnyView(RemindersView(module: self, compact: true)) }

    func complete(_ item: ReminderItem) {
        guard let reminder = reminders[item.id] else { return }
        reminder.isCompleted = true
        do {
            try store.save(reminder, commit: true)
            problem = nil
        } catch {
            problem = "Nie udało się odhaczyć: \(error.localizedDescription)"
        }
    }

    private func reload() {
        let now = Date()
        let endOfToday = Calendar.current.startOfDay(for: now).addingTimeInterval(24 * 3600)
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: endOfToday, calendars: nil)
        store.fetchReminders(matching: predicate) { [weak self] fetched in
            let boxed = ReminderBox(items: fetched ?? [])
            Task { @MainActor in self?.apply(boxed, now: now) }
        }
        scheduleMidnightReload()
    }

    private func apply(_ box: ReminderBox, now: Date) {
        reminders = Dictionary(box.items.map { ($0.calendarItemIdentifier, $0) }, uniquingKeysWith: { first, _ in first })
        let items = box.items.map { reminder in
            ReminderItem(
                id: reminder.calendarItemIdentifier,
                title: reminder.title ?? "Bez tytułu",
                due: reminder.dueDateComponents?.date ?? reminder.dueDateComponents.flatMap { Calendar.current.date(from: $0) },
                listName: reminder.calendar?.title ?? "",
                priority: reminder.priority
            )
        }
        sections = ReminderSections.group(items, now: now)
    }

    private func scheduleMidnightReload() {
        midnightTask?.cancel()
        let midnight = Calendar.current.startOfDay(for: Date()).addingTimeInterval(24 * 3600)
        midnightTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(1, midnight.timeIntervalSinceNow)))
            guard !Task.isCancelled else { return }
            self?.reload()
        }
    }
}

/// EKReminder nie jest Sendable; obiekty przechodzą z wątku EventKit na główny bez współdzielenia.
private struct ReminderBox: @unchecked Sendable {
    let items: [EKReminder]
}

struct RemindersView: View {
    let module: RemindersModule
    var compact = false

    var body: some View {
        let sections = module.sections
        if sections.overdue.isEmpty && sections.today.isEmpty {
            Label(module.problem ?? "Na dziś wszystko zrobione.", systemImage: "checkmark.circle")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if compact {
                        SectionTitle(text: "Przypomnienia", tint: .white.opacity(0.5))
                        ForEach(Array((sections.overdue + sections.today).prefix(5))) { ReminderRow(item: $0, complete: module.complete) }
                    } else {
                        if !sections.overdue.isEmpty {
                            SectionTitle(text: "Zaległe", tint: .red)
                            ForEach(sections.overdue) { ReminderRow(item: $0, complete: module.complete) }
                        }
                        if !sections.today.isEmpty {
                            SectionTitle(text: "Dziś", tint: .white.opacity(0.5))
                            ForEach(sections.today) { ReminderRow(item: $0, complete: module.complete) }
                        }
                    }
                }
            }
        }
    }
}

private struct SectionTitle: View {
    let text: String
    let tint: Color
    var body: some View {
        Text(text.uppercased()).font(.system(size: 9.5, weight: .bold)).foregroundStyle(tint).padding(.top, 4)
    }
}

private struct ReminderRow: View {
    let item: ReminderItem
    let complete: (ReminderItem) -> Void
    @State private var done = false
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.spring(response: 0.25)) { done = true }
                complete(item)
            } label: {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15))
                    .foregroundStyle(done ? .green : .white.opacity(isHovered ? 0.8 : 0.45))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(IslandPressStyle())
            .onHover { isHovered = $0 }
            .accessibilityLabel("Oznacz jako zrobione")
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).font(.system(size: 12.5)).strikethrough(done).lineLimit(1)
                Text(detail).font(.system(size: 10)).foregroundStyle(.white.opacity(0.45)).lineLimit(1)
            }
        }
        .padding(.vertical, 3)
        .opacity(done ? 0.5 : 1)
    }

    private var detail: String {
        let time = item.due.map { $0.formatted(.dateTime.day().month(.abbreviated).hour().minute()) }
        return [item.listName, time].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

#if DEBUG
extension RemindersModule {
    /// Dane demonstracyjne do zrzutów ekranu w README (tylko build debug).
    func showDemo(_ demo: ReminderSections.Grouped) {
        sections = demo
    }
}
#endif
