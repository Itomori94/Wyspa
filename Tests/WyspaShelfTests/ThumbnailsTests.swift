import Foundation
import Testing
@testable import WyspaShelf

@Suite("Miniatury na Półce")
struct ThumbnailsTests {
    @Test("Folder dostaje zwykłą ikonę (bez Quick Look), zwykły plik lokalny — miniaturę")
    func plainIconForFolders() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("wyspa-thumbs-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("notatka.txt")
        try Data("a".utf8).write(to: file)
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isPackageKey, .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]
        #expect(Thumbnails.needsPlainIcon(try directory.resourceValues(forKeys: keys)))
        #expect(!Thumbnails.needsPlainIcon(try file.resourceValues(forKeys: keys)))
        #expect(!Thumbnails.needsPlainIcon(nil))
    }
}
