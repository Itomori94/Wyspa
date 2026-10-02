import Foundation

public enum IslandPhase: Equatable, Sendable {
    /// Wirtualny notch bez aktywności: widoczny jest tylko cienki pas do najechania.
    case hidden
    /// Spoczynek, ewentualnie z live activity po bokach.
    case collapsed
    /// Kursor nad wyspą, czekamy na opóźnienie rozwinięcia.
    case peek
    case expanded
}

public enum SwipeDirection: Equatable, Sendable {
    case up, down, left, right
}

public enum IslandTimer: Hashable, Sendable {
    case expand
    case collapse
}

public enum IslandEvent: Equatable, Sendable {
    case pointerEntered
    case pointerExited
    case clicked
    case swipe(SwipeDirection)
    case toggleRequested
    /// Rozwinięcie na żądanie (moduł prosi o uwagę, kliknięcie aktywności) — działa też, gdy wisi karta.
    case expandRequested
    /// Przeciąganie weszło nad wyspę; `preferredTab` = zakładka modułu przyjmującego upuszczenia.
    case dragEntered(preferredTab: Int?)
    case dragExited
    case timerFired(IslandTimer)
    case activityChanged(hasActivity: Bool)
    /// Pod notchem wisi karta (np. powiadomienie), którą można kliknąć.
    case cardChanged(Bool)
    case tabCountChanged(Int)
    case tabSelected(Int)
    /// Pole tekstowe w wyspie dostało albo straciło klawiaturę.
    case editingChanged(Bool)
}

public enum IslandEffect: Equatable, Sendable {
    case schedule(IslandTimer, after: TimeInterval)
    case cancel(IslandTimer)
    case haptic
}

public struct IslandConfig: Equatable, Sendable {
    public var expandOnHover: Bool
    public var hoverDelay: TimeInterval
    public var collapseDelay: TimeInterval
    /// true dla wirtualnego notcha w trybie „tylko gdy coś się dzieje”.
    public var hidesWhenIdle: Bool

    public init(expandOnHover: Bool, hoverDelay: TimeInterval, collapseDelay: TimeInterval, hidesWhenIdle: Bool) {
        self.expandOnHover = expandOnHover
        self.hoverDelay = hoverDelay
        self.collapseDelay = collapseDelay
        self.hidesWhenIdle = hidesWhenIdle
    }
}

public struct IslandState: Equatable, Sendable {
    public let phase: IslandPhase
    public let hasActivity: Bool
    public let tabCount: Int
    public let selectedTab: Int
    /// Użytkownik pisze w polu tekstowym wyspy: zjechanie kursorem nie zwija wyspy.
    public let isEditing: Bool
    /// Karta pod notchem przyjmuje najechanie i kliknięcia sama — wtedy wyspa nie rozwija się od kursora.
    public let hasCard: Bool

    public init(phase: IslandPhase, hasActivity: Bool = false, tabCount: Int = 0, selectedTab: Int = 0, isEditing: Bool = false,
                hasCard: Bool = false) {
        self.phase = phase
        self.hasCard = hasCard
        self.hasActivity = hasActivity
        self.tabCount = tabCount
        self.selectedTab = selectedTab
        self.isEditing = isEditing
    }

    public static func initial(config: IslandConfig) -> IslandState {
        IslandState(phase: config.hidesWhenIdle ? .hidden : .collapsed)
    }

    func with(
        phase: IslandPhase? = nil,
        hasActivity: Bool? = nil,
        tabCount: Int? = nil,
        selectedTab: Int? = nil,
        isEditing: Bool? = nil,
        hasCard: Bool? = nil
    ) -> IslandState {
        IslandState(
            phase: phase ?? self.phase,
            hasActivity: hasActivity ?? self.hasActivity,
            tabCount: tabCount ?? self.tabCount,
            selectedTab: selectedTab ?? self.selectedTab,
            isEditing: isEditing ?? self.isEditing,
            hasCard: hasCard ?? self.hasCard
        )
    }
}

/// Czysty reducer stanów wyspy. Opóźnienia są efektami, więc całość jest deterministyczna i testowalna.
public enum IslandStateMachine {
    public typealias Result = (state: IslandState, effects: [IslandEffect])

