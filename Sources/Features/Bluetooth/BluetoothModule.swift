import SwiftUI
import WyspaCore

/// Bluetooth: podłączenie i odłączenie urządzeń z poziomem baterii słuchawek; zakładka z listą urządzeń.
@MainActor
@Observable
public final class BluetoothModule: IslandModule {
    public static let descriptor = ModuleDescriptor(
        id: "bluetooth",
        name: "Bluetooth",
        summary: "Pokazuje podłączenie słuchawek i innych urządzeń Bluetooth z poziomem ich baterii.",
        symbol: "headphones",
        content: .neutral,
        permissions: [.bluetooth],
        widgetMinWidth: 130
    )

    static let eventDuration: Duration = .seconds(4)
    /// Słuchawki podają poziom baterii chwilę po połączeniu.
    static let batteryRefreshDelay: Duration = .seconds(2)
    /// Odczyt baterii co kilka minut, tylko gdy podłączone jest urządzenie podające jej poziom
    /// (system nie powiadamia o zmianie baterii).
    static let batteryPollInterval: Duration = .seconds(300)

    public private(set) var devices: [ConnectedDevice] = []
    public private(set) var event: BluetoothEvent?

    @ObservationIgnored private var monitor: BluetoothMonitor?
    @ObservationIgnored private var hideTask: Task<Void, Never>?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var batteryPollTask: Task<Void, Never>?
    @ObservationIgnored private var lowBattery = LowBatteryTracker()

    public required init(context: ModuleContext) {}

    public func activate() async throws {
        let monitor = BluetoothMonitor { [weak self] event in self?.handle(event) }
        self.monitor = monitor
        monitor.start()
    }

    public func deactivate() {
        monitor?.stop()
        monitor = nil
        hideTask?.cancel()
        refreshTask?.cancel()
        batteryPollTask?.cancel()
        batteryPollTask = nil
        lowBattery = LowBatteryTracker()
        devices = []
        event = nil
    }

    public var liveActivity: LiveActivity? {
        guard let event else { return nil }
        switch event {
        case .connected(let device):
            let current = devices.first { $0.id == device.id } ?? device
            return LiveActivity(id: "bluetooth", priority: .alert, wingWidth: 46) {
                Image(systemName: current.kind.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .symbolEffect(.bounce, value: current.id)
            } trailing: {
                BatteryBadge(level: current.battery.summary)
            }
        case .lowBattery(let device):
            return LiveActivity(id: "bluetooth.low", priority: .alert, accent: .red, wingWidth: 46) {
                Image(systemName: device.kind.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
            } trailing: {
                HStack(spacing: 2) {
                    Image(systemName: "battery.25percent").font(.system(size: 11, weight: .semibold))
                    Text(device.battery.summary.map { "\($0)%" } ?? "")
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded)).monospacedDigit()
                }
                .foregroundStyle(.red)
            }
        case .disconnected(let device):
            return LiveActivity(id: "bluetooth", priority: .alert, wingWidth: 46) {
                Image(systemName: device.kind.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.4))
            } trailing: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    public func makeExpandedView() -> AnyView? {
        AnyView(BluetoothExpandedView(devices: devices))
    }

    public func makeWidgetView() -> AnyView? {
        AnyView(BluetoothWidget(devices: devices))
    }

    private func handle(_ newEvent: BluetoothEvent?) {
        refreshDevices()
        guard let newEvent else { return }
        show(newEvent)
        if case .connected = newEvent {
            refreshTask?.cancel()
            refreshTask = Task { [weak self] in
                try? await Task.sleep(for: Self.batteryRefreshDelay)
                guard !Task.isCancelled else { return }
                self?.refreshDevices()
            }
        }
    }

    private func show(_ newEvent: BluetoothEvent) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { event = newEvent }
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: Self.eventDuration)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) { self?.event = nil }
        }
    }

    private func refreshDevices() {
        guard let monitor else { return }
        devices = monitor.devices.values.map(monitor.snapshot(of:)).sorted { $0.name < $1.name }
        let (tracker, alerts) = lowBattery.evaluating(devices)
        lowBattery = tracker
        if let weakest = alerts.min(by: { ($0.battery.summary ?? 100) < ($1.battery.summary ?? 100) }) {
            show(.lowBattery(weakest))
        }
        updateBatteryPolling()
    }

    /// Okresowy odczyt tylko wtedy, gdy jest co odczytywać; bez urządzeń z baterią — żadnego zegara.
    private func updateBatteryPolling() {
        let needsPolling = devices.contains { $0.battery.summary != nil }
        guard needsPolling != (batteryPollTask != nil) else { return }
        batteryPollTask?.cancel()
        // Jednorazowe odczekanie; `refreshDevices()` po odczycie planuje kolejne, jeśli nadal jest co odczytywać.
        batteryPollTask = needsPolling ? Task { [weak self] in
            try? await Task.sleep(for: Self.batteryPollInterval)
            guard !Task.isCancelled else { return }
            self?.batteryPollTask = nil
            self?.refreshDevices()
        } : nil
    }
}

#if DEBUG
extension BluetoothModule {
    /// Dane demonstracyjne do zrzutów ekranu w README (tylko build debug).
    func showDemo(_ demo: [ConnectedDevice], event demoEvent: BluetoothEvent?) {
        devices = demo
        event = demoEvent
    }
}
#endif
