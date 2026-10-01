import Foundation
import SwiftUI
import Testing
import UniformTypeIdentifiers
@testable import WyspaCore

@MainActor
final class FakePermissions: PermissionProviding {
    var statuses: [Permission: PermissionStatus]
    var answer: PermissionStatus
    private(set) var requested: [Permission] = []

    init(statuses: [Permission: PermissionStatus] = [:], answer: PermissionStatus = .granted) {
        self.statuses = statuses
        self.answer = answer
    }

    func status(of permission: Permission) -> PermissionStatus { statuses[permission] ?? .notDetermined }

    func request(_ permission: Permission) async -> PermissionStatus {
        requested.append(permission)
        statuses[permission] = answer
        return answer
    }
}

@MainActor
enum Probe {
    static var activations: [String] = []
    static var deactivations: [String] = []
    static var shouldFail = false

    static func reset() {
        activations = []
        deactivations = []
        shouldFail = false
    }
}

struct ProbeError: LocalizedError {
    var errorDescription: String? { "awaria testowa" }
}

@MainActor
@Observable
final class PlainModule: IslandModule {
    static let descriptor = ModuleDescriptor(id: "plain", name: "Prosty", summary: "", symbol: "circle")
    var activity: ActivityPriority?

    init(context: ModuleContext) {}
    func activate() async throws {
        if Probe.shouldFail { throw ProbeError() }
        Probe.activations.append("plain")
    }
    func deactivate() { Probe.deactivations.append("plain") }
    var liveActivity: LiveActivity? {
        activity.map { LiveActivity(id: "plain", priority: $0, leading: { EmptyView() }, trailing: { EmptyView() }) }
    }
    func makeExpandedView() -> AnyView? { AnyView(Text("plain")) }
}

@MainActor
@Observable
final class CameraModule: IslandModule {
    static let descriptor = ModuleDescriptor(
        id: "camera", name: "Kamera", summary: "", symbol: "camera", permissions: [.camera]
    )
    init(context: ModuleContext) {}
    func activate() async throws { Probe.activations.append("camera") }
    func deactivate() { Probe.deactivations.append("camera") }
    var liveActivity: LiveActivity? {
        LiveActivity(id: "camera", priority: .status, leading: { EmptyView() }, trailing: { EmptyView() })
    }
    func makeExpandedView() -> AnyView? { nil }
}

@MainActor
@Observable
final class DropModule: IslandModule, IslandDropHandling {
    static let descriptor = ModuleDescriptor(id: "drop", name: "Upuść", summary: "", symbol: "tray")
    static let acceptedDropTypes: [UTType] = [.fileURL, .image]
    static var drops: [String?] = []

    init(context: ModuleContext) {}
    func activate() async throws {}
    func deactivate() {}
    var liveActivity: LiveActivity? { nil }
    func makeExpandedView() -> AnyView? { AnyView(Text("drop")) }
    func performDrop(_ providers: [NSItemProvider], zoneID: String?) -> Bool {
        Self.drops.append(zoneID)
        return true
    }
}

@MainActor
@Suite("Rejestr modułów", .serialized)
struct ModuleRegistryTests {
    private func makeSettings() -> SettingsStore {
        let name = "wyspa.tests.\(UUID().uuidString)"
        return SettingsStore(defaults: UserDefaults(suiteName: name)!)
    }

    private func makeRegistry(
        settings: SettingsStore,
        permissions: FakePermissions = FakePermissions()
    ) -> ModuleRegistry {
        Probe.reset()
        return ModuleRegistry(
            catalog: [PlainModule.self, CameraModule.self],
            settings: settings,
            permissions: permissions,
            requestExpand: {}
        )
    }

    @Test("Domyślnie żaden moduł nie działa i nic nie prosi o uprawnienia")
    func nothingRunsByDefault() async {
        let permissions = FakePermissions()
        let registry = makeRegistry(settings: makeSettings(), permissions: permissions)
        await registry.startEnabledModules()
        #expect(registry.entries.allSatisfy { !$0.isActive })
        #expect(permissions.requested.isEmpty)
        #expect(Probe.activations.isEmpty)
    }

    @Test("Włączenie modułu bez uprawnień uruchamia go i pokazuje zakładkę")
    func enablePlain() async {
        let settings = makeSettings()
        let registry = makeRegistry(settings: settings)
        await registry.setEnabled("plain", true)
        #expect(Probe.activations == ["plain"])
        #expect(settings.isModuleEnabled("plain"))
        #expect(registry.tabs.map(\.id) == ["plain"])
    }

