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
                + "\n\nAktualizacja pobierze zmiany, zbuduje i zainstaluje Wyspę (budowanie trwa kilka minut) — potem "
                + "aplikacja zamknie się i uruchomi ponownie sama."
            alert.addButton(withTitle: "Zaktualizuj teraz")
            alert.addButton(withTitle: "Później")
            // Postęp i ewentualny błąd pokazuje okienko aktualizacji (UpdateProgressWindowController).
            if alert.runModal() == .alertFirstButtonReturn { service.update() }
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

    /// Po ponownym uruchomieniu: potwierdzenie aktualizacji zaczętej w poprzedniej kopii Wyspy.
    static func confirmFinishedUpdate(service: UpdateService = .shared) {
        guard let finished = service.consumeFinishedUpdate() else { return }
        NSApp.activate()
        let alert = NSAlert()
        switch finished {
        case .updated(let version, let titles):
            alert.messageText = "Wyspa została zaktualizowana"
            var text = "Masz najnowszą wersję: \(version)."
            if !titles.isEmpty {
                text += "\n\nZmiany:\n" + titles.prefix(maxListedChanges).map { "• \($0)" }.joined(separator: "\n")
                if titles.count > maxListedChanges { text += "\n… i \(titles.count - maxListedChanges) więcej" }
            }
            alert.informativeText = text
        case .unchanged:
            alert.alertStyle = .warning
            alert.messageText = "Aktualizacja się nie udała"
            alert.informativeText = "Wyspa uruchomiła się w poprzedniej wersji. Przebieg: ~/Library/Logs/Wyspa/aktualizacja.log."
        }
        alert.runModal()
    }

    private static func changesText(_ check: UpdateCheck) -> String {
        let count = PolishPlural.format(check.changes.count, one: "zmiana", few: "zmiany", many: "zmian")
        var lines = check.changes.prefix(maxListedChanges).map { "• \($0.title)" }
        if check.changes.count > maxListedChanges { lines.append("… i \(check.changes.count - maxListedChanges) więcej") }
        return "\(count):\n" + lines.joined(separator: "\n")
    }
}
