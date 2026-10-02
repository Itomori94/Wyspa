import SwiftUI

/// Krótki komunikat po akcji („Skopiowano”, „Mikrofon wyciszony”), który sam znika — jedno zadanie, bez zegara.
@MainActor
@Observable
public final class TransientMessage {
    public private(set) var text: String?
    @ObservationIgnored private var task: Task<Void, Never>?

    public init() {}

    /// Nowy komunikat zastępuje poprzedni i liczy czas od nowa.
    public func show(_ text: String, for duration: Duration) {
        withAnimation { self.text = text }
        task?.cancel()
        task = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            withAnimation { self?.text = nil }
        }
    }

    public func clear() {
        task?.cancel()
        task = nil
        text = nil
    }
}
