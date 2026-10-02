import Foundation
import Testing
@testable import WyspaCore

@Suite("Polecenia wyspa://")
struct ScriptCommandTests {
    private func command(_ string: String) -> ScriptCommand? {
        URL(string: string).flatMap(ScriptCommand.init(url:))
    }

    @Test("Karta: tytuł i treść, polskie znaki z kodowania procentowego")
    func notify() {
        #expect(command("wyspa://notify?title=Backup%20gotowy") == .notify(title: "Backup gotowy", body: nil))
        #expect(command("wyspa://notify?title=Za%C5%BC%C3%B3%C5%82%C4%87&body=g%C4%99%C5%9Bl%C4%85%20ja%C5%BA%C5%84")
                == .notify(title: "Zażółć", body: "gęślą jaźń"))
        #expect(command("wyspa:notify?title=A") == .notify(title: "A", body: nil), "zapis bez //")
        #expect(command("WYSPA://Notify?title=A") == .notify(title: "A", body: nil))
    }

    @Test("Karta bez tytułu albo z samymi spacjami jest odrzucana")
    func notifyWithoutTitle() {
        #expect(command("wyspa://notify") == nil)
        #expect(command("wyspa://notify?title=%20%0A%20") == nil)
    }

    @Test("Postęp: ułamek, procent, przecinek, przycięcie do 0…1, nieokreślony")
    func progress() {
        #expect(command("wyspa://progress?value=0.4&label=Build") == .progress(id: "default", fraction: 0.4, label: "Build"))
        #expect(command("wyspa://progress?value=40%25&id=build") == .progress(id: "build", fraction: 0.4, label: nil))
        #expect(command("wyspa://progress?value=0,25") == .progress(id: "default", fraction: 0.25, label: nil))
        #expect(command("wyspa://progress?value=7") == .progress(id: "default", fraction: 1, label: nil))
        #expect(command("wyspa://progress?value=-3") == .progress(id: "default", fraction: 0, label: nil))
        #expect(command("wyspa://progress?label=Kopia") == .progress(id: "default", fraction: nil, label: "Kopia"))
        #expect(command("wyspa://progress?value=abc") == nil)
        #expect(command("wyspa://progress?value=nan") == nil)
    }

    @Test("Koniec postępu i nieznane polecenia")
    func doneAndUnknown() {
        #expect(command("wyspa://done?id=build") == .done(id: "build"))
        #expect(command("wyspa://done") == .done(id: "default"))
        #expect(command("wyspa://open?path=/etc") == nil)
        #expect(command("https://notify?title=A") == nil)
    }

    @Test("Teksty: bez znaków sterujących, zwinięte spacje, limit z wielokropkiem")
    func cleaning() {
        #expect(ScriptCommand.clean("  a\n\tb\u{7}  c ", limit: 50) == "a b c")
        let long = String(repeating: "x", count: 500)
        let title = ScriptCommand.clean(long, limit: ScriptCommand.maxTitle)
        #expect(title?.count == ScriptCommand.maxTitle && title?.hasSuffix("…") == true)
        #expect(ScriptCommand.clean("", limit: 10) == nil)
    }

    @Test("Identyfikator: tylko bezpieczne znaki, inaczej domyślny")
    func identifiers() {
        #expect(ScriptCommand.identifier("build-1.x_y") == "build-1.x_y")
        #expect(ScriptCommand.identifier("a b") == "default")
        #expect(ScriptCommand.identifier("../x/") == "default")
        #expect(ScriptCommand.identifier(String(repeating: "a", count: 41)) == "default")
        #expect(ScriptCommand.identifier(nil) == "default")
    }

    @Test("Centrum poleceń: bufor do startu modułu (najnowsze), potem bezpośrednio")
    @MainActor
    func center() {
        let center = ScriptCommandCenter()
        for index in 0..<7 { center.post(.done(id: "p\(index)")) }
        var received: [ScriptCommand] = []
        center.setHandler { received.append($0) }
        #expect(received == (2..<7).map { .done(id: "p\($0)") })
        center.post(.done(id: "now"))
        #expect(received.last == .done(id: "now"))
        center.setHandler(nil)
        center.post(.done(id: "later"))
        #expect(received.count == 6)
    }
}
