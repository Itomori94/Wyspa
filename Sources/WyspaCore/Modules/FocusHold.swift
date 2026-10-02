import Observation

/// Wspólny stan „trwa skupienie” (faza skupienia Pomodoro): Timer go ustawia, Powiadomienia wstrzymują wtedy karty.
/// Moduły nie znają siebie nawzajem — rozmawiają przez ten obiekt z `ModuleContext`.
@MainActor
@Observable
public final class FocusHold {
    public private(set) var isActive = false

    public init() {}

    public func set(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
    }
}
