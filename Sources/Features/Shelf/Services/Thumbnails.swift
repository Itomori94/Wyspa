import AppKit
import QuickLookThumbnailing

/// Miniatury Quick Look z pamięcią podręczną; ikona pliku, gdy miniatura nie powstanie.
@MainActor
final class Thumbnails {
    static let shared = Thumbnails()
    private static let limit = 200

    private var cache: [String: NSImage] = [:]
    private var order: [String] = []

    func thumbnail(for url: URL, side: CGFloat) async -> NSImage {
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)?
            .timeIntervalSince1970 ?? 0
        let key = "\(url.path)|\(modified)|\(side)"
        if let cached = cache[key] { return cached }

        // Zwykła ikona zamiast Quick Look dla folderu (Quick Look potrafi przeglądać jego zawartość) i dla elementu
        // iCloud, który nie jest pobrany (np. Biurko w iCloud z „Optymalizuj miejsce”): miniatura wymusiłaby pobranie.
        if Self.needsPlainIcon(try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey, .isUbiquitousItemKey,
                                                                .ubiquitousItemDownloadingStatusKey])) {
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            store(icon, for: key)
            return icon
        }
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let request = QLThumbnailGenerator.Request(
            fileAt: url, size: CGSize(width: side, height: side), scale: scale, representationTypes: .all
        )
        let image: NSImage
        if let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
            image = representation.nsImage
        } else {
            image = NSWorkspace.shared.icon(forFile: url.path)
        }
        store(image, for: key)
        return image
    }

    /// Czysta decyzja (testy): folder, który nie jest pakietem, albo element iCloud bez pobranej aktualnej wersji.
    nonisolated static func needsPlainIcon(_ values: URLResourceValues?) -> Bool {
        guard let values else { return false }
        if values.isDirectory == true && values.isPackage != true { return true }
        if values.isUbiquitousItem == true, values.ubiquitousItemDownloadingStatus != .current { return true }
        return false
    }

    private func store(_ image: NSImage, for key: String) {
        cache[key] = image
        order.append(key)
        if order.count > Self.limit {
            let evicted = order.removeFirst()
            cache[evicted] = nil
        }
    }
}
