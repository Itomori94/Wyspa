import Foundation
import Testing
@testable import WyspaCore

@Suite("Wspólne pomocniki")
struct SharedHelpersTests {
    @Test("Postęp: średnia znanych wartości, tekst procentu w dół")
    func progress() {
        #expect(ProgressSummary.average([0.2, nil, 0.6]) == 0.4)
        #expect(ProgressSummary.average([nil, nil]) == nil)
        #expect(ProgressSummary.average([]) == nil)
        #expect(ProgressSummary.percentText(0.999) == "99%")
        #expect(ProgressSummary.percentText(0.429) == "42%")
        #expect(ProgressSummary.percentText(nil) == "…")
        #expect(ProgressSummary.percentText(1.5) == "100%")
    }

    @Test("Poufne i tymczasowe treści schowka są pomijane")
    func pasteboardPrivacy() {
        #expect(PasteboardPrivacy.shouldIgnore(types: ["public.utf8-plain-text", PasteboardPrivacy.concealed]))
        #expect(PasteboardPrivacy.shouldIgnore(types: ["org.nspasteboard.TransientType"]))
        #expect(!PasteboardPrivacy.shouldIgnore(types: ["public.utf8-plain-text"]))
    }

    @Test("Komunikat znika sam; nowy zastępuje stary")
    @MainActor
    func transientMessage() async throws {
        let message = TransientMessage()
        message.show("a", for: .seconds(60))
        message.show("b", for: .milliseconds(20))
        #expect(message.text == "b")
        try await Task.sleep(for: .milliseconds(300))
        #expect(message.text == nil)
        message.show("c", for: .seconds(60))
        message.clear()
        #expect(message.text == nil)
    }
}
