import Foundation
import Testing
@testable import WyspaClipboard

@Suite("Historia schowka")
struct ClipboardHistoryTests {
    let now = Date(timeIntervalSince1970: 0)
    private func text(_ value: String) -> ClipboardEntry { ClipboardEntry(content: .text(value), copiedAt: now) }

    @Test("Najnowszy wpis na górze")
    func order() {
        let history = ClipboardHistory().adding(text("a")).adding(text("b"))
        #expect(history.entries.map(\.searchableText) == ["b", "a"])
    }

    @Test("Ponowne skopiowanie przesuwa wpis na górę bez duplikatu")
    func dedupe() {
        let history = ClipboardHistory().adding(text("a")).adding(text("b")).adding(text("a"))
        #expect(history.entries.map(\.searchableText) == ["a", "b"])
    }

    @Test("Limit obcina najstarsze wpisy")
    func limit() {
        var history = ClipboardHistory(limit: 10)
        for index in 0..<15 { history = history.adding(text("\(index)")) }
        #expect(history.entries.count == 10)
        #expect(history.entries.first?.searchableText == "14")
        #expect(history.withLimit(10_000).limit == ClipboardHistory.limitRange.upperBound)
        #expect(history.withLimit(1).entries.count == ClipboardHistory.limitRange.lowerBound)
    }

    @Test("Wyszukiwanie ignoruje wielkość liter i polskie znaki")
    func search() {
        let history = ClipboardHistory().adding(text("Żółw w ogrodzie")).adding(text("kot"))
        #expect(history.matching("zolw").map(\.searchableText) == ["Żółw w ogrodzie"])
        #expect(history.matching("  ").count == 2)
        #expect(history.matching("ŻÓŁW").count == 1)
        #expect(SearchNormalizer.normalize("Łódź ŁAŃCUCH") == "lodz lancuch")
    }

    @Test("Usuwanie i czyszczenie")
    func removeAndClear() {
        let history = ClipboardHistory().adding(text("a")).adding(text("b"))
        #expect(history.removing(history.entries[0].id).entries.map(\.searchableText) == ["a"])
        #expect(history.cleared().entries.isEmpty)
        #expect(history.cleared().limit == history.limit)
    }

    @Test("Pliki i obrazy mają czytelny opis")
    func descriptions() {
        let files = ClipboardEntry(content: .files([URL(fileURLWithPath: "/tmp/raport.pdf")]), copiedAt: now)
        let image = ClipboardEntry(content: .image(png: Data([1]), width: 640, height: 480), copiedAt: now)
        #expect(files.searchableText == "raport.pdf")
        #expect(image.searchableText == "Obraz 640×480")
    }

    @Test("Hasła i treści tymczasowe są pomijane")
    func privacy() {
        #expect(PasteboardPrivacy.shouldIgnore(types: ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"]))
        #expect(PasteboardPrivacy.shouldIgnore(types: ["org.nspasteboard.TransientType"]))
        #expect(!PasteboardPrivacy.shouldIgnore(types: ["public.utf8-plain-text"]))
    }
}
