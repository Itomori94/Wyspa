import AppKit
import SwiftUI
import Testing
@testable import WyspaCore
@testable import WyspaUI

// Test wizualny: renderuje wyspę poza ekranem i sprawdza, że żadna treść nie wychodzi poza kształt wyspy.
// Cień wyspy jest czarny, więc „jasny piksel poza wyspą” oznacza wyciekającą treść.

@MainActor
private final class AllGranted: PermissionProviding {
    func status(of permission: Permission) -> PermissionStatus { .granted }
    func request(_ permission: Permission) async -> PermissionStatus { .granted }
}

/// Konfiguracja modułów testowych (ile zakładek, jaka aktywność).
@MainActor
private enum Scenario {
    static var activityWing: CGFloat?
}

/// Szeroka, jasna treść zakładki: wypełnia całą dostępną szerokość jak widok mediów.
private struct WideContent: View {
    var body: some View {
        HStack {
            Rectangle().fill(.white).frame(width: 90, height: 90)
            Text("Bardzo długi tytuł utworu, który się nie mieści").font(.system(size: 15)).foregroundStyle(.white)
            Rectangle().fill(.white).frame(height: 4)
        }
        .frame(maxWidth: .infinity)
    }
}

@MainActor
@Observable
private class TabModuleBase {
    required init(context: ModuleContext) {}
    func activate() async throws {}
    func deactivate() {}
    func makeExpandedView() -> AnyView? { AnyView(WideContent()) }
}

@MainActor @Observable private final class Tab0: TabModuleBase, IslandModule {
    static let descriptor = ModuleDescriptor(id: "t0", name: "T0", summary: "", symbol: "music.note")
    var liveActivity: LiveActivity? {
        Scenario.activityWing.map { wing in
            LiveActivity(id: "a", priority: .hud, wingWidth: wing) {
                Rectangle().fill(.white).frame(maxWidth: .infinity).frame(height: 10)
            } trailing: {
                Rectangle().fill(.white).frame(maxWidth: .infinity).frame(height: 10)
            }
        }
    }
}
@MainActor @Observable private final class Tab1: TabModuleBase, IslandModule {
    static let descriptor = ModuleDescriptor(id: "t1", name: "T1", summary: "", symbol: "tray.full")
    var liveActivity: LiveActivity? { nil }
}
@MainActor @Observable private final class Tab2: TabModuleBase, IslandModule {
    static let descriptor = ModuleDescriptor(id: "t2", name: "T2", summary: "", symbol: "bolt")
    var liveActivity: LiveActivity? { nil }
}
@MainActor @Observable private final class Tab3: TabModuleBase, IslandModule {
    static let descriptor = ModuleDescriptor(id: "t3", name: "T3", summary: "", symbol: "headphones")
    var liveActivity: LiveActivity? { nil }
}
@MainActor @Observable private final class Tab4: TabModuleBase, IslandModule {
    static let descriptor = ModuleDescriptor(id: "t4", name: "T4", summary: "", symbol: "calendar")
    var liveActivity: LiveActivity? { nil }
}
@MainActor @Observable private final class Tab5: TabModuleBase, IslandModule {
    static let descriptor = ModuleDescriptor(id: "t5", name: "T5", summary: "", symbol: "timer")
    var liveActivity: LiveActivity? { nil }
}
@MainActor @Observable private final class Tab6: TabModuleBase, IslandModule {
    static let descriptor = ModuleDescriptor(id: "t6", name: "T6", summary: "", symbol: "note.text")
    var liveActivity: LiveActivity? { nil }
}
@MainActor @Observable private final class Tab7: TabModuleBase, IslandModule {
    static let descriptor = ModuleDescriptor(id: "t7", name: "T7", summary: "", symbol: "doc.on.clipboard")
    var liveActivity: LiveActivity? { nil }
}
@MainActor @Observable private final class Tab8: TabModuleBase, IslandModule {
    static let descriptor = ModuleDescriptor(id: "t8", name: "T8", summary: "", symbol: "square.stack.3d.up")
    var liveActivity: LiveActivity? { nil }
}
@MainActor @Observable private final class Tab9: TabModuleBase, IslandModule {
    static let descriptor = ModuleDescriptor(id: "t9", name: "T9", summary: "", symbol: "camera")
    var liveActivity: LiveActivity? { nil }
}

