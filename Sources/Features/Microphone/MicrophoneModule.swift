import AppKit
import Carbon.HIToolbox
import SwiftUI
import WyspaCore
import WyspaUI

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
    static let wingWidth: CGFloat = 80
    static let mutedPriority = ActivityPriority(52)
    static let toggleFeedback: Duration = .milliseconds(1500)
    private static let shortcutKey = "shortcut"
    private static let volumesKey = "restoreVolumes"

    private(set) var reading: MicrophoneControl.Reading?
    public private(set) var shortcut: HotkeyShortcut?
    public private(set) var shortcutProblem: String?
    /// Krótki komunikat po przełączeniu („Mikrofon wyciszony”) — także przy niewyciszonym mikrofonie.
    public var feedback: String? { message.text }

    @ObservationIgnored private let context: ModuleContext
    @ObservationIgnored private var control: MicrophoneControl?
    @ObservationIgnored private var hotkey: GlobalHotkey?
    @ObservationIgnored private let message = TransientMessage()

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
        message.clear()
        reading = nil
    }

    /// Jedna aktywność o stałej szerokości dla komunikatu po przełączeniu i dla stałego wyciszenia — ikona zostaje
    /// w tym samym miejscu, a zmienia się tylko jej stan (kreska rysuje się albo zmazuje).
    public var liveActivity: LiveActivity? {
        let muted = reading?.isMuted ?? false
        guard feedback != nil || muted else { return nil }
        let priority = feedback != nil ? ActivityPriority.alert : Self.mutedPriority
        return LiveActivity(id: "microphone", priority: priority, accent: muted ? .red : .green, wingWidth: Self.wingWidth) {
            ToggleSymbol(on: "mic.slash.fill", off: "mic.fill", isOn: muted)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(muted ? .red : .green)
        } trailing: {
            Text(feedback ?? "Wyciszony")
                .font(.system(size: 11, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                .foregroundStyle(muted ? .red : .white.opacity(0.85))
                .contentTransition(.opacity)
                .animation(.snappy, value: feedback)
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

    private func show(_ text: String) {
        message.show(text, for: Self.toggleFeedback)
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
