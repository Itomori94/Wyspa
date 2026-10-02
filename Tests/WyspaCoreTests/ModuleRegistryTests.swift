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
@Observable
final class MediaLikeModule: IslandModule {
    static let descriptor = ModuleDescriptor(id: "media-like", name: "Media", summary: "", symbol: "music.note")
    static var playing = false
    init(context: ModuleContext) {}
    func activate() async throws {}
    func deactivate() {}
    var liveActivity: LiveActivity? {
        Self.playing ? LiveActivity(id: "media", priority: .media, leading: { EmptyView() }, trailing: { EmptyView() }) : nil
    }
    func makeExpandedView() -> AnyView? { nil }
}

@MainActor
@Observable
final class HUDLikeModule: IslandModule {
    static let descriptor = ModuleDescriptor(id: "hud-like", name: "HUD", summary: "", symbol: "speaker")
    static var showing = false
    init(context: ModuleContext) {}
    func activate() async throws {}
    func deactivate() {}
    var liveActivity: LiveActivity? {
        Self.showing
            ? LiveActivity(id: "hud", priority: .hud, wingWidth: 70, leading: { EmptyView() }, trailing: { EmptyView() })
            : nil
    }
    func makeExpandedView() -> AnyView? { nil }
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
        #expect(registry.pages.flatMap(\.moduleIDs) == ["plain"])
    }

    @Test("Wyłączenie zwalnia moduł")
    func disable() async {
        let registry = makeRegistry(settings: makeSettings())
        await registry.setEnabled("plain", true)
        await registry.setEnabled("plain", false)
        #expect(Probe.deactivations == ["plain"])
        #expect(registry.pages.isEmpty)
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
        #expect(registry.pages.count == 1)
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

    @Test("Arbiter: HUD zastępuje media na czas wyświetlania, potem media wracają")
    func hudReplacesMediaTemporarily() async {
        MediaLikeModule.playing = true
        HUDLikeModule.showing = false
        let registry = ModuleRegistry(
            catalog: [MediaLikeModule.self, HUDLikeModule.self], settings: makeSettings(),
            permissions: FakePermissions(), requestExpand: {}
        )
        await registry.setEnabled("media-like", true)
        await registry.setEnabled("hud-like", true)
        #expect(registry.currentActivity?.id == "media")

        HUDLikeModule.showing = true
        #expect(registry.currentActivity?.id == "hud")
        #expect(registry.currentActivity?.wingWidth == 70)

        HUDLikeModule.showing = false
        #expect(registry.currentActivity?.id == "media")
        #expect(registry.currentActivity?.wingWidth == IslandLayout.wingWidth)
        MediaLikeModule.playing = false
    }

    @Test("Szerokość skrzydła jest ograniczona do maksimum")
    func wingWidthClamped() {
        let activity = LiveActivity(id: "x", priority: .status, wingWidth: 500, leading: { EmptyView() }, trailing: { EmptyView() })
        #expect(activity.wingWidth == IslandLayout.maxWingWidth)
    }

    @Test("Strony z zapisanego układu: tylko działające moduły, puste strony pominięte")
    func pagesFromBoard() async throws {
        let settings = makeSettings()
        let registry = ModuleRegistry(
            catalog: [PlainModule.self, DropModule.self], settings: settings,
            permissions: FakePermissions(), requestExpand: {}
        )
        await registry.setEnabled("plain", true)
        await registry.setEnabled("drop", true)
        // Bez zapisanego układu: strony startowe z działających modułów.
        #expect(Set(registry.pages.flatMap(\.moduleIDs)) == ["plain", "drop"])

        let board = IslandBoard().addingModulePage("drop").addingModulePage("plain").addingModulePage("nieobecny")
        registry.setBoard(board)
        #expect(registry.pages.map(\.moduleIDs) == [["drop"], ["plain"]])
        #expect(registry.dropTabIndex == 0)

        await registry.setEnabled("drop", false)
        #expect(registry.pages.map(\.moduleIDs) == [["plain"]])
    }

    @Test("Włączony moduł spoza układu dostaje swoją stronę na końcu")
    func newlyEnabledIsPlaced() async {
        let settings = makeSettings()
        let registry = ModuleRegistry(
            catalog: [PlainModule.self, DropModule.self], settings: settings,
            permissions: FakePermissions(), requestExpand: {}
        )
        await registry.setEnabled("plain", true)
        registry.setBoard(IslandBoard().addingModulePage("plain"))
        await registry.setEnabled("drop", true)
        #expect(settings.board?.pages.map(\.content) == [.module("plain"), .module("drop")])
    }


    @Test("Wyłączenie w trakcie czekania na zgodę: moduł nie zostaje uruchomiony")
    func disableWhilePending() async {
        let settings = makeSettings()
        let permissions = SlowPermissions()
        let registry = ModuleRegistry(catalog: [CameraModule.self], settings: settings, permissions: permissions, requestExpand: {})
        Probe.reset()
        let enabling = Task { await registry.setEnabled("camera", true) }
        await permissions.waitUntilAsked()
        await registry.setEnabled("camera", false)
        permissions.answer(.granted)
        await enabling.value
        #expect(registry.entries.first { $0.id == "camera" }?.isActive == false)
        #expect(!settings.isModuleEnabled("camera"))
        #expect(Probe.activations == Probe.deactivations)
    }
}

