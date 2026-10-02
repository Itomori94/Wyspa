import Foundation
import Testing
@testable import WyspaCore

@Suite("Układ wyspy: widżety i strony")
struct IslandBoardTests {
    /// Domyślne minimum 20 jednostek (⅙); „media” potrzebuje 40 (⅓).
    let minimum: IslandBoard.Minimum = { $0 == "media" ? WidgetWidth(units: 40) : WidgetWidth(units: 20) }

    private func w(_ units: Int) -> WidgetWidth { WidgetWidth(units: units) }

    private func page(_ units: [Int]) -> (IslandBoard, [UUID]) {
        let widgets = units.enumerated().map { BoardWidget(moduleID: "m\($0.offset)", width: WidgetWidth(units: $0.element)) }
        return (IslandBoard(pages: [BoardPage(content: .widgets(widgets))]), widgets.map(\.id))
    }

    @Test("Pierwszy widżet zajmuje całą stronę, kolejne dzielą ją po równo")
    func insertion() throws {
        let (empty, page) = IslandBoard().addingWidgetPage()
        let one = try empty.inserting(moduleID: "media", intoPage: page, at: 0, minimum: minimum)
        #expect(one.pages[0].widgets.map(\.width) == [.full])
        let three = try one
            .inserting(moduleID: "timer", intoPage: page, at: 1, minimum: minimum)
            .inserting(moduleID: "calendar", intoPage: page, at: 1, minimum: minimum)
        #expect(three.pages[0].widgets.map(\.moduleID) == ["media", "calendar", "timer"])
        #expect(three.pages[0].widgets.map(\.width) == [w(40), w(40), w(40)])
        #expect(three.pages[0].usedUnits == WidgetWidth.totalUnits)
    }

    @Test("Brak miejsca, gdy równy podział złamałby minimum")
    func noRoom() throws {
        let (empty, page) = IslandBoard().addingWidgetPage()
        var board = empty
        for id in ["media", "b", "c"] { board = try board.inserting(moduleID: id, intoPage: page, at: 9, minimum: minimum) }
        #expect(throws: BoardError.noRoom) { try board.inserting(moduleID: "d", intoPage: page, at: 9, minimum: minimum) }
    }

    @Test("Dzielnik przesuwa szerokości płynnie, suma pary stała, minima respektowane")
    func divider() throws {
        let (board, _) = page([60, 60])
        let pageID = board.pages[0].id
        let moved = try board.movingDivider(onPage: pageID, after: 0, by: 7, minimum: minimum)
        #expect(moved.pages[0].widgets.map(\.width) == [w(67), w(53)])
        let clamped = try board.movingDivider(onPage: pageID, after: 0, by: -100, minimum: minimum)
        #expect(clamped.pages[0].widgets.map(\.width) == [w(20), w(100)])
        let other = try board.movingDivider(onPage: pageID, after: 0, by: 100, minimum: minimum)
        #expect(other.pages[0].widgets.map(\.width) == [w(100), w(20)])
    }

    @Test("Przenoszenie widżetu w obrębie strony i na inną stronę")
    func moving() throws {
        let (empty, page) = IslandBoard().addingWidgetPage()
        var board = empty
        for id in ["a", "b", "c"] { board = try board.inserting(moduleID: id, intoPage: page, at: 9, minimum: minimum) }
        let a = board.pages[0].widgets[0].id
        let reordered = try board.moving(widget: a, toPage: page, at: 3, minimum: minimum)
        #expect(reordered.pages[0].widgets.map(\.moduleID) == ["b", "c", "a"])

        let (withSecond, second) = reordered.addingWidgetPage()
        let moved = try withSecond.moving(widget: a, toPage: second, at: 0, minimum: minimum)
        #expect(moved.pages[0].widgets.map(\.moduleID) == ["b", "c"])
        #expect(moved.pages[0].usedUnits == WidgetWidth.totalUnits)
        #expect(moved.pages[1].widgets.map(\.width) == [.full])
    }

