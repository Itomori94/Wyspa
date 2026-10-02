import Foundation
import Observation

/// Tryb prywatny: przy udostępnianiu albo nagrywaniu ekranu wyspa chowa treść powiadomień, schowka i odpowiedzi Claude.
///
/// Bez odpytywania: stan sprawdzany jest w chwili, gdy wyspa ma coś pokazać (rozwinięcie, nowa karta) i przy zmianie
/// aktywnej aplikacji (zwykle tak zaczyna się udostępnianie w Zoomie, Teams czy przeglądarce).
@MainActor
@Observable
public final class PrivacyState {
    public enum Mode: String, CaseIterable, Codable, Sendable {
        case automatic, always, off

        public var displayName: String {
            switch self {
            case .automatic: "Przy udostępnianiu i nagrywaniu ekranu"
            case .always: "Zawsze"
            case .off: "Nigdy"
            }
        }
    }

    public private(set) var isActive = false

    @ObservationIgnored private let mode: @MainActor () -> Mode
    @ObservationIgnored private let isScreenCaptured: @MainActor () -> Bool

    public init(mode: @escaping @MainActor () -> Mode, isScreenCaptured: @escaping @MainActor () -> Bool = ScreenCaptureDetector.isCaptured) {
        self.mode = mode
        self.isScreenCaptured = isScreenCaptured
    }

    /// Ustala stan na teraz; zwraca go, żeby wołający mógł od razu zdecydować, co pokazać.
    @discardableResult
    public func refresh() -> Bool {
        let next = Self.resolve(mode(), captured: { isScreenCaptured() })
        if next != isActive { isActive = next }
        return next
    }

    /// Wykrywanie wołane tylko w trybie automatycznym.
    static func resolve(_ mode: Mode, captured: () -> Bool) -> Bool {
        switch mode {
        case .always: true
        case .off: false
        case .automatic: captured()
        }
    }
}

/// Czy ktoś przechwytuje ekran (udostępnianie, nagrywanie, zrzut wideo).
///
/// Prywatne API `SLSIsScreenWatcherPresent` (SkyLight). Gdy zniknie, wykrywanie nie działa — tryb „Zawsze” nadal tak.
public enum ScreenCaptureDetector {
    private typealias Watcher = @convention(c) () -> Bool

    private static let watcher: Watcher? = PrivateSymbol.load(
        "SLSIsScreenWatcherPresent", from: "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", as: Watcher.self
    )

    public static var isAvailable: Bool { watcher != nil }

    @MainActor
    public static func isCaptured() -> Bool {
        watcher?() ?? false
    }
}