/// Uprawnienia, które odpowiadają dopiero na żądanie testu (symulacja otwartego dialogu systemowego).
@MainActor
final class SlowPermissions: PermissionProviding {
    private var continuation: CheckedContinuation<PermissionStatus, Never>?
    private var askedContinuation: CheckedContinuation<Void, Never>?
    private var asked = false

    func status(of permission: Permission) -> PermissionStatus { .notDetermined }

    func request(_ permission: Permission) async -> PermissionStatus {
        asked = true
        askedContinuation?.resume()
        askedContinuation = nil
        return await withCheckedContinuation { continuation = $0 }
    }

    func waitUntilAsked() async {
        guard !asked else { return }
        await withCheckedContinuation { askedContinuation = $0 }
    }

    func answer(_ status: PermissionStatus) {
        continuation?.resume(returning: status)
        continuation = nil
    }

    @Test("Aktywność domyślnie widoczna w nagłówku rozwiniętej wyspy, można to wyłączyć")
    func headerVisibility() {
        let shown = LiveActivity(id: "a", priority: .hud, leading: { EmptyView() }, trailing: { EmptyView() })
        let hidden = LiveActivity(id: "b", priority: .media, showsInExpandedHeader: false, leading: { EmptyView() }, trailing: { EmptyView() })
        #expect(shown.showsInExpandedHeader && !hidden.showsInExpandedHeader)
    }
}

@Suite("Aktywność w nagłówku rozwiniętej wyspy")
@MainActor
struct HeaderActivityTests {
    let timer = LiveActivity(id: "timer", priority: .timer, leading: { EmptyView() }, trailing: { EmptyView() })

    @Test("Moduł widoczny na stronie nie dubluje się w nagłówku")
    func hiddenWhenOnPage() {
        #expect(!ModuleRegistry.showsInHeader(timer, from: "timer", pageModuleIDs: ["notes", "timer"]))
    }

    @Test("Na innej stronie aktywność zostaje w nagłówku")
    func shownElsewhere() {
        #expect(ModuleRegistry.showsInHeader(timer, from: "timer", pageModuleIDs: ["media"]))
        #expect(ModuleRegistry.showsInHeader(timer, from: "timer", pageModuleIDs: []))
    }

    @Test("Aktywność, która sama nie chce nagłówka, nie pojawia się nigdzie")
    func optOut() {
        let media = LiveActivity(id: "media", priority: .media, showsInExpandedHeader: false,
                                 leading: { EmptyView() }, trailing: { EmptyView() })
        #expect(!ModuleRegistry.showsInHeader(media, from: "media", pageModuleIDs: ["timer"]))
    }
}

@MainActor
@Observable
final class ActivityPageModule: IslandModule {
    static let descriptor = ModuleDescriptor(id: "activity-page", name: "Timer", summary: "", symbol: "timer")
    static var active = false
    init(context: ModuleContext) {}
    func activate() async throws {}
    func deactivate() {}
    var liveActivity: LiveActivity? {
        Self.active ? LiveActivity(id: "timer", priority: .timer, leading: { EmptyView() }, trailing: { EmptyView() }) : nil
    }
    func makeExpandedView() -> AnyView? { AnyView(Text("timer")) }
}

@Suite("Kliknięcie aktywności otwiera stronę modułu", .serialized)
@MainActor
struct ActivityTabTests {
    @Test("Strona modułu z widoczną aktywnością; bez aktywności — brak")
    func activityTab() async {
        let settings = SettingsStore(defaults: UserDefaults(suiteName: "wyspa.tests.\(UUID().uuidString)")!)
        let registry = ModuleRegistry(catalog: [PlainModule.self, ActivityPageModule.self], settings: settings,
                                      permissions: FakePermissions(), requestExpand: {})
        await registry.setEnabled("plain", true)
        await registry.setEnabled("activity-page", true)
        ActivityPageModule.active = false
        #expect(registry.activityTabIndex == nil)
        ActivityPageModule.active = true
        defer { ActivityPageModule.active = false }
        #expect(registry.activityTabIndex == registry.pageIndex(for: "activity-page"))
        #expect(registry.activityTabIndex != nil && registry.activityTabIndex != registry.pageIndex(for: "plain"))
    }

    @Test("Przekazanie do strefy innego modułu tylko, gdy ten moduł działa (bez zastępczego odbiorcy)")
    func strictDelivery() async {
        DropModule.drops = []
        let settings = SettingsStore(defaults: UserDefaults(suiteName: "wyspa.tests.\(UUID().uuidString)")!)
        let registry = ModuleRegistry(catalog: [PlainModule.self, DropModule.self], settings: settings,
                                      permissions: FakePermissions(), requestExpand: {})
        await registry.setEnabled("plain", true)
        #expect(!registry.deliver([], toZone: "drop.store"))
        await registry.setEnabled("drop", true)
        #expect(registry.deliver([], toZone: "drop.store"))
        #expect(!registry.deliver([], toZone: "shelf.store"))
    }
}
