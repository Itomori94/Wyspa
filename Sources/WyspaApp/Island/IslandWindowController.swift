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
    private var keyMonitor: Any?
    private var keyObservers: [NSObjectProtocol] = []
    /// Aplikacja, która miała klawiaturę, zanim wyspa ją przejęła (do oddania po zakończeniu pisania).
    private var appBeforeEditing: NSRunningApplication?
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
        applyAppearance()
        model.onOpenSettings = openSettings
        model.onSelectTab = { [weak self] index in self?.selectTab(index) }
        model.onClick = { [weak self] in self?.clicked() }
        model.onOpenActivity = { [weak self] in self?.open(self?.registry.activityModuleID) }
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
        installKeyMonitor()
        observeKeyboardFocus()
        observeModules()
        syncModuleState()
    }

    /// Motyw i przyciemnienie szkła — bez przebudowy okna (suwak działa płynnie).
    func applyAppearance() {
        model.theme = settings.islandTheme
        model.glassTint = settings.glassTint
    }

    func update(screen: ScreenInfo) {
        self.screen = screen
        model.notch = screen.notch
        model.expandedSize = settings.islandSize.expandedSize
        layout()
        // Tryb wirtualnego notcha mógł się zmienić: przelicz fazę spoczynku.
        send(.activityChanged(hasActivity: registry.currentActivity != nil))
        send(.cardChanged(registry.currentActivity?.detail != nil))
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
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        keyObservers.forEach(NotificationCenter.default.removeObserver)
        keyObservers = []
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
            panel.acceptsKeyboard = next.phase == .expanded
            if next.phase != .expanded { model.standaloneModuleID = nil }
            if next.phase == .expanded { registry.privacy.refresh() }
            if previous.phase == .expanded, panel.isKeyWindow { returnKeyboard() }
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
            TrackpadHaptics.shared.perform(settings.hapticStrength)
        }
    }

    private func selectTab(_ index: Int) {
        model.standaloneModuleID = nil
        send(.tabSelected(index))
    }

    /// Kliknięcie zwiniętej wyspy z aktywnością (okładka, timer, Claude) otwiera stronę tego modułu.
    private func clicked() {
        if state.phase != .expanded, !state.hasCard, let moduleID = registry.activityModuleID {
            open(moduleID)
        } else {
            send(.clicked)
        }
    }

    /// Rozwija wyspę na stronie modułu; bez strony w układzie pokazuje jego widok doraźnie (np. zgoda dla Claude).
    func open(_ moduleID: String?) {
        if let moduleID {
            if let index = registry.pageIndex(for: moduleID) {
                model.standaloneModuleID = nil
                send(.tabSelected(index))
            } else if registry.standaloneView(for: moduleID) != nil {
                model.standaloneModuleID = moduleID
            }
        }
        send(.expandRequested)
    }

    private static func config(for screen: ScreenInfo, settings: SettingsStore) -> IslandConfig {
        let hides = !screen.notch.isPhysical && settings.virtualNotchMode == .whenActive
        return settings.islandConfig(hidesWhenIdle: hides)
    }

    // MARK: - Klawiatura

    private func observeKeyboardFocus() {
        let center = NotificationCenter.default
        keyObservers = [
            center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: panel, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    // Panel nie aktywuje aplikacji, więc na pierwszym planie wciąż jest ta, której oddamy klawiaturę.
                    self?.appBeforeEditing = NSWorkspace.shared.frontmostApplication
                    self?.send(.editingChanged(true))
                }
            },
            center.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.editingEnded() }
            },
        ]
        model.onEscape = { [weak self] in
            guard self?.state.phase == .expanded else { return }
            self?.send(.toggleRequested)
        }
    }

    /// Skrót globalny: rozwinięta wyspa od razu przyjmuje klawiaturę (strzałki, pisanie, Enter, Esc).
    /// Panel nie aktywuje Wyspy, więc aplikacja pod spodem zostaje na pierwszym planie i po zwinięciu odzyskuje klawiaturę.
    func toggleWithKeyboard() {
        send(.toggleRequested)
        guard state.phase == .expanded else { return }
        panel.acceptsKeyboard = true
        panel.makeKey()
        // Bez fokusu w polu tekstowym: strzałki zmieniają strony, a pisanie trafia do wyszukiwania schowka.
        panel.makeFirstResponder(nil)
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let handled = MainActor.assumeIsolated { self?.handleKey(event) ?? false }
            return handled ? nil : event
        }
    }

    /// `true` = klawisz obsłużony (nie trafia do pola tekstowego ani dalej).
    private func handleKey(_ event: NSEvent) -> Bool {
        guard event.window === panel, state.phase == .expanded else { return false }
        let flags = event.modifierFlags
        var modifiers: IslandKeyRouter.Modifiers = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        // Edytor pola tekstowego SwiftUI to NSTextView (edytor pola okna).
        let isEditingText = panel.firstResponder is NSTextView
        switch IslandKeyRouter.route(keyCode: event.keyCode, characters: event.characters,
                                     modifiers: modifiers, isEditingText: isEditingText) {
        case .pass:
            return false
        case .collapse:
            send(.toggleRequested)
            return true
        case .stepTab(let step):
            model.standaloneModuleID = nil
            send(.tabStepped(step))
            return true
        case .forward(let key):
            return registry.handleKey(key, moduleIDs: visibleModuleIDs, whileEditingText: isEditingText)
        case .typeToSearch(let text):
            guard let moduleID = registry.typedTextModuleID else { return false }
            // Pełna strona modułu ma pierwszeństwo przed jego widżetem (tam widać pole i wyniki).
            let isShowing = model.standaloneModuleID.map { $0 == moduleID }
                ?? (registry.pageIndex(for: moduleID) == state.selectedTab)
            if !isShowing { open(moduleID) }
            return registry.handleKey(.text(text), moduleIDs: [moduleID])
        }
    }

    /// Moduły widocznej strony (albo moduł pokazany doraźnie).
    private var visibleModuleIDs: [String] {
        if let standalone = model.standaloneModuleID { return [standalone] }
        let pages = registry.pages
        guard !pages.isEmpty else { return [] }
        return pages[min(state.selectedTab, pages.count - 1)].moduleIDs
    }

    private func editingEnded() {
        guard state.isEditing else { return }
        send(.editingChanged(false))
        // Kursor mógł opuścić wyspę w trakcie pisania (zdarzenie zostało wtedy zignorowane).
        if state.phase == .expanded, !container.isPointerOverIsland { send(.pointerExited) }
    }

    /// Oddaje klawiaturę aplikacji, która miała ją przed pisaniem w wyspie.
    private func returnKeyboard() {
        let target = appBeforeEditing ?? NSWorkspace.shared.frontmostApplication
        appBeforeEditing = nil
        if target?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            target?.activate()
        }
    }

    // MARK: - Moduły

    private func observeModules() {
        observeChanges(
            { [weak self] in
                _ = self?.registry.currentActivity
                _ = self?.registry.pages.count
            },
            isActive: { [weak self] in self?.isAlive ?? false },
            onChange: { [weak self] in self?.syncModuleState() }
        )
    }

    private func syncModuleState() {
        let hasActivity = registry.currentActivity != nil
        let tabCount = registry.pages.count
        if hasActivity != state.hasActivity { send(.activityChanged(hasActivity: hasActivity)) }
        let hasCard = registry.currentActivity?.detail != nil
        if hasCard != state.hasCard { send(.cardChanged(hasCard)) }
        if tabCount != state.tabCount { send(.tabCountChanged(tabCount)) }
        updateInteractiveRect()
    }

    // MARK: - Geometria

    private func layout() {
        let size = IslandLayout.panelSize(
            expanded: settings.islandSize.expandedSize, notch: screen.notch.size, shadowMargin: Self.shadowMargin
        )
        panel.setFrame(IslandPlacement.topCentered(size, in: screen.frame), display: true)
        updateInteractiveRect()
    }

    private func updateInteractiveRect() {
        let size = IslandLayout.size(
            for: state.phase,
            notch: screen.notch.size,
            activityWingWidth: registry.currentActivity?.wingWidth,
            activityDetailHeight: registry.currentActivity.flatMap { $0.detail == nil ? nil : $0.detailHeight },
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
        guard event.window === panel, !isOverScrollableContent(event) else { return }
        // Ruch palców: przy „naturalnym” przewijaniu delty już mają kierunek palców.
        let sign: CGFloat = event.isDirectionInvertedFromDevice ? 1 : -1
        let direction = swipeRecognizer.handle(
            phase: Self.scrollPhase(of: event),
            dx: event.scrollingDeltaX * sign,
            dy: event.scrollingDeltaY * sign
        )
        if let direction { send(.swipe(direction)) }
    }

    /// Przewijanie listy (schowek, przypomnienia, notatka) należy do listy, nie do gestu wyspy.
    private func isOverScrollableContent(_ event: NSEvent) -> Bool {
        var view = panel.contentView?.hitTest(event.locationInWindow)
        while let current = view {
            if let scrollView = current as? NSScrollView,
               let document = scrollView.documentView,
               document.frame.height > scrollView.contentView.bounds.height + 1
                || document.frame.width > scrollView.contentView.bounds.width + 1 {
                return true
            }
            view = current.superview
        }
        return false
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
