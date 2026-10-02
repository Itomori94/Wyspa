import Testing
@testable import WyspaClaudeMonitor

@Suite("Podgląd ostatniej odpowiedzi Claude")
struct MessagePreviewTests {
    @Test("Markdown, kod i linki znikają, białe znaki zwinięte")
    func plain() {
        let text = "## Gotowe\n\n**Naprawione** i `zainstalowane`:\n- punkt [link](https://x.pl)\n```swift\nlet a = 1\n```\nKoniec."
        #expect(MessagePreview.make(text) == "Gotowe Naprawione i zainstalowane: punkt link Koniec.")
    }

    @Test("Długi tekst skracany z wielokropkiem, pusty — brak podglądu")
    func limits() {
        let long = String(repeating: "słowo ", count: 100)
        let preview = MessagePreview.make(long)
        #expect(preview?.count ?? 0 <= MessagePreview.limit && preview?.hasSuffix("…") == true)
        #expect(MessagePreview.make("   \n ") == nil && MessagePreview.make(nil) == nil)
    }
}
