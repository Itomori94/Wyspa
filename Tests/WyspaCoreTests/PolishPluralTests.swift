import Testing
@testable import WyspaCore

@Suite("Odmiana liczebników")
struct PolishPluralTests {
    @Test(arguments: [
        (1, "element"), (2, "elementy"), (4, "elementy"), (5, "elementów"), (11, "elementów"),
        (12, "elementów"), (14, "elementów"), (22, "elementy"), (25, "elementów"), (0, "elementów"),
    ])
    func forms(n: Int, expected: String) {
        #expect(PolishPlural.word(for: n, one: "element", few: "elementy", many: "elementów") == expected)
    }
}
