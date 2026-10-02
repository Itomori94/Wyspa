import CoreGraphics
import Foundation

/// Szerokość widżetu w dwunastkach wnętrza rozwiniętej wyspy (stopnie: ¼, ⅓, ½, ⅔, ¾, całość).
public enum WidgetWidth: Int, Codable, CaseIterable, Comparable, Sendable {
    case quarter = 3
    case third = 4
    case half = 6
    case twoThirds = 8
    case threeQuarters = 9
    case full = 12

    public static let totalUnits = 12

    public var units: Int { rawValue }
    public var fraction: CGFloat { CGFloat(rawValue) / CGFloat(Self.totalUnits) }

    public var displayName: String {
        switch self {
        case .quarter: "¼"
        case .third: "⅓"
        case .half: "½"
        case .twoThirds: "⅔"
        case .threeQuarters: "¾"
        case .full: "całość"
        }
    }

    public static func < (lhs: WidgetWidth, rhs: WidgetWidth) -> Bool { lhs.rawValue < rhs.rawValue }
}

public struct BoardWidget: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let moduleID: String
    public let width: WidgetWidth

    public init(id: UUID = UUID(), moduleID: String, width: WidgetWidth) {
        self.id = id
        self.moduleID = moduleID
        self.width = width
    }

    func with(width: WidgetWidth) -> BoardWidget {
        BoardWidget(id: id, moduleID: moduleID, width: width)
    }
}

public struct BoardPage: Codable, Equatable, Identifiable, Sendable {
    public enum Content: Codable, Equatable, Sendable {
        /// Kilka widżetów obok siebie.
        case widgets([BoardWidget])
        /// Pełny widok jednego modułu (np. półka, historia schowka).
        case module(String)
    }

    public let id: UUID
    public let content: Content

    public init(id: UUID = UUID(), content: Content) {
        self.id = id
        self.content = content
    }

    public var widgets: [BoardWidget] {
        if case .widgets(let widgets) = content { return widgets }
        return []
    }

    public var usedUnits: Int { widgets.map(\.width.units).reduce(0, +) }

    func with(widgets: [BoardWidget]) -> BoardPage {
        BoardPage(id: id, content: .widgets(widgets))
    }
}

public enum BoardError: Error, Equatable, Sendable {
    case noRoom
    case unknownPage
    case unknownWidget
    case notAWidgetPage

    public var message: String {
        switch self {
        case .noRoom: "Na tej stronie brak miejsca. Zmniejsz albo usuń inny widżet, albo dodaj nową stronę."
        case .unknownPage: "Ta strona już nie istnieje."
        case .unknownWidget: "Ten widżet już nie istnieje."
        case .notAWidgetPage: "Na stronie z pełnym widokiem modułu nie ma miejsca na widżety."
        }
    }
}

/// Układ rozwiniętej wyspy: strony z widżetami albo pełnymi widokami modułów. Niemutowalny.
///
/// Minimalna szerokość widżetu zależy od rozmiaru wyspy, więc operacje dostają ją jako funkcję `minimum`.
public struct IslandBoard: Codable, Equatable, Sendable {
    public typealias Minimum = (String) -> WidgetWidth

    public let pages: [BoardPage]

    public init(pages: [BoardPage] = []) {
        self.pages = pages
    }

    // MARK: - Widżety

    /// Dodaje widżet na stronę. Gdy brak wolnego miejsca, wyrównuje szerokości wszystkich widżetów na stronie.
    public func inserting(moduleID: String, intoPage pageID: UUID, at index: Int, minimum: Minimum) throws(BoardError) -> IslandBoard {
        let page = try widgetPage(pageID)
        let widgets = page.widgets
        let remaining = WidgetWidth.totalUnits - page.usedUnits
        let insertAt = min(max(index, 0), widgets.count)

        if let width = WidgetWidth.allCases.filter({ $0.units <= remaining && $0 >= minimum(moduleID) }).max() {
            var next = widgets
            next.insert(BoardWidget(moduleID: moduleID, width: width), at: insertAt)
            return replacing(page.with(widgets: next))
        }
        // Brak wolnego miejsca: równy podział, jeśli każdy widżet go zniesie.
        var next = widgets
        next.insert(BoardWidget(moduleID: moduleID, width: .full), at: insertAt)
        guard let equal = Self.equalWidth(count: next.count),
              next.allSatisfy({ equal >= minimum($0.moduleID) })
        else { throw .noRoom }
        return replacing(page.with(widgets: next.map { $0.with(width: equal) }))
    }

