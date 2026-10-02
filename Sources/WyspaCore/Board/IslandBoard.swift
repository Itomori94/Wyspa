import CoreGraphics
import Foundation

/// Szerokość widżetu w jednostkach wnętrza rozwiniętej wyspy (120 jednostek = cała szerokość).
///
/// Szerokość jest płynna (regulowana dzielnikiem); 120 dzieli się przez 1–6, więc równy podział jest zawsze dokładny.
public struct WidgetWidth: Codable, Equatable, Hashable, Comparable, Sendable {
    public static let totalUnits = 120
    public static let full = WidgetWidth(units: totalUnits)

    public let units: Int

    public init(units: Int) {
        self.units = min(max(units, 1), Self.totalUnits)
    }

    public var fraction: CGFloat { CGFloat(units) / CGFloat(Self.totalUnits) }

    public static func < (lhs: WidgetWidth, rhs: WidgetWidth) -> Bool { lhs.units < rhs.units }

    public init(from decoder: Decoder) throws {
        self.init(units: try decoder.singleValueContainer().decode(Int.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(units)
    }
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
        case .noRoom: "Na tej stronie brak miejsca. Zwęź albo usuń inny widżet, albo dodaj nową stronę."
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

    /// Skala zapisu szerokości; starsze układy zapisywano w dwunastkach.
    static let unitScale = WidgetWidth.totalUnits
    static let legacyUnitScale = 12

    public let pages: [BoardPage]

    public init(pages: [BoardPage] = []) {
        self.pages = pages
    }

    private enum CodingKeys: String, CodingKey { case pages, unitScale }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decoded = try container.decode([BoardPage].self, forKey: .pages)
        let scale = try container.decodeIfPresent(Int.self, forKey: .unitScale) ?? Self.legacyUnitScale
        guard scale != Self.unitScale, scale > 0 else {
            pages = decoded
            return
        }
        // Przeliczenie układu zapisanego w innej skali (np. dwunastkach) na bieżącą.
        pages = decoded.map { page in
            guard case .widgets(let widgets) = page.content else { return page }
            return page.with(widgets: widgets.map {
                $0.with(width: WidgetWidth(units: $0.width.units * Self.unitScale / scale))
            })
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pages, forKey: .pages)
        try container.encode(Self.unitScale, forKey: .unitScale)
    }

    // MARK: - Widżety

    /// Dodaje widżet na stronę: zajmuje wolne miejsce, a gdy go brak — wszystkie widżety dzielą stronę po równo.
    public func inserting(moduleID: String, intoPage pageID: UUID, at index: Int, minimum: Minimum) throws(BoardError) -> IslandBoard {
        let page = try widgetPage(pageID)
        let widgets = page.widgets
        let remaining = WidgetWidth.totalUnits - page.usedUnits
        let insertAt = min(max(index, 0), widgets.count)

        if remaining >= minimum(moduleID).units {
            var next = widgets
            next.insert(BoardWidget(moduleID: moduleID, width: WidgetWidth(units: remaining)), at: insertAt)
            return replacing(page.with(widgets: next))
        }
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
        let withoutSource = removing(widget: widgetID)
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

    /// Przesuwa dzielnik między widżetami `dividerIndex` i `dividerIndex + 1` o `delta` jednostek (płynnie).
    /// Suma pary się nie zmienia, oba widżety zachowują swoje minima.
    public func movingDivider(onPage pageID: UUID, after dividerIndex: Int, by delta: Int, minimum: Minimum) throws(BoardError) -> IslandBoard {
        let page = try widgetPage(pageID)
        var widgets = page.widgets
        guard widgets.indices.contains(dividerIndex), widgets.indices.contains(dividerIndex + 1) else { throw .unknownWidget }
        let left = widgets[dividerIndex]
        let right = widgets[dividerIndex + 1]
        let pair = left.width.units + right.width.units
        let lowest = minimum(left.moduleID).units
        let highest = pair - minimum(right.moduleID).units
        guard lowest <= highest else { return self }
        let newLeft = min(max(left.width.units + delta, lowest), highest)
        widgets[dividerIndex] = left.with(width: WidgetWidth(units: newLeft))
        widgets[dividerIndex + 1] = right.with(width: WidgetWidth(units: pair - newLeft))
        return replacing(page.with(widgets: widgets))
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

    /// Strony z wolnym miejscem (np. starszy zapis) wypełnione do pełnej szerokości.
    public func normalized() -> IslandBoard {
        IslandBoard(pages: pages.map { page in
            let widgets = page.widgets
            guard !widgets.isEmpty, page.usedUnits != WidgetWidth.totalUnits else { return page }
            let allEqual = Set(widgets.map(\.width)).count == 1
            return page.with(widgets: Self.filling(widgets, freedAt: widgets.count, keepEqual: allEqual))
        })
    }

    // MARK: - Pomocnicze

    /// Najmniejsza szerokość, która przy danym wnętrzu wyspy ma co najmniej `points` punktów.
    public static func minimumWidth(points: CGFloat, innerWidth: CGFloat) -> WidgetWidth {
        guard innerWidth > 0 else { return .full }
        let units = Int((points / innerWidth * CGFloat(WidgetWidth.totalUnits)).rounded(.up))
        return WidgetWidth(units: max(units, 1))
    }

    static func equalWidth(count: Int) -> WidgetWidth? {
        guard count > 0, WidgetWidth.totalUnits % count == 0 else { return nil }
        return WidgetWidth(units: WidgetWidth.totalUnits / count)
    }

    /// Rozdziela wolne (albo nadmiarowe) miejsce strony tak, żeby widżety zajmowały dokładnie całą szerokość.
    static func filling(_ widgets: [BoardWidget], freedAt index: Int, keepEqual: Bool) -> [BoardWidget] {
        guard !widgets.isEmpty else { return widgets }
        if keepEqual, let equal = equalWidth(count: widgets.count) {
            return widgets.map { $0.with(width: equal) }
        }
        let difference = WidgetWidth.totalUnits - widgets.map(\.width.units).reduce(0, +)
        guard difference != 0 else { return widgets }
        // Miejsce dostaje sąsiad z lewej (albo pierwszy z prawej).
        let target = widgets.indices.contains(index - 1) ? index - 1 : min(index, widgets.count - 1)
        var result = widgets
        result[target] = widgets[target].with(width: WidgetWidth(units: widgets[target].width.units + difference))
        return result
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
    /// Najwięcej widżetów na jednej stronie w układzie automatycznym (ręcznie można dodać więcej).
    public static let autoWidgetsPerPage = 3

    public enum Placement: Equatable, Sendable {
        /// Moduł jako widżet (grupowany z innymi na stronie).
        case widget(String)
        /// Moduł jako pełna strona.
        case page(String)
    }

    /// Układ automatyczny w podanej kolejności: pełne strony tam, gdzie wskazano, a widżety grupowane
    /// po `autoWidgetsPerPage` na stronę z zachowaniem minimalnych szerokości.
    public static func arranged(_ placements: [Placement], minimum: Minimum) -> IslandBoard {
        placements.reduce(IslandBoard()) { board, placement in
            switch placement {
            case .page(let id): board.addingModulePage(id)
            case .widget(let id): board.appendingWidget(id, minimum: minimum)
            }
        }
    }

    /// Dodaje widżet do ostatniej strony z widżetami, jeśli jest na niej miejsce; inaczej na nowej stronie.
    public func appendingWidget(_ moduleID: String, minimum: Minimum) -> IslandBoard {
        guard !contains(moduleID: moduleID) else { return self }
        if let last = pages.last(where: { if case .widgets = $0.content { true } else { false } }),
           last.widgets.count < Self.autoWidgetsPerPage,
           let placed = try? inserting(moduleID: moduleID, intoPage: last.id, at: .max, minimum: minimum) {
            return placed
        }
        let (withPage, pageID) = addingWidgetPage()
        return (try? withPage.inserting(moduleID: moduleID, intoPage: pageID, at: 0, minimum: minimum)) ?? self
    }
}

public extension Array where Element == BoardWidget {
    /// Moduł, który reprezentuje stronę z widżetami (np. jej ikoną na pasku zakładek): najszerszy, przy remisie pierwszy.
    var dominantModuleID: String? {
        enumerated().max { lhs, rhs in
            lhs.element.width.units != rhs.element.width.units
                ? lhs.element.width.units < rhs.element.width.units
                : lhs.offset > rhs.offset
        }?.element.moduleID
    }
}
