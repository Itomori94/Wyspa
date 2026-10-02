import Foundation

/// Instaluje komendę `wyspa`  w `~/.local/bin` — tylko na prośbę użytkownika.
///
/// Źródło: `Contents/Resources/wyspa` (zasoby są pieczętowane podpisem pakietu). Kopia, nie dowiązanie: komenda działa po przeniesieniu aplikacji, bo sama woła tylko `open wyspa://…`.
/// Cudzy plik o tej nazwie (bez znacznika `wyspa-cli`) nigdy nie jest nadpisywany ani usuwany.
public enum CommandInstaller {
    public static let marker = "wyspa-cli"

    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/wyspa")
    }

    public static var bundledURL: URL {
        Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/wyspa")
    }

    public enum Status: Equatable, Sendable {
        case missing
        case installed
        /// Zainstalowana starsza wersja (inna treść niż w aplikacji).
        case outdated
        /// Pod tą ścieżką jest inny program.
        case foreign
    }

    public enum InstallError: LocalizedError, Equatable {
        case foreignFile(String)
        case missingSource

        public var errorDescription: String? {
            switch self {
            case .foreignFile(let path): "Pod \(path) jest już inny program — Wyspa go nie nadpisze."
            case .missingSource: "W pakiecie aplikacji brakuje komendy wyspa (zbuduj aplikację scripts/build-app.sh)."
            }
        }
    }

    public static func status(source: URL = bundledURL, at url: URL = defaultURL) -> Status {
        guard let installed = try? Data(contentsOf: url) else {
            return FileManager.default.fileExists(atPath: url.path) ? .foreign : .missing
        }
        guard isOurs(installed) else { return .foreign }
        return (try? Data(contentsOf: source)) == installed ? .installed : .outdated
    }

    public static func install(source: URL = bundledURL, at url: URL = defaultURL) throws {
        guard let contents = try? Data(contentsOf: source), isOurs(contents) else { throw InstallError.missingSource }
        if status(source: source, at: url) == .foreign { throw InstallError.foreignFile(url.path) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    /// Usuwa tylko własną komendę.
    public static func uninstall(at url: URL = defaultURL) throws {
        guard let installed = try? Data(contentsOf: url), isOurs(installed) else { return }
        try FileManager.default.removeItem(at: url)
    }

    static func isOurs(_ data: Data) -> Bool {
        // Znacznik w nagłówku skryptu (pierwsze linie).
        String(decoding: data.prefix(512), as: UTF8.self).contains(marker)
    }
}
