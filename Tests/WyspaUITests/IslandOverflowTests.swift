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
    /// Wysokość karty pod notchem (powiadomienie, HUD); nil = bez karty.
    static var detailHeight: CGFloat?
}

/// Za duża, jasna karta: sprawdza, że wyspa przycina kartę do swojego kształtu.
private struct OversizedCard: View {
    var body: some View {
        Rectangle().fill(.white).frame(width: 2000, height: 400)
    }
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
    func makeWidgetView() -> AnyView? { AnyView(WideContent()) }
}

@MainActor @Observable private final class Tab0: TabModuleBase, IslandModule {
    static let descriptor = ModuleDescriptor(id: "t0", name: "T0", summary: "", symbol: "music.note", content: .neutral, widgetMinWidth: 60)
    var liveActivity: LiveActivity? {
        Scenario.activityWing.map { wing in
            if let detail = Scenario.detailHeight {
                return LiveActivity(id: "a", priority: .hud, wingWidth: wing, detailHeight: detail) {
                    Rectangle().fill(.white).frame(maxWidth: .infinity).frame(height: 10)
                } trailing: {
                    Rectangle().fill(.white).frame(maxWidth: .infinity).frame(height: 10)
                } detail: {
                    OversizedCard()
                }
            }
            return LiveActivity(id: "a", priority: .hud, wingWidth: wing) {
                Rectangle().fill(.white).frame(maxWidth: .infinity).frame(height: 10)
            } trailing: {
                Rectangle().fill(.white).frame(maxWidth: .infinity).frame(height: 10)
            }
        }
    }
}
@MainActor @Observable private final class Tab1: TabModuleBase, IslandModule {
    static let descriptor = ModuleDescriptor(id: "t1", name: "T1", summary: "", symbol: "tray.full", content: .neutral, widgetMinWidth: 60)
    var liveActivity: LiveActivity? { nil }
}
@MainActor @Observable private final class Tab2: TabModuleBase, IslandModule {
    static let descriptor = ModuleDescriptor(id: "t2", name: "T2", summary: "", symbol: "bolt", content: .neutral, widgetMinWidth: 60)
    var liveActivity: LiveActivity? { nil }
}
@MainActor @Observable private final class Tab3: TabModuleBase, IslandModule {
    static let descriptor = ModuleDescriptor(id: "t3", name: "T3", summary: "", symbol: "headphones", content: .neutral, widgetMinWidth: 60)
    var liveActivity: LiveActivity? { nil }
}
@MainActor @Observable private final class Tab4: TabModuleBase, IslandModule {
    static let descriptor = ModuleDescriptor(id: "t4", name: "T4", summary: "", symbol: "calendar", content: .neutral, widgetMinWidth: 60)
    var liveActivity: LiveActivity? { nil }
}
@MainActor @Observable private final class Tab5: TabModuleBase, IslandModule {
    static let descriptor = ModuleDescriptor(id: "t5", name: "T5", summary: "", symbol: "timer", content: .neutral, widgetMinWidth: 60)
    var liveActivity: LiveActivity? { nil }
}
@MainActor @Observable private final class Tab6: TabModuleBase, IslandModule {
    static let descriptor = ModuleDescriptor(id: "t6", name: "T6", summary: "", symbol: "note.text", content: .neutral, widgetMinWidth: 60)
    var liveActivity: LiveActivity? { nil }
}
@MainActor @Observable private final class Tab7: TabModuleBase, IslandModule {
    static let descriptor = ModuleDescriptor(id: "t7", name: "T7", summary: "", symbol: "doc.on.clipboard", content: .neutral, widgetMinWidth: 60)
    var liveActivity: LiveActivity? { nil }
}
@MainActor @Observable private final class Tab8: TabModuleBase, IslandModule {
    static let descriptor = ModuleDescriptor(id: "t8", name: "T8", summary: "", symbol: "square.stack.3d.up", content: .neutral, widgetMinWidth: 60)
    var liveActivity: LiveActivity? { nil }
}
@MainActor @Observable private final class Tab9: TabModuleBase, IslandModule {
    static let descriptor = ModuleDescriptor(id: "t9", name: "T9", summary: "", symbol: "camera", content: .neutral, widgetMinWidth: 60)
    var liveActivity: LiveActivity? { nil }
}

@MainActor @Observable private final class Tab10: TabModuleBase, IslandModule {
    static let descriptor = ModuleDescriptor(id: "t10", name: "T10", summary: "", symbol: "checklist", content: .neutral, widgetMinWidth: 60)
    var liveActivity: LiveActivity? { nil }
}
@MainActor @Observable private final class Tab11: TabModuleBase, IslandModule {
    static let descriptor = ModuleDescriptor(id: "t11", name: "T11", summary: "", symbol: "headphones", content: .neutral, widgetMinWidth: 60)
    var liveActivity: LiveActivity? { nil }
}

@MainActor
private let allTabModules: [any IslandModule.Type] = [
    Tab0.self, Tab1.self, Tab2.self, Tab3.self, Tab4.self, Tab5.self, Tab6.self, Tab7.self, Tab8.self, Tab9.self,
    Tab10.self, Tab11.self,
]

@MainActor
@Suite("Wyspa nie wycieka poza swój kształt", .serialized)
struct IslandOverflowTests {
    nonisolated static let shadowMargin: CGFloat = 36
    nonisolated static let notch = NotchMetrics(size: CGSize(width: 200, height: 38), isPhysical: true)

