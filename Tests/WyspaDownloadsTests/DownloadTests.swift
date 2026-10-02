import Foundation
import Testing
@testable import WyspaDownloads

@Suite("Pobierania")
struct DownloadTests {
    private func item(_ name: String, _ fraction: Double?) -> DownloadItem {
        DownloadItem(id: UUID(), fileURL: URL(fileURLWithPath: "/Users/x/Downloads/\(name)"), fraction: fraction)
    }

    @Test("Nazwa pliku bez końcówki przeglądarki")
    func names() {
        #expect(item("film.mp4.crdownload", 0.5).displayName == "film.mp4")
        #expect(item("raport.pdf.download", nil).displayName == "raport.pdf")
        #expect(item("obraz.iso.part", nil).displayName == "obraz.iso")
        #expect(item("zwykly.zip", nil).displayName == "zwykly.zip")
    }

    @Test("Łączny postęp i zaokrąglanie")
    func summary() {
        #expect(DownloadSummary.fraction(of: [item("a", 0.2), item("b", 0.6), item("c", nil)]) == 0.4)
        #expect(DownloadSummary.fraction(of: [item("a", nil)]) == nil)
        #expect(DownloadSummary.quantized(0.4567) == 0.45 && DownloadSummary.quantized(1.7) == 1)
    }
}
