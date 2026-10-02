import SwiftUI

/// Widok modułu osobistego: w trybie prywatnym zamiast treści pokazuje wersję prywatną modułu albo zasłonę.
/// Obserwuje stan prywatności, więc przełącza się od razu, także przy rozwiniętej wyspie.
struct PrivacyGate: View {
    let privacy: PrivacyState
    let name: String
    let symbol: String
    let content: AnyView
    let privateContent: AnyView?

    var body: some View {
        if privacy.isActive {
            if let privateContent {
                privateContent
            } else {
                PrivacyCurtain(name: name, symbol: symbol)
            }
        } else {
            content
        }
    }
}

/// Zasłona: nazwa modułu i informacja, że treść jest ukryta.
struct PrivacyCurtain: View {
    let name: String
    let symbol: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "eye.slash").font(.system(size: 18, weight: .medium))
            Text("\(name) — ukryte podczas udostępniania ekranu")
                .font(.system(size: 11))
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.white.opacity(0.5))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}
