import Foundation
import Testing
@testable import WyspaCore

@Suite("Układ wyspy: widżety i strony")
struct IslandBoardTests {
    /// Domyślnie każdy widżet zniesie ¼; „media” potrzebuje co najmniej ⅓.
    let minimum: IslandBoard.Minimum = { $0 == "media" ? .third : .quarter }

    private func boardWithEmptyPage() -> (IslandBoard, UUID) {
        IslandBoard().addingWidgetPage()
    }

    @Test("Pierwszy widżet zajmuje całą stronę, następne biorą wolne miejsce albo dzielą równo")
    func insertion() throws {
        let (empty, page) = boardWithEmptyPage()
        let one = try empty.inserting(moduleID: "media", intoPage: page, at: 0, minimum: minimum)
        #expect(one.pages[0].widgets.map(\.width) == [.full])

        let two = try one.inserting(moduleID: "timer", intoPage: page, at: 1, minimum: minimum)
        #expect(two.pages[0].widgets.map(\.width) == [.half, .half])

        let three = try two.inserting(moduleID: "calendar", intoPage: page, at: 1, minimum: minimum)
        #expect(three.pages[0].widgets.map(\.moduleID) == ["media", "calendar", "timer"])
        #expect(three.pages[0].widgets.map(\.width) == [.third, .third, .third])
        #expect(three.pages[0].usedUnits == 12)
    }

    @Test("Wolne miejsce jest wykorzystane bez ruszania innych widżetów")
    func usesRemainingSpace() throws {
        let (empty, page) = boardWithEmptyPage()
        let board = try empty
            .inserting(moduleID: "a", intoPage: page, at: 0, minimum: minimum)
            .inserting(moduleID: "b", intoPage: page, at: 1, minimum: minimum)
        let shrunk = try board.resizing(widget: board.pages[0].widgets[0].id, to: .quarter, minimum: minimum)
        // ¼ + ½ = 9 z 12 → zostaje ¼
        let next = try shrunk.inserting(moduleID: "c", intoPage: page, at: 2, minimum: minimum)
        #expect(next.pages[0].widgets.map(\.width) == [.quarter, .half, .quarter])
    }

    @Test("Brak miejsca, gdy równy podział złamałby minimum widżetu")
    func noRoom() throws {
        let (empty, page) = boardWithEmptyPage()
        var board = empty
        for id in ["media", "b", "c"] { board = try board.inserting(moduleID: id, intoPage: page, at: 9, minimum: minimum) }
        // Czwarty wymusiłby ¼ dla „media”, które potrzebuje ⅓.
        #expect(throws: BoardError.noRoom) { try board.inserting(moduleID: "d", intoPage: page, at: 9, minimum: minimum) }
        // Bez „media” cztery ćwiartki się mieszczą.
        let (other, otherPage) = IslandBoard().addingWidgetPage()
        var quarters = other
        for id in ["a", "b", "c", "d"] { quarters = try quarters.inserting(moduleID: id, intoPage: otherPage, at: 9, minimum: minimum) }
        #expect(quarters.pages[0].widgets.map(\.width) == [.quarter, .quarter, .quarter, .quarter])
        #expect(throws: BoardError.noRoom) { try quarters.inserting(moduleID: "e", intoPage: otherPage, at: 9, minimum: minimum) }
    }

    @Test("Przeciąganie dzielnika: przyciąganie do stopni, suma pary bez zmian, minimum respektowane")
    func divider() throws {
        let (empty, page) = boardWithEmptyPage()
        let board = try empty
            .inserting(moduleID: "media", intoPage: page, at: 0, minimum: minimum)
            .inserting(moduleID: "b", intoPage: page, at: 1, minimum: minimum)
        let wider = try board.movingDivider(onPage: page, after: 0, by: 2, minimum: minimum)
        #expect(wider.pages[0].widgets.map(\.width) == [.twoThirds, .third])
        let snapped = try board.movingDivider(onPage: page, after: 0, by: 1, minimum: minimum)
        #expect(snapped.pages[0].usedUnits == 12)
        // „media” nie zejdzie poniżej ⅓.
        let narrow = try board.movingDivider(onPage: page, after: 0, by: -6, minimum: minimum)
        #expect(narrow.pages[0].widgets[0].width == .third)
        #expect(narrow.pages[0].widgets[1].width == .twoThirds)
    }

    @Test("Przenoszenie widżetu w obrębie strony i na inną stronę")
    func moving() throws {
        let (empty, page) = boardWithEmptyPage()
        var board = empty
        for id in ["a", "b", "c"] { board = try board.inserting(moduleID: id, intoPage: page, at: 9, minimum: minimum) }
        let a = board.pages[0].widgets[0].id
        let reordered = try board.moving(widget: a, toPage: page, at: 3, minimum: minimum)
        #expect(reordered.pages[0].widgets.map(\.moduleID) == ["b", "c", "a"])

        let (withSecond, second) = reordered.addingWidgetPage()
        let moved = try withSecond.moving(widget: a, toPage: second, at: 0, minimum: minimum)
        #expect(moved.pages[0].widgets.map(\.moduleID) == ["b", "c"])
        #expect(moved.pages[1].widgets.map(\.moduleID) == ["a"])
    }

