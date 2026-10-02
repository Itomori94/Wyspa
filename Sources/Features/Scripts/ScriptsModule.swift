import AppKit
import SwiftUI
import WyspaCore

/// Karty i paski postępu ze skryptów, Skrótów i crona: komenda `wyspa` i adresy `wyspa://`.
///
/// Bez odpytywania: polecenia przychodzą jako adresy otwierane przez system (`application(_:open:)`).
@MainActor
@Observable
public final class ScriptsModule: IslandModule {
    public static let descriptor = ModuleDescriptor(
        id: "scripts",
        name: "Skrypty",
        summary: "Komenda wyspa i adresy wyspa:// — karty („Backup gotowy”) i paski postępu ze skryptów, Skrótów i crona.",
        symbol: "terminal.fill",
        content: .personal,
        widgetMinWidth: 150
    )

    static let noticeSeconds = 5
    static let cardHeight: CGFloat = 62
    /// Ukończony postęp pokazuje znacznik jeszcze przez chwilę.
    static let finishedSeconds = 2
    /// Jak pobieranie: ważniejsze niż odtwarzanie, mniej ważne niż timer.
    static let progressPriority = ActivityPriority(55)

    public private(set) var state = ScriptsState()
    public private(set) var commandStatus: CommandInstaller.Status = .missing
    public private(set) var installProblem: String?

    @ObservationIgnored private let context: ModuleContext
    @ObservationIgnored private let log = Log.logger("scripts")
    @ObservationIgnored private var noticeTask: Task<Void, Never>?
    @ObservationIgnored private var expiryTask: Task<Void, Never>?
    @ObservationIgnored private var finishTasks: [String: Task<Void, Never>] = [:]

    public required init(context: ModuleContext) {
        self.context = context
    }

    public func activate() async throws {
        refreshCommandStatus()
        ScriptCommandCenter.shared.setHandler { [weak self] command in self?.receive(command) }
    }

    public func deactivate() {
        ScriptCommandCenter.shared.setHandler(nil)
        noticeTask?.cancel()
        expiryTask?.cancel()
        finishTasks.values.forEach { $0.cancel() }
        finishTasks = [:]
        state = ScriptsState()
    }

    public var liveActivity: LiveActivity? {
        if let notice = state.notice {
            let waiting = state.waiting.count
            return LiveActivity(id: "scripts.notice.\(notice.id)", priority: .alert, detailHeight: Self.cardHeight) {
                Image(systemName: "terminal.fill").font(.system(size: 12)).foregroundStyle(.green)
            } trailing: {
                if waiting > 0 {
                    Text("+\(waiting)").font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(.white.opacity(0.7))
                }
            } detail: {
                ScriptNoticeCard(notice: notice, isPrivate: false) { [weak self] in self?.nextNotice() }
            }
            .withPrivateDetail {
                ScriptNoticeCard(notice: notice, isPrivate: true) { [weak self] in self?.nextNotice() }
            }
        }
        guard !state.progress.isEmpty else { return nil }
        let fraction = state.overallFraction
        let finished = state.progress.allSatisfy(\.isFinished)
        let count = state.progress.count
        return LiveActivity(id: "scripts.progress", priority: Self.progressPriority, accent: .green, wingWidth: 52) {
            ScriptProgressRing(fraction: fraction, finished: finished)
        } trailing: {
            Text(count > 1 ? "\(count) × \(ScriptsState.percentText(fraction))" : (finished ? "Gotowe" : ScriptsState.percentText(fraction)))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .foregroundStyle(.white.opacity(0.85))
        }
    }

    public func makeExpandedView() -> AnyView? { AnyView(ScriptsView(module: self)) }
    public func makeWidgetView() -> AnyView? { AnyView(ScriptsView(module: self)) }
    public func makeSettingsView() -> AnyView? { AnyView(ScriptsSettingsView(module: self)) }

    // MARK: - Polecenia

    func receive(_ command: ScriptCommand) {
        let hadNotice = state.notice != nil
        if case .notify = command { context.privacy.refresh() }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { state = state.applying(command, at: .now) }
        if !hadNotice, state.notice != nil { scheduleNoticeDismiss() }
        scheduleFinishes()
        scheduleExpiry()
    }

    func nextNotice() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { state = state.advancingNotice() }
        if state.notice != nil { scheduleNoticeDismiss() } else { noticeTask?.cancel() }
    }

    func dismissProgress(_ id: String) {
        finishTasks[id]?.cancel()
        finishTasks[id] = nil
        withAnimation { state = state.removingProgress(id) }
        scheduleExpiry()
    }

    private func scheduleNoticeDismiss() {
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.noticeSeconds))
            guard !Task.isCancelled else { return }
            self?.nextNotice()
        }
    }

    /// Ukończone postępy znikają po chwili; jedno zadanie na postęp.
    private func scheduleFinishes() {
        for item in state.progress where item.isFinished && finishTasks[item.id] == nil {
            let id = item.id
            finishTasks[id] = Task { [weak self] in
                try? await Task.sleep(for: .seconds(Self.finishedSeconds))
                guard !Task.isCancelled else { return }
                self?.finishTasks[id] = nil
                self?.dismissProgress(id)
            }
        }
        // Postęp wznowiony po ukończeniu (ten sam identyfikator) nie znika.
        for (id, task) in finishTasks where !state.progress.contains(where: { $0.id == id && $0.isFinished }) {
            task.cancel()
            finishTasks[id] = nil
        }
    }

    /// Jedno zaplanowane wybudzenie na najbliższe przedawnienie (skrypt padł bez `wyspa done`).
    private func scheduleExpiry() {
        expiryTask?.cancel()
        guard let expiry = state.nextExpiry else { return }
        expiryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(expiry.timeIntervalSinceNow, 1)))
            guard !Task.isCancelled, let self else { return }
            withAnimation { self.state = self.state.expiring(at: .now) }
            self.scheduleExpiry()
        }
    }

    // MARK: - Komenda w terminalu

    func refreshCommandStatus() {
        commandStatus = CommandInstaller.status()
    }

    func installCommand() {
        do {
            try CommandInstaller.install()
            installProblem = nil
        } catch {
            log.error("Instalacja komendy wyspa: \(error.localizedDescription)")
            installProblem = error.localizedDescription
        }
        refreshCommandStatus()
    }

    func uninstallCommand() {
        do {
            try CommandInstaller.uninstall()
            installProblem = nil
        } catch {
            installProblem = error.localizedDescription
        }
        refreshCommandStatus()
    }
}

#if DEBUG
extension ScriptsModule {
    /// Dane demonstracyjne do zrzutów ekranu w README (tylko build debug).
    func showDemo(_ demo: ScriptsState) {
        state = demo
    }
}
#endif