    /// Przenosi widżet w obrębie strony albo na inną stronę (w miejsce `index`).
    public func moving(widget widgetID: UUID, toPage pageID: UUID, at index: Int, minimum: Minimum) throws(BoardError) -> IslandBoard {
        guard let source = pages.first(where: { $0.widgets.contains { $0.id == widgetID } }),
              let widget = source.widgets.first(where: { $0.id == widgetID })
        else { throw .unknownWidget }

        if source.id == pageID {
            var widgets = source.widgets.filter { $0.id != widgetID }
            let currentIndex = source.widgets.firstIndex { $0.id == widgetID } ?? 0
            // Indeks docelowy liczony w układzie przed usunięciem — po usunięciu przesuwa się o jeden.
            let adjusted = index > currentIndex ? index - 1 : index
            widgets.insert(widget, at: min(max(adjusted, 0), widgets.count))
            return replacing(source.with(widgets: widgets))
        }
        let withoutSource = replacing(source.with(widgets: source.widgets.filter { $0.id != widgetID }))
        let target = try withoutSource.widgetPage(pageID)
        let remaining = WidgetWidth.totalUnits - target.usedUnits
        var widgets = target.widgets
        if widget.width.units <= remaining {
            widgets.insert(widget, at: min(max(index, 0), widgets.count))
            return withoutSource.replacing(target.with(widgets: widgets))
        }
        // Za szeroki na wolne miejsce: spróbuj węższej szerokości, potem równego podziału.
        return try withoutSource.inserting(moduleID: widget.moduleID, intoPage: pageID, at: index, minimum: minimum)
    }

    /// Usuwa widżet i oddaje zwolnione miejsce pozostałym: równe szerokości zostają równe,
    /// a przy własnych proporcjach miejsce dostaje sąsiad usuniętego widżetu.
    public func removing(widget widgetID: UUID) -> IslandBoard {
        guard let page = pages.first(where: { $0.widgets.contains { $0.id == widgetID } }),
              let index = page.widgets.firstIndex(where: { $0.id == widgetID })
        else { return self }
        let wasEqual = Set(page.widgets.map(\.width)).count == 1
        let remaining = page.widgets.filter { $0.id != widgetID }
        return replacing(page.with(widgets: Self.filling(remaining, freedAt: index, keepEqual: wasEqual)))
    }

    /// Strony z wolnym miejscem (np. układ zapisany przed wypełnianiem po usunięciu) wypełnione do pełnej szerokości.
    public func normalized() -> IslandBoard {
        IslandBoard(pages: pages.map { page in
            let widgets = page.widgets
            guard !widgets.isEmpty, page.usedUnits < WidgetWidth.totalUnits else { return page }
            let allEqual = Set(widgets.map(\.width)).count == 1
            return page.with(widgets: Self.filling(widgets, freedAt: widgets.count, keepEqual: allEqual))
        })
    }

    /// Rozdziela wolne miejsce strony tak, żeby widżety znów zajmowały całą szerokość.
    static func filling(_ widgets: [BoardWidget], freedAt index: Int, keepEqual: Bool) -> [BoardWidget] {
        guard !widgets.isEmpty else { return widgets }
        let free = WidgetWidth.totalUnits - widgets.map(\.width.units).reduce(0, +)
        guard free > 0 else { return widgets }
        if keepEqual, let equal = equalWidth(count: widgets.count) {
            return widgets.map { $0.with(width: equal) }
        }
        // Najpierw sąsiad z lewej, potem z prawej, potem dowolny widżet, który przyjmie całe wolne miejsce.
        let neighbours = [index - 1, index] + Array(widgets.indices)
        for candidate in neighbours where widgets.indices.contains(candidate) {
            if let wider = WidgetWidth(rawValue: widgets[candidate].width.units + free) {
                var result = widgets
                result[candidate] = widgets[candidate].with(width: wider)
                return result
            }
        }
        // Wolnego miejsca nie da się oddać jednemu widżetowi w stopniach — równy podział, jeśli możliwy.
        if let equal = equalWidth(count: widgets.count), widgets.allSatisfy({ $0.width <= equal }) {
            return widgets.map { $0.with(width: equal) }
        }
        return widgets
    }

    /// Przesuwa dzielnik między widżetami `dividerIndex` i `dividerIndex + 1` o `delta` dwunastek.
    /// Szerokości przeskakują do najbliższych dozwolonych stopni; suma pary się nie zmienia.
    public func movingDivider(onPage pageID: UUID, after dividerIndex: Int, by delta: Int, minimum: Minimum) throws(BoardError) -> IslandBoard {
        let page = try widgetPage(pageID)
        var widgets = page.widgets
        guard widgets.indices.contains(dividerIndex), widgets.indices.contains(dividerIndex + 1) else { throw .unknownWidget }
        let left = widgets[dividerIndex]
        let right = widgets[dividerIndex + 1]
        let pair = left.width.units + right.width.units
        let target = left.width.units + delta

        let candidates = WidgetWidth.allCases.compactMap { newLeft -> (WidgetWidth, WidgetWidth)? in
            guard let newRight = WidgetWidth(rawValue: pair - newLeft.units),
                  newLeft >= minimum(left.moduleID), newRight >= minimum(right.moduleID)
            else { return nil }
            return (newLeft, newRight)
        }
        guard let best = candidates.min(by: { abs($0.0.units - target) < abs($1.0.units - target) }) else { return self }
        widgets[dividerIndex] = left.with(width: best.0)
        widgets[dividerIndex + 1] = right.with(width: best.1)
        return replacing(page.with(widgets: widgets))
    }

