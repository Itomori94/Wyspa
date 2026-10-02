import AppKit
import SwiftUI
import WyspaUI

struct DayView: View {
    let events: [DayEvent]
    let highlighted: String?

    var body: some View {
        let today = events.filter { Calendar.current.isDateInToday($0.start) || ($0.start < Date() && $0.end > Date()) }
        if today.isEmpty {
            Label("Dziś nic więcej w kalendarzu.", systemImage: "calendar.badge.checkmark")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(today) { EventRow(event: $0, isHighlighted: $0.id == highlighted) }
                }
            }
        }
    }
}

private struct EventRow: View {
    let event: DayEvent
    let isHighlighted: Bool
    @State private var isHovered = false

    private var tint: Color { Color(red: event.color[0], green: event.color[1], blue: event.color[2]) }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let isPast = context.date >= event.end
            HStack(spacing: 10) {
                Capsule().fill(tint).frame(width: 4, height: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(event.title).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                    Text(subtitle).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
                }
                Spacer(minLength: 6)
                if !event.isAllDay, !isPast {
                    Text(EventTimeText.countdown(to: event, at: context.date))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(isHighlighted ? tint : .white.opacity(0.6))
                }
                if let url = event.joinURL, !isPast {
                    Button("Dołącz") { NSWorkspace.shared.open(url) }
                        .buttonStyle(IslandCapsuleButtonStyle())
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(isHighlighted ? 0.1 : (isHovered ? 0.06 : 0))))
            .opacity(isPast ? 0.4 : 1)
        }
        .onHover { isHovered = $0 }
    }

    private var subtitle: String {
        let time = event.isAllDay
            ? "Cały dzień"
            : "\(event.start.formatted(.dateTime.hour().minute()))–\(event.end.formatted(.dateTime.hour().minute()))"
        return event.location.map { "\(time) · \($0)" } ?? time
    }
}