@MainActor
private let allTabModules: [any IslandModule.Type] = [
    Tab0.self, Tab1.self, Tab2.self, Tab3.self, Tab4.self, Tab5.self, Tab6.self, Tab7.self, Tab8.self, Tab9.self,
]

@MainActor
@Suite("Wyspa nie wycieka poza swój kształt", .serialized)
struct IslandOverflowTests {
    nonisolated static let shadowMargin: CGFloat = 36
    nonisolated static let notch = NotchMetrics(size: CGSize(width: 200, height: 38), isPhysical: true)

    struct Case: CustomTestStringConvertible, Sendable {
        let phase: IslandPhase
        let size: IslandSize
        let tabCount: Int
        let wing: CGFloat?
        var testDescription: String { "\(phase) \(size) zakładki:\(tabCount) skrzydło:\(wing.map { "\(Int($0))" } ?? "brak")" }
    }

    nonisolated static let cases: [Case] = {
        var result: [Case] = []
        for phase in [IslandPhase.collapsed, .expanded] {
            for size in IslandSize.allCases {
                for tabCount in [0, 1, 4, 10] {
                    for wing in [nil, IslandLayout.wingWidth, 70, IslandLayout.maxWingWidth] as [CGFloat?] {
                        result.append(Case(phase: phase, size: size, tabCount: tabCount, wing: wing))
                    }
                }
            }
        }
        return result
    }()

    @Test("Żaden jasny piksel poza kształtem wyspy", arguments: cases)
    func noContentOutsideIsland(_ scenario: Case) async throws {
        Scenario.activityWing = scenario.wing
        let defaults = UserDefaults(suiteName: "overflow.\(UUID())")!
        let catalog = Array(allTabModules.prefix(max(scenario.tabCount, 1)))
        let registry = ModuleRegistry(catalog: catalog, settings: SettingsStore(defaults: defaults),
                                      permissions: AllGranted(), requestExpand: {})
        for type in catalog { await registry.setEnabled(type.descriptor.id, true) }

        let expanded = scenario.size.expandedSize
        let model = IslandViewModel(phase: scenario.phase, notch: Self.notch, expandedSize: expanded, registry: registry)
        let panel = IslandLayout.panelSize(expanded: expanded, notch: Self.notch.size, shadowMargin: Self.shadowMargin)
        let host = NSHostingView(rootView: IslandView(model: model))
        host.frame = CGRect(origin: .zero, size: panel)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
        host.layoutSubtreeIfNeeded()

        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)

        // Podgląd do oceny wzrokowej: WYSPA_RENDER_DIR=/ścieżka swift test --filter IslandOverflowTests
        if let directory = ProcessInfo.processInfo.environment["WYSPA_RENDER_DIR"],
           let png = rep.representation(using: .png, properties: [:]) {
            let name = scenario.testDescription.replacingOccurrences(of: " ", with: "_").replacingOccurrences(of: ":", with: "-")
            try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png"))
        }

        let island = model.islandSize
        let scale = CGFloat(rep.pixelsWide) / panel.width
        let minX = (panel.width - island.width) / 2 * scale
        let maxX = (panel.width + island.width) / 2 * scale
        let maxY = island.height * scale
        var leaks = 0
        for y in stride(from: 0, to: rep.pixelsHigh, by: 2) {
            for x in stride(from: 0, to: rep.pixelsWide, by: 2) {
                let inside = CGFloat(x) >= minX && CGFloat(x) < maxX && CGFloat(y) < maxY
                guard !inside, let color = rep.colorAt(x: x, y: y) else { continue }
                let rgb = color.usingColorSpace(.deviceRGB) ?? color
                let brightness = max(rgb.redComponent, rgb.greenComponent, rgb.blueComponent) * rgb.alphaComponent
                if brightness > 0.25 { leaks += 1 }
            }
        }
        #expect(leaks == 0, "\(leaks) jasnych pikseli poza wyspą")
    }
}
