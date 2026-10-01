import AppKit
import Quartz

/// Podgląd Quick Look dla elementów półki.
///
/// Panel wyspy nie może być oknem kluczowym, więc źródło danych ustawiamy bezpośrednio na panelu podglądu.
@MainActor
final class QuickLook: NSObject, QLPreviewPanelDataSource {
    static let shared = QuickLook()

    private var urls: [URL] = []

    func show(_ urls: [URL]) {
        guard !urls.isEmpty, let panel = QLPreviewPanel.shared() else { return }
        self.urls = urls
        NSApp.activate()
        panel.dataSource = self
        panel.reloadData()
        panel.currentPreviewItemIndex = 0
        panel.makeKeyAndOrderFront(nil)
    }

    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        MainActor.assumeIsolated { urls.count }
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        MainActor.assumeIsolated { urls[index] as NSURL }
    }
}
