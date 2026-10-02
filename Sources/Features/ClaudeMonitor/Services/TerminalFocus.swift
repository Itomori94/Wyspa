import AppKit
import WyspaCore

/// Przenosi do okna terminala albo edytora, w którym działa sesja Claude Code.
///
/// Terminal i iTerm2: wybór karty po urządzeniu TTY przez AppleScript (system zapyta o zgodę na automatyzację).
/// VS Code i Cursor: otwarcie folderu projektu (przenosi do właściwego okna). Inne aplikacje: tylko aktywacja.
@MainActor
enum TerminalFocus {
    private static let log = Log.logger("claude.focus")

    static func focus(bundleID: String?, claudePID: Int32?, cwd: String?) {
        guard let bundleID else { return }
        let tty = claudePID.flatMap(Self.ttyPath(of:))
        switch bundleID {
        case "com.apple.Terminal":
            runScript(tty.map(terminalScript) , fallback: bundleID)
        case "com.googlecode.iterm2":
            runScript(tty.map(itermScript), fallback: bundleID)
        case "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders":
            openFolder(scheme: bundleID == "com.microsoft.VSCode" ? "vscode" : "vscode-insiders", cwd: cwd, fallback: bundleID)
        case "com.todesktop.230313mzl4w4u92":
            openFolder(scheme: "cursor", cwd: cwd, fallback: bundleID)
        default:
            activate(bundleID)
        }
    }

    static func activate(_ bundleID: String) {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.activate()
    }

    /// Urządzenie TTY procesu (np. /dev/ttys003) z jądra, bez uruchamiania `ps`.
    static func ttyPath(of pid: Int32) -> String? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let device = info.kp_eproc.e_tdev
        guard device != UInt32.max, device != 0, let name = devname(dev_t(device), S_IFCHR) else { return nil }
        return "/dev/" + String(cString: name)
    }

    private static func terminalScript(_ tty: String) -> String {
        """
        tell application "Terminal"
            repeat with w in windows
                repeat with t in tabs of w
                    if tty of t is "\(tty)" then
                        set selected of t to true
                        set index of w to 1
                        activate
                        return
                    end if
                end repeat
            end repeat
        end tell
        """
    }

    private static func itermScript(_ tty: String) -> String {
        """
        tell application "iTerm2"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if tty of s is "\(tty)" then
                            select w
                            select t
                            select s
                            activate
                            return
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        """
    }

    private static func runScript(_ source: String?, fallback bundleID: String) {
        guard let source else { return activate(bundleID) }
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            log.error("Nie udało się wybrać karty terminala: \(error[NSAppleScript.errorNumber] as? Int ?? 0)")
            activate(bundleID)
        }
    }

    private static func openFolder(scheme: String, cwd: String?, fallback bundleID: String) {
        guard let cwd, let url = URL(string: "\(scheme)://file\(cwd.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? cwd)")
        else { return activate(bundleID) }
        NSWorkspace.shared.open(url)
    }
}
