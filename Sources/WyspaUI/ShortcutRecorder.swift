import AppKit
import SwiftUI
import WyspaCore

/// Pole nagrywania skrótu: kliknij, naciśnij kombinację; Esc anuluje, ⌫ usuwa skrót.
public struct ShortcutRecorder: View {
    @Binding var shortcut: HotkeyShortcut?

    public init(shortcut: Binding<HotkeyShortcut?>) {
        _shortcut = shortcut
    }
    @State private var isRecording = false
    @State private var hint: String?
    @State private var monitor: Any?

    public var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 6) {
                Button(action: toggleRecording) {
                    Text(label)
                        .monospaced()
                        .frame(minWidth: 110)
                }
                .buttonStyle(.bordered)
                .tint(isRecording ? .accentColor : nil)
                if shortcut != .defaultToggle {
                    Button("Domyślny") { shortcut = .defaultToggle }
                        .buttonStyle(.link)
                }
            }
            if let hint {
                Text(hint).font(.caption).foregroundStyle(.secondary)
            }
        }
        .onDisappear(perform: stopRecording)
    }

    private var label: String {
        if isRecording { return "Naciśnij skrót…" }
        return shortcut?.displayString ?? "Brak"
    }

    private func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        isRecording = true
        hint = "Esc anuluje, ⌫ usuwa skrót"
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated { handle(event) }
            return nil
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
    }

    private func handle(_ event: NSEvent) {
        let plain = ShortcutModifiers(event.modifierFlags).isEmpty
        switch Int(event.keyCode) {
        case 53 where plain: // Esc
            hint = nil
            stopRecording()
        case 51 where plain, 117 where plain: // ⌫, ⌦
            shortcut = nil
            hint = nil
            stopRecording()
        default:
            guard let recorded = HotkeyShortcut(event: event) else {
                hint = "Dodaj ⌃, ⌥ albo ⌘"
                return
            }
            shortcut = recorded
            hint = nil
            stopRecording()
        }
    }
}
