import AppKit
import CoreLocation
import SwiftUI
import WyspaCore

/// Pogoda dla okolicy z Open-Meteo; kliknięcie otwiera aplikację Pogoda.
///
/// Bez zegara w tle: dane odświeżają się przy włączeniu modułu i przy otwarciu widoku, gdy mają ponad 15 minut.
@MainActor
@Observable
public final class WeatherModule: IslandModule {
    public static let descriptor = ModuleDescriptor(
        id: "weather",
        name: "Pogoda",
        summary: "Temperatura i prognoza na kilka dni dla Twojej okolicy (Open-Meteo). Kliknięcie otwiera aplikację Pogoda.",
        symbol: "cloud.sun.fill",
        permissions: [.location],
        widgetMinWidth: 130
    )

    public enum Status: Equatable {
        case loading
        case ready
        case failed(String)
    }

    static let weatherAppID = "com.apple.weather"
    private static let collapsedKey = "showInCollapsed"

    public private(set) var forecast: Forecast?
    public private(set) var status: Status = .loading
    /// Temperatura stale w zwiniętej wyspie (domyślnie wyłączone, żeby wyspa była pusta, gdy nic się nie dzieje).
    public var showsInCollapsed: Bool {
        didSet { context.settings.set(showsInCollapsed, for: Self.collapsedKey) }
    }

    @ObservationIgnored private let context: ModuleContext
    @ObservationIgnored private var locator: OneShotLocator?
    @ObservationIgnored private var isRefreshing = false

    public required init(context: ModuleContext) {
        self.context = context
        showsInCollapsed = context.settings.value(Self.collapsedKey, default: false)
    }

    public func activate() async throws {
        refresh()
    }

    public func deactivate() {
        locator = nil
        isRefreshing = false
    }

    public var liveActivity: LiveActivity? {
        guard showsInCollapsed, let forecast else { return nil }
        return LiveActivity(id: "weather", priority: .status, wingWidth: 44) {
            Image(systemName: WeatherCode.symbol(for: forecast.code, isDay: forecast.isDay))
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 13))
        } trailing: {
            Text(WeatherCode.format(forecast.temperature))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }
    }

    public func makeExpandedView() -> AnyView? { AnyView(WeatherView(module: self, compact: false)) }
    public func makeWidgetView() -> AnyView? { AnyView(WeatherView(module: self, compact: true)) }
    public func makeSettingsView() -> AnyView? { AnyView(WeatherSettingsView(module: self)) }

    /// Wywoływane przy otwarciu widoku: pobiera dane tylko, gdy są nieaktualne.
    func refreshIfStale() {
        guard forecast?.isStale(at: Date()) ?? true else { return }
        refresh()
    }

    func openWeatherApp() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.weatherAppID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        if forecast == nil { status = .loading }
        let locator = OneShotLocator { [weak self] location in
            self?.locator = nil
            guard let self else { return }
            guard let location else {
                self.finish(nil, error: "Nie udało się ustalić lokalizacji.")
                return
            }
            Task { await self.fetch(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude) }
        }
        self.locator = locator
        locator.start()
    }

    private func fetch(latitude: Double, longitude: Double) async {
        guard let url = OpenMeteo.url(latitude: latitude, longitude: longitude) else { return }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200, let forecast = OpenMeteo.parse(data, fetchedAt: Date()) else {
                finish(nil, error: "Serwis pogody zwrócił nieoczekiwaną odpowiedź.")
                return
            }
            finish(forecast, error: nil)
        } catch {
            finish(nil, error: "Brak połączenia z serwisem pogody.")
        }
    }

    private func finish(_ newForecast: Forecast?, error: String?) {
        isRefreshing = false
        if let newForecast {
            withAnimation { forecast = newForecast }
            status = .ready
        } else if let error {
            // Stare dane zostają widoczne; błąd tylko, gdy nie ma czego pokazać.
            status = forecast == nil ? .failed(error) : .ready
        }
    }
}

/// Jednorazowe ustalenie lokalizacji (bez śledzenia). Dokładność kilometrowa wystarcza do pogody.
@MainActor
final class OneShotLocator: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private let completion: @MainActor (CLLocation?) -> Void
    private var finished = false

    init(completion: @escaping @MainActor (CLLocation?) -> Void) {
        self.completion = completion
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func start() {
        manager.requestLocation()
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let last = locations.last
        MainActor.assumeIsolated { finish(last) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        MainActor.assumeIsolated { finish(nil) }
    }

    private func finish(_ location: CLLocation?) {
        guard !finished else { return }
        finished = true
        completion(location)
    }
}
