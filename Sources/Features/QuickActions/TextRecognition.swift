import Foundation
import Vision

/// Rozpoznawanie tekstu na zrzucie (Vision, na urządzeniu, bez sieci); polski i angielski.
enum TextRecognition {
    static let languages = ["pl-PL", "en-US"]

    /// Wiersze tekstu w kolejności czytania. Praca poza głównym wątkiem (Vision jest synchroniczny).
    static func lines(inImageAt url: URL) async throws -> [String] {
        try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            let supported = (try? request.supportedRecognitionLanguages()) ?? []
            let wanted = languages.filter(supported.contains)
            if !wanted.isEmpty { request.recognitionLanguages = wanted }
            try VNImageRequestHandler(url: url).perform([request])
            return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        }.value
    }
}
