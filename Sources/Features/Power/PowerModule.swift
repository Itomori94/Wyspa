import IOKit.ps
import SwiftUI
import WyspaCore

/// Zasilanie: podłączenie ładowarki, pełne naładowanie, niski poziom baterii; zakładka ze stanem baterii.
@MainActor
@Observable
public final class PowerModule: IslandModule {
    public static let descriptor = ModuleDescriptor(
        id: "power",
        name: "Zasilanie",
        summary: "Pokazuje podłączenie ładowarki, pełne naładowanie i niski poziom baterii.",
        symbol: "battery.100percent.bolt",
        content: .neutral,
        widgetMinWidth: 90
    )

    static let eventDuration: Duration = .seconds(3)

    public private(set) var state: PowerState?
    public private(set) var event: PowerEvent?

    @ObservationIgnored private var detector = PowerEventDetector()
    @ObservationIgnored private var runLoopSource: CFRunLoopSource?
    @ObservationIgnored private var hideTask: Task<Void, Never>?

    public required init(context: ModuleContext) {}

    public func activate() async throws {
        state = PowerState.current()
        if let state { _ = detector.update(state) }
        let context = Unmanaged.passUnretained(self).toOpaque()
        // Powiadomienie IOKit przy każdej zmianie źródeł zasilania — bez odpytywania.
        guard let source = IOPSNotificationCreateRunLoopSource(powerSourceChanged, context)?.takeRetainedValue() else {
            return
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        runLoopSource = source
    }

    public func deactivate() {
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .defaultMode) }
        runLoopSource = nil
        hideTask?.cancel()
        hideTask = nil
        event = nil
    }

    public var liveActivity: LiveActivity? {
        guard let event, let state else { return nil }
        let tint = Self.tint(for: event)
        return LiveActivity(id: "power", priority: .alert, accent: tint, wingWidth: 46) {
            Image(systemName: Self.symbol(for: event, state: state))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .symbolEffect(.bounce, value: event)
        } trailing: {
            Text("\(state.level)%")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
        }
    }

    public func makeExpandedView() -> AnyView? {
        AnyView(PowerExpandedView(state: state))
    }

    public func makeWidgetView() -> AnyView? {
        AnyView(PowerWidget(state: state))
    }

    fileprivate func refresh() {
        guard let newState = PowerState.current() else { return }
        state = newState
        guard let newEvent = detector.update(newState) else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { event = newEvent }
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: Self.eventDuration)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) { self?.event = nil }
        }
    }

    private static func symbol(for event: PowerEvent, state: PowerState) -> String {
        switch event {
        case .pluggedIn, .charged: "bolt.fill"
        case .unplugged: state.symbol
        case .low: "battery.25percent"
        }
    }

    private static func tint(for event: PowerEvent) -> Color {
        switch event {
        case .pluggedIn, .charged: .green
        case .unplugged: .white
        case .low(let threshold): threshold <= 10 ? .red : .orange
        }
    }
}

/// Callback IOKit; źródło jest w głównej pętli, więc działa na głównym wątku.
private func powerSourceChanged(context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    let module = Unmanaged<PowerModule>.fromOpaque(context).takeUnretainedValue()
    MainActor.assumeIsolated { module.refresh() }
}

#if DEBUG
extension PowerModule {
    /// Dane demonstracyjne do zrzutów ekranu w README (tylko build debug).
    func showDemo(state demoState: PowerState, event demoEvent: PowerEvent?) {
        state = demoState
        event = demoEvent
    }
}
#endif
