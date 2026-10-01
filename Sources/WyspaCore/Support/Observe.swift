import Observation

/// Wywołuje `onChange` przy każdej zmianie wartości odczytanych w `read` (Observation, bez timerów).
/// Obserwacja trwa, dopóki `isActive` zwraca true.
@MainActor
public func observeChanges(
    _ read: @escaping @MainActor () -> Void,
    isActive: @escaping @MainActor () -> Bool = { true },
    onChange: @escaping @MainActor () -> Void
) {
    guard isActive() else { return }
    withObservationTracking(read) {
        Task { @MainActor in
            guard isActive() else { return }
            onChange()
            observeChanges(read, isActive: isActive, onChange: onChange)
        }
    }
}
