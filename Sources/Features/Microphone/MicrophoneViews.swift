import SwiftUI
import WyspaCore
import WyspaUI

struct MicrophoneView: View {
    let module: MicrophoneModule

    var body: some View {
        let muted = module.reading?.isMuted ?? false
        Button { module.toggle() } label: {
            VStack(spacing: 6) {
                Image(systemName: muted ? "mic.slash.fill" : "mic.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(muted ? .red : .white)
                    .frame(width: 54, height: 54)
                    .background(Circle().fill(muted ? Color.red.opacity(0.18) : Color.white.opacity(0.1)))
                    .symbolSwapTransition()
                    .animation(.snappy, value: muted)
                Text(muted ? "Wyciszony" : "Włączony")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(muted ? .red : .white)
                Text(module.reading?.deviceName ?? "Brak mikrofonu")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
                if let shortcut = module.shortcut {
                    Text(shortcut.displayString)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.35))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(IslandPressStyle())
        .disabled(module.reading?.canMute == false)
        .help(muted ? "Włącz mikrofon" : "Wycisz mikrofon")
    }
}

struct MicrophoneSettingsView: View {
    let module: MicrophoneModule

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LabeledContent("Wycisz / włącz mikrofon") {
                ShortcutRecorder(shortcut: Binding(get: { module.shortcut }, set: { module.setShortcut($0) }))
            }
            if let problem = module.shortcutProblem {
                Text(problem).font(.caption).foregroundStyle(.orange)
            }
            if let reading = module.reading, !reading.canMute {
                Text("„\(reading.deviceName)” nie pozwala się wyciszyć ani zmienić głośności wejścia.")
                    .font(.caption).foregroundStyle(.orange)
            }
            Text("Wyciszenie działa dla domyślnego wejścia z Ustawień systemowych → Dźwięk. Gdy mikrofon nie ma "
                 + "przełącznika wyciszenia, Wyspa ustawia głośność wejścia na zero i przywraca ją po włączeniu. "
                 + "Wyspa nie słucha dźwięku z mikrofonu.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
