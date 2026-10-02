import Foundation

public struct ReminderItem: Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let due: Date?
    public let listName: String
    public let priority: Int

    public init(id: String, title: String, due: Date?, listName: String, priority: Int = 0) {
        self.id = id
        self.title = title
        self.due = due
        self.listName = listName
        self.priority = priority
    }
}

public enum ReminderSections {
    public struct Grouped: Equatable, Sendable {
        public let overdue: [ReminderItem]
        public let today: [ReminderItem]
    }

    /// Zaległe (termin przed dziś) i na dziś; najpierw ważniejsze (priorytet 1 = wysoki), potem po terminie.
    public static func group(_ items: [ReminderItem], now: Date, calendar: Calendar = .current) -> Grouped {
        let startOfToday = calendar.startOfDay(for: now)
        let endOfToday = startOfToday.addingTimeInterval(24 * 3600)
        let ordered = items.sorted { lhs, rhs in
            let left = lhs.priority == 0 ? Int.max : lhs.priority
            let right = rhs.priority == 0 ? Int.max : rhs.priority
            if left != right { return left < right }
            return (lhs.due ?? .distantFuture) < (rhs.due ?? .distantFuture)
        }
        return Grouped(
            overdue: ordered.filter { ($0.due ?? .distantFuture) < startOfToday },
            today: ordered.filter { guard let due = $0.due else { return false }; return due >= startOfToday && due < endOfToday }
        )
    }
}