    public static func reduce(_ state: IslandState, _ event: IslandEvent, config: IslandConfig) -> Result {
        switch event {
        case .pointerEntered:
            return pointerEntered(state, config: config)
        case .pointerExited:
            return pointerExited(state, config: config)
        case .clicked:
            // Kliknięcie w kartę obsługuje karta (np. otwiera aplikację), nie rozwija wyspy.
            return state.phase == .expanded || state.hasCard ? (state, []) : expand(state)
        case .swipe(let direction):
            return swipe(state, direction, config: config)
        case .expandRequested:
            return state.phase == .expanded ? (state, [.cancel(.collapse)]) : expand(state)
        case .toggleRequested:
            return state.phase == .expanded ? collapse(state, config: config) : expand(state)
        case .dragEntered(let preferredTab):
            let target = preferredTab.flatMap { (0..<state.tabCount).contains($0) ? $0 : nil } ?? state.selectedTab
            let retabbed = state.with(selectedTab: target)
            return state.phase == .expanded
                ? (retabbed, [.cancel(.collapse)])
                : expand(retabbed)
        case .dragExited:
            return state.phase == .expanded
                ? (state, [.schedule(.collapse, after: config.collapseDelay)])
                : (state, [])
        case .timerFired(.expand):
            return state.phase == .peek && !state.hasCard ? expand(state) : (state, [])
        case .timerFired(.collapse):
            return state.phase == .expanded ? collapse(state, config: config) : (state, [])
        case .activityChanged(let hasActivity):
            return activityChanged(state, hasActivity: hasActivity, config: config)
        case .cardChanged(let hasCard):
            let updated = state.with(hasCard: hasCard)
            if hasCard, state.phase == .peek { return (updated, [.cancel(.expand)]) }
            // Karta zniknęła spod kursora (np. po kliknięciu „otwórz”): nie rozwijamy wyspy na otwartą aplikację.
            // Rozwinie ją dopiero ponowne najechanie albo kliknięcie.
            return (updated, [])
        case .tabCountChanged(let count):
            let selected = count == 0 ? 0 : min(state.selectedTab, count - 1)
            return (state.with(tabCount: count, selectedTab: selected), [])
        case .tabSelected(let index):
            guard state.tabCount > 0, (0..<state.tabCount).contains(index) else { return (state, []) }
            return (state.with(selectedTab: index), [])
        case .editingChanged(let editing):
            // Koniec pisania przy kursorze poza wyspą zgłasza kontroler osobnym `pointerExited`.
            return (state.with(isEditing: editing), editing ? [.cancel(.collapse)] : [])
        }
    }

    static func restingPhase(hasActivity: Bool, config: IslandConfig) -> IslandPhase {
        config.hidesWhenIdle && !hasActivity ? .hidden : .collapsed
    }

    private static func pointerEntered(_ state: IslandState, config: IslandConfig) -> Result {
        switch state.phase {
        case .hidden, .collapsed:
            let effects: [IslandEffect] = config.expandOnHover && !state.hasCard
                ? [.schedule(.expand, after: config.hoverDelay)]
                : []
            return (state.with(phase: .peek), effects)
        case .peek:
            return (state, [])
        case .expanded:
            return (state, [.cancel(.collapse)])
        }
    }

    private static func pointerExited(_ state: IslandState, config: IslandConfig) -> Result {
        switch state.phase {
        case .peek:
            let resting = restingPhase(hasActivity: state.hasActivity, config: config)
            return (state.with(phase: resting), [.cancel(.expand)])
        case .expanded:
            return state.isEditing ? (state, []) : (state, [.schedule(.collapse, after: config.collapseDelay)])
        case .hidden, .collapsed:
            return (state, [])
        }
    }

    private static func swipe(_ state: IslandState, _ direction: SwipeDirection, config: IslandConfig) -> Result {
        switch (state.phase, direction) {
        case (.expanded, .up):
            return collapse(state, config: config)
        case (.expanded, .left), (.expanded, .right):
            guard state.tabCount > 1 else { return (state, []) }
            let step = direction == .left ? 1 : -1
            let next = (state.selectedTab + step + state.tabCount) % state.tabCount
            return (state.with(selectedTab: next), [.haptic])
        case (.collapsed, .down), (.peek, .down), (.hidden, .down):
            return expand(state)
        default:
            return (state, [])
        }
    }

    private static func activityChanged(_ state: IslandState, hasActivity: Bool, config: IslandConfig) -> Result {
        let updated = state.with(hasActivity: hasActivity)
        switch state.phase {
        case .hidden, .collapsed:
            return (updated.with(phase: restingPhase(hasActivity: hasActivity, config: config)), [])
        case .peek, .expanded:
            return (updated, [])
        }
    }

    private static func expand(_ state: IslandState) -> Result {
        (state.with(phase: .expanded), [.cancel(.expand), .cancel(.collapse), .haptic])
    }

    private static func collapse(_ state: IslandState, config: IslandConfig) -> Result {
        let resting = restingPhase(hasActivity: state.hasActivity, config: config)
        return (state.with(phase: resting, isEditing: false), [.cancel(.expand), .cancel(.collapse)])
    }
}
