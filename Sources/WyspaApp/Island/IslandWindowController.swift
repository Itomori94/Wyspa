import AppKit
import SwiftUI
import WyspaCore
import WyspaUI

/// Jedna wyspa na jednym ekranie: panel, maszyna stanów, opóźnienia, gesty i haptyka.
@MainActor
final class IslandWindowController {
    static let shadowMargin: CGFloat = 36

    private(set) var screen: ScreenInfo
    private let settings: SettingsStore
    private let registry: ModuleRegistry
    private let panel = IslandPanel()
    private let model: IslandViewModel
    private let container: IslandContainerView

    private var state: IslandState
    private var timers: [IslandTimer: Task<Void, Never>] = [:]
    private var swipeRecognizer = SwipeRecognizer()
    private var scrollMonitor: Any?
    private var isAlive = true

    init(screen: ScreenInfo, settings: SettingsStore, registry: ModuleRegistry, openSettings: @escaping () -> Void) {
        self.screen = screen
        self.settings = settings
        self.registry = registry
        let config = Self.config(for: screen, settings: settings)
        state = IslandState.initial(config: config)
        model = IslandViewModel(
            phase: state.phase,
            notch: screen.notch,
            expandedSize: settings.islandSize.expandedSize,
            registry: registry
        )
        container = IslandContainerView(content: IslandView(model: model))
        model.onOpenSettings = openSettings
        model.onSelectTab = { [weak self] index in self?.selectTab(index) }
        model.onClick = { [weak self] in self?.send(.clicked) }
        model.onDragEntered = { [weak self] in
            self?.send(.dragEntered(preferredTab: self?.registry.dropTabIndex))
        }
        model.onDragExited = { [weak self] in self?.send(.dragExited) }
        model.onDropFinished = { [weak self] in self?.container.resyncPointer() }

        panel.contentView = container
        container.onPointerEntered = { [weak self] in self?.send(.pointerEntered) }
        container.onPointerExited = { [weak self] in self?.send(.pointerExited) }

        layout()
        panel.orderFrontRegardless()
        installScrollMonitor()
        observeModules()
        syncModuleState()
    }

    func update(screen: ScreenInfo) {
        self.screen = screen
        model.notch = screen.notch
        model.expandedSize = settings.islandSize.expandedSize
        layout()
        // Tryb wirtualnego notcha mógł się zmienić: przelicz fazę spoczynku.
        send(.activityChanged(hasActivity: registry.currentActivity != nil))
    }

    func send(_ event: IslandEvent) {
        let config = Self.config(for: screen, settings: settings)
        let (next, effects) = IslandStateMachine.reduce(state, event, config: config)
        effects.forEach(perform)
        apply(next)
    }

    func close() {
        isAlive = false
        timers.values.forEach { $0.cancel() }
        timers = [:]
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
        scrollMonitor = nil
        panel.orderOut(nil)
        panel.close()
    }

    // MARK: - Stan

    private func apply(_ next: IslandState) {
        let previous = state
        state = next
        if next.phase != previous.phase {
            withAnimation(IslandMotion.animation(to: next.phase)) {
                model.phase = next.phase
            }
        }
        if next.selectedTab != model.selectedTab {
            model.selectedTab = next.selectedTab
        }
        updateInteractiveRect()
    }

    private func perform(_ effect: IslandEffect) {
        switch effect {
        case .schedule(let timer, let delay):
            timers[timer]?.cancel()
            timers[timer] = Task { [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                self?.timers[timer] = nil
                self?.send(.timerFired(timer))
            }
        case .cancel(let timer):
            timers[timer]?.cancel()
            timers[timer] = nil
        case .haptic:
            guard settings.hapticsEnabled else { return }
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }
    }

    private func selectTab(_ index: Int) {
        send(.tabSelected(index))
    }

    private static func config(for screen: ScreenInfo, settings: SettingsStore) -> IslandConfig {
        let hides = !screen.notch.isPhysical && settings.virtualNotchMode == .whenActive
        return settings.islandConfig(hidesWhenIdle: hides)
    }

    // MARK: - Moduły

    private func observeModules() {
        observeChanges(
            { [weak self] in
                _ = self?.registry.currentActivity
                _ = self?.registry.tabs.count
            },
            isActive: { [weak self] in self?.isAlive ?? false },
            onChange: { [weak self] in self?.syncModuleState() }
        )
    }

    private func syncModuleState() {
        let hasActivity = registry.currentActivity != nil
        let tabCount = registry.tabs.count
        if hasActivity != state.hasActivity { send(.activityChanged(hasActivity: hasActivity)) }
        if tabCount != state.tabCount { send(.tabCountChanged(tabCount)) }
        updateInteractiveRect()
    }

    // MARK: - Geometria

    private func layout() {
        let size = IslandLayout.panelSize(expanded: settings.islandSize.expandedSize, shadowMargin: Self.shadowMargin)
        panel.setFrame(IslandPlacement.topCentered(size, in: screen.frame), display: true)
        updateInteractiveRect()
    }

    private func updateInteractiveRect() {
        let size = IslandLayout.size(
            for: state.phase,
            notch: screen.notch.size,
            hasActivity: registry.currentActivity != nil,
            expanded: settings.islandSize.expandedSize
        )
        let bounds = container.bounds
        container.interactiveRect = CGRect(
            x: bounds.midX - size.width / 2,
            y: bounds.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    // MARK: - Gesty

    private func installScrollMonitor() {
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            MainActor.assumeIsolated { self?.handleScroll(event) }
            return event
        }
    }

    private func handleScroll(_ event: NSEvent) {
        guard event.window === panel else { return }
        // Ruch palców: przy „naturalnym” przewijaniu delty już mają kierunek palców.
        let sign: CGFloat = event.isDirectionInvertedFromDevice ? 1 : -1
        let direction = swipeRecognizer.handle(
            phase: Self.scrollPhase(of: event),
            dx: event.scrollingDeltaX * sign,
            dy: event.scrollingDeltaY * sign
        )
        if let direction { send(.swipe(direction)) }
    }

    private static func scrollPhase(of event: NSEvent) -> TrackpadPhase {
        guard event.momentumPhase.isEmpty else { return .other }
        switch event.phase {
        case .began: return .began
        case .changed: return .changed
        case .ended: return .ended
        case .cancelled: return .cancelled
        default: return .other
        }
    }
}
