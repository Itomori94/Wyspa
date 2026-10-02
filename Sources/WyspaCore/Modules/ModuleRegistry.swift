import Observation
import SwiftUI
import UniformTypeIdentifiers

/// Stan modułu widoczny w ustawieniach.
public struct ModuleEntry: Identifiable {
    public let descriptor: ModuleDescriptor
    public let isEnabled: Bool
    public let isActive: Bool
    public let problem: String?

    public var id: String { descriptor.id }
}

/// Strona rozwiniętej wyspy gotowa do wyświetlenia.
public struct IslandPage: Identifiable {
    public struct Widget: Identifiable {
        public let id: UUID
        public let moduleID: String
        public let name: String
        public let width: WidgetWidth
        public let content: AnyView
    }

    public enum Content {
        case widgets([Widget])
        case module(AnyView)
    }

    public let id: UUID
    public let name: String
    public let symbol: String
    public let content: Content
    /// Moduły obecne na stronie (do kierowania upuszczeń).
    public let moduleIDs: [String]
}

/// Tworzy, włącza i wyłącza moduły zgodnie z ustawieniami i uprawnieniami.
@MainActor
@Observable
public final class ModuleRegistry {
    private let catalog: [any IslandModule.Type]
    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let permissions: PermissionProviding
    @ObservationIgnored private let requestExpand: @MainActor () -> Void
    @ObservationIgnored private let log = Log.logger("modules")

    private var instances: [String: any IslandModule] = [:]
    private var problems: [String: String] = [:]
    private var pending: Set<String> = []

    public init(
        catalog: [any IslandModule.Type],
        settings: SettingsStore,
        permissions: PermissionProviding,
        requestExpand: @escaping @MainActor () -> Void
    ) {
        self.catalog = catalog
        self.settings = settings
        self.permissions = permissions
        self.requestExpand = requestExpand
    }

    public var entries: [ModuleEntry] {
        catalog.map { type in
            let id = type.descriptor.id
            return ModuleEntry(
                descriptor: type.descriptor,
                isEnabled: settings.isModuleEnabled(id),
                isActive: instances[id] != nil,
                problem: problems[id]
            )
        }
    }

    public func isPending(_ id: String) -> Bool { pending.contains(id) }

    /// Aktywność o najwyższym priorytecie spośród działających modułów.
    public var currentActivity: LiveActivity? { currentActivityWithSource?.activity }

    /// Bieżąca aktywność razem z identyfikatorem modułu, który ją zgłosił.
    public var currentActivityWithSource: (activity: LiveActivity, moduleID: String)? {
        activeModules
            .compactMap { module in module.liveActivity.map { ($0, type(of: module).descriptor.id) } }
            .max { $0.0.priority < $1.0.priority }
            .map { (activity: $0.0, moduleID: $0.1) }
    }

    /// Czy pokazać aktywność w nagłówku rozwiniętej wyspy: nie, gdy dubluje treść widocznej strony
    /// (moduł, który ją zgłosił, jest na tej stronie) albo gdy sama tego nie chce (np. okładka mediów).
    public static func showsInHeader(_ activity: LiveActivity, from moduleID: String, pageModuleIDs: [String]) -> Bool {
        activity.showsInExpandedHeader && !pageModuleIDs.contains(moduleID)
    }

    /// Układ wyspy: zapisany albo automatyczny z bieżących modułów.
    public var board: IslandBoard {
        settings.board?.normalized() ?? arrangedBoard
    }

    /// Moduły, które w układzie automatycznym dostają pełną stronę zamiast widżetu.
    static let preferredFullPages: Set<String> = ["media", "shelf", "clipboard"]

    /// Układ automatyczny z działających modułów w kolejności katalogu.
    public var arrangedBoard: IslandBoard {
        IslandBoard.arranged(activeModules.compactMap(placement(for:)), minimum: minimumWidth(for:))
    }

    /// Zastępuje zapisany układ automatycznym (przycisk „Uporządkuj automatycznie”).
    public func autoArrange() {
        settings.setBoard(arrangedBoard)
    }

    private func placement(for module: any IslandModule) -> IslandBoard.Placement? {
        let descriptor = type(of: module).descriptor
        let hasWidget = descriptor.widgetMinWidth != nil && module.makeWidgetView() != nil
        if hasWidget && !Self.preferredFullPages.contains(descriptor.id) { return .widget(descriptor.id) }
        return descriptor.providesPage ? .page(descriptor.id) : nil
    }

