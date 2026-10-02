import Foundation
import Testing
@testable import WyspaNotes

@Suite("Notatka")
struct NoteStoreTests {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("wyspa-notes-\(UUID().uuidString)/a/notatka.md")

    @Test("Brak pliku to pusta notatka")
    func missing() throws {
        #expect(try NoteStore(fileURL: url).load() == "")
    }

    @Test("Zapis tworzy katalogi i zachowuje polskie znaki")
    func roundTrip() throws {
        let store = NoteStore(fileURL: url)
        try store.save("Zażółć gęślą jaźń\n– punkt 1")
        #expect(try store.load() == "Zażółć gęślą jaźń\n– punkt 1")
    }

    @Test("Nieczytelny plik zgłasza błąd zamiast udawać pustą notatkę")
    func unreadable() throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([0xFF, 0xFE, 0x00, 0xD8]).write(to: url)
        #expect(throws: (any Error).self) { try NoteStore(fileURL: url).load() }
    }
}
