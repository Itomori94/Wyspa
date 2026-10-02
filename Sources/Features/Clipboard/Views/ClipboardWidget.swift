import SwiftUI

/// Ostatnie wpisy schowka (przypięte pierwsze); kliknięcie wkleja albo kopiuje.
struct ClipboardWidget: View {
    let module: ClipboardModule

    var body: some View {
        // Wyniki pisania z klawiatury (gdy schowek nie ma pełnej strony) widać też w widżecie.
        let entries = Array(module.history.matching(module.query).prefix(4))
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text("SCHOWEK").font(.system(size: 9.5, weight: .bold)).foregroundStyle(.white.opacity(0.45))
                if !module.query.isEmpty {
                    Text(module.query).font(.system(size: 9.5, weight: .semibold)).foregroundStyle(.white.opacity(0.8)).lineLimit(1)
                }
            }
            if entries.isEmpty {
                Text(module.query.isEmpty ? "Skopiuj coś" : "Nic nie pasuje").font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.45))
            }
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                Button { module.choose(entry) } label: {
                    HStack(spacing: 4) {
                        if entry.isPinned {
                            Image(systemName: "pin.fill").font(.system(size: 8)).foregroundStyle(.orange)
                        }
                        Text(entry.searchableText.replacingOccurrences(of: "\n", with: " "))
                            .font(.system(size: 11.5))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(index == module.selectedIndex ? 0.16 : 0.06)))
                }
                .buttonStyle(.plain)
                .help(module.pastesOnClick ? "Kliknij, żeby wkleić do aktywnej aplikacji" : "Kliknij, żeby skopiować ponownie")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
