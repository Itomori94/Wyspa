import SwiftUI

/// Statyczny opis modułu, dostępny bez tworzenia instancji (lista w ustawieniach).
public struct ModuleDescriptor: Sendable, Identifiable {
    public let id: String
    public let name: String
    public let summary: String
    public let symbol: String
    public let permissions: Set<Permission>
    /// Minimalna szerokość widżetu w punktach; nil = moduł nie ma widżetu.
    public let widgetMinWidth: CGFloat?
    /// Czy moduł ma pełny widok na osobnej stronie wyspy.
    public let providesPage: Bool

    public init(
        id: String, name: String, summary: String, symbol: String, permissions: Set<Permission> = [],
        widgetMinWidth: CGFloat? = nil, providesPage: Bool = true
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.symbol = symbol
        self.permissions = permissions
        self.widgetMinWidth = widgetMinWidth
        self.providesPage = providesPage
    }
}

/// Priorytety live activity: wyższy wygrywa miejsce w zwiniętej wyspie.
public struct ActivityPriority: Comparable, Sendable {
    public let rawValue: Int
    public init(_ rawValue: Int) { self.rawValue = rawValue }

    public static let hud = ActivityPriority(100)
    public static let attention = ActivityPriority(80)
    /// Krótkie zdarzenia systemowe (ładowarka, słuchawki): wygrywają z multimediami na kilka sekund.
    public static let alert = ActivityPriority(70)
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
    /// Szerokość każdego skrzydła; szersze dla treści typu pasek poziomu albo tekst (najwyżej `IslandLayout.maxWingWidth`).
    public let wingWidth: CGFloat
    /// Czy skrzydła pokazywać też w nagłówku rozwiniętej wyspy. Wyłączone, gdy rozwinięta treść
    /// i tak pokazuje to samo (np. odtwarzacz z dużą okładką).
    public let showsInExpandedHeader: Bool
    public let leading: AnyView
    public let trailing: AnyView
    /// Opcjonalna karta pod skrzydłami w zwiniętej wyspie (np. treść powiadomienia).
    public let detail: AnyView?
    public let detailHeight: CGFloat

    public init<Leading: View, Trailing: View>(
        id: String,
        priority: ActivityPriority,
        accent: Color? = nil,
        wingWidth: CGFloat = IslandLayout.wingWidth,
        showsInExpandedHeader: Bool = true,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.id = id
        self.priority = priority
        self.accent = accent
        self.wingWidth = IslandLayout.clampedWingWidth(wingWidth)
        self.showsInExpandedHeader = showsInExpandedHeader
        self.leading = AnyView(leading())
        self.trailing = AnyView(trailing())
        self.detail = nil
        self.detailHeight = 0
    }

    /// Aktywność z kartą pod skrzydłami (wysokość ograniczona do `IslandLayout.maxDetailHeight`).
    public init<Leading: View, Trailing: View, Detail: View>(
        id: String,
        priority: ActivityPriority,
        accent: Color? = nil,
        wingWidth: CGFloat = IslandLayout.wingWidth,
        detailHeight: CGFloat,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing,
        @ViewBuilder detail: () -> Detail
    ) {
        self.id = id
        self.priority = priority
        self.accent = accent
        self.wingWidth = IslandLayout.clampedWingWidth(wingWidth)
        self.showsInExpandedHeader = false
        self.leading = AnyView(leading())
        self.trailing = AnyView(trailing())
        self.detail = AnyView(detail())
        self.detailHeight = IslandLayout.clampedDetailHeight(detailHeight)
    }
}

/// Usługi wyspy udostępniane modułom.
@MainActor
public struct ModuleContext {
    public let settings: ModuleSettings
    /// Prośba o rozwinięcie wyspy na ekranie pod kursorem (np. przy nowym zdarzeniu).
    public let requestExpand: @MainActor () -> Void
    /// Przekazuje elementy do strefy innego modułu (np. zrzut ekranu na Półkę). `false`, gdy ten moduł nie działa.
    public let deliver: @MainActor (_ providers: [NSItemProvider], _ zoneID: String) -> Bool

    public init(settings: ModuleSettings, requestExpand: @escaping @MainActor () -> Void,
                deliver: @escaping @MainActor ([NSItemProvider], String) -> Bool = { _, _ in false }) {
        self.settings = settings
        self.requestExpand = requestExpand
        self.deliver = deliver
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
    /// Kompaktowy widżet do strony z kilkoma modułami obok siebie; nil, gdy moduł go nie ma.
    func makeWidgetView() -> AnyView?
}

extension IslandModule {
    public func makeSettingsView() -> AnyView? { nil }
    public func makeWidgetView() -> AnyView? { nil }
}
