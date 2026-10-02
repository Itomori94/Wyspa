import Testing
@testable import WyspaCore

@Suite("Maszyna stanów wyspy")
struct IslandStateMachineTests {
    let config = IslandConfig(expandOnHover: true, hoverDelay: 0.2, collapseDelay: 0.4, hidesWhenIdle: false)

    private func reduce(_ state: IslandState, _ event: IslandEvent, config: IslandConfig? = nil) -> IslandStateMachine.Result {
        IslandStateMachine.reduce(state, event, config: config ?? self.config)
    }

    @Test("Stan początkowy zależy od trybu wirtualnego notcha")
    func initialState() {
        #expect(IslandState.initial(config: config).phase == .collapsed)
        let hiding = IslandConfig(expandOnHover: true, hoverDelay: 0, collapseDelay: 0, hidesWhenIdle: true)
        #expect(IslandState.initial(config: hiding).phase == .hidden)
    }

    @Test("Najechanie: podgląd i zaplanowane rozwinięcie")
    func hoverSchedulesExpand() {
        let result = reduce(IslandState(phase: .collapsed), .pointerEntered)
        #expect(result.state.phase == .peek)
        #expect(result.effects == [.schedule(.expand, after: 0.2)])
    }

    @Test("Bez rozwijania po najechaniu: sam podgląd")
    func hoverWithoutAutoExpand() {
        let manual = IslandConfig(expandOnHover: false, hoverDelay: 0.2, collapseDelay: 0.4, hidesWhenIdle: false)
        let result = reduce(IslandState(phase: .collapsed), .pointerEntered, config: manual)
        #expect(result.state.phase == .peek)
        #expect(result.effects.isEmpty)
    }

    @Test("Upływ opóźnienia rozwija wyspę z haptyką")
    func expandTimer() {
        let result = reduce(IslandState(phase: .peek), .timerFired(.expand))
        #expect(result.state.phase == .expanded)
        #expect(result.effects.contains(.haptic))
    }

    @Test("Spóźniony timer rozwinięcia po opuszczeniu jest ignorowany")
    func staleExpandTimer() {
        let result = reduce(IslandState(phase: .collapsed), .timerFired(.expand))
        #expect(result.state.phase == .collapsed)
        #expect(result.effects.isEmpty)
    }

    @Test("Opuszczenie podglądu wraca do spoczynku i anuluje rozwinięcie")
    func exitPeek() {
        let result = reduce(IslandState(phase: .peek), .pointerExited)
        #expect(result.state.phase == .collapsed)
        #expect(result.effects == [.cancel(.expand)])
    }

    @Test("Opuszczenie rozwiniętej planuje zwinięcie, powrót je anuluje")
    func exitAndReturnExpanded() {
        let expanded = IslandState(phase: .expanded)
        #expect(reduce(expanded, .pointerExited).effects == [.schedule(.collapse, after: 0.4)])
        #expect(reduce(expanded, .pointerEntered).effects == [.cancel(.collapse)])
    }

    @Test("Timer zwinięcia zwija rozwiniętą wyspę")
    func collapseTimer() {
        #expect(reduce(IslandState(phase: .expanded), .timerFired(.collapse)).state.phase == .collapsed)
    }

    @Test("Kliknięcie rozwija od razu, w rozwiniętej nic nie robi")
    func click() {
        #expect(reduce(IslandState(phase: .collapsed), .clicked).state.phase == .expanded)
        let expanded = reduce(IslandState(phase: .expanded), .clicked)
        #expect(expanded.state.phase == .expanded && expanded.effects.isEmpty)
    }

    @Test("Przesunięcie w dół rozwija, w górę zwija")
    func verticalSwipes() {
        #expect(reduce(IslandState(phase: .collapsed), .swipe(.down)).state.phase == .expanded)
        #expect(reduce(IslandState(phase: .expanded), .swipe(.up)).state.phase == .collapsed)
        #expect(reduce(IslandState(phase: .collapsed), .swipe(.up)).state.phase == .collapsed)
    }

    @Test("Przesunięcia w poziomie przełączają zakładki cyklicznie")
    func horizontalSwipes() {
        let state = IslandState(phase: .expanded, tabCount: 3, selectedTab: 2)
        #expect(reduce(state, .swipe(.left)).state.selectedTab == 0)
        #expect(reduce(state, .swipe(.right)).state.selectedTab == 1)
    }

    @Test("Jedna zakładka: przesunięcie w poziomie nic nie zmienia")
    func singleTabSwipe() {
        let result = reduce(IslandState(phase: .expanded, tabCount: 1), .swipe(.left))
        #expect(result.state.selectedTab == 0 && result.effects.isEmpty)
    }

    @Test("Skrót przełącza rozwinięcie")
    func toggle() {
        #expect(reduce(IslandState(phase: .collapsed), .toggleRequested).state.phase == .expanded)
        #expect(reduce(IslandState(phase: .expanded), .toggleRequested).state.phase == .collapsed)
    }

