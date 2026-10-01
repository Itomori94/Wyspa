import Foundation
import Testing
@testable import WyspaShelf

@Suite("Zaznaczanie na półce")
struct ShelfSelectionTests {
    let ids = (0..<5).map { _ in UUID() }

    @Test("Zwykły klik zaznacza tylko jeden element")
    func single() {
        var selection = ShelfSelection()
        selection.click(ids[0], modifier: .none, order: ids)
        selection.click(ids[2], modifier: .none, order: ids)
        #expect(selection.selected == [ids[2]])
    }

    @Test("⌘-klik przełącza element")
    func toggle() {
        var selection = ShelfSelection()
        selection.click(ids[0], modifier: .none, order: ids)
        selection.click(ids[3], modifier: .toggle, order: ids)
        #expect(selection.selected == [ids[0], ids[3]])
        selection.click(ids[0], modifier: .toggle, order: ids)
        #expect(selection.selected == [ids[3]])
    }

    @Test("⇧-klik zaznacza zakres od kotwicy w obie strony")
    func range() {
        var selection = ShelfSelection()
        selection.click(ids[3], modifier: .none, order: ids)
        selection.click(ids[1], modifier: .range, order: ids)
        #expect(selection.selected == Set(ids[1...3]))
    }

    @Test("⇧-klik bez kotwicy działa jak zwykły klik")
    func rangeWithoutAnchor() {
        var selection = ShelfSelection()
        selection.click(ids[2], modifier: .range, order: ids)
        #expect(selection.selected == [ids[2]])
    }

    @Test("Przeciąganie: całe zaznaczenie albo tylko chwycony element")
    func dragSet() {
        var selection = ShelfSelection()
        selection.selectAll(Array(ids[0...2]))
        #expect(selection.dragSet(grabbing: ids[1]) == Set(ids[0...2]))
        #expect(selection.dragSet(grabbing: ids[4]) == [ids[4]])
    }

    @Test("Usunięte elementy znikają z zaznaczenia")
    func retain() {
        var selection = ShelfSelection()
        selection.selectAll(ids)
        selection.retain(Array(ids[0...1]))
        #expect(selection.selected == Set(ids[0...1]))
    }
}

@Suite("Odmiana liczebników")
struct PolishPluralTests {
    @Test(arguments: [
        (1, "element"), (2, "elementy"), (4, "elementy"), (5, "elementów"), (11, "elementów"),
        (12, "elementów"), (14, "elementów"), (22, "elementy"), (25, "elementów"), (0, "elementów"),
    ])
    func forms(n: Int, expected: String) {
        #expect(PolishPlural.word(for: n, one: "element", few: "elementy", many: "elementów") == expected)
    }
}