    @Test("Wyłączenie zwalnia moduł")
    func disable() async {
        let registry = makeRegistry(settings: makeSettings())
        await registry.setEnabled("plain", true)
        await registry.setEnabled("plain", false)
        #expect(Probe.deactivations == ["plain"])
        #expect(registry.tabs.isEmpty)
        #expect(registry.entries.first { $0.id == "plain" }?.isActive == false)
    }

    @Test("Uprawnienie jest wymagane dopiero przy włączeniu")
    func permissionRequestedOnEnable() async {
        let permissions = FakePermissions(answer: .granted)
        let registry = makeRegistry(settings: makeSettings(), permissions: permissions)
        await registry.setEnabled("camera", true)
        #expect(permissions.requested == [.camera])
        #expect(Probe.activations == ["camera"])
    }

    @Test("Odmowa uprawnienia: moduł nie startuje i pokazuje problem")
    func permissionDenied() async {
        let permissions = FakePermissions(answer: .denied)
        let registry = makeRegistry(settings: makeSettings(), permissions: permissions)
        await registry.setEnabled("camera", true)
        let entry = registry.entries.first { $0.id == "camera" }
        #expect(entry?.isActive == false)
        #expect(entry?.problem?.contains("Kamera") == true)
        #expect(Probe.activations.isEmpty)
    }

    @Test("Przy starcie aplikacji brakujące uprawnienie nie wywołuje dialogu")
    func startupDoesNotPrompt() async {
        let settings = makeSettings()
        settings.setModule("camera", enabled: true)
        let permissions = FakePermissions()
        let registry = makeRegistry(settings: settings, permissions: permissions)
        await registry.startEnabledModules()
        #expect(permissions.requested.isEmpty)
        #expect(registry.entries.first { $0.id == "camera" }?.problem != nil)
    }

    @Test("Błąd aktywacji: moduł jest sprzątany, aplikacja działa dalej")
    func activationFailure() async {
        let registry = makeRegistry(settings: makeSettings())
        Probe.shouldFail = true
        await registry.setEnabled("plain", true)
        let entry = registry.entries.first { $0.id == "plain" }
        #expect(entry?.isActive == false)
        #expect(entry?.problem?.contains("awaria testowa") == true)
        #expect(Probe.deactivations == ["plain"])
    }

    @Test("Wygrywa aktywność o najwyższym priorytecie")
    func activityArbitration() async {
        let permissions = FakePermissions(statuses: [.camera: .granted])
        let registry = makeRegistry(settings: makeSettings(), permissions: permissions)
        await registry.setEnabled("camera", true)
        await registry.setEnabled("plain", true)
        #expect(registry.currentActivity?.id == "camera")
        #expect(registry.tabs.count == 1)
    }

    @Test("Nieznany identyfikator jest ignorowany")
    func unknownModule() async {
        let settings = makeSettings()
        let registry = makeRegistry(settings: settings)
        await registry.setEnabled("nieistnieje", true)
        #expect(!settings.isModuleEnabled("nieistnieje"))
    }

    @Test("Upuszczenia: typy, zakładka i kierowanie do strefy modułu")
    func dropRouting() async {
        Probe.reset()
        DropModule.drops = []
        let settings = makeSettings()
        let registry = ModuleRegistry(
            catalog: [PlainModule.self, DropModule.self], settings: settings,
            permissions: FakePermissions(), requestExpand: {}
        )
        #expect(registry.dropTypes.isEmpty)
        #expect(!registry.performDrop([], zoneID: nil))

        await registry.setEnabled("plain", true)
        await registry.setEnabled("drop", true)
        #expect(registry.dropTypes == [.fileURL, .image])
        #expect(registry.dropTabIndex == 1)

        #expect(registry.performDrop([], zoneID: "drop.airdrop"))
        #expect(registry.performDrop([], zoneID: nil))
        #expect(registry.performDrop([], zoneID: "obcy.strefa"))
        #expect(DropModule.drops == ["drop.airdrop", nil, nil])
    }

    @Test("Identyfikator modułu ze strefy upuszczania")
    func zoneModuleID() {
        #expect(DropZoneID.moduleID(of: "shelf.airdrop") == "shelf")
        #expect(DropZoneID.moduleID(of: "shelf") == "shelf")
    }

    @Test("Ponowienie startu po nadaniu uprawnienia, bez dialogu")
    func retryAfterGrant() async {
        let settings = makeSettings()
        settings.setModule("camera", enabled: true)
        let permissions = FakePermissions(statuses: [.camera: .denied])
        let registry = makeRegistry(settings: settings, permissions: permissions)
        await registry.startEnabledModules()
        #expect(registry.entries.first { $0.id == "camera" }?.isActive == false)

        permissions.statuses[.camera] = .granted
        await registry.retryInactiveModules()
        #expect(registry.entries.first { $0.id == "camera" }?.isActive == true)
        #expect(permissions.requested.isEmpty)
    }
}
