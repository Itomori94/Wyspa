import Foundation
import WyspaCore

/// Powiadomienie odczytane z banera macOS.
public struct NotificationCard: Equatable, Identifiable, Sendable {
    /// Identyfikator banera z systemu (ten sam baner nie trafia do wyspy dwa razy).
    public let id: String
    public let appName: String
    public let title: String
    public let subtitle: String?
    public let body: String?
    public let receivedAt: Date

    public init(id: String, appName: String, title: String, subtitle: String?, body: String?, receivedAt: Date) {
        self.id = id
        self.appName = appName
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.receivedAt = receivedAt
    }
}

/// Odczyt banera z drzewa Dostępności (budowa sprawdzona na macOS 27.2):
/// grupa `AXNotificationCenterBanner` z opisem „aplikacja, tytuł, podtytuł, treść”
/// i tekstami o identyfikatorach `title`, `subtitle`, `body`.
public enum BannerParser {
    public static let bannerSubrole = "AXNotificationCenterBanner"

    public static func card(identifier: String?, description: String?, texts: [String: String], at date: Date) -> NotificationCard? {
        let title = texts["title"]?.trimmed
        let subtitle = texts["subtitle"]?.trimmed
        let body = texts["body"]?.trimmed
        guard let headline = title ?? body, !headline.isEmpty else { return nil }
        let id = identifier ?? [description ?? "", headline].joined(separator: "|")
        return NotificationCard(
            id: id,
            appName: appName(from: description, parts: [title, subtitle, body].compactMap { $0 }),
            title: headline,
            subtitle: subtitle?.nilIfEmpty,
            body: title == nil ? nil : body?.nilIfEmpty,
            receivedAt: date
        )
    }

    /// Nazwa aplikacji to początek opisu przed resztą pól (nazwa sama może zawierać przecinek).
    static func appName(from description: String?, parts: [String]) -> String {
        guard let description, !description.isEmpty else { return "Powiadomienie" }
        let suffix = parts.isEmpty ? "" : ", " + parts.joined(separator: ", ")
        if !suffix.isEmpty, description.hasSuffix(suffix) {
            let name = String(description.dropLast(suffix.count))
            if !name.isEmpty { return name }
        }
        return description.components(separatedBy: ", ").first ?? description
    }
}

/// Kolejka powiadomień do pokazania: jedno naraz, reszta czeka. Niemutowalna.
public struct NotificationQueue: Equatable, Sendable {
    public static let maxWaiting = 10

    public let current: NotificationCard?
    public let waiting: [NotificationCard]

    public init(current: NotificationCard? = nil, waiting: [NotificationCard] = []) {
        self.current = current
        self.waiting = waiting
    }

    /// Nowe powiadomienie: pokazane od razu albo dopisane do kolejki (najstarsze odpadają ponad limit).
    public func enqueueing(_ card: NotificationCard) -> NotificationQueue {
        guard current != nil else { return NotificationQueue(current: card, waiting: waiting) }
        return NotificationQueue(current: current, waiting: Array((waiting + [card]).suffix(Self.maxWaiting)))
    }

    /// Bieżące znika, następne z kolejki wchodzi na jego miejsce.
    public func advancing() -> NotificationQueue {
        NotificationQueue(current: waiting.first, waiting: Array(waiting.dropFirst()))
    }

    public func cleared() -> NotificationQueue { NotificationQueue() }
}

/// Wspólne dla odczytu banera i widoku karty (jedno miejsce w module).
extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

/// Powiadomienia wstrzymane na czas skupienia (Pomodoro) i ich podsumowanie po sesji. Czyste funkcje.
public enum FocusDigest {
    /// Ile wstrzymanych kart pamiętamy (starsze liczą się tylko w podsumowaniu).
    public static let maxHeld = 50
    public static let summaryAppName = "Pomodoro"

    public static func holding(_ held: [NotificationCard], _ card: NotificationCard) -> [NotificationCard] {
        Array((held + [card]).suffix(maxHeld))
    }

    /// Po skupieniu: karta z podsumowaniem, a za nią najnowsze wstrzymane (tyle, ile zmieści kolejka).
    public static func release(_ held: [NotificationCard], total: Int, at date: Date) -> [NotificationCard] {
        guard !held.isEmpty else { return [] }
        let summary = NotificationCard(
            id: "focus-digest-\(Int(date.timeIntervalSince1970))",
            appName: summaryAppName,
            title: "Po skupieniu: \(countText(total))",
            subtitle: nil,
            body: appsText(held),
            receivedAt: date
        )
        return [summary] + held.suffix(NotificationQueue.maxWaiting)
    }

    /// „1 powiadomienie”, „3 powiadomienia”, „5 powiadomień”, „22 powiadomienia”.
    public static func countText(_ count: Int) -> String {
        PolishPlural.format(count, one: "powiadomienie", few: "powiadomienia", many: "powiadomień")
    }

    public enum Disposition: Equatable, Sendable {
        /// Karta od razu w wyspie.
        case show
        /// Karta czeka do końca skupienia.
        case hold
        /// Bez karty: system i tak pokazał swój baner, karta po sesji byłaby tym samym powiadomieniem drugi raz.
        case skip
    }

    /// Co zrobić z nowym powiadomieniem. Wstrzymanie ma sens tylko, gdy systemowy baner jest chowany.
    public static func disposition(focusActive: Bool, hidesOriginal: Bool) -> Disposition {
        guard focusActive else { return .show }
        return hidesOriginal ? .hold : .skip
    }

    /// Aplikacje w kolejności pierwszego powiadomienia, najwyżej cztery („Mail, Slack, Wiadomości, Kalendarz +2”).
    static func appsText(_ held: [NotificationCard]) -> String {
        var seen: [String] = []
        for card in held where !seen.contains(card.appName) { seen.append(card.appName) }
        let shown = seen.prefix(4).joined(separator: ", ")
        return seen.count > 4 ? "\(shown) +\(seen.count - 4)" : shown
    }
}
