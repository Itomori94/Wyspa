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
        summary: "Wycisza wszystkie mikrofony globalnym skrótem (domyślnie ⌃⌥M). Wyciszony mikrofon to czerwona ikona w zwiniętej wyspie.",
        symbol: "mic.fill",
        content: .neutral,
        widgetMinWidth: 120
    )

    public static let defaultShortcut = HotkeyShortcut(keyCode: UInt32(kVK_ANSI_M), modifiers: [.control, .option], keyName: "M")
    /// Ważniejsze niż odtwarzanie i najbliższe spotkanie (wyciszenie liczy się w trakcie rozmowy), mniej ważne niż timer.
    static let wingWidth: CGFloat = 80
    static let mutedPriority = ActivityPriority(52)
    static let toggleAnimationWindow: TimeInterval = 1
    static let toggleFeedback: Duration = .milliseconds(1500)
    private static let shortcutKey = "shortcut"
    private static let volumesKey = "restoreVolumes"
    private static let soundKey = "playsSound"

    /// Dźwięk po przełączeniu skrótem albo kliknięciem: niski przy wyciszeniu, wysoki przy włączeniu (dźwięki systemowe).
    static func soundName(muted: Bool) -> String { muted ? "Bottle" : "Tink" }

    private(set) var reading: MicrophoneControl.Reading?
    public private(set) var shortcut: HotkeyShortcut?
    public private(set) var shortcutProblem: String?
    /// Dźwięk przy wyciszeniu i włączeniu mikrofonu (domyślnie włączony).
    public var playsSound: Bool { didSet { context.settings.set(playsSound, for: Self.soundKey) } }
    /// Krótki komunikat po przełączeniu („Mikrofon wyciszony”) — także przy niewyciszonym mikrofonie.
    public var feedback: String? { message.text }

    @ObservationIgnored private var mutedChangedAt: Date?
    /// Czy użytkownik chce mieć wyciszone — niezależnie od tego, które wejście jest akurat domyślne.
    @ObservationIgnored private var wantsMuted = false
    @ObservationIgnored private let context: ModuleContext
    @ObservationIgnored private var control: MicrophoneControl?
    @ObservationIgnored private var hotkey: GlobalHotkey?
    @ObservationIgnored private let message = TransientMessage()

    public required init(context: ModuleContext) {
        self.context = context
        shortcut = context.settings.value(Self.shortcutKey, default: StoredShortcut(shortcut: Self.defaultShortcut)).shortcut
        playsSound = context.settings.value(Self.soundKey, default: true)
    }

    public func activate() async throws {
        let control = MicrophoneControl(onChange: { [weak self] in self?.refresh() },
                                        onDevicesChanged: { [weak self] in self?.muteNewInputs() })
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
            ToggleSymbol(on: "mic.slash.fill", off: "mic.fill", isOn: muted, animatesAppearance: justToggled)
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
        guard setAllMuted(!current.isMuted) else {
            show("Nie udało się przełączyć mikrofonu")
            return
        }
        refresh()
        let muted = reading?.isMuted == true
        show(muted ? "Wyciszony" : "Włączony")
        if playsSound { NSSound(named: Self.soundName(muted: muted))?.play() }
    }

    /// Wycisza albo włącza wszystkie wejścia; głośności sprzed wyciszenia zapamiętane per urządzenie.
    private func setAllMuted(_ muted: Bool) -> Bool {
        guard let control else { return false }
        let volumes: [String: Float] = context.settings.value(Self.volumesKey, default: [:])
        let outcome = control.setMuted(muted, restoreVolumes: volumes)
        if !outcome.volumesToRemember.isEmpty {
            context.settings.set(volumes.merging(outcome.volumesToRemember) { _, new in new }, for: Self.volumesKey)
        }
        return outcome.succeeded
    }

    /// Mikrofon podłączony w trakcie wyciszenia (np. AirPods w środku rozmowy) też ma być wyciszony.
    private func muteNewInputs() {
        guard wantsMuted else { return }
        _ = setAllMuted(true)
    }

    /// Podpis w widżecie: jeden mikrofon z nazwy, kilka — „Wszystkie mikrofony (3)”.
    nonisolated static func devicesLabel(name: String, count: Int) -> String {
        count > 1 ? "Wszystkie mikrofony (\(count))" : name
    }

    private func refresh() {
        let previous = reading
        reading = control?.reading
        if previous == nil || previous?.deviceUIDs == reading?.deviceUIDs {
            // Te same mikrofony: zmiana wyciszenia (także z Ustawień systemowych) to nowa intencja.
            wantsMuted = reading?.isMuted ?? false
        } else if wantsMuted, reading?.isMuted == false, setAllMuted(true) {
            // Nowy mikrofon w trakcie wyciszenia (np. podłączone AirPods) — też wyciszony.
            reading = control?.reading
        }
        if let previous, previous.isMuted != reading?.isMuted { mutedChangedAt = Date() }
    }

    /// Wyciszenie zmieniło się przed chwilą — tylko wtedy ikona rysuje albo zmazuje kreskę przy pojawieniu się.
    private var justToggled: Bool {
        mutedChangedAt.map { Date().timeIntervalSince($0) < Self.toggleAnimationWindow } ?? false
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
        reading = MicrophoneControl.Reading(inputs: [
            MicrophoneControl.Input(uid: "demo", name: "Mikrofon MacBooka Pro", isDefault: true, isMuted: muted, canMute: true),
        ])
    }
}
#endif
