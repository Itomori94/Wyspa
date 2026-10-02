import SwiftUI
import WyspaUI

struct DownloadRing: View {
    let fraction: Double?

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.2), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: fraction ?? 0.25)
                .stroke(Color.blue, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.3), value: fraction)
            Image(systemName: "arrow.down").font(.system(size: 8, weight: .bold)).foregroundStyle(.white)
        }
        .frame(width: 16, height: 16)
    }
}

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
                                    Text(DownloadSummary.percentText(item.fraction))
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
