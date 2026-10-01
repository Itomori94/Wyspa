import Foundation

/// Źródło informacji o odtwarzaniu. Implementacje są wymienne, moduł zna tylko ten protokół.
@MainActor
public protocol NowPlayingSource: AnyObject {
    var kind: MediaSourceKind { get }

    /// Zaczyna dostarczać aktualizacje. `onFailure` sygnalizuje trwałą awarię źródła.
    func start(
        onUpdate: @escaping @MainActor (NowPlaying?) -> Void,
        onFailure: @escaping @MainActor (String) -> Void
    )
    func stop()
    func send(_ command: MediaCommand)
    func seek(to seconds: TimeInterval)
}