    /// Ustawia szerokość widżetu, jeśli zmieści się na stronie.
    public func resizing(widget widgetID: UUID, to width: WidgetWidth, minimum: Minimum) throws(BoardError) -> IslandBoard {
        guard let page = pages.first(where: { $0.widgets.contains { $0.id == widgetID } }),
              let widget = page.widgets.first(where: { $0.id == widgetID })
        else { throw .unknownWidget }
        guard width >= minimum(widget.moduleID) else { return self }
        guard page.usedUnits - widget.width.units + width.units <= WidgetWidth.totalUnits else { throw .noRoom }
        return replacing(page.with(widgets: page.widgets.map { $0.id == widgetID ? $0.with(width: width) : $0 }))
    }

    // MARK: - Strony

    public func addingWidgetPage(at index: Int? = nil) -> (IslandBoard, UUID) {
        let page = BoardPage(content: .widgets([]))
        var next = pages
        next.insert(page, at: min(max(index ?? next.count, 0), next.count))
        return (IslandBoard(pages: next), page.id)
    }

    /// Strona z pełnym widokiem modułu; ten sam moduł nie dostaje drugiej takiej strony.
    public func addingModulePage(_ moduleID: String, at index: Int? = nil) -> IslandBoard {
        guard !pages.contains(where: { $0.content == .module(moduleID) }) else { return self }
        var next = pages
        next.insert(BoardPage(content: .module(moduleID)), at: min(max(index ?? next.count, 0), next.count))
        return IslandBoard(pages: next)
    }

    public func removingPage(_ pageID: UUID) -> IslandBoard {
        IslandBoard(pages: pages.filter { $0.id != pageID })
    }

    public func movingPage(_ pageID: UUID, to index: Int) -> IslandBoard {
        guard let current = pages.firstIndex(where: { $0.id == pageID }) else { return self }
        var next = pages
        let page = next.remove(at: current)
        let adjusted = index > current ? index - 1 : index
        next.insert(page, at: min(max(adjusted, 0), next.count))
        return IslandBoard(pages: next)
    }

    /// Czy moduł jest gdziekolwiek na wyspie (jako widżet albo strona).
    public func contains(moduleID: String) -> Bool {
        pages.contains { page in
            page.content == .module(moduleID) || page.widgets.contains { $0.moduleID == moduleID }
        }
    }

    // MARK: - Pomocnicze

    /// Najwęższa dozwolona szerokość, która przy danym wnętrzu wyspy ma co najmniej `points` punktów.
    public static func minimumWidth(points: CGFloat, innerWidth: CGFloat) -> WidgetWidth {
        guard innerWidth > 0 else { return .full }
        return WidgetWidth.allCases.first { $0.fraction * innerWidth >= points } ?? .full
    }

    static func equalWidth(count: Int) -> WidgetWidth? {
        guard count > 0, WidgetWidth.totalUnits % count == 0 else { return nil }
        return WidgetWidth(rawValue: WidgetWidth.totalUnits / count)
    }

    func widgetPage(_ pageID: UUID) throws(BoardError) -> BoardPage {
        guard let page = pages.first(where: { $0.id == pageID }) else { throw .unknownPage }
        guard case .widgets = page.content else { throw .notAWidgetPage }
        return page
    }

    func replacing(_ page: BoardPage) -> IslandBoard {
        IslandBoard(pages: pages.map { $0.id == page.id ? page : $0 })
    }
}

extension IslandBoard {
    /// Układ startowy: pierwsza strona z widżetami (tyle, ile zmieści się z zachowaniem minimów),
    /// potem pełne strony — dla modułów stron oraz widżetów, które się nie zmieściły.
    public static func initial(widgetModules: [String], pageModules: [String], minimum: Minimum) -> IslandBoard {
        var (board, pageID) = IslandBoard().addingWidgetPage()
        var overflow: [String] = []
        for id in widgetModules {
            if let next = try? board.inserting(moduleID: id, intoPage: pageID, at: .max, minimum: minimum) {
                board = next
            } else {
                overflow.append(id)
            }
        }
        if board.pages.first?.widgets.isEmpty ?? true { board = board.removingPage(pageID) }
        for id in overflow + pageModules where !board.contains(moduleID: id) {
            board = board.addingModulePage(id)
        }
        return board
    }
}
