import SwiftUI
import WyspaUI

/// Karta powiadomienia pod notchem: ikona i nazwa aplikacji, tytuł, treść.
struct NotificationCardView: View {
    let card: NotificationCard
    let icon: NSImage
    /// Ekran udostępniany: bez tytułu i treści, tylko aplikacja.
    let isPrivate: Bool
    let hover: (Bool) -> Void
    let open: () -> Void
    let close: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(nsImage: icon).resizable().frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(card.appName).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.white.opacity(0.5))
                    Spacer(minLength: 4)
                    if isHovered {
                        Button(action: close) { Image(systemName: "xmark.circle.fill").foregroundStyle(.white.opacity(0.6)) }
                            .buttonStyle(.plain)
                            .help("Ukryj")
                    }
                }
                Text(isPrivate ? "Nowe powiadomienie" : card.title).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                if isPrivate {
                    Label("Treść ukryta — ekran jest udostępniany", systemImage: "eye.slash")
                        .font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.6))
                } else if let line = [card.subtitle, card.body].compactMap({ $0 }).joined(separator: " — ").nilIfEmpty {
                    Text(line).font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.75)).lineLimit(2)
                }
            }
        }
        .padding(.vertical, 6)
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
        .onHover { inside in
            isHovered = inside
            hover(inside)
        }
        .onTapGesture(perform: open)
        .help("Kliknij, żeby otworzyć \(card.appName)")
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

struct NotificationsSettingsView: View {
    @Bindable var module: NotificationsModule

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Chowaj systemowy baner (zostaje w Centrum powiadomień)", isOn: $module.hidesOriginal)
            Picker("Pokazuj przez", selection: $module.durationSeconds) {
                ForEach(NotificationsModule.durations, id: \.self) { Text("\($0) s").tag($0) }
            }
            .fixedSize()
            Text("Przyciski z powiadomień (np. „Odpowiedz”) działają tylko w systemowym banerze — kliknięcie karty otwiera aplikację. "
                 + "Gdy nowa wersja macOS zmieni budowę banerów, moduł przestanie je widzieć, a powiadomienia działają zwyczajnie.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
