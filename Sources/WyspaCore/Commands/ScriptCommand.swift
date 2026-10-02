import Foundation

/// Polecenie ze skryptu, Skrótu albo crona, przysłane adresem `wyspa://` (komenda `wyspa`).
///
/// Adres może otworzyć każda aplikacja i każda strona WWW (przeglądarka pyta wtedy o zgodę), więc polecenia tylko
/// pokazują tekst w wyspie: bez plików, poleceń powłoki i innych skutków ubocznych. Teksty są przycinane i oczyszczane.
public enum ScriptCommand: Equatable, Sendable {
    /// Karta pod notchem na kilka sekund.
    case notify(title: String, body: String?)
    /// Pasek postępu w zwiniętej wyspie; `fraction == nil` = postęp nieokreślony.
    case progress(id: String, fraction: Double?, label: String?)
    /// Koniec postępu o danym identyfikatorze.
    case done(id: String)

    public static let scheme = "wyspa"
    public static let defaultProgressID = "default"
    static let maxTitle = 80
    static let maxBody = 240
    static let maxLabel = 60
    static let maxID = 40

    /// `wyspa://notify?title=…&body=…`, `wyspa://progress?value=0.4&label=…&id=…`, `wyspa://done?id=…`.
    /// Wartość postępu: 0–1 albo procent (`40%`); brak wartości = postęp nieokreślony. Nieznany adres = nil.
    public init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }
        // `wyspa://notify?…` ma polecenie w hoście, `wyspa:notify?…` w ścieżce.
        let verb = (components.host?.nilIfEmpty ?? components.path).trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        var query: [String: String] = [:]
        for item in components.queryItems ?? [] where query[item.name] == nil {
            query[item.name] = item.value ?? ""
        }
        let id = Self.identifier(query["id"])
        switch verb {
        case "notify":
            guard let title = Self.clean(query["title"], limit: Self.maxTitle) else { return nil }
            self = .notify(title: title, body: Self.clean(query["body"], limit: Self.maxBody))
        case "progress":
            let label = Self.clean(query["label"], limit: Self.maxLabel)
            guard let raw = query["value"]?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else {
                self = .progress(id: id, fraction: nil, label: label)
                return
            }
            guard let fraction = Self.fraction(raw) else { return nil }
            self = .progress(id: id, fraction: fraction, label: label)
        case "done":
            self = .done(id: id)
        default:
            return nil
        }
    }

    /// „0.4”, „0,4”, „40%” → 0,4; przycięte do 0…1. Tekst, który nie jest liczbą, albo NaN = nil.
    static func fraction(_ raw: String) -> Double? {
        let percent = raw.hasSuffix("%")
        let number = (percent ? String(raw.dropLast()) : raw).replacingOccurrences(of: ",", with: ".")
        guard let value = Double(number), value.isFinite else { return nil }
        return min(max(percent ? value / 100 : value, 0), 1)
    }

    /// Tekst bez znaków sterujących (nowe linie → spacje), bez nadmiarowych spacji, przycięty z wielokropkiem.
    static func clean(_ text: String?, limit: Int) -> String? {
        guard let text else { return nil }
        let scalars = text.unicodeScalars.map { scalar -> Character in
            CharacterSet.controlCharacters.contains(scalar) || CharacterSet.newlines.contains(scalar) ? " " : Character(scalar)
        }
        let collapsed = String(scalars).split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        guard !collapsed.isEmpty else { return nil }
        return collapsed.count > limit ? String(collapsed.prefix(limit - 1)) + "…" : collapsed
    }

    /// Identyfikator postępu: litery, cyfry, `-`, `_`, `.`; inny albo pusty = domyślny.
    static func identifier(_ raw: String?) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        guard let raw, !raw.isEmpty, raw.count <= maxID, raw.unicodeScalars.allSatisfy(allowed.contains) else {
            return defaultProgressID
        }
        return raw
    }
}

/// Dostarcza polecenia `wyspa://` do modułu, który je obsługuje (moduły nie znają aplikacji ani siebie nawzajem).
///
/// Polecenia, które przyszły przed startem modułu (np. adres uruchomił Wyspę), czekają w krótkim buforze.
@MainActor
public final class ScriptCommandCenter {
    public static let shared = ScriptCommandCenter()
    static let bufferLimit = 5

    private var handler: (@MainActor (ScriptCommand) -> Void)?
    private var buffered: [ScriptCommand] = []

    init() {}

    public func post(_ command: ScriptCommand) {
        if let handler {
            handler(command)
        } else {
            buffered = Array((buffered + [command]).suffix(Self.bufferLimit))
        }
    }

    /// Jeden odbiorca naraz; nowy zastępuje poprzedniego i dostaje polecenia z bufora.
    public func setHandler(_ handler: (@MainActor (ScriptCommand) -> Void)?) {
        self.handler = handler
        guard let handler else { return }
        let pending = buffered
        buffered = []
        pending.forEach(handler)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
