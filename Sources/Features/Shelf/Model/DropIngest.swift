import Foundation
import UniformTypeIdentifiers
import WyspaCore

/// Upuszczona treść po wczytaniu z `NSItemProvider`.
public enum IngestedItem: Sendable, Equatable {
    case file(URL)
    case data(Data, suggestedName: String)
    /// Plik tymczasowy (np. spełniona obietnica pliku) — trzeba go skopiować, zanim system go usunie.
    case temporaryFile(URL, suggestedName: String)
}

/// Sposób wczytania jednego dostawcy, wybierany po zarejestrowanych typach (od najbogatszego).
public enum IngestPlan: Equatable, Sendable {
    case fileURL
    case image(typeIdentifier: String)
    case fileRepresentation(typeIdentifier: String)
    case webLink
    case text
    case unsupported

    public static func choose(for typeIdentifiers: [String]) -> IngestPlan {
        let types = typeIdentifiers.compactMap(UTType.init)
        if types.contains(.fileURL) { return .fileURL }
        if let image = types.first(where: { $0.conforms(to: .image) }) { return .image(typeIdentifier: image.identifier) }
        if types.contains(where: { $0.conforms(to: .url) }) { return .webLink }
        if types.contains(where: { $0.conforms(to: .plainText) }) { return .text }
        if let data = types.first(where: { $0.conforms(to: .data) && !$0.conforms(to: .text) }) {
            return .fileRepresentation(typeIdentifier: data.identifier)
        }
        return .unsupported
    }
}

public enum DropIngest {
    private static let log = Log.logger("shelf.ingest")

    /// Wczytuje wszystkich dostawców równolegle; nieczytelne elementy są pomijane i logowane.
    @MainActor
    public static func load(_ providers: [NSItemProvider]) async -> [IngestedItem] {
        let boxes = providers.map(ProviderBox.init)
        return await withTaskGroup(of: (Int, IngestedItem?).self) { group in
            for (index, box) in boxes.enumerated() {
                group.addTask { (index, await load(box)) }
            }
            var results: [(Int, IngestedItem)] = []
            for await (index, item) in group {
                if let item { results.append((index, item)) }
            }
            return results.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    private static func load(_ box: ProviderBox) async -> IngestedItem? {
        let provider = box.provider
        let name = provider.suggestedName
        switch IngestPlan.choose(for: provider.registeredTypeIdentifiers) {
        case .fileURL:
            return await loadURL(provider).map(IngestedItem.file)
        case .image(let type):
            guard let data = await loadData(provider, type: type) else { return nil }
            let ext = UTType(type)?.preferredFilenameExtension ?? "png"
            return .data(data, suggestedName: fileName(name, fallback: "Obraz", extension: ext))
        case .fileRepresentation(let type):
            return await loadFileCopy(provider, type: type, suggestedName: name)
        case .webLink:
            guard let url = await loadURL(provider), let data = WebLocation.data(for: url) else { return nil }
            return .data(data, suggestedName: fileName(name ?? url.host(), fallback: "Link", extension: "webloc"))
        case .text:
            guard let text = await loadText(provider) else { return nil }
            return .data(Data(text.utf8), suggestedName: fileName(name, fallback: "Tekst", extension: "txt"))
        case .unsupported:
            log.info("Pominięto element o typach: \(provider.registeredTypeIdentifiers.joined(separator: ", "))")
            return nil
        }
    }

    static func fileName(_ suggested: String?, fallback: String, extension ext: String) -> String {
        let base = (suggested?.isEmpty == false ? suggested! : fallback)
        return base.lowercased().hasSuffix(".\(ext.lowercased())") ? base : "\(base).\(ext)"
    }

    private static func loadURL(_ provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { url, error in
                if let error { log.error("Nie udało się wczytać URL: \(error.localizedDescription)") }
                continuation.resume(returning: url)
            }
        }
    }

    private static func loadData(_ provider: NSItemProvider, type: String) async -> Data? {
        await withCheckedContinuation { continuation in
            _ = provider.loadDataRepresentation(forTypeIdentifier: type) { data, error in
                if let error { log.error("Nie udało się wczytać danych: \(error.localizedDescription)") }
                continuation.resume(returning: data)
            }
        }
    }

    private static func loadText(_ provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: NSString.self) { text, _ in
                continuation.resume(returning: text as? String)
            }
        }
    }

    /// Plik z `loadFileRepresentation` istnieje tylko w callbacku, więc kopiujemy go od razu.
    private static func loadFileCopy(_ provider: NSItemProvider, type: String, suggestedName: String?) async -> IngestedItem? {
        await withCheckedContinuation { continuation in
            _ = provider.loadFileRepresentation(forTypeIdentifier: type) { url, error in
                guard let url else {
                    if let error { log.error("Nie udało się wczytać pliku: \(error.localizedDescription)") }
                    continuation.resume(returning: nil)
                    return
                }
                let copy = FileManager.default.temporaryDirectory
                    .appendingPathComponent("Wyspa-\(UUID().uuidString)-\(url.lastPathComponent)")
                do {
                    try FileManager.default.copyItem(at: url, to: copy)
                    continuation.resume(returning: .temporaryFile(copy, suggestedName: suggestedName ?? url.lastPathComponent))
                } catch {
                    log.error("Nie udało się skopiować pliku: \(error.localizedDescription)")
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

/// NSItemProvider nie jest Sendable, ale jego metody wczytujące są bezpieczne wątkowo.
private struct ProviderBox: @unchecked Sendable {
    let provider: NSItemProvider
}

/// Plik .webloc (lista właściwości z kluczem URL), który Finder otwiera w przeglądarce.
enum WebLocation {
    static func data(for url: URL) -> Data? {
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else { return nil }
        return try? PropertyListSerialization.data(fromPropertyList: ["URL": url.absoluteString], format: .xml, options: 0)
    }
}
