import Foundation

/// Stały pośrednik dla hooków i linii statusu Claude Code, poza pakietem aplikacji.
///
/// `~/.local/share/wyspa/bin/wyspa-hook` (ścieżka bez spacji) uruchamia pomocnika z Wyspa.app, a gdy aplikacji nie ma —
/// kończy się po cichu z kodem 0. Usunięcie albo przeniesienie aplikacji nie psuje więc Claude Code.
public enum HookShim {
    public static var url: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/share/wyspa/bin/\(HookInstaller.marker)")
    }

    /// Treść skryptu dla danej ścieżki pomocnika (w apostrofach, bezpieczna dla dowolnej ścieżki).
    public static func script(helperPath: String) -> String {
        let quoted = "'" + helperPath.replacingOccurrences(of: "'", with: "'\\''") + "'"
        return """
        #!/bin/sh
        # Wyspa: pośrednik hooków Claude Code. Bez aplikacji kończy się po cichu, więc Claude Code działa jak bez hooków.
        HELPER=\(quoted)
        if [ -x "$HELPER" ]; then exec "$HELPER" "$@"; fi
        cat > /dev/null
        exit 0

        """
    }

    /// Zapisuje skrypt, gdy go nie ma albo wskazuje inną kopię Wyspy. Katalog i plik tylko dla właściciela.
    public static func install(helperPath: String, at url: URL = url) throws {
        let fileManager = FileManager.default
        let directory = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let contents = Data(script(helperPath: helperPath).utf8)
        if (try? Data(contentsOf: url)) != contents {
            try contents.write(to: url, options: .atomic)
        }
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }
}
