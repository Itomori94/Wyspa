import SwiftUI
import WyspaUI

/// Widżet odtwarzacza: przy dużej szerokości pełny odtwarzacz (jak na osobnej stronie),
/// w wąskim miejscu wersja kompaktowa.
struct MediaWidget: View {
    let module: MediaModule

    var body: some View {
        // Decyduje faktyczna szerokość widżetu (szerokość idealna rośnie z długością tytułu).
        GeometryReader { proxy in
            if let metrics = PlayerMetrics.forWidth(proxy.size.width) {
                MediaExpandedView(module: module, metrics: metrics)
            } else {
                CompactMediaWidget(module: module)
            }
        }
    }
}

/// Kompaktowy odtwarzacz: okładka, tytuł, wykonawca, cienki pasek postępu i sterowanie.
private struct CompactMediaWidget: View {
    let module: MediaModule

    var body: some View {
        if let nowPlaying = module.nowPlaying {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    ArtworkView(image: module.artwork, size: 46, cornerRadius: 10)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(nowPlaying.title).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                        Text(nowPlaying.artist ?? "").font(.system(size: 11)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                    }
                }
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let duration = nowPlaying.duration ?? 0
                    let fraction = duration > 0 ? (nowPlaying.elapsed(at: context.date) ?? 0) / duration : 0
                    Capsule().fill(.white.opacity(0.15)).frame(height: 3)
                        .overlay(alignment: .leading) {
                            GeometryReader { proxy in
                                Capsule().fill(module.accent ?? .white).frame(width: proxy.size.width * fraction)
                            }
                        }
                }
                HStack(spacing: 0) {
                    WidgetControl(symbol: "backward.fill", size: 13) { module.send(.previous) }
                    WidgetControl(symbol: nowPlaying.isPlaying ? "pause.fill" : "play.fill", size: 18) { module.send(.togglePlayPause) }
                    WidgetControl(symbol: "forward.fill", size: 13) { module.send(.next) }
                }
            }
        } else {
            VStack(spacing: 6) {
                ArtworkView(image: nil, size: 40, cornerRadius: 10)
                Text("Nic nie gra").font(.system(size: 11.5, weight: .medium)).foregroundStyle(.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct WidgetControl: View {
    let symbol: String
    let size: CGFloat
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .frame(maxWidth: .infinity, minHeight: 28)
                .background(Capsule().fill(.white.opacity(isHovered ? 0.12 : 0)))
        }
        .buttonStyle(IslandPressStyle())
        .onHover { isHovered = $0 }
    }
}
