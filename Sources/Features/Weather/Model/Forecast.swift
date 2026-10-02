import Foundation

/// Pogoda z Open-Meteo: teraz i kilka następnych dni.
public struct Forecast: Equatable, Sendable {
    public struct Day: Equatable, Sendable {
        public let date: Date
        public let code: Int
        public let high: Double
        public let low: Double
    }

    public let temperature: Double
    public let code: Int
    public let isDay: Bool
    public let days: [Day]
    public let fetchedAt: Date

    /// Dane starsze niż to odświeżamy przy następnym otwarciu (bez zegara w tle).
    public static let maxAge: TimeInterval = 15 * 60

    public func isStale(at date: Date) -> Bool {
        date.timeIntervalSince(fetchedAt) >= Self.maxAge
    }
}

public enum OpenMeteo {
    public static let forecastDays = 4

    /// Współrzędne zaokrąglone do 0,01° (ok. 1 km) — serwis nie dostaje dokładnej pozycji.
    public static func rounded(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }

    public static func url(latitude: Double, longitude: Double) -> URL? {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), rounded(latitude))),
            URLQueryItem(name: "longitude", value: String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), rounded(longitude))),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: String(forecastDays)),
        ]
        return components?.url
    }

    /// Odczyt odpowiedzi; `nil`, gdy brakuje bieżących danych. Dni z niepełnymi danymi są pomijane.
    public static func parse(_ data: Data, fetchedAt: Date) -> Forecast? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let current = object["current"] as? [String: Any],
              let temperature = (current["temperature_2m"] as? NSNumber)?.doubleValue,
              let code = (current["weather_code"] as? NSNumber)?.intValue
        else { return nil }
        let isDay = (current["is_day"] as? NSNumber)?.intValue != 0
        let daily = object["daily"] as? [String: Any] ?? [:]
        let dates = daily["time"] as? [String] ?? []
        let codes = daily["weather_code"] as? [NSNumber] ?? []
        let highs = daily["temperature_2m_max"] as? [NSNumber] ?? []
        let lows = daily["temperature_2m_min"] as? [NSNumber] ?? []
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let count = min(dates.count, codes.count, highs.count, lows.count)
        let days = (0..<count).compactMap { index -> Forecast.Day? in
            guard let date = formatter.date(from: dates[index]) else { return nil }
            return Forecast.Day(date: date, code: codes[index].intValue, high: highs[index].doubleValue, low: lows[index].doubleValue)
        }
        return Forecast(temperature: temperature, code: code, isDay: isDay, days: days, fetchedAt: fetchedAt)
    }
}

/// Kody pogody WMO używane przez Open-Meteo → symbol SF i opis.
public enum WeatherCode {
    public static func symbol(for code: Int, isDay: Bool = true) -> String {
        switch code {
        case 0: isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: "cloud.fill"
        case 45, 48: "cloud.fog.fill"
        case 51, 53, 55, 56, 57: "cloud.drizzle.fill"
        case 61, 63, 80, 81: "cloud.rain.fill"
        case 65, 82: "cloud.heavyrain.fill"
        case 66, 67: "cloud.sleet.fill"
        case 71, 73, 75, 77, 85, 86: "cloud.snow.fill"
        case 95, 96, 99: "cloud.bolt.rain.fill"
        default: "cloud.fill"
        }
    }

    public static func description(for code: Int) -> String {
        switch code {
        case 0: "Bezchmurnie"
        case 1: "Przeważnie słonecznie"
        case 2: "Częściowe zachmurzenie"
        case 3: "Pochmurno"
        case 45, 48: "Mgła"
        case 51, 53, 55: "Mżawka"
        case 56, 57: "Marznąca mżawka"
        case 61, 80: "Słaby deszcz"
        case 63, 81: "Deszcz"
        case 65, 82: "Ulewa"
        case 66, 67: "Marznący deszcz"
        case 71, 85: "Słaby śnieg"
        case 73, 75, 86: "Śnieg"
        case 77: "Krupa śnieżna"
        case 95: "Burza"
        case 96, 99: "Burza z gradem"
        default: "Pogoda nieznana"
        }
    }

    /// Temperatura bez części dziesiętnej, ze znakiem stopnia („−3°”).
    public static func format(_ temperature: Double) -> String {
        let value = Int(temperature.rounded())
        return value < 0 ? "−\(-value)°" : "\(value)°"
    }
}
