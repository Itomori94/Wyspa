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
        try? FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        var lines = ["Zaufanie Dostępności: \(AXIsProcessTrusted())", "System: \(ProcessInfo.processInfo.operatingSystemVersionString)"]
        let candidates = NSWorkspace.shared.runningApplications.filter {
            ["com.apple.notificationcenterui", "com.apple.UserNotificationCenter"].contains($0.bundleIdentifier ?? "")
                || ["NotificationCenter", "UIKitSystem"].contains($0.localizedName ?? "")
        }
        lines.append("Procesy: " + candidates.map { "\($0.bundleIdentifier ?? "?") pid \($0.processIdentifier)" }.joined(separator: ", "))
        var seen = Set<String>()
        let deadline = Date().addingTimeInterval(duration)
        // Odpytywanie tylko w diagnostyce (20 s), nie w module.
        Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { timer in
            for app in candidates {
                let element = AXUIElementCreateApplication(app.processIdentifier)
                // Tylko okna (bez paska menu, który zawiera ostatnio otwierane pliki).
                let windows = children(of: element, attribute: kAXWindowsAttribute)
                let dump = "okna: \(windows.count)\n" + windows.map { describe($0, depth: 1) }.joined(separator: "\n")
                if seen.insert("\(app.processIdentifier)" + dump).inserted {
                    lines.append("=== \(Date()) proces \(app.localizedName ?? "?") (\(app.bundleIdentifier ?? "?"))")
                    lines.append(dump)
                }
            }
            if Date() > deadline {
                timer.invalidate()
                try? lines.joined(separator: "\n").write(to: output, atomically: true, encoding: .utf8)
                print("Zapisano: \(output.path)")
                NSApp.terminate(nil)
            }
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
