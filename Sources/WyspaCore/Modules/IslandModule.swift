import SwiftUI

/// Statyczny opis modułu, dostępny bez tworzenia instancji (lista w ustawieniach).
public struct ModuleDescriptor: Sendable, Identifiable {
    public let id: String
    public let name: String
    public let summary: String
    public let symbol: String
    public let permissions: Set<Permission>

    public init(id: String, name: String, summary: String, symbol: String, permissions: Set<Permission> = []) {
        self.id = id
        self.name = name
        self.summary = summary
        self.symbol = symbol
        self.permissions = permissions
    }
}

/// Priorytety live activity: wyższy wygrywa miejsce w zwiniętej wyspie.
public struct ActivityPriority: Comparable, Sendable {
    public let rawValue: Int
    public init(_ rawValue: Int) { self.rawValue = rawValue }

    public static let hud = ActivityPriority(100)
    public static let attention = ActivityPriority(80)
    public static let timer = ActivityPriority(60)
    public static let upcomingEvent = ActivityPriority(50)
    public static let media = ActivityPriority(40)
    public static let status = ActivityPriority(20)

    public static func < (lhs: ActivityPriority, rhs: ActivityPriority) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Zawartość zwiniętej wyspy: lewe i prawe „skrzydło” obok notcha.
public struct LiveActivity {
    public let id: String
    public let priority: ActivityPriority
    public let accent: Color?
    public let leading: AnyView
    public let trailing: AnyView

    public init<Leading: View, Trailing: View>(
        id: String,
        priority: ActivityPriority,
        accent: Color? = nil,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.id = id
        self.priority = priority
        self.accent = accent
        self.leading = AnyView(leading())
        self.trailing = AnyView(trailing())
    }
}

/// Usługi wyspy udostępniane modułom.
@MainActor
public struct ModuleContext {
    public let settings: ModuleSettings
    /// Prośba o rozwinięcie wyspy na ekranie pod kursorem (np. przy nowym zdarzeniu).
    public let requestExpand: @MainActor () -> Void

    public init(settings: ModuleSettings, requestExpand: @escaping @MainActor () -> Void) {
        self.settings = settings
        self.requestExpand = requestExpand
    }
}

/// Wspólny protokół wszystkich funkcji wyspy.
///
/// Cykl życia: instancja powstaje dopiero po włączeniu modułu i po przyznaniu uprawnień,
/// `activate()` uruchamia zasoby, `deactivate()` je zwalnia, po czym instancja jest porzucana.
@MainActor
public protocol IslandModule: AnyObject, Observable {
    static var descriptor: ModuleDescriptor { get }

    init(context: ModuleContext)

    func activate() async throws
    func deactivate()

    /// Aktywność w zwiniętej wyspie; nil, gdy moduł nie ma nic do pokazania.
    var liveActivity: LiveActivity? { get }
    /// Zakładka w rozwiniętej wyspie; nil, gdy moduł nie ma widoku rozwiniętego.
    func makeExpandedView() -> AnyView?
    /// Szczegółowe ustawienia w oknie ustawień; nil, gdy moduł ich nie ma.
    func makeSettingsView() -> AnyView?
}

extension IslandModule {
    public func makeSettingsView() -> AnyView? { nil }
}
