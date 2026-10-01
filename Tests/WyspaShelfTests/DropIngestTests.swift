import Foundation
import Testing
import UniformTypeIdentifiers
@testable import WyspaShelf

@Suite("Wybór sposobu wczytania upuszczonego elementu")
struct IngestPlanTests {
    @Test("Plik z Findera ma pierwszeństwo")
    func fileURL() {
        #expect(IngestPlan.choose(for: [UTType.fileURL.identifier, UTType.png.identifier]) == .fileURL)
    }

    @Test("Obraz z przeglądarki: dane obrazu zamiast linku")
    func image() {
        let plan = IngestPlan.choose(for: [UTType.url.identifier, UTType.jpeg.identifier])
        #expect(plan == .image(typeIdentifier: UTType.jpeg.identifier))
    }

    @Test("Link i tekst")
    func linkAndText() {
        #expect(IngestPlan.choose(for: [UTType.url.identifier, UTType.plainText.identifier]) == .webLink)
        #expect(IngestPlan.choose(for: [UTType.utf8PlainText.identifier]) == .text)
    }

    @Test("Inne dane jako plik, nieznane typy pomijane")
    func dataAndUnknown() {
        #expect(IngestPlan.choose(for: [UTType.pdf.identifier]) == .fileRepresentation(typeIdentifier: UTType.pdf.identifier))
        #expect(IngestPlan.choose(for: ["dyn.nieznany-typ"]) == .unsupported)
    }

    @Test("Nazwa pliku dostaje rozszerzenie tylko raz")
    func fileName() {
        #expect(DropIngest.fileName("zdjęcie", fallback: "Obraz", extension: "png") == "zdjęcie.png")
        #expect(DropIngest.fileName("zdjęcie.PNG", fallback: "Obraz", extension: "png") == "zdjęcie.PNG")
        #expect(DropIngest.fileName(nil, fallback: "Obraz", extension: "png") == "Obraz.png")
    }

    @Test("Plik .webloc tylko dla http(s)")
    func webloc() throws {
        let data = try #require(WebLocation.data(for: URL(string: "https://example.com/a")!))
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String]
        #expect(plist?["URL"] == "https://example.com/a")
        #expect(WebLocation.data(for: URL(string: "file:///etc/passwd")!) == nil)
    }
}
