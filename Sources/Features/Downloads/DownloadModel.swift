import Foundation

/// Trwające pobieranie widziane przez postęp publikowany przez przeglądarkę (Safari, Chrome, Firefox).
public struct DownloadItem: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let fileURL: URL
    public let fraction: Double?

    public init(id: UUID, fileURL: URL, fraction: Double?) {
        self.id = id
        self.fileURL = fileURL
        self.fraction = fraction
    }

    /// Nazwa pliku bez tymczasowej końcówki przeglądarki.
    public var displayName: String { DownloadNaming.finalURL(for: fileURL).lastPathComponent }
}

public enum DownloadNaming {
    /// Końcówki plików w trakcie pobierania: Safari, Chrome, Firefox.
    static let partialExtensions: Set<String> = ["download", "crdownload", "part"]

    /// Docelowy plik po zakończeniu (bez końcówki tymczasowej).
    public static func finalURL(for url: URL) -> URL {
        partialExtensions.contains(url.pathExtension.lowercased()) ? url.deletingPathExtension() : url
    }
}

public enum DownloadSummary {
    /// Łączny postęp kilku pobierań; `nil`, gdy żadne nie zna rozmiaru.
    public static func fraction(of items: [DownloadItem]) -> Double? {
        let known = items.compactMap(\.fraction)
        guard !known.isEmpty else { return nil }
        return min(max(known.reduce(0, +) / Double(known.count), 0), 1)
    }

    public static func percentText(_ fraction: Double?) -> String {
        fraction.map { "\(Int(($0 * 100).rounded(.down)))%" } ?? "…"
    }

    /// Postęp zaokrąglony do pełnego procenta — wyspa odświeża się najwyżej sto razy na pobranie.
    public static func quantized(_ fraction: Double) -> Double {
        (min(max(fraction, 0), 1) * 100).rounded(.down) / 100
    }
}
