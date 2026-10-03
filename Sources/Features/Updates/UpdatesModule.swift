import AppKit
import SwiftUI
import WyspaCore
import WyspaUI

/// Aktualizacje: porównanie zainstalowanej wersji z GitHubem i aktualizacja jednym przyciskiem
/// (`git pull --ff-only` + `scripts/install.sh` w katalogu, z którego zbudowano aplikację).
@MainActor
@Observable
public final class UpdatesModule: IslandModule {
    public static let descriptor = ModuleDescriptor(
        id: "updates",
        name: "Aktualizacje",
        summary: "Sprawdza, czy na GitHubie jest nowsza wersja Wyspy, pokazuje listę zmian i aktualizuje jednym przyciskiem.",
        symbol: "arrow.triangle.2.circlepath",
        content: .neutral,
        providesPage: false
    )

    /// Sprawdzanie przy starcie i co 6 godzin — jedno zaplanowane zadanie, tylko gdy moduł jest włączony.
    static let checkInterval: Duration = .seconds(6 * 3600)
    static let cardDisplay: Duration = .seconds(8)
    private static let announcedKey = "announcedCommit"

    public var service: UpdateService { .shared }
    /// Krótka karta w wyspie po znalezieniu nowej wersji (raz na wersję).
    public private(set) var announcement: UpdateCheck?

    @ObservationIgnored private let context: ModuleContext
    @ObservationIgnored private var scheduleTask: Task<Void, Never>?
    @ObservationIgnored private var cardTask: Task<Void, Never>?

    public required init(context: ModuleContext) {
        self.context = context
    }

    public func activate() async throws {
        scheduleTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.check()
                try? await Task.sleep(for: Self.checkInterval)
            }
        }
    }

    public func deactivate() {
        scheduleTask?.cancel()
        cardTask?.cancel()
        scheduleTask = nil
        announcement = nil
    }

    public var liveActivity: LiveActivity? {
        guard let announcement else { return nil }
        return LiveActivity(id: "updates", priority: .status, accent: .blue, wingWidth: 46, detailHeight: 46) {
            Image(systemName: "arrow.down.circle.fill").font(.system(size: 14, weight: .semibold)).foregroundStyle(.blue)
        } trailing: {
            Text("\(announcement.changes.count)").font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(.blue)
        } detail: {
            UpdateCard(check: announcement)
        }
    }

    public func makeExpandedView() -> AnyView? { nil }
    public func makeSettingsView() -> AnyView? { AnyView(UpdatesSettingsView(module: self)) }

    // MARK: - Sprawdzanie

    func check() async {
        if case .available(let result) = await service.check() { announceIfNew(result) }
    }

    /// Karta w wyspie tylko raz na nową wersję.
    private func announceIfNew(_ result: UpdateCheck) {
        guard let latest = result.latestCommit,
              context.settings.value(Self.announcedKey, default: "") != latest
        else { return }
        context.settings.set(latest, for: Self.announcedKey)
        withAnimation { announcement = result }
        cardTask?.cancel()
        cardTask = Task { [weak self] in
            try? await Task.sleep(for: Self.cardDisplay)
            guard !Task.isCancelled else { return }
            withAnimation { self?.announcement = nil }
        }
    }
}
