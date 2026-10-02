import SwiftUI
import WyspaCore
import WyspaUI

struct DownloadsView: View {
    let module: DownloadsModule

    var body: some View {
        if module.items.isEmpty {
            Label("Nic się nie pobiera", systemImage: "arrow.down.circle")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.5))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(module.items) { item in
                        Button { module.reveal(item) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(item.displayName).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                    Spacer()
                                    Text(ProgressSummary.percentText(item.fraction))
                                        .font(.system(size: 11, weight: .semibold)).monospacedDigit()
                                        .foregroundStyle(.white.opacity(0.6))
                                }
                                if let fraction = item.fraction {
                                    ProgressView(value: fraction).tint(.blue)
                                } else {
                                    ProgressView().progressViewStyle(.linear).tint(.blue)
                                }
                            }
                            .foregroundStyle(.white)
                        }
                        .buttonStyle(IslandPressStyle())
                        .help("Pokaż w Finderze")
                    }
                }
            }
        }
    }
}

struct DownloadsSettingsView: View {
    @Bindable var module: DownloadsModule

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Po zakończeniu odkładaj plik na Półkę", isOn: $module.addsToShelf)
            Text("Działa z Safari, Chrome i innymi przeglądarkami, które pokazują postęp na ikonie pliku w Finderze. "
                 + "Na Półkę trafia odnośnik do pliku w Pobranych (wymaga włączonej Półki).")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
