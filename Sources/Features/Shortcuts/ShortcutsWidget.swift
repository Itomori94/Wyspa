import SwiftUI
import WyspaUI

/// Pierwsze ulubione skróty jako przyciski.
struct ShortcutsWidget: View {
    let module: ShortcutsModule

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("SKRÓTY").font(.system(size: 9.5, weight: .bold)).foregroundStyle(.white.opacity(0.45))
            ForEach(module.visible.prefix(4), id: \.self) { name in
                Button { module.run(name) } label: {
                    HStack(spacing: 6) {
                        Group {
                            if module.states[name] == .running {
                                ProgressView().controlSize(.mini)
                            } else {
                                Image(systemName: module.states[name] == .succeeded ? "checkmark" : "play.fill")
                                    .font(.system(size: 9))
                            }
                        }
                        .frame(width: 12)
                        Text(name).font(.system(size: 11.5, weight: .medium)).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(RoundedRectangle(cornerRadius: 7).fill(.white.opacity(0.08)))
                }
                .buttonStyle(IslandPressStyle())
            }
            if module.visible.isEmpty {
                Text("Brak skrótów").font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.45))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
