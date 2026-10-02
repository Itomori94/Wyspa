import AppKit
import Carbon.HIToolbox
import SwiftUI
import WyspaCore

/// Wyciszanie mikrofonu globalnym skrótem; wyciszony mikrofon to czerwona ikona w zwiniętej wyspie.
@MainActor
@Observable
public final class MicrophoneModule: IslandModule {
    public static let descriptor = ModuleDescriptor(
        id: "microphone",
        name: "Mikrofon",
        summary: "Wycisza mikrofon globalnym skrótem (domyślnie ⌃⌥M). Wyciszony mikrofon to czerwona ikona w zwiniętej wyspie.",
        symbol: "mic.fill",
        content: .neutral,
        widgetMinWidth: 120
    )

    public static let defaultShortcut = HotkeyShortcut(keyCode: UInt32(kVK_ANSI_M), modifiers: [.control, .option], keyName: "M")
    /// Ważniejsze niż odtwarzanie i najbliższe spotkanie (wyciszenie liczy się w trakcie rozmowy), mniej ważne niż timer.
    static let mutedPriority = ActivityPriority(52)
    static let toggleFeedback: Duration = .milliseconds(1500)
    private static let shortcutKey = "shortcut"
    private static let volumesKey = "restoreVolumes"

    private(set) var reading: MicrophoneControl.Reading?
    public private(set) var shortcut: HotkeyShortcut?
    public private(set) var shortcutProblem: String?
    /// Krótki komunikat po przełączeniu („Mikrofon wyciszony”) — także przy niewyciszonym mikrofonie.
    public private(set) var feedback: String?

    @ObservationIgnored private let context: ModuleContext
    @ObservationIgnored private var control: MicrophoneControl?
    @ObservationIgnored private var hotkey: GlobalHotkey?
    @ObservationIgnored private var feedbackTask: Task<Void, Never>?

    public required init(context: ModuleContext) {
        self.context = context
        shortcut = context.settings.value(Self.shortcutKey, default: StoredShortcut(shortcut: Self.defaultShortcut)).shortcut
    }

    public func activate() async throws {
        let control = MicrophoneControl { [weak self] in self?.refresh() }
        control.start()
        self.control = control
        refresh()
        registerHotkey()
    }

    public func deactivate() {
        hotkey = nil
        control?.stop()
        control = nil
        feedbackTask?.cancel()
        reading = nil
        feedback = nil
    }

    public var liveActivity: LiveActivity? {
        if let feedback {
            let muted = reading?.isMuted ?? false
            return LiveActivity(id: "microphone.feedback", priority: .alert, accent: muted ? .red : .green, wingWidth: 80) {
                Image(systemName: muted ? "mic.slash.fill" : "mic.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(muted ? .red : .green)
            } trailing: {
                Text(feedback).font(.system(size: 11, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        guard reading?.isMuted == true else { return nil }
        return LiveActivity(id: "microphone.muted", priority: Self.mutedPriority, accent: .red) {
            Image(systemName: "mic.slash.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.red)
        } trailing: {
            Circle().fill(.red).frame(width: 7, height: 7)
        }
    }

    public func makeExpandedView() -> AnyView? { AnyView(MicrophoneView(module: self)) }
    public func makeWidgetView() -> AnyView? { AnyView(MicrophoneView(module: self)) }
    public func makeSettingsView() -> AnyView? { AnyView(MicrophoneSettingsView(module: self)) }

    // MARK: - Wyciszanie

    func toggle() {
        guard let control, let current = control.reading else {
            show("Brak mikrofonu")
            return
        }
        guard current.canMute else {
            show("Tego mikrofonu nie da się wyciszyć")
            return
        }
        var volumes: [String: Float] = context.settings.value(Self.volumesKey, default: [:])
        let outcome = control.setMuted(!current.isMuted, restoreVolume: volumes[current.deviceUID])
        guard outcome.succeeded else {
            show("Nie udało się przełączyć mikrofonu")
            return
        }
        if let remember = outcome.volumeToRemember {
            volumes[current.deviceUID] = remember
            context.settings.set(volumes, for: Self.volumesKey)
        }
        refresh()
        show(reading?.isMuted == true ? "Wyciszony" : "Włączony")
    }

    private func refresh() {
        reading = control?.reading
    }

    private func show(_ message: String) {
        withAnimation { feedback = message }
        feedbackTask?.cancel()
        feedbackTask = Task { [weak self] in
            try? await Task.sleep(for: Self.toggleFeedback)
            guard !Task.isCancelled else { return }
            withAnimation { self?.feedback = nil }
        }
    }

    // MARK: - Skrót

    func setShortcut(_ newValue: HotkeyShortcut?) {
        shortcut = newValue
        context.settings.set(StoredShortcut(shortcut: newValue), for: Self.shortcutKey)
        registerHotkey()
    }

    private func registerHotkey() {
        hotkey = nil
        shortcutProblem = nil
        guard let shortcut else { return }
        let hotkey = GlobalHotkey { [weak self] in self?.toggle() }
        do {
            try hotkey.register(shortcut)
            self.hotkey = hotkey
        } catch {
            shortcutProblem = error.message
        }
    }
}

/// Zapis skrótu z rozróżnieniem „brak skrótu” od „nigdy nie ustawiony” (wtedy domyślny).
struct StoredShortcut: Codable, Equatable {
    let shortcut: HotkeyShortcut?
}

#if DEBUG
extension MicrophoneModule {
    /// Dane demonstracyjne do zrzutów ekranu w README (tylko build debug).
    func showDemo(muted: Bool) {
        reading = MicrophoneControl.Reading(deviceUID: "demo", deviceName: "Mikrofon MacBooka Pro", isMuted: muted, canMute: true)
    }
}
#endif
