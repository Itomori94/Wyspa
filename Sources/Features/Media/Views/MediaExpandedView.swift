import AppKit
import SwiftUI
import WyspaUI

struct MediaExpandedView: View {
    let module: MediaModule
    var metrics: PlayerMetrics = .full

    var body: some View {
        if let nowPlaying = module.nowPlaying {
            HStack(alignment: .center, spacing: metrics.spacing) {
                ArtworkView(image: module.artwork, size: metrics.artworkSize, cornerRadius: 16 * metrics.artworkSize / 92)
                    .shadow(color: (module.accent ?? .black).opacity(0.45), radius: 14, y: 4)
                VStack(alignment: .leading, spacing: 8) {
                    TrackInfo(nowPlaying: nowPlaying, module: module)
                    Scrubber(nowPlaying: nowPlaying, accent: module.accent ?? .white, seek: module.seek)
                    Controls(isPlaying: nowPlaying.isPlaying, spacing: metrics.controlSpacing, send: module.send)
                }
            }
            .frame(maxHeight: .infinity)
        } else {
            NothingPlaying(status: module.status, scope: module.scope)
        }
    }
}

private struct TrackInfo: View {
    let nowPlaying: NowPlaying
    let module: MediaModule

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(nowPlaying.title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                Text([nowPlaying.artist, nowPlaying.album].compactMap { $0 }.joined(separator: " — "))
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if module.supportsAirPlay { AirPlayMenu(module: module) }
            AppBadge(bundleIdentifier: nowPlaying.bundleIdentifier)
        }
    }
}

/// Wybór głośników AirPlay Muzyki (jeden lub kilka naraz, jak w samej Muzyce).
private struct AirPlayMenu: View {
    let module: MediaModule

    var body: some View {
        Menu {
            if module.airPlayDevices.isEmpty {
                Text("Brak głośników — sprawdź zgodę na sterowanie Muzyką")
            }
            ForEach(module.airPlayDevices) { device in
                Button {
                    module.toggleAirPlay(device)
                } label: {
                    Label(device.name, systemImage: device.isSelected ? "checkmark" : device.symbol)
                }
                .disabled(!device.isAvailable)
            }
        } label: {
            Image(systemName: "airplayaudio")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(module.airPlayDevices.contains { $0.isSelected && $0.kind.lowercased() != "computer" }
                                 ? Color.accentColor : .white.opacity(0.75))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Głośniki AirPlay")
        .onAppear(perform: module.refreshAirPlay)
        .accessibilityLabel("Głośniki AirPlay")
    }
}

/// Ikona aplikacji, z której pochodzi dźwięk; kliknięcie przenosi do niej.
private struct AppBadge: View {
    let bundleIdentifier: String

    var body: some View {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            Button {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            } label: {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(IslandPressStyle())
            .help(FileManager.default.displayName(atPath: url.path))
        }
    }
}

private struct Scrubber: View {
    let nowPlaying: NowPlaying
    let accent: Color
    let seek: (TimeInterval) -> Void
    @State private var dragFraction: Double?
    @State private var isHovered = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let duration = nowPlaying.duration ?? 0
            let elapsed = nowPlaying.elapsed(at: context.date) ?? 0
            let fraction = dragFraction ?? (duration > 0 ? elapsed / duration : 0)
            VStack(spacing: 4) {
                track(fraction: fraction, enabled: duration > 0, duration: duration)
                HStack {
                    Text(Self.format(fraction * duration))
                    Spacer()
                    Text("−" + Self.format(max(0, duration - fraction * duration)))
                }
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.45))
                .opacity(duration > 0 ? 1 : 0)
            }
        }
    }

    private func track(fraction: Double, enabled: Bool, duration: TimeInterval) -> some View {
        GeometryReader { proxy in
            let height: CGFloat = isHovered || dragFraction != nil ? 7 : 4
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.18))
                Capsule()
                    .fill(accent)
                    .frame(width: max(height, proxy.size.width * min(max(fraction, 0), 1)))
            }
            .frame(height: height)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard enabled else { return }
                    dragFraction = min(max(value.location.x / proxy.size.width, 0), 1)
                }
                .onEnded { _ in
                    if let dragFraction, enabled { seek(dragFraction * duration) }
                    dragFraction = nil
                })
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: height)
        }
        .frame(height: 10)
        .onHover { isHovered = $0 }
        .accessibilityElement()
        .accessibilityLabel("Pozycja odtwarzania")
        .accessibilityValue(Self.format(fraction * duration))
    }

    static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.down))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }
}

private struct Controls: View {
    let isPlaying: Bool
    let spacing: CGFloat
    let send: (MediaCommand) -> Void

    var body: some View {
        HStack(spacing: spacing) {
            ControlButton(symbol: "backward.fill", size: 15, label: "Poprzedni") { send(.previous) }
            ControlButton(symbol: isPlaying ? "pause.fill" : "play.fill", size: 22,
                          label: isPlaying ? "Pauza" : "Odtwarzaj") { send(.togglePlayPause) }
            ControlButton(symbol: "forward.fill", size: 15, label: "Następny") { send(.next) }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ControlButton: View {
    let symbol: String
    let size: CGFloat
    let label: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .contentTransition(.symbolEffect(.replace.downUp))
                .frame(width: 34, height: 30)
                .background(Circle().fill(.white.opacity(isHovered ? 0.14 : 0)).frame(width: 34, height: 34))
        }
        .buttonStyle(IslandPressStyle())
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .accessibilityLabel(label)
    }
}

private struct NothingPlaying: View {
    let status: MediaModule.SourceStatus
    let scope: MediaScope

    var body: some View {
        HStack(spacing: 14) {
            ArtworkView(image: nil, size: 64, cornerRadius: 14)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var title: String {
        switch status {
        case .starting: "Sprawdzanie źródła mediów…"
        case .running: "Nic nie gra"
        case .failed: "Media niedostępne"
        }
    }

    private var detail: String {
        switch status {
        case .starting: "To potrwa kilka sekund."
        case .running(let decision):
            if scope == .appleMusic {
                "Włącz muzykę w Apple Music."
            } else if decision.kind == .adapter {
                "Włącz muzykę, podcast albo film w dowolnej aplikacji."
            } else {
                "Włącz muzykę w Muzyce albo Spotify."
            }
        case .failed(let message): message
        }
    }
}
