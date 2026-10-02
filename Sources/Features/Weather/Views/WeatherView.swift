import SwiftUI
import WyspaUI

/// Pogoda w wyspie; całość klikalna — otwiera aplikację Pogoda.
struct WeatherView: View {
    let module: WeatherModule
    let compact: Bool
    @State private var isHovered = false

    var body: some View {
        Group {
            if let forecast = module.forecast {
                if compact { compactBody(forecast) } else { fullBody(forecast) }
            } else if case .failed(let message) = module.status {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11)).foregroundStyle(.orange)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(isHovered ? 0.06 : 0)))
        .onHover { isHovered = $0 }
        .onTapGesture(perform: module.openWeatherApp)
        .help("Otwórz aplikację Pogoda")
        .onAppear(perform: module.refreshIfStale)
    }

    private func compactBody(_ forecast: Forecast) -> some View {
        VStack(spacing: 4) {
            Image(systemName: WeatherCode.symbol(for: forecast.code, isDay: forecast.isDay))
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 26))
            Text(WeatherCode.format(forecast.temperature))
                .font(.system(size: 24, weight: .bold, design: .rounded))
            Text(WeatherCode.description(for: forecast.code))
                .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
            if let today = forecast.days.first {
                Text("\(WeatherCode.format(today.high)) / \(WeatherCode.format(today.low))")
                    .font(.system(size: 10.5, weight: .medium)).foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    private func fullBody(_ forecast: Forecast) -> some View {
        HStack(spacing: 22) {
            HStack(spacing: 12) {
                Image(systemName: WeatherCode.symbol(for: forecast.code, isDay: forecast.isDay))
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 44))
                VStack(alignment: .leading, spacing: 2) {
                    Text(WeatherCode.format(forecast.temperature))
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                    Text(WeatherCode.description(for: forecast.code))
                        .font(.system(size: 12)).foregroundStyle(.white.opacity(0.65))
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 14) {
                ForEach(forecast.days, id: \.date) { day in
                    VStack(spacing: 5) {
                        Text(day.date, format: .dateTime.weekday(.abbreviated))
                            .font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.white.opacity(0.55))
                        Image(systemName: WeatherCode.symbol(for: day.code))
                            .symbolRenderingMode(.multicolor)
                            .font(.system(size: 18))
                            .frame(height: 22)
                        Text(WeatherCode.format(day.high)).font(.system(size: 12, weight: .semibold))
                        Text(WeatherCode.format(day.low)).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 6)
    }
}

struct WeatherSettingsView: View {
    @Bindable var module: WeatherModule

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Temperatura w zwiniętej wyspie", isOn: $module.showsInCollapsed)
            Text("Dane z Open-Meteo (bez konta). Wysyłane są tylko współrzędne zaokrąglone do ok. 1 km; odświeżanie przy "
                 + "otwarciu wyspy, gdy dane mają ponad 15 minut. Kliknięcie pogody otwiera aplikację Pogoda.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