    /// Strony do wyświetlenia: tylko działające moduły; puste strony są pomijane.
    public var pages: [IslandPage] {
        board.pages.compactMap(resolve)
    }

    public func setBoard(_ newBoard: IslandBoard) {
        settings.setBoard(newBoard)
    }

    /// Minimalna szerokość widżetu modułu przy bieżącym rozmiarze wyspy.
    public func minimumWidth(for moduleID: String) -> WidgetWidth {
        let points = catalog.first { $0.descriptor.id == moduleID }?.descriptor.widgetMinWidth ?? 0
        return IslandBoard.minimumWidth(points: points, innerWidth: settings.expandedInnerWidth)
    }

    public func descriptor(for moduleID: String) -> ModuleDescriptor? {
        catalog.first { $0.descriptor.id == moduleID }?.descriptor
    }

    /// Widok widżetu działającego modułu (podgląd w edytorze).
    public func widgetView(for moduleID: String) -> AnyView? {
        instances[moduleID]?.makeWidgetView()
    }

    public func isActive(_ moduleID: String) -> Bool {
        instances[moduleID] != nil
    }

    private func resolve(_ page: BoardPage) -> IslandPage? {
        switch page.content {
        case .module(let id):
            guard let module = instances[id], let view = module.makeExpandedView() else { return nil }
            let descriptor = type(of: module).descriptor
            return IslandPage(id: page.id, name: descriptor.name, symbol: descriptor.symbol, content: .module(view), moduleIDs: [id])
        case .widgets(let widgets):
            let resolved = widgets.compactMap { widget -> IslandPage.Widget? in
                guard let module = instances[widget.moduleID], let view = module.makeWidgetView() else { return nil }
                return IslandPage.Widget(id: widget.id, moduleID: widget.moduleID, name: type(of: module).descriptor.name,
                                         width: widget.width, content: view)
            }
            guard !resolved.isEmpty else { return nil }
            let name = resolved.map(\.name).joined(separator: " · ")
            let leading = resolved.map { BoardWidget(id: $0.id, moduleID: $0.moduleID, width: $0.width) }.dominantModuleID
            let symbol = leading.flatMap { descriptor(for: $0)?.symbol } ?? "square.grid.2x2"
            return IslandPage(id: page.id, name: name, symbol: symbol, content: .widgets(resolved),
                              moduleIDs: resolved.map(\.moduleID))
        }
    }

    // MARK: - Przeciąganie

    /// Typy przyjmowane przez którykolwiek aktywny moduł; pusta lista = wyspa nie jest celem upuszczania.
    public var dropTypes: [UTType] {
        var seen = Set<UTType>()
        return dropModules
            .flatMap { type(of: $0).acceptedDropTypes }
            .filter { seen.insert($0).inserted }
    }

    /// Strona z modułem przyjmującym upuszczenia (najpierw pełny widok, potem widżet), pokazywana przy przeciąganiu.
    public var dropTabIndex: Int? {
        guard let first = dropModules.first else { return nil }
        return pageIndex(for: type(of: first).descriptor.id)
    }

    /// Strona modułu, którego aktywność widać w zwiniętej wyspie — tam otwiera kliknięcie w aktywność.
    public var activityTabIndex: Int? {
        currentActivityWithSource.flatMap { pageIndex(for: $0.moduleID) }
    }

    /// Strona modułu: najpierw jego pełny widok, potem strona z jego widżetem.
    public func pageIndex(for moduleID: String) -> Int? {
        let pages = pages
        let fullPage = pages.firstIndex { page in
            if case .module = page.content { return page.moduleIDs == [moduleID] }
            return false
        }
        return fullPage ?? pages.firstIndex { $0.moduleIDs.contains(moduleID) }
    }

    /// Kieruje upuszczenie do modułu właściciela strefy, a bez strefy do pierwszego modułu przyjmującego.
    @discardableResult
    public func performDrop(_ providers: [NSItemProvider], zoneID: String?) -> Bool {
        let target = zoneID
            .map(DropZoneID.moduleID(of:))
            .flatMap { id in dropModules.first { type(of: $0).descriptor.id == id } }
            ?? dropModules.first
        guard let target else { return false }
        let ownZone = zoneID.flatMap { DropZoneID.moduleID(of: $0) == type(of: target).descriptor.id ? $0 : nil }
        return target.performDrop(providers, zoneID: ownZone)
    }

    private var dropModules: [any IslandDropHandling] {
        activeModules.compactMap { $0 as? any IslandDropHandling }
    }