    @Test("Strony: pełny widok bez duplikatów, przenoszenie, usuwanie, brak widżetów na stronie modułu")
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

    @Test("Usunięcie jednego z trzech równych: dwa po połowie, potem jeden na całość")
    func removalKeepsEqualSplit() {
        let (board, ids) = page([40, 40, 40])
        let two = board.removing(widget: ids[1])
        #expect(two.pages[0].widgets.map(\.width) == [w(60), w(60)])
        #expect(two.removing(widget: ids[0]).pages[0].widgets.map(\.width) == [.full])
    }

    @Test("Usunięcie przy własnych proporcjach: miejsce dostaje sąsiad")
    func removalGivesSpaceToNeighbour() {
        let (board, ids) = page([55, 35, 30])
        #expect(board.removing(widget: ids[1]).pages[0].widgets.map(\.width) == [w(90), w(30)])
        #expect(board.removing(widget: ids[0]).pages[0].widgets.map(\.width) == [w(90), w(30)])
    }

    @Test("Każde usunięcie zostawia stronę wypełnioną", arguments: [[40, 40, 40], [55, 35, 30], [30, 30, 30, 30], [70, 50], [24, 24, 24, 24, 24]])
    func removalAlwaysFills(units: [Int]) {
        let (board, ids) = page(units)
        for id in ids {
            let next = board.removing(widget: id)
            if !next.pages[0].widgets.isEmpty { #expect(next.pages[0].usedUnits == WidgetWidth.totalUnits) }
        }
    }

    @Test("Operacje nie zmieniają oryginału")
    func immutability() {
        let (board, ids) = page([60, 60])
        _ = board.removing(widget: ids[0])
        #expect(board.pages[0].widgets.count == 2)
    }

    @Test("Minimalna szerokość w jednostkach zależy od wnętrza wyspy")
    func minimumWidth() {
        // mała wyspa: wnętrze 452 pt → 150 pt to 39,8 jednostki → 40
        #expect(IslandBoard.minimumWidth(points: 150, innerWidth: 452) == w(40))
        #expect(IslandBoard.minimumWidth(points: 500, innerWidth: 452) == .full)
    }

    @Test("Układ startowy z zachowaniem minimów, nadmiarowe widżety na osobnych stronach")
    func initial() {
        let board = IslandBoard.initial(widgetModules: ["media", "calendar", "timer", "power"],
                                        pageModules: ["shelf", "timer"], minimum: minimum)
        #expect(board.pages[0].widgets.map(\.moduleID) == ["media", "calendar", "timer"])
        #expect(board.pages.dropFirst().map(\.content) == [.module("power"), .module("shelf")])
    }

    @Test("Zapis i odczyt układu")
    func codable() throws {
        let (board, _) = page([67, 53])
        #expect(try JSONDecoder().decode(IslandBoard.self, from: JSONEncoder().encode(board)) == board)
    }

    @Test("Układ zapisany w dwunastkach (poprzednia wersja) jest przeliczany")
    func legacyMigration() throws {
        let id = UUID()
        let json = """
        {"pages":[{"id":"\(id.uuidString)","content":{"widgets":{"_0":[
          {"id":"\(UUID().uuidString)","moduleID":"a","width":4},
          {"id":"\(UUID().uuidString)","moduleID":"b","width":8}]}}}]}
        """
        let board = try JSONDecoder().decode(IslandBoard.self, from: Data(json.utf8))
        #expect(board.pages[0].widgets.map(\.width) == [w(40), w(80)])
    }

    @Test("Zapisany układ z luką jest wypełniany przy odczycie")
    func normalization() {
        let (gap, _) = page([40, 40])
        #expect(gap.normalized().pages[0].widgets.map(\.width) == [w(60), w(60)])
        let (full, _) = page([70, 50])
        #expect(full.normalized() == full)
    }
}
