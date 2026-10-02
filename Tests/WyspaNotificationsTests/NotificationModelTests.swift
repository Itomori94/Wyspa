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
