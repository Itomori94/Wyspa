import CoreGraphics
import Testing
@testable import WyspaCore

@Suite("Geometria notcha")
struct NotchMetricsTests {
    @Test("Fizyczny notch: szerokość to ekran minus obszary pomocnicze")
    func physicalNotch() {
        let metrics = NotchMetrics.resolve(
            screenWidth: 1512, safeAreaTop: 38, leftAuxWidth: 662, rightAuxWidth: 665, menuBarHeight: 38
        )
        #expect(metrics == NotchMetrics(size: CGSize(width: 185, height: 38), isPhysical: true))
    }

    @Test("Ekran bez notcha dostaje wirtualny notch o wysokości paska menu")
    func virtualNotch() {
        let metrics = NotchMetrics.resolve(
            screenWidth: 2560, safeAreaTop: 0, leftAuxWidth: nil, rightAuxWidth: nil, menuBarHeight: 25
        )
        #expect(metrics == NotchMetrics(size: CGSize(width: NotchMetrics.virtualWidth, height: 25), isPhysical: false))
    }

    @Test("Ukryty pasek menu: wirtualny notch używa wysokości zapasowej")
    func hiddenMenuBar() {
        let metrics = NotchMetrics.resolve(
            screenWidth: 1920, safeAreaTop: 0, leftAuxWidth: nil, rightAuxWidth: nil, menuBarHeight: 0
        )
        #expect(metrics.size.height == NotchMetrics.fallbackMenuBarHeight)
    }

    @Test("Niespójne dane safe area nie dają ujemnej szerokości")
    func inconsistentAuxAreas() {
        let metrics = NotchMetrics.resolve(
            screenWidth: 1000, safeAreaTop: 32, leftAuxWidth: 600, rightAuxWidth: 600, menuBarHeight: 32
        )
        #expect(metrics.isPhysical == false)
    }

    @Test("Wyśrodkowanie przy górnej krawędzi ekranu z przesunięciem (drugi monitor)")
    func topCentered() {
        let frame = CGRect(x: 1512, y: 200, width: 2560, height: 1440)
        let rect = IslandPlacement.topCentered(CGSize(width: 200, height: 32), in: frame)
        #expect(rect == CGRect(x: 2692, y: 1608, width: 200, height: 32))
    }
}

@Suite("Wymiary wyspy")
struct IslandLayoutTests {
    let notch = CGSize(width: 185, height: 38)
    let expanded = IslandSize.medium.expandedSize

    @Test("Zwinięta bez aktywności obejmuje notch i wklęsłe rogi")
    func collapsedWithoutActivity() {
        let size = IslandLayout.size(for: .collapsed, notch: notch, activityWingWidth: nil, expanded: expanded)
        #expect(size == CGSize(width: 185 + 2 * IslandLayout.collapsedTopRadius, height: 38))
    }

    @Test("Aktywność dodaje dwa skrzydła")
    func collapsedWithActivity() {
        let without = IslandLayout.size(for: .collapsed, notch: notch, activityWingWidth: nil, expanded: expanded)
        let with = IslandLayout.size(for: .collapsed, notch: notch, activityWingWidth: IslandLayout.wingWidth, expanded: expanded)
        #expect(with.width - without.width == IslandLayout.wingWidth * 2)
    }

    @Test("Szersze skrzydła aktywności poszerzają wyspę")
    func wideWings() {
        let narrow = IslandLayout.size(for: .collapsed, notch: notch, activityWingWidth: 40, expanded: expanded)
        let wide = IslandLayout.size(for: .collapsed, notch: notch, activityWingWidth: 70, expanded: expanded)
        #expect(wide.width - narrow.width == 60)
    }

    @Test("Podgląd jest nieco większy od stanu zwiniętego")
    func peekGrows() {
        let collapsed = IslandLayout.size(for: .collapsed, notch: notch, activityWingWidth: nil, expanded: expanded)
        let peek = IslandLayout.size(for: .peek, notch: notch, activityWingWidth: nil, expanded: expanded)
        #expect(peek.width > collapsed.width && peek.height > collapsed.height)
    }

    @Test("Rozwinięta nigdy nie jest węższa od zwiniętej")
    func expandedAtLeastCollapsed() {
        let wideNotch = CGSize(width: 600, height: 40)
        let size = IslandLayout.size(for: .expanded, notch: wideNotch, activityWingWidth: IslandLayout.wingWidth, expanded: IslandSize.small.expandedSize)
        #expect(size.width >= 600 + IslandLayout.wingWidth * 2)
    }

    @Test("Ukryta to cienki pas o szerokości notcha")
    func hidden() {
        let size = IslandLayout.size(for: .hidden, notch: notch, activityWingWidth: nil, expanded: expanded)
        #expect(size == CGSize(width: 185, height: IslandLayout.hiddenHotZoneHeight))
    }

    @Test("Panel mieści rozwiniętą wyspę z marginesem na cień")
    func panelSize() {
        let size = IslandLayout.panelSize(expanded: CGSize(width: 600, height: 230), shadowMargin: 30)
        #expect(size == CGSize(width: 660, height: 260))
    }
}

@Suite("Wybór ekranów")
struct ScreenSelectionTests {
    let builtIn = ScreenInfo(
        id: 1, name: "Wbudowany", frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        notch: NotchMetrics(size: CGSize(width: 185, height: 38), isPhysical: true), isMain: false
    )
    let external = ScreenInfo(
        id: 2, name: "Zewnętrzny", frame: CGRect(x: 1512, y: 0, width: 2560, height: 1440),
        notch: NotchMetrics(size: CGSize(width: 190, height: 25), isPhysical: false), isMain: true
    )

    @Test func allScreens() {
        #expect(ScreenSelection.all.select(from: [builtIn, external]).map(\.id) == [1, 2])
    }

    @Test func notchedOnly() {
        #expect(ScreenSelection.notched.select(from: [builtIn, external]).map(\.id) == [1])
    }

    @Test("Brak ekranu z notchem: wybór przechodzi na ekran główny")
    func notchedFallsBackToMain() {
        #expect(ScreenSelection.notched.select(from: [external]).map(\.id) == [2])
    }

    @Test func mainOnly() {
        #expect(ScreenSelection.main.select(from: [builtIn, external]).map(\.id) == [2])
    }

    @Test("Brak ekranów nie powoduje błędu")
    func empty() {
        for selection in ScreenSelection.allCases {
            #expect(selection.select(from: []).isEmpty)
        }
    }
}
