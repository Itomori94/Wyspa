import Testing
@testable import WyspaShortcuts

@Suite("Lista skrótów")
struct ShortcutsCLITests {
    @Test("Jedna nazwa w wierszu, bez pustych i duplikatów, z zachowaniem kolejności")
    func parse() {
        let output = "Włącz tryb pracy\n\n  Wyślij lokalizację  \nWłącz tryb pracy\nZróbmy „cytat”; rm -rf /\n"
        #expect(ShortcutsCLI.parseList(output) == ["Włącz tryb pracy", "Wyślij lokalizację", "Zróbmy „cytat”; rm -rf /"])
    }

    @Test("Puste wyjście")
    func empty() {
        #expect(ShortcutsCLI.parseList("\n").isEmpty)
    }
}
