import Foundation
import Testing
@testable import WyspaShelf

@MainActor
@Suite("Magazyn półki")
struct ShelfStoreTests {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("wyspa-shelf-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    private var storeDirectory: URL { root.appendingPathComponent("Shelf") }

    private func makeFile(_ name: String, contents: String = "x") throws -> URL {
        let url = root.appendingPathComponent(name)
        try Data(contents.utf8).write(to: url)
        return url
    }

    @Test("Dodane pliki przetrwają ponowne otwarcie magazynu")
    func persistence() throws {
        let file = try makeFile("raport.pdf")
        let store = try ShelfStore(directory: storeDirectory)
        try store.addFiles([file])

        let reopened = try ShelfStore(directory: storeDirectory)
        #expect(reopened.items.map(\.name) == ["raport.pdf"])
        #expect(reopened.url(for: reopened.items[0])?.standardizedFileURL == file.standardizedFileURL)
    }

    @Test("Ten sam plik nie trafia na półkę dwa razy")
    func deduplicates() throws {
        let file = try makeFile("a.txt")
        let store = try ShelfStore(directory: storeDirectory)
        try store.addFiles([file, file])
        try store.addFiles([file])
        #expect(store.items.count == 1)
    }

    @Test("Bookmark znajduje przeniesiony oryginał")
    func followsMovedFile() throws {
        let file = try makeFile("przenoszony.txt")
        let store = try ShelfStore(directory: storeDirectory)
        try store.addFiles([file])
        let moved = root.appendingPathComponent("nowe-miejsce.txt")
        try FileManager.default.moveItem(at: file, to: moved)
        #expect(store.url(for: store.items[0])?.lastPathComponent == "nowe-miejsce.txt")
    }

    @Test("Usunięty oryginał: element zostaje, ale nie ma adresu")
    func missingOriginal() throws {
        let file = try makeFile("znika.txt")
        let store = try ShelfStore(directory: storeDirectory)
        try store.addFiles([file])
        try FileManager.default.removeItem(at: file)
        #expect(store.items.count == 1)
        #expect(store.url(for: store.items[0]) == nil)
    }

    @Test("Treść bez pliku jest kopiowana, a usunięcie kasuje kopię")
    func storedData() throws {
        let store = try ShelfStore(directory: storeDirectory)
        let item = try store.addData(Data("obraz".utf8), suggestedName: "Zdjęcie.png")
        let url = try #require(store.url(for: item))
        #expect(try Data(contentsOf: url) == Data("obraz".utf8))
        #expect(item.isStoredCopy)

        try store.remove([item.id])
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(store.items.isEmpty)
    }

    @Test("Usunięcie odnośnika nie rusza oryginału użytkownika")
    func removeKeepsOriginal() throws {
        let file = try makeFile("ważne.txt")
        let store = try ShelfStore(directory: storeDirectory)
        try store.addFiles([file])
        try store.removeAll()
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test("Kopia pliku tymczasowego")
    func copyTemporary() throws {
        let temp = try makeFile("obietnica.bin", contents: "dane")
        let store = try ShelfStore(directory: storeDirectory)
        let item = try store.addCopy(of: temp)
        try FileManager.default.removeItem(at: temp)
        #expect(store.url(for: item) != nil)
    }

    @Test("Uszkodzony indeks: pusta półka zamiast awarii")
    func corruptedIndex() throws {
        try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
        try Data("{nie json".utf8).write(to: storeDirectory.appendingPathComponent(ShelfStore.indexFileName))
        #expect(try ShelfStore(directory: storeDirectory).items.isEmpty)
    }

    @Test("Nazwy plików są oczyszczane z separatorów ścieżki")
    func sanitizedNames() {
        #expect(ShelfStore.sanitizedFileName("../../etc/passwd") == "-..-etc-passwd")
        #expect(ShelfStore.sanitizedFileName("a/b:c") == "a-b-c")
        #expect(ShelfStore.sanitizedFileName("   ") == "Element")
        #expect(ShelfStore.sanitizedFileName("...") == "Element")
    }

    @Test("Złośliwa nazwa nie wychodzi poza katalog półki")
    func pathTraversal() throws {
        let store = try ShelfStore(directory: storeDirectory)
        let item = try store.addData(Data("x".utf8), suggestedName: "../../ucieczka.txt")
        let url = try #require(store.url(for: item))
        #expect(url.standardizedFileURL.path.hasPrefix(storeDirectory.standardizedFileURL.path))
    }
}
