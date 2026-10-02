import Foundation
import Testing
@testable import WyspaNotifications

@Suite("Odczyt banera powiadomienia")
struct BannerParserTests {
    let now = Date(timeIntervalSince1970: 0)

    @Test("Baner z tytułem, podtytułem i treścią (budowa z macOS 27.2)")
    func full() throws {
        let card = try #require(BannerParser.card(
            identifier: "20E10605", description: "Edytor skryptów, Wyspa — test, Czy widzisz ten baner?, Treść testowa",
            texts: ["title": "Wyspa — test", "subtitle": "Czy widzisz ten baner?", "body": "Treść testowa"], at: now))
        #expect(card.id == "20E10605" && card.appName == "Edytor skryptów")
        #expect(card.title == "Wyspa — test" && card.subtitle == "Czy widzisz ten baner?" && card.body == "Treść testowa")
    }

    @Test("Nazwa aplikacji z przecinkiem")
    func appNameWithComma() throws {
        let card = try #require(BannerParser.card(identifier: "x", description: "Foo, Inc. App, Tytuł, Treść",
                                                  texts: ["title": "Tytuł", "body": "Treść"], at: now))
        #expect(card.appName == "Foo, Inc. App")
    }

    @Test("Tylko treść: treść staje się nagłówkiem")
    func bodyOnly() throws {
        let card = try #require(BannerParser.card(identifier: "x", description: "Mail, Nowa wiadomość", texts: ["body": "Nowa wiadomość"], at: now))
        #expect(card.title == "Nowa wiadomość" && card.body == nil && card.appName == "Mail")
    }

    @Test("Baner bez tekstu jest pomijany")
    func empty() {
        #expect(BannerParser.card(identifier: "x", description: "App", texts: [:], at: now) == nil)
        #expect(BannerParser.card(identifier: "x", description: "App", texts: ["title": "  "], at: now) == nil)
    }
}

@Suite("Kolejka powiadomień")
struct NotificationQueueTests {
    private func card(_ id: String) -> NotificationCard {
        NotificationCard(id: id, appName: "A", title: id, subtitle: nil, body: nil, receivedAt: .distantPast)
    }

    @Test("Pierwsze od razu, kolejne czekają, następne wchodzi po bieżącym")
    func order() {
        var queue = NotificationQueue().enqueueing(card("1")).enqueueing(card("2")).enqueueing(card("3"))
        #expect(queue.current?.id == "1" && queue.waiting.map(\.id) == ["2", "3"])
        queue = queue.advancing()
        #expect(queue.current?.id == "2")
        queue = queue.advancing().advancing()
        #expect(queue.current == nil && queue.waiting.isEmpty)
    }

    @Test("Ponad limit odpadają najstarsze czekające")
    func limit() {
        var queue = NotificationQueue().enqueueing(card("pierwsze"))
        for index in 0..<15 { queue = queue.enqueueing(card("\(index)")) }
        #expect(queue.waiting.count == NotificationQueue.maxWaiting)
        #expect(queue.waiting.last?.id == "14" && queue.current?.id == "pierwsze")
    }
}

@Suite("Powiadomienia wstrzymane na czas skupienia")
struct FocusDigestTests {
    let now = Date(timeIntervalSince1970: 0)

    private func card(_ id: Int, app: String) -> NotificationCard {
        NotificationCard(id: "\(id)", appName: app, title: "t\(id)", subtitle: nil, body: nil, receivedAt: now)
    }

    @Test("Wstrzymane mają limit, starsze odpadają")
    func holding() {
        var held: [NotificationCard] = []
        for index in 0..<(FocusDigest.maxHeld + 5) { held = FocusDigest.holding(held, card(index, app: "Mail")) }
        #expect(held.count == FocusDigest.maxHeld)
        #expect(held.first?.id == "5")
    }

    @Test("Po skupieniu: podsumowanie z łączną liczbą, aplikacje bez powtórzeń, potem najnowsze karty")
    func release() {
        let held = (0..<14).map { card($0, app: ["Mail", "Slack", "Mail", "Wiadomości", "Kalendarz", "Notatki"][$0 % 6]) }
        let cards = FocusDigest.release(held, total: 60, at: now)
        #expect(cards.first?.title == "Po skupieniu: 60 powiadomień")
        #expect(cards.first?.appName == FocusDigest.summaryAppName)
        #expect(cards.first?.body == "Mail, Slack, Wiadomości, Kalendarz +1")
        #expect(cards.count == 1 + NotificationQueue.maxWaiting)
        #expect(cards.last?.id == "13")
        #expect(FocusDigest.release([], total: 0, at: now).isEmpty)
    }

    @Test("Odmiana liczby powiadomień")
    func countText() {
        #expect(FocusDigest.countText(1) == "1 powiadomienie")
        #expect(FocusDigest.countText(3) == "3 powiadomienia")
        #expect(FocusDigest.countText(5) == "5 powiadomień")
        #expect(FocusDigest.countText(13) == "13 powiadomień")
        #expect(FocusDigest.countText(24) == "24 powiadomienia")
    }
}
