import Testing
@testable import WyspaCore

@Suite("Rozpoznawanie przesunięć")
struct SwipeRecognizerTests {
    @Test("Ruch w dół powyżej progu daje jedno przesunięcie na gest")
    func downOncePerGesture() {
        var recognizer = SwipeRecognizer(threshold: 20)
        #expect(recognizer.handle(phase: .began, dx: 0, dy: 8) == nil)
        #expect(recognizer.handle(phase: .changed, dx: 1, dy: 15) == .down)
        #expect(recognizer.handle(phase: .changed, dx: 0, dy: 40) == nil)
        #expect(recognizer.handle(phase: .ended, dx: 0, dy: 0) == nil)
    }

    @Test("Po zakończeniu gestu można rozpoznać kolejny")
    func resetsAfterEnd() {
        var recognizer = SwipeRecognizer(threshold: 20)
        _ = recognizer.handle(phase: .began, dx: 0, dy: -25)
        _ = recognizer.handle(phase: .ended, dx: 0, dy: 0)
        #expect(recognizer.handle(phase: .began, dx: -30, dy: 0) == .left)
    }

    @Test("Dominująca oś wyznacza kierunek")
    func dominantAxis() {
        var recognizer = SwipeRecognizer(threshold: 20)
        #expect(recognizer.handle(phase: .began, dx: 25, dy: -18) == .right)
    }

    @Test("Zdarzenia bez fazy (kółko myszy, bezwładność) są ignorowane")
    func ignoresOther() {
        var recognizer = SwipeRecognizer(threshold: 20)
        #expect(recognizer.handle(phase: .other, dx: 0, dy: 100) == nil)
    }

    @Test("Anulowanie czyści nagromadzony ruch")
    func cancelResets() {
        var recognizer = SwipeRecognizer(threshold: 20)
        _ = recognizer.handle(phase: .began, dx: 0, dy: 15)
        _ = recognizer.handle(phase: .cancelled, dx: 0, dy: 0)
        #expect(recognizer.handle(phase: .began, dx: 0, dy: 10) == nil)
    }
}
