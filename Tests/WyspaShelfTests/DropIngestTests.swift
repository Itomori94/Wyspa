import AppKit
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

@Suite("Wczytywanie upuszczonych elementów (prawdziwe NSItemProvider)")
@MainActor
struct DropIngestLoadingTests {
    private func temporaryFile(_ name: String, contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("wyspa-ingest-\(UUID().uuidString)-\(name)")
        try Data(contents.utf8).write(to: url)
        return url
    }

    @Test("Plik z Findera trafia jako odnośnik do pliku")
    func fileURL() async throws {
        let url = try temporaryFile("notatka.txt", contents: "x")
        defer { try? FileManager.default.removeItem(at: url) }
        let items = await DropIngest.load([NSItemProvider(contentsOf: url)!])
        #expect(items == [.file(url)])
    }

    @Test("Tekst i link: plik .txt i .webloc z sensowną nazwą")
    func textAndLink() async throws {
        let text = NSItemProvider(object: "Lista zakupów" as NSString)
        let link = NSItemProvider(object: URL(string: "https://example.com/strona")! as NSURL)
        let items = await DropIngest.load([text, link])
        #expect(items.count == 2)
        guard case .data(let textData, let textName) = items[0], case .data(let linkData, let linkName) = items[1] else {
            Issue.record("oczekiwano danych")
            return
        }
        #expect(String(decoding: textData, as: UTF8.self) == "Lista zakupów" && textName == "Tekst.txt")
        #expect(linkName == "example.com.webloc")
        let plist = try PropertyListSerialization.propertyList(from: linkData, format: nil) as? [String: String]
        #expect(plist?["URL"] == "https://example.com/strona")
    }

    @Test("Obraz jako dane PNG, nieobsługiwany typ pominięty, kolejność zachowana")
    func imageAndUnsupported() async throws {
        let image = NSImage(size: NSSize(width: 4, height: 4))
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 4, height: 4).fill()
        image.unlockFocus()
        let tiff = try #require(image.tiffRepresentation)
        let png = try #require(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
        let imageProvider = NSItemProvider(item: png as NSData, typeIdentifier: UTType.png.identifier)
        imageProvider.suggestedName = "kropka"
        let unknown = NSItemProvider(item: Data([1, 2, 3]) as NSData, typeIdentifier: "com.example.nieznany")
        let items = await DropIngest.load([unknown, imageProvider])
        #expect(items == [.data(png, suggestedName: "kropka.png")])
    }

    @Test("Inny plik (np. PDF) kopiowany od razu do pliku tymczasowego")
    func fileRepresentation() async throws {
        let source = try temporaryFile("raport.pdf", contents: "%PDF-1.4 test")
        defer { try? FileManager.default.removeItem(at: source) }
        let provider = NSItemProvider()
        provider.registerFileRepresentation(forTypeIdentifier: UTType.pdf.identifier, fileOptions: [], visibility: .all) { completion in
            completion(source, false, nil)
            return nil
        }
        provider.suggestedName = "raport.pdf"
        let items = await DropIngest.load([provider])
        guard case .temporaryFile(let copy, let name)? = items.first else {
            Issue.record("oczekiwano kopii pliku")
            return
        }
        defer { try? FileManager.default.removeItem(at: copy) }
        #expect(name == "raport.pdf" && copy != source)
        #expect(try Data(contentsOf: copy) == Data("%PDF-1.4 test".utf8))
    }
}