    @Test("Przeciąganie rozwija i blokuje zwijanie do czasu wyjścia")
    func dragging() {
        #expect(reduce(IslandState(phase: .collapsed), .dragEntered(preferredTab: nil)).state.phase == .expanded)
        #expect(reduce(IslandState(phase: .expanded), .dragEntered(preferredTab: nil)).effects == [.cancel(.collapse)])
        #expect(reduce(IslandState(phase: .expanded), .dragExited).effects == [.schedule(.collapse, after: 0.4)])
    }

    @Test("Wirtualny notch: ukrywa się bez aktywności i pojawia z aktywnością")
    func hidingVirtualNotch() {
        let hiding = IslandConfig(expandOnHover: true, hoverDelay: 0.2, collapseDelay: 0.4, hidesWhenIdle: true)
        let shown = reduce(IslandState(phase: .hidden), .activityChanged(hasActivity: true), config: hiding)
        #expect(shown.state.phase == .collapsed)
        let hidden = reduce(shown.state, .activityChanged(hasActivity: false), config: hiding)
        #expect(hidden.state.phase == .hidden)
        let collapsedFromExpanded = reduce(IslandState(phase: .expanded), .timerFired(.collapse), config: hiding)
        #expect(collapsedFromExpanded.state.phase == .hidden)
    }

    @Test("Zmiana aktywności nie przerywa rozwinięcia")
    func activityWhileExpanded() {
        let result = reduce(IslandState(phase: .expanded), .activityChanged(hasActivity: true))
        #expect(result.state.phase == .expanded && result.state.hasActivity)
    }

    @Test("Zmniejszenie liczby zakładek koryguje zaznaczenie")
    func tabCountClamp() {
        let state = IslandState(phase: .expanded, tabCount: 4, selectedTab: 3)
        #expect(reduce(state, .tabCountChanged(2)).state.selectedTab == 1)
        #expect(reduce(state, .tabCountChanged(0)).state.selectedTab == 0)
    }

    @Test("Wybór zakładki kliknięciem, indeks spoza zakresu ignorowany")
    func tabSelection() {
        let state = IslandState(phase: .expanded, tabCount: 3)
        #expect(reduce(state, .tabSelected(2)).state.selectedTab == 2)
        #expect(reduce(state, .tabSelected(5)).state.selectedTab == 0)
        #expect(reduce(state, .tabSelected(-1)).state.selectedTab == 0)
    }

    @Test("Przeciąganie przełącza na zakładkę modułu przyjmującego upuszczenia")
    func dragSwitchesTab() {
        let state = IslandState(phase: .collapsed, tabCount: 3, selectedTab: 0)
        let result = reduce(state, .dragEntered(preferredTab: 2))
        #expect(result.state.phase == .expanded && result.state.selectedTab == 2)
        #expect(reduce(state, .dragEntered(preferredTab: 7)).state.selectedTab == 0)
        let expanded = IslandState(phase: .expanded, tabCount: 2, selectedTab: 0)
        #expect(reduce(expanded, .dragEntered(preferredTab: 1)).state.selectedTab == 1)
    }

    @Test("Podczas pisania zjechanie kursorem nie zwija wyspy")
    func editingKeepsExpanded() {
        let editing = reduce(IslandState(phase: .expanded), .editingChanged(true))
        #expect(editing.state.isEditing && editing.effects == [.cancel(.collapse)])
        #expect(reduce(editing.state, .pointerExited).effects.isEmpty)
        let done = reduce(editing.state, .editingChanged(false))
        #expect(reduce(done.state, .pointerExited).effects == [.schedule(.collapse, after: 0.4)])
    }

    @Test("Zwinięcie kończy pisanie")
    func collapseEndsEditing() {
        let state = IslandState(phase: .expanded, isEditing: true)
        let result = reduce(state, .swipe(.up))
        #expect(result.state.phase == .collapsed && !result.state.isEditing)
    }

    @Test("Karta pod notchem: najechanie i kliknięcie jej nie rozwijają wyspy, skrót tak")
    func cardBlocksHoverExpand() {
        let card = IslandState(phase: .collapsed, hasActivity: true, hasCard: true)
        let hovered = reduce(card, .pointerEntered)
        #expect(hovered.state.phase == .peek && hovered.effects.isEmpty)
        #expect(reduce(hovered.state, .clicked).state.phase == .peek)
        #expect(reduce(hovered.state, .timerFired(.expand)).state.phase == .peek)
        #expect(reduce(hovered.state, .toggleRequested).state.phase == .expanded)
    }

    @Test("Karta pojawia się pod kursorem: zaplanowane rozwinięcie zostaje anulowane; znika — wraca")
    func cardAppearsAndGoes() {
        let peek = reduce(IslandState(phase: .collapsed), .pointerEntered).state
        let withCard = reduce(peek, .cardChanged(true))
        #expect(withCard.state.hasCard && withCard.effects == [.cancel(.expand)])
        let without = reduce(withCard.state, .cardChanged(false))
        #expect(!without.state.hasCard && without.effects == [.schedule(.expand, after: config.hoverDelay)])
    }
}