    enum Layout: Sendable {
        /// N pełnych stron (sprawdza pasek stron w nagłówku).
        case fullPages(Int)
        /// Jedna strona z N widżetami po równo (sprawdza wiersz widżetów).
        case widgets(Int)

        var moduleCount: Int {
            switch self {
            case .fullPages(let count), .widgets(let count): count
            }
        }

        var label: String {
            switch self {
            case .fullPages(let count): "strony:\(count)"
            case .widgets(let count): "widżety:\(count)"
            }
        }
    }

    struct Case: CustomTestStringConvertible, Sendable {
        let phase: IslandPhase
        let size: IslandSize
        let layout: Layout
        let wing: CGFloat?
        var detail: CGFloat? = nil
        var testDescription: String {
            "\(phase) \(size) \(layout.label) skrzydło:\(wing.map { "\(Int($0))" } ?? "brak")"
                + (detail.map { " karta:\(Int($0))" } ?? "")
        }
    }

    nonisolated static let cases: [Case] = {
        var result: [Case] = []
        let layouts: [Layout] = [.fullPages(0), .fullPages(1), .fullPages(4), .fullPages(12),
                                 .widgets(1), .widgets(2), .widgets(3), .widgets(4)]
        for phase in [IslandPhase.collapsed, .expanded] {
            for size in IslandSize.allCases {
                for layout in layouts {
                    for wing in [nil, IslandLayout.wingWidth, 70, IslandLayout.maxWingWidth] as [CGFloat?] {
                        result.append(Case(phase: phase, size: size, layout: layout, wing: wing))
                    }
                }
            }
        }
        // Karta pod notchem (zwinięta wyspa i najechanie), także o wysokości ponad limit.
        for phase in [IslandPhase.collapsed, .peek] {
            for size in IslandSize.allCases {
                for wing in [IslandLayout.wingWidth, IslandLayout.maxWingWidth] {
                    for detail in [20, 72, IslandLayout.maxDetailHeight, 300] as [CGFloat] {
                        result.append(Case(phase: phase, size: size, layout: .fullPages(1), wing: wing, detail: detail))
                    }
                }
            }
        }
        return result
    }()

    @Test("Żaden jasny piksel poza kształtem wyspy", arguments: cases)
    func noContentOutsideIsland(_ scenario: Case) async throws {
        Scenario.activityWing = scenario.wing
        Scenario.detailHeight = scenario.detail
        let defaults = UserDefaults(suiteName: "overflow.\(UUID())")!
        let catalog = Array(allTabModules.prefix(max(scenario.layout.moduleCount, 1)))
        let registry = ModuleRegistry(catalog: catalog, settings: SettingsStore(defaults: defaults),
                                      permissions: AllGranted(), requestExpand: { _ in })
        for type in catalog { await registry.setEnabled(type.descriptor.id, true) }
        let ids = catalog.map { $0.descriptor.id }
        switch scenario.layout {
        case .fullPages(let count):
            var board = IslandBoard()
            for id in ids.prefix(count) { board = board.addingModulePage(id) }
            registry.setBoard(board)
        case .widgets(let count):
            let (empty, page) = IslandBoard().addingWidgetPage()
            var board = empty
            // Wszystkie moduły testowe znoszą ćwiartkę wyspy.
            let minimum: IslandBoard.Minimum = { _ in WidgetWidth(units: 20) }
            for id in ids.prefix(count) {
                board = try board.inserting(moduleID: id, intoPage: page, at: .max, minimum: minimum)
            }
            registry.setBoard(board)
        }

        let model = IslandViewModel(phase: scenario.phase, notch: Self.notch, expandedSize: scenario.size.expandedSize,
                                    registry: registry)
        let leaks = try await leakCount(of: model, name: scenario.testDescription)
        #expect(leaks == 0, "\(leaks) jasnych pikseli poza wyspą")
    }

    @Test("Motywy ze szkłem (Szkło, Przezroczysty z Liquid Glass) renderują się bez treści poza wyspą",
          arguments: [IslandTheme.glass, .clear])
    func glassThemes(theme: IslandTheme) async throws {
        Scenario.activityWing = IslandLayout.wingWidth
        Scenario.detailHeight = nil
        let defaults = UserDefaults(suiteName: "overflow.\(UUID())")!
        let catalog = Array(allTabModules.prefix(2))
        let registry = ModuleRegistry(catalog: catalog, settings: SettingsStore(defaults: defaults),
                                      permissions: AllGranted(), requestExpand: { _ in })
        for type in catalog { await registry.setEnabled(type.descriptor.id, true) }
        let model = IslandViewModel(phase: .expanded, notch: Self.notch, expandedSize: IslandSize.medium.expandedSize,
                                    registry: registry)
        model.theme = theme
        let leaks = try await leakCount(of: model, name: "motyw-\(theme.rawValue)")
        #expect(leaks == 0, "\(leaks) jasnych pikseli poza wyspą")
    }

    /// Renderuje wyspę poza ekranem w ramie panelu i liczy jasne piksele poza prostokątem wyspy.
    private func leakCount(of model: IslandViewModel, name: String) async throws -> Int {
        let panel = IslandLayout.panelSize(expanded: model.expandedSize, notch: Self.notch.size, shadowMargin: Self.shadowMargin)
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
            let file = name.replacingOccurrences(of: " ", with: "_").replacingOccurrences(of: ":", with: "-")
            try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(file).png"))
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
        return leaks
    }
}
