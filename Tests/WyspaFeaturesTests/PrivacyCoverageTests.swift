import Foundation
import Testing
import WyspaCore
@testable import WyspaFeatures

@MainActor
private final class NoPermissions: PermissionProviding {
    func status(of permission: Permission) -> PermissionStatus { .notDetermined }
    func request(_ permission: Permission) async -> PermissionStatus { .denied }
}

@Suite("Tryb prywatny obejmuje wszystkie moduły z katalogu")
@MainActor
struct PrivacyCoverageTests {
    /// Moduły pokazujące osobistą treść. Nowy moduł musi świadomie trafić tu albo nie (deklaracja w opisie jest obowiązkowa).
    static let personal: Set<String> = ["shelf", "calendar", "reminders", "notes", "clipboard", "notifications", "claude", "downloads", "scripts"]

    @Test("Każdy moduł z katalogu ma świadomie przypisaną treść")
    func classification() {
        let declared = Set(ModuleCatalog.all.filter { $0.descriptor.content == .personal }.map { $0.descriptor.id })
        #expect(declared == Self.personal)
    }

    @Test("W trybie prywatnym zasłonięte są dokładnie moduły osobiste")
    func masking() throws {
        let settings = SettingsStore(defaults: try #require(UserDefaults(suiteName: "wyspa.privacy.\(UUID().uuidString)")))
        let registry = ModuleRegistry(catalog: ModuleCatalog.all, settings: settings, permissions: NoPermissions(), requestExpand: { _ in })
        settings.privacyMode = .always
        registry.privacy.refresh()
        for module in ModuleCatalog.all {
            let id = module.descriptor.id
            #expect(registry.isMasked(id) == Self.personal.contains(id), "moduł \(id)")
        }
        settings.privacyMode = .off
        registry.privacy.refresh()
        #expect(ModuleCatalog.all.allSatisfy { !registry.isMasked($0.descriptor.id) })
    }
}
