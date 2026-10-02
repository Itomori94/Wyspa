import SwiftUI
import WyspaUI

struct QuickActionsView: View {
    let module: QuickActionsModule
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: compact ? 2 : 4)
            LazyVGrid(columns: columns, spacing: 8) {
                ActionTile(symbol: "camera.viewfinder", title: "Zrzut na Półkę", tint: .blue, compact: compact,
                           action: module.captureToShelf)
                ActionTile(symbol: "eyedropper", title: "Pipeta koloru", tint: .pink, compact: compact,
                           action: module.pickColor)
                ActionTile(symbol: "lock.fill", title: "Zablokuj ekran", tint: .gray, compact: compact,
                           action: module.lockScreen)
                ActionTile(symbol: module.isKeepingAwake ? "cup.and.saucer.fill" : "cup.and.saucer",
                           title: module.isKeepingAwake ? "Nie usypia" : "Nie usypiaj", tint: .orange, compact: compact,
                           isOn: module.isKeepingAwake, action: module.toggleKeepAwake)
            }
            if let feedback = module.feedback {
                Text(feedback)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct ActionTile: View {
    let symbol: String
    let title: String
    let tint: Color
    let compact: Bool
    var isOn = false
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: compact ? 3 : 6) {
                Image(systemName: symbol)
                    .font(.system(size: compact ? 15 : 20, weight: .semibold))
                    .foregroundStyle(isOn ? .black : tint)
                    .frame(height: compact ? 18 : 24)
                Text(title)
                    .font(.system(size: compact ? 9.5 : 11, weight: .medium))
                    .foregroundStyle(isOn ? .black : .white.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, compact ? 6 : 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isOn ? tint : .white.opacity(isHovered ? 0.14 : 0.07))
            )
        }
        .buttonStyle(IslandPressStyle())
        .onHover { isHovered = $0 }
        .accessibilityLabel(title)
    }
}
