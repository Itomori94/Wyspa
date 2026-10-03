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

        // Folder: zwykła ikona. Quick Look potrafi przeglądać zawartość dużego folderu (albo pakietu) przy każdym pokazaniu.
        if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
           (try? url.resourceValues(forKeys: [.isPackageKey]).isPackage) != true {
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

    private func store(_ image: NSImage, for key: String) {
        cache[key] = image
        order.append(key)
        if order.count > Self.limit {
            let evicted = order.removeFirst()
            cache[evicted] = nil
        }
    }
}
