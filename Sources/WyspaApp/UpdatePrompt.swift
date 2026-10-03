import AppKit
import WyspaCore
import WyspaUpdates

/// „Sprawdź aktualizacje…” z menu Wyspy: sprawdza GitHuba i pokazuje wynik w okienku (także przy wyłączonym module).
@MainActor
enum UpdatePrompt {
    private static let maxListedChanges = 6

    static func checkAndShow(service: UpdateService = .shared) async {
        let status = await service.check()
        NSApp.activate()
        let alert = NSAlert()
        switch status {
        case .available(let check):
            alert.messageText = "Dostępna nowa wersja Wyspy"
            alert.informativeText = changesText(check)
                + "\n\nAktualizacja pobierze zmiany, zbuduje i zainstaluje Wyspę — aplikacja zamknie się i uruchomi ponownie."
            alert.addButton(withTitle: "Zaktualizuj teraz")
            alert.addButton(withTitle: "Później")
            if alert.runModal() == .alertFirstButtonReturn {
                service.update()
                await waitForFailure(service)
            }
            return
        case .upToDate:
            alert.messageText = "Masz najnowszą wersję Wyspy"
            alert.informativeText = service.source.map { "Zainstalowana wersja: \($0.shortCommit)" } ?? ""
        case .failed(let message):
            alert.alertStyle = .warning
            alert.messageText = "Nie udało się sprawdzić aktualizacji"
            alert.informativeText = message
        case .idle, .checking, .updating:
            return
        }
        alert.runModal()
    }

    private static func changesText(_ check: UpdateCheck) -> String {
        let count = PolishPlural.format(check.changes.count, one: "zmiana", few: "zmiany", many: "zmian")
        var lines = check.changes.prefix(maxListedChanges).map { "• \($0.title)" }
        if check.changes.count > maxListedChanges { lines.append("… i \(check.changes.count - maxListedChanges) więcej") }
        return "\(count):\n" + lines.joined(separator: "\n")
    }

    /// Udana aktualizacja kończy tę kopię Wyspy; błąd przed instalacją (np. niezapisane zmiany) pokazujemy.
    private static func waitForFailure(_ service: UpdateService) async {
        while service.status == .updating {
            try? await Task.sleep(for: .milliseconds(300))
        }
        guard case .failed(let message) = service.status else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Aktualizacja się nie udała"
        alert.informativeText = message
        alert.runModal()
    }
}