    public func settingsView(for id: String) -> AnyView? {
        instances[id]?.makeSettingsView()
    }

    /// Przy starcie włącza moduły zapisane jako włączone, ale bez pokazywania dialogów uprawnień.
    public func startEnabledModules() async {
        for type in catalog where settings.isModuleEnabled(type.descriptor.id) {
            await activate(type, promptForPermissions: false)
        }
    }

    /// Ponawia start modułów włączonych, ale nieaktywnych (np. po nadaniu uprawnienia w Ustawieniach systemowych).
    /// Nie pokazuje dialogów uprawnień.
    public func retryInactiveModules() async {
        for type in catalog where settings.isModuleEnabled(type.descriptor.id) && instances[type.descriptor.id] == nil {
            await activate(type, promptForPermissions: false)
        }
    }

    public func setEnabled(_ id: String, _ enabled: Bool) async {
        guard let type = catalog.first(where: { $0.descriptor.id == id }) else { return }
        // Wyłączenie zawsze działa; trwająca aktywacja sprawdzi ustawienie po zakończeniu i posprząta moduł.
        if enabled && pending.contains(id) { return }
        if enabled {
            settings.setModule(id, enabled: true)
            await activate(type, promptForPermissions: true)
            placeNewlyEnabled(type)
        } else {
            settings.setModule(id, enabled: false)
            deactivate(id)
            problems = problems.filter { $0.key != id }
        }
    }

    /// Nowo włączony moduł dołącza do zapisanego układu: widżet do ostatniej strony z widżetami (jeśli jest miejsce),
    /// pełna strona tylko dla modułów, które jej wymagają.
    private func placeNewlyEnabled(_ type: any IslandModule.Type) {
        let id = type.descriptor.id
        guard let module = instances[id], let saved = settings.board, !saved.contains(moduleID: id) else { return }
        switch placement(for: module) {
        case .widget(let id): settings.setBoard(saved.appendingWidget(id, minimum: minimumWidth(for:)))
        case .page(let id): settings.setBoard(saved.addingModulePage(id))
        case nil: break
        }
    }

    public func stopAll() {
        instances.keys.forEach(deactivate)
    }

    private var activeModules: [any IslandModule] {
        catalog.compactMap { instances[$0.descriptor.id] }
    }

    private func activate(_ type: any IslandModule.Type, promptForPermissions: Bool) async {
        let descriptor = type.descriptor
        // Jedna aktywacja naraz: np. ponowienie po nadaniu Dostępności nie uruchomi drugiej instancji modułu.
        guard instances[descriptor.id] == nil, !pending.contains(descriptor.id) else { return }
        pending = pending.union([descriptor.id])
        defer { pending = pending.subtracting([descriptor.id]) }

        let missing = await missingPermissions(descriptor.permissions, prompt: promptForPermissions)
        guard missing.isEmpty else {
            let names = missing.map(\.displayName).sorted().joined(separator: ", ")
            setProblem("Brak uprawnienia: \(names). Nadaj je w Ustawieniach systemowych.", for: descriptor.id)
            return
        }

        let context = ModuleContext(settings: settings.moduleSettings(for: descriptor.id), requestExpand: requestExpand)
        let module = type.init(context: context)
        do {
            try await module.activate()
            // Użytkownik mógł wyłączyć moduł w trakcie aktywacji.
            guard settings.isModuleEnabled(descriptor.id) else {
                module.deactivate()
                return
            }
            instances = instances.merging([descriptor.id: module]) { _, new in new }
            setProblem(nil, for: descriptor.id)
        } catch {
            module.deactivate()
            log.error("Moduł \(descriptor.id) nie wystartował: \(error.localizedDescription)")
            setProblem("Nie udało się uruchomić: \(error.localizedDescription)", for: descriptor.id)
        }
    }

    private func missingPermissions(_ required: Set<Permission>, prompt: Bool) async -> [Permission] {
        var missing: [Permission] = []
        for permission in required.sorted(by: { $0.rawValue < $1.rawValue }) {
            var status = permissions.status(of: permission)
            if status != .granted, prompt {
                status = await permissions.request(permission)
            }
            if status != .granted { missing.append(permission) }
        }
        return missing
    }

    private func deactivate(_ id: String) {
        guard let module = instances[id] else { return }
        module.deactivate()
        instances = instances.filter { $0.key != id }
    }

    private func setProblem(_ problem: String?, for id: String) {
        problems = problems.filter { $0.key != id }.merging(problem.map { [id: $0] } ?? [:]) { _, new in new }
    }
}
