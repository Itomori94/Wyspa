import Foundation
import Testing
@testable import WyspaWeather

@Suite("Pogoda z Open-Meteo")
struct WeatherTests {
    let json = Data("""
    {"current":{"temperature_2m":21.4,"weather_code":2,"is_day":1},
     "daily":{"time":["2026-10-02","2026-10-03","2026-10-04"],"weather_code":[2,61,3],
              "temperature_2m_max":[22.1,18.0,15.5],"temperature_2m_min":[11.2,9.8],"extra":[]}}
    """.utf8)

    @Test("Odczyt bieżącej pogody i dni (niepełne dni pominięte)")
    func parse() throws {
        let forecast = try #require(OpenMeteo.parse(json, fetchedAt: Date(timeIntervalSince1970: 0)))
        #expect(forecast.temperature == 21.4 && forecast.code == 2 && forecast.isDay)
        #expect(forecast.days.count == 2 && forecast.days[1].code == 61 && forecast.days[1].low == 9.8)
        #expect(OpenMeteo.parse(Data("{}".utf8), fetchedAt: Date()) == nil)
    }

    @Test("Zapytanie z współrzędnymi zaokrąglonymi do ok. 1 km")
    func query() throws {
        let url = try #require(OpenMeteo.url(latitude: 52.229_676, longitude: 21.012_229))
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(url.scheme == "https" && url.host == "api.open-meteo.com")
        #expect(items.contains(URLQueryItem(name: "latitude", value: "52.23")))
        #expect(items.contains(URLQueryItem(name: "longitude", value: "21.01")))
    }

    @Test("Dane nieaktualne po 15 minutach")
    func staleness() throws {
        let forecast = try #require(OpenMeteo.parse(json, fetchedAt: Date(timeIntervalSince1970: 0)))
        #expect(!forecast.isStale(at: Date(timeIntervalSince1970: 14 * 60)))
        #expect(forecast.isStale(at: Date(timeIntervalSince1970: 15 * 60)))
    }

    @Test("Symbole, opisy i format temperatury")
    func codes() {
        #expect(WeatherCode.symbol(for: 0, isDay: false) == "moon.stars.fill")
        #expect(WeatherCode.symbol(for: 95) == "cloud.bolt.rain.fill")
        #expect(WeatherCode.description(for: 61) == "Słaby deszcz" && WeatherCode.description(for: 1234) == "Pogoda nieznana")
        #expect(WeatherCode.format(21.4) == "21°" && WeatherCode.format(-2.6) == "−3°" && WeatherCode.format(-0.2) == "0°")
    }
}
