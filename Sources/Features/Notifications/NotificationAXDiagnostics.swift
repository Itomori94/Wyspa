import AppKit
import ApplicationServices
import WyspaCore

/// Diagnostyka: zapisuje drzewo Dostępności banerów powiadomień do pliku.
///
/// Uruchamiana wyłącznie ręcznie: `open -n Wyspa.app --args --dump-notification-ax`.
/// Zrzut zawiera treść powiadomień, więc trafia tylko do lokalnego pliku wskazanego w logu.
public enum NotificationAXDiagnostics {
    public static let flag = "--dump-notification-ax"
    static let duration: TimeInterval = 60

    @MainActor
    public static func run() {
        let output = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/Wyspa/notification-ax.txt")
        try? FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        // Stary plik mógłby mieć szersze prawa — `createFile` ustawia 0600 tylko nowemu plikowi.
        try? FileManager.default.removeItem(at: output)
        let candidates = NSWorkspace.shared.runningApplications.filter {
            ["com.apple.notificationcenterui", "com.apple.UserNotificationCenter"].contains($0.bundleIdentifier ?? "")
                || ["NotificationCenter", "UIKitSystem"].contains($0.localizedName ?? "")
        }
        let session = DiagnosticsSession(output: output, candidates: candidates, deadline: Date().addingTimeInterval(duration))
        // Odpytywanie tylko w diagnostyce (przez `duration` sekund), nigdy w module.
        Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { timer in
            let finished = MainActor.assumeIsolated { session.tick() }
            if finished { timer.invalidate() }
        }
    }

    /// Stan jednego uruchomienia diagnostyki (główny wątek).
    @MainActor
    private final class DiagnosticsSession {
        private let output: URL
        private let candidates: [NSRunningApplication]
        private let deadline: Date
        private var lines: [String]
        private var seen = Set<String>()

        init(output: URL, candidates: [NSRunningApplication], deadline: Date) {
            self.output = output
            self.candidates = candidates
            self.deadline = deadline
            lines = [
                "Zaufanie Dostępności: \(AXIsProcessTrusted())",
                "System: \(ProcessInfo.processInfo.operatingSystemVersionString)",
                "Procesy: " + candidates.map { "\($0.bundleIdentifier ?? "?") pid \($0.processIdentifier)" }.joined(separator: ", "),
            ]
        }

        /// Zwraca true po zakończeniu diagnostyki (plik zapisany).
        func tick() -> Bool {
            for app in candidates {
                let element = AXUIElementCreateApplication(app.processIdentifier)
                // Tylko okna (bez paska menu, który zawiera ostatnio otwierane pliki).
                let windows = NotificationAXDiagnostics.children(of: element, attribute: kAXWindowsAttribute)
                let dump = "okna: \(windows.count)\n" + windows.map { NotificationAXDiagnostics.describe($0, depth: 1) }.joined(separator: "\n")
                if seen.insert("\(app.processIdentifier)" + dump).inserted {
                    lines.append("=== \(Date()) proces \(app.localizedName ?? "?") (\(app.bundleIdentifier ?? "?"))")
                    lines.append(dump)
                }
            }
            guard Date() > deadline else { return false }
            // Zrzut zawiera treść powiadomień: plik tylko dla właściciela.
            FileManager.default.createFile(atPath: output.path, contents: Data(lines.joined(separator: "\n").utf8),
                                           attributes: [.posixPermissions: 0o600])
            print("Zapisano: \(output.path)")
            NSApp.terminate(nil)
            return true
        }
    }

    static func describe(_ element: AXUIElement, depth: Int) -> String {
        guard depth < 14 else { return "" }
        let indent = String(repeating: "  ", count: depth)
        let attributes = [kAXRoleAttribute, kAXSubroleAttribute, kAXIdentifierAttribute, kAXTitleAttribute,
                          kAXDescriptionAttribute, kAXValueAttribute, kAXHelpAttribute]
        let parts = attributes.compactMap { name -> String? in
            guard let value = string(element, name), !value.isEmpty else { return nil }
            return "\(name.replacingOccurrences(of: "AX", with: ""))=\(value)"
        }
        var actions: CFArray?
        AXUIElementCopyActionNames(element, &actions)
        let actionList = (actions as? [String])?.joined(separator: ",") ?? ""
        var result = indent + parts.joined(separator: " | ") + (actionList.isEmpty ? "" : " | akcje=\(actionList)")
        for child in children(of: element, attribute: kAXChildrenAttribute) {
            result += "\n" + describe(child, depth: depth + 1)
        }
        return result
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success, let value else { return nil }
        if let text = value as? String { return text.replacingOccurrences(of: "\n", with: "⏎") }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    static func children(of element: AXUIElement, attribute: String) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return [] }
        return (value as? [AXUIElement]) ?? []
    }
}
