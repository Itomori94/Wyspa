import SwiftUI

/// Najbliższe wydarzenia dnia; pierwsze z odliczaniem.
struct CalendarWidget: View {
    let events: [DayEvent]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let upcoming = events.filter { $0.end > context.date && Calendar.current.isDate($0.start, inSameDayAs: context.date) }
            VStack(alignment: .leading, spacing: 6) {
                Text(context.date, format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(.red.opacity(0.9))
                    .textCase(.uppercase)
                if upcoming.isEmpty {
                    Text("Dziś nic więcej").font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
                } else {
                    ForEach(upcoming.prefix(3)) { event in
                        HStack(spacing: 7) {
                            Capsule().fill(Color(red: event.color[0], green: event.color[1], blue: event.color[2]))
                                .frame(width: 3, height: 24)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(event.title).font(.system(size: 11.5, weight: .semibold)).lineLimit(1)
                                Text(event.isAllDay ? "Cały dzień" : EventTimeText.countdown(to: event, at: context.date))
                                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
