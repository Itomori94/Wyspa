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

/// Zakładka rozwiniętej wyspy.
public struct ModuleTab: Identifiable {
    public let id: String
    public let name: String
    public let symbol: String
    public let content: AnyView
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
    public var currentActivity: LiveActivity? {
        activeModules
            .compactMap(\.liveActivity)
            .max { $0.priority < $1.priority }
    }

    public var tabs: [ModuleTab] {
        activeModules.compactMap { module in
            let descriptor = type(of: module).descriptor
            return module.makeExpandedView().map {
                ModuleTab(id: descriptor.id, name: descriptor.name, symbol: descriptor.symbol, content: $0)
            }
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

    /// Zakładka modułu przyjmującego upuszczenia, pokazywana przy przeciąganiu nad wyspą.
    public var dropTabIndex: Int? {
        guard let first = dropModules.first else { return nil }
        let id = type(of: first).descriptor.id
        return tabs.firstIndex { $0.id == id }
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
        guard let type = catalog.first(where: { $0.descriptor.id == id }), !pending.contains(id) else { return }
        if enabled {
            settings.setModule(id, enabled: true)
            await activate(type, promptForPermissions: true)
        } else {
            settings.setModule(id, enabled: false)
            deactivate(id)
            problems = problems.filter { $0.key != id }
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
        guard instances[descriptor.id] == nil else { return }
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
