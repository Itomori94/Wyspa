import CoreGraphics
import Testing
@testable import WyspaMedia

@Suite("Wymiary dużego odtwarzacza")
struct PlayerMetricsTests {
    @Test("Na całej stronie pełne wymiary")
    func full() {
        #expect(PlayerMetrics.forWidth(532) == .full)
        #expect(PlayerMetrics.forWidth(340) == .full)
    }

    @Test("Widżet obok drugiego (połowa średniej wyspy) dostaje ten sam odtwarzacz, ciaśniej")
    func half() throws {
        let metrics = try #require(PlayerMetrics.forWidth(260))
        #expect(metrics.artworkSize == 78 && metrics.controlSpacing < PlayerMetrics.full.controlSpacing)
    }

    @Test("Za wąsko na duży odtwarzacz: wersja kompaktowa")
    func tooNarrow() {
        #expect(PlayerMetrics.forWidth(229) == nil)
        #expect(PlayerMetrics.forWidth(150) == nil)
    }
}
