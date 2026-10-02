import Testing
@testable import WyspaCore

@Suite("Klawiatura w rozwiniętej wyspie")
struct IslandKeyRouterTests {
    private func route(_ keyCode: UInt16, _ characters: String? = nil, _ modifiers: IslandKeyRouter.Modifiers = [],
                       editing: Bool = false) -> IslandKeyRouter.Action {
        IslandKeyRouter.route(keyCode: keyCode, characters: characters, modifiers: modifiers, isEditingText: editing)
    }

    @Test("Strzałki w bok zmieniają stronę, Esc zwija, Backspace i pionowe strzałki do modułu")
    func navigation() {
        #expect(route(123) == .stepTab(-1))
        #expect(route(124) == .stepTab(1))
        #expect(route(53) == .collapse)
        #expect(route(126) == .forward(.up))
        #expect(route(125) == .forward(.down))
        #expect(route(36) == .forward(.enter))
        #expect(route(76) == .forward(.enter))
        #expect(route(51) == .forward(.backspace))
    }

    @Test("Pisanie trafia do wyszukiwania, także polskie znaki")
    func typing() {
        #expect(route(0, "a") == .typeToSearch("a"))
        #expect(route(0, "ż", [.option]) == .typeToSearch("ż"))
        #expect(route(49, " ") == .typeToSearch(" "))
        #expect(route(0, "A", [.shift]) == .typeToSearch("A"))
    }

    @Test("Skróty z ⌘/⌃, klawisze funkcyjne i ⌥← zostają dla systemu")
    func passes() {
        #expect(route(8, "c", [.command]) == .pass)
        #expect(route(0, "a", [.control]) == .pass)
        #expect(route(126, nil, [.command]) == .pass)
        #expect(route(123, nil, [.option]) == .pass)
        #expect(route(122, "\u{F704}") == .pass, "F1: znak z obszaru prywatnego")
        #expect(route(48, "\t") == .pass)
        #expect(route(0, "") == .pass)
    }

    @Test("W polu tekstowym tylko ↑ ↓ Enter idą do modułu")
    func editing() {
        #expect(route(125, editing: true) == .forward(.down))
        #expect(route(36, editing: true) == .forward(.enter))
        #expect(route(123, editing: true) == .pass)
        #expect(route(53, editing: true) == .pass)
        #expect(route(51, editing: true) == .pass)
        #expect(route(0, "a", editing: true) == .pass)
    }
}
