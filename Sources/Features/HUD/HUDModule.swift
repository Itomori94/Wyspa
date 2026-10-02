import AppKit
import SwiftUI
import WyspaCore

/// Zamiennik systemowego HUD głośności, jasności i podświetlenia klawiatury, rysowany w wyspie.
@MainActor
@Observable
public final class HUDModule: IslandModule {
    public static let descriptor = ModuleDescriptor(
        id: "hud",
        name: "HUD głośności i jasności",
        summary: "Zamiast systemowego okienka pokazuje głośność, jasność ekranu i podświetlenie klawiatury w wyspie.",
        symbol: "speaker.wave.2.fill",
        content: .neutral,
        permissions: [.accessibility],
        providesPage: false
    )

    static let displayDuration: Duration = .milliseconds(1600)
    private static let wingWidth: CGFloat = 46
    /// Wysokość paska pod notchem: jeden pasek na środku ekranu, nie przecięty notchem.
    private static let barHeight: CGFloat = 20

    public private(set) var reading: HUDReading?
    public private(set) var hasBrightnessControl = false
    public private(set) var hasKeyboardControl = false

    /// Które rodzaje klawiszy przechwytywać (wybór użytkownika).
    public var enabledKinds: Set<HUDKind> {
        didSet { context.settings.set(enabledKinds.map(\.rawValue).sorted(), for: Self.kindsKey) }
    }

    @ObservationIgnored private static let kindsKey = "enabledKinds"
    @ObservationIgnored private let context: ModuleContext
    @ObservationIgnored private let volume = VolumeControl()
    @ObservationIgnored private var brightness: DisplayBrightnessControl?
    @ObservationIgnored private var keyboard: KeyboardBacklightControl?
    @ObservationIgnored private var tap: MediaKeyTap?
    @ObservationIgnored private var hideTask: Task<Void, Never>?

    public required init(context: ModuleContext) {
        self.context = context
        let stored = context.settings.value(Self.kindsKey, default: HUDKind.allCases.map(\.rawValue))
        enabledKinds = Set(stored.compactMap(HUDKind.init))
    }

    public func activate() async throws {
        brightness = DisplayBrightnessControl.make()
        keyboard = KeyboardBacklightControl.make()
        hasBrightnessControl = brightness != nil
        hasKeyboardControl = keyboard != nil
        let tap = MediaKeyTap { [weak self] event, modifiers in
            self?.handle(event, modifiers: modifiers) ?? false
        }
        try tap.start()
        self.tap = tap
    }

    public func deactivate() {
        tap?.stop()
        tap = nil
        hideTask?.cancel()
        hideTask = nil
        reading = nil
        brightness = nil
        keyboard = nil
    }

    public var liveActivity: LiveActivity? {
        guard let reading else { return nil }
        return LiveActivity(id: "hud", priority: .hud, wingWidth: Self.wingWidth, detailHeight: Self.barHeight) {
            HUDIcon(reading: reading)
        } trailing: {
            HUDPercent(reading: reading)
        } detail: {
            HUDLevelBar(reading: reading)
        }
    }

    /// HUD nie ma własnej zakładki: pojawia się tylko w zwiniętej wyspie.
    public func makeExpandedView() -> AnyView? { nil }

    public func makeSettingsView() -> AnyView? {
        AnyView(HUDSettingsView(module: self))
    }

    // MARK: - Klawisze

    private var capabilities: HUDCapabilities {
        HUDCapabilities(
            volume: enabledKinds.contains(.volume) && volume.canControl,
            brightness: enabledKinds.contains(.brightness) && brightness != nil,
            keyboard: enabledKinds.contains(.keyboard) && keyboard != nil
        )
    }

    private func handle(_ event: MediaKeyEvent, modifiers: HUDKeyRouter.Modifiers) -> Bool {
        let action = HUDKeyRouter.route(event, modifiers: modifiers, capabilities: capabilities)
        switch action {
        case .passThrough:
            return false
        case .swallow:
            return true
        case .toggleMute:
            return show(volume.toggleMute())
        case .toggleKeyboardBacklight:
            return show(keyboard?.toggle())
        case .adjust(let kind, let up, let size):
            return show(adjust(kind, up: up, size: size))
        }
    }

    private func adjust(_ kind: HUDKind, up: Bool, size: StepSize) -> HUDReading? {
        switch kind {
        case .volume:
            guard let current = volume.reading() else { return nil }
            // Głośność w górę przy wyciszeniu zaczyna od bieżącego poziomu i zdejmuje wyciszenie.
            let base = current.isMuted && !up ? 0 : current.level
            return volume.set(level: LevelStepper.step(base, up: up, size: size))
        case .brightness:
            guard let brightness, let current = brightness.reading() else { return nil }
            return brightness.set(level: LevelStepper.step(current.level, up: up, size: size))
        case .keyboard:
            guard let keyboard else { return nil }
            return keyboard.set(level: LevelStepper.step(keyboard.reading().level, up: up, size: size))
        }
    }

    /// Pokazuje odczyt w wyspie; gdy zmiana się nie udała, zdarzenie wraca do systemu.
    private func show(_ newReading: HUDReading?) -> Bool {
        guard let newReading else { return false }
        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
            reading = newReading
        }
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: Self.displayDuration)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) { self?.reading = nil }
        }
        return true
    }
}

#if DEBUG
extension HUDModule {
    /// Dane demonstracyjne do zrzutów ekranu w README (tylko build debug).
    func showDemo(_ demo: HUDReading) {
        reading = demo
    }
}
#endif
