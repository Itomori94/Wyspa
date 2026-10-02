import CoreGraphics
import Testing
@testable import WyspaCore

@Suite("Plan paska zakładek")
struct TabStripPlanTests {
    @Test("Wszystkie zakładki ze skrzydłem, gdy jest miejsce")
    func allFit() {
        let plan = TabStripPlan.make(tabCount: 4, selected: 0, available: 200, wingWidth: 40)
        #expect(plan.style == .regular && plan.visible == [0, 1, 2, 3] && plan.overflow.isEmpty && plan.showsWing)
    }

    @Test("Najpierw kompaktowy styl, potem rezygnacja ze skrzydła")
    func degradeOrder() {
        // regular: 4×26+3×4 = 116; compact: 4×22+3×2 = 94
        #expect(TabStripPlan.make(tabCount: 4, selected: 0, available: 150, wingWidth: 40) ==
            TabStripPlan(style: .compact, visible: [0, 1, 2, 3], overflow: [], showsWing: true))
        #expect(TabStripPlan.make(tabCount: 4, selected: 0, available: 126, wingWidth: 40) ==
            TabStripPlan(style: .regular, visible: [0, 1, 2, 3], overflow: [], showsWing: false))
        #expect(TabStripPlan.make(tabCount: 4, selected: 0, available: 100, wingWidth: 70) ==
            TabStripPlan(style: .compact, visible: [0, 1, 2, 3], overflow: [], showsWing: false))
    }

    @Test("Za dużo zakładek: menu „⋯” zamiast przewijania, wszystko mieści się w dostępnej szerokości")
    func overflow() {
        let plan = TabStripPlan.make(tabCount: 11, selected: 0, available: 126, wingWidth: 40)
        #expect(!plan.overflow.isEmpty && !plan.showsWing)
        #expect(Set(plan.visible + plan.overflow) == Set(0..<11))
        let used = TabStripPlan.stripWidth(count: plan.visible.count, style: plan.style)
            + plan.style.spacing + TabStripPlan.overflowButtonWidth
        #expect(used <= 126)
    }

    @Test("Wybrana zakładka z menu jest zawsze widoczna w pasku")
    func selectedVisible() {
        let plan = TabStripPlan.make(tabCount: 11, selected: 9, available: 126, wingWidth: nil)
        #expect(plan.visible.contains(9))
        #expect(!plan.overflow.contains(9))
        #expect(plan.visible.count == Set(plan.visible).count)
    }

    @Test("Każda kombinacja mieści się w dostępnej szerokości", arguments: [60.0, 90.0, 126.0, 160.0, 220.0])
    func alwaysFits(available: Double) {
        for count in 2...12 {
            for wing in [nil, 40.0, 70.0] as [CGFloat?] {
                let plan = TabStripPlan.make(tabCount: count, selected: count - 1, available: available, wingWidth: wing)
                var width = TabStripPlan.stripWidth(count: plan.visible.count, style: plan.style)
                if !plan.overflow.isEmpty { width += plan.style.spacing + TabStripPlan.overflowButtonWidth }
                if plan.showsWing, let wing { width += TabStripPlan.wingSpacing + wing }
                // Minimum to jedna zakładka z menu — w skrajnie wąskiej wyspie mieści się przycięta przez kształt.
                if plan.visible.count > 1 || plan.overflow.isEmpty { #expect(width <= available, "\(count) \(String(describing: wing))") }
                #expect(Set(plan.visible + plan.overflow) == Set(0..<count))
            }
        }
    }

    @Test("Jedna zakładka: bez paska, skrzydło jeśli się mieści")
    func single() {
        #expect(TabStripPlan.make(tabCount: 1, selected: 0, available: 100, wingWidth: 40) ==
            TabStripPlan(style: .regular, visible: [], overflow: [], showsWing: true))
    }

    @Test("Szerokość połowy nagłówka")
    func headerSide() {
        // mała wyspa 520: wnętrze 520 − 2×(14+20) = 452; minus notch 200 → 126 na połowę
        #expect(IslandLayout.headerSideWidth(islandWidth: 520, notchGap: 200) == 126)
        #expect(IslandLayout.headerSideWidth(islandWidth: 100, notchGap: 200) == 0)
    }

    @Test("Pojemność paska zgodna z szerokością paska")
    func capacity() {
        #expect(TabStripPlan.capacity(available: 126, style: .regular) == 4)   // 4×26+3×4 = 116 ≤ 126 < 146
        #expect(TabStripPlan.capacity(available: 20, style: .regular) == 0)
        for available in stride(from: 26.0, to: 300.0, by: 7.0) {
            let n = TabStripPlan.capacity(available: available, style: .compact)
            #expect(TabStripPlan.stripWidth(count: n, style: .compact) <= available)
            #expect(TabStripPlan.stripWidth(count: n + 1, style: .compact) > available)
        }
    }
}
