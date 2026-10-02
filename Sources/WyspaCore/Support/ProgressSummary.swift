/// Wspólne dla pasków postępu (pobierania, skrypty): łączny postęp i tekst procentu.
public enum ProgressSummary {
    /// Średnia znanych wartości (0…1); nieokreślone (`nil`) nie zaniżają średniej. `nil`, gdy żadna nie jest znana.
    public static func average(_ fractions: [Double?]) -> Double? {
        let known = fractions.compactMap { $0 }
        guard !known.isEmpty else { return nil }
        return min(max(known.reduce(0, +) / Double(known.count), 0), 1)
    }

    /// „42%” (w dół, żeby 99,9% nie pokazywało 100%); „…” dla postępu nieokreślonego.
    public static func percentText(_ fraction: Double?) -> String {
        fraction.map { "\(Int((min(max($0, 0), 1) * 100).rounded(.down)))%" } ?? "…"
    }
}
