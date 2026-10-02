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

    /// Reaguje od razu na początek i koniec przechwytywania ekranu (także przy rozwiniętej wyspie).
    /// Zwraca `false`, gdy system nie pozwala na powiadomienia — wtedy zostają punkty sprawdzania w `refresh()`.
    @discardableResult
    public func observeCaptureChanges() -> Bool {
        ScreenCaptureDetector.observe { [weak self] in self?.refresh() }
    }

    /// Ustala stan na teraz; zwraca go, żeby wołający mógł od razu zdecydować, co pokazać.
    @discardableResult
    public func refresh() -> Bool {
        let next = Self.resolve(mode(), captured: { isScreenCaptured() })
        if next != isActive {
            isActive = next
            Log.logger("privacy").notice("tryb prywatny: \(next ? "włączony" : "wyłączony", privacy: .public)")
        }
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

    // MARK: - Zdarzenia (bez odpytywania)

    /// Typy powiadomień serwera okien przy starcie i końcu przechwytywania ekranu — ustalone eksperymentem
    /// na macOS 27.2 (`SLSRegisterNotifyProc`, nagrywanie `screencapture -V`): 1502 start, 1503 koniec.
    static let captureStarted: UInt32 = 1502
    static let captureStopped: UInt32 = 1503

    private typealias NotifyCallback = @convention(c) (UInt32, UnsafeMutableRawPointer?, Int, UnsafeMutableRawPointer?) -> Void
    private typealias RegisterNotify = @convention(c) (NotifyCallback, UInt32, UnsafeMutableRawPointer?) -> Int32

    private static let registerNotify: RegisterNotify? = PrivateSymbol.load(
        "SLSRegisterNotifyProc", from: "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", as: RegisterNotify.self
    )

    /// Odbiorcy zmian (wołani na głównym wątku). Rejestracja w systemie odbywa się raz na proces.
    @MainActor private static var handlers: [() -> Void] = []
    @MainActor private static var isRegistered = false

    @MainActor
    static func observe(_ handler: @escaping @MainActor () -> Void) -> Bool {
        guard let registerNotify else { return false }
        if !isRegistered {
            let callback: NotifyCallback = { _, _, _, _ in
                DispatchQueue.main.async { MainActor.assumeIsolated { ScreenCaptureDetector.notifyHandlers() } }
            }
            let started = registerNotify(callback, captureStarted, nil) == 0
            let stopped = registerNotify(callback, captureStopped, nil) == 0
            guard started, stopped else { return false }
            isRegistered = true
        }
        handlers.append(handler)
        return true
    }

    @MainActor
    private static func notifyHandlers() {
        handlers.forEach { $0() }
    }

    /// Czy Wyspa dostaje zdarzenia o przechwytywaniu (a nie tylko sprawdza stan w wybranych momentach).
    public static var isObservable: Bool { registerNotify != nil && watcher != nil }
}
