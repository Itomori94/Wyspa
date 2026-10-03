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

    @Test("Przypięte: na górze, poza limitem, zostają po „Wyczyść”, znikają przy wyłączeniu modułu")
    func pinned() {
        var history = ClipboardHistory(limit: 10).adding(text("ważne"))
        history = history.togglingPin(history.entries[0].id)
        for index in 0..<15 { history = history.adding(text("\(index)")) }
        #expect(history.entries.first?.searchableText == "ważne" && history.entries.first?.isPinned == true)
        #expect(history.entries.count == 11, "10 zwykłych + przypięty")
        #expect(history.cleared().entries.map(\.searchableText) == ["ważne"])
        #expect(history.clearedAll().entries.isEmpty)
    }

    @Test("Ponowne skopiowanie przypiętego zostawia go przypiętym, bez duplikatu")
    func pinnedCopiedAgain() {
        var history = ClipboardHistory().adding(text("a")).adding(text("b"))
        history = history.togglingPin(history.entries.first { $0.searchableText == "a" }!.id)
        history = history.adding(text("c")).adding(text("a"))
        #expect(history.entries.map(\.searchableText) == ["a", "c", "b"])
        #expect(history.entries.filter(\.isPinned).map(\.searchableText) == ["a"])
    }

    @Test("Przy pełnym limicie przypiętych przypięcie nic nie zmienia (żaden przypięty nie wypada)")
    func pinLimit() {
        var history = ClipboardHistory(limit: ClipboardHistory.limitRange.upperBound)
        for index in 0..<(ClipboardHistory.maxPinned + 1) { history = history.adding(text("p\(index)")) }
        for entry in history.entries.dropFirst() { history = history.togglingPin(entry.id) }
        #expect(history.pinnedEntries.count == ClipboardHistory.maxPinned && !history.canPinMore)
        let extra = history.entries.first { !$0.isPinned }!
        #expect(history.togglingPin(extra.id) == history)
        #expect(history.entries.count == ClipboardHistory.maxPinned + 1)
    }

    @Test("Odpięcie wraca między zwykłe wpisy według daty")
    func unpin() {
        let early = ClipboardEntry(content: .text("stary"), copiedAt: Date(timeIntervalSince1970: 10))
        let late = ClipboardEntry(content: .text("nowy"), copiedAt: Date(timeIntervalSince1970: 30))
        let middle = ClipboardEntry(content: .text("środek"), copiedAt: Date(timeIntervalSince1970: 20))
        var history = ClipboardHistory().adding(early).adding(middle).adding(late)
        history = history.togglingPin(middle.id)
        #expect(history.entries.map(\.searchableText) == ["środek", "nowy", "stary"])
        history = history.togglingPin(middle.id)
        #expect(history.entries.map(\.searchableText) == ["nowy", "środek", "stary"])
        #expect(history.entries.allSatisfy { !$0.isPinned })
    }

    @Test("Wybór strzałkami: od pierwszego wpisu, bez zawijania; Enter bez wyboru = pierwszy")
    func keyboardSelection() {
        #expect(ClipboardSelection.moved(nil, by: 1, count: 3) == 0)
        #expect(ClipboardSelection.moved(nil, by: -1, count: 3) == 0)
        #expect(ClipboardSelection.moved(1, by: 1, count: 3) == 2)
        #expect(ClipboardSelection.moved(2, by: 1, count: 3) == 2)
        #expect(ClipboardSelection.moved(0, by: -1, count: 3) == 0)
        #expect(ClipboardSelection.moved(0, by: 1, count: 0) == nil)
        #expect(ClipboardSelection.chosen(nil, count: 2) == 0)
        #expect(ClipboardSelection.chosen(5, count: 2) == 1)
        #expect(ClipboardSelection.chosen(nil, count: 0) == nil)
    }

    @Test("Pliki, których już nie ma, nie trafiają do schowka; wpis bez żadnego pliku jest niedostępny")
    func missingFiles() {
        let kept = URL(fileURLWithPath: "/tmp/zostal.pdf")
        let gone = URL(fileURLWithPath: "/tmp/Items/1/Tekst.txt")
        let entry = ClipboardEntry(content: .files([gone, kept]), copiedAt: now)
        #expect(entry.availableContent(fileExists: { $0 == kept }) == .files([kept]))
        #expect(entry.availableContent(fileExists: { _ in false }) == nil)
        #expect(text("a").availableContent(fileExists: { _ in false }) == .text("a"), "tekst nie zależy od plików")
    }

    @Test("Pliki i obrazy mają czytelny opis")
    func descriptions() {
        let files = ClipboardEntry(content: .files([URL(fileURLWithPath: "/tmp/raport.pdf")]), copiedAt: now)
        let image = ClipboardEntry(content: .image(png: Data([1]), width: 640, height: 480), copiedAt: now)
        #expect(files.searchableText == "raport.pdf")
        #expect(image.searchableText == "Obraz 640×480")
    }
}