    @Test("Strony: pełny widok modułu bez duplikatów, przenoszenie, usuwanie, widżet nie trafia na stronę modułu")
    func pages() throws {
        let board = IslandBoard().addingModulePage("shelf").addingModulePage("clipboard").addingModulePage("shelf")
        #expect(board.pages.count == 2)
        let moved = board.movingPage(board.pages[1].id, to: 0)
        #expect(moved.pages.map(\.content) == [.module("clipboard"), .module("shelf")])
        #expect(moved.removingPage(moved.pages[0].id).pages.count == 1)
        #expect(throws: BoardError.notAWidgetPage) {
            try board.inserting(moduleID: "a", intoPage: board.pages[0].id, at: 0, minimum: minimum)
        }
        #expect(board.contains(moduleID: "shelf") && !board.contains(moduleID: "timer"))
    }

    @Test("Usunięcie widżetu i operacje niczego nie zmieniają w oryginale")
    func removalImmutability() throws {
        let (empty, page) = boardWithEmptyPage()
        let board = try empty.inserting(moduleID: "a", intoPage: page, at: 0, minimum: minimum)
        let removed = board.removing(widget: board.pages[0].widgets[0].id)
        #expect(removed.pages[0].widgets.isEmpty)
        #expect(board.pages[0].widgets.count == 1)
    }

    private func page(_ widths: [WidgetWidth]) -> (IslandBoard, [UUID]) {
        let widgets = widths.enumerated().map { BoardWidget(moduleID: "m\($0.offset)", width: $0.element) }
        return (IslandBoard(pages: [BoardPage(content: .widgets(widgets))]), widgets.map(\.id))
    }

    @Test("Usunięcie jednego z trzech równych: dwa pozostałe po połowie, potem jeden na całość")
    func removalKeepsEqualSplit() {
        let (board, ids) = page([.third, .third, .third])
        let two = board.removing(widget: ids[1])
        #expect(two.pages[0].widgets.map(\.width) == [.half, .half])
        #expect(two.pages[0].usedUnits == 12)
        let one = two.removing(widget: ids[0])
        #expect(one.pages[0].widgets.map(\.width) == [.full])
    }

    @Test("Usunięcie przy własnych proporcjach: miejsce dostaje sąsiad, reszta bez zmian")
    func removalGivesSpaceToNeighbour() {
        let (board, ids) = page([.half, .quarter, .quarter])
        #expect(board.removing(widget: ids[2]).pages[0].widgets.map(\.width) == [.half, .half])
        #expect(board.removing(widget: ids[1]).pages[0].widgets.map(\.width) == [.threeQuarters, .quarter])
        let (four, fourIDs) = page([.quarter, .quarter, .quarter, .quarter])
        #expect(four.removing(widget: fourIDs[0]).pages[0].widgets.map(\.width) == [.third, .third, .third])
    }

    @Test("Każde usunięcie zostawia stronę wypełnioną", arguments: [
        [WidgetWidth.third, .third, .third], [.half, .quarter, .quarter], [.quarter, .half, .quarter],
        [.twoThirds, .third], [.quarter, .threeQuarters], [.quarter, .quarter, .quarter, .quarter], [.half, .half],
    ])
    func removalAlwaysFills(widths: [WidgetWidth]) {
        let (board, ids) = page(widths)
        for id in ids {
            let next = board.removing(widget: id)
            if !next.pages[0].widgets.isEmpty { #expect(next.pages[0].usedUnits == 12, "\(widths) bez \(id)") }
        }
    }

    @Test("Minimalna szerokość w stopniach zależy od wnętrza wyspy")
    func minimumWidth() {
        // mała wyspa: wnętrze 452 → ¼ = 113, ⅓ ≈ 150,7
        #expect(IslandBoard.minimumWidth(points: 110, innerWidth: 452) == .quarter)
        #expect(IslandBoard.minimumWidth(points: 150, innerWidth: 452) == .third)
        #expect(IslandBoard.minimumWidth(points: 500, innerWidth: 452) == .full)
    }

    @Test("Układ startowy: widżety z zachowaniem minimów, nadmiarowe na osobnych stronach")
    func initial() {
        let board = IslandBoard.initial(widgetModules: ["media", "calendar", "timer", "power"],
                                        pageModules: ["shelf", "timer"], minimum: minimum)
        // Czwarty widżet wymusiłby ¼ dla „media” (minimum ⅓), więc „power” dostaje własną stronę.
        #expect(board.pages[0].widgets.map(\.moduleID) == ["media", "calendar", "timer"])
        #expect(board.pages[0].widgets.map(\.width) == [.third, .third, .third])
        #expect(board.pages.dropFirst().map(\.content) == [.module("power"), .module("shelf")])
        #expect(IslandBoard.initial(widgetModules: [], pageModules: ["shelf"], minimum: minimum).pages.map(\.content)
            == [.module("shelf")])
    }

    @Test("Zapis i odczyt układu")
    func codable() throws {
        let (empty, page) = boardWithEmptyPage()
        let board = try empty.inserting(moduleID: "a", intoPage: page, at: 0, minimum: minimum).addingModulePage("shelf")
        #expect(try JSONDecoder().decode(IslandBoard.self, from: JSONEncoder().encode(board)) == board)
    }

    @Test("Zapisany układ z dziurą jest wypełniany przy odczycie")
    func normalization() {
        let (gap, _) = page([.third, .third])
        #expect(gap.normalized().pages[0].widgets.map(\.width) == [.half, .half])
        let (custom, _) = page([.half, .quarter])
        #expect(custom.normalized().pages[0].usedUnits == 12)
        let (full, _) = page([.half, .half])
        #expect(full.normalized() == full)
    }
}
