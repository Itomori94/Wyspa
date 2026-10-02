import WyspaHookKit
import Foundation

/// Różnica linia po linii (najdłuższy wspólny podciąg) do podglądu zmian Edit/Write w wyspie.
public enum LineDiff {
    public enum Line: Equatable, Sendable {
        case same(String)
        case removed(String)
        case added(String)
    }

    /// Powyżej tego rozmiaru (linie × linie) diff jest uproszczony do „usunięte, potem dodane”.
    static let maxMatrixCells = 250_000

    public static func lines(from old: String, to new: String) -> [Line] {
        let a = old.isEmpty ? [] : old.components(separatedBy: "\n")
        let b = new.isEmpty ? [] : new.components(separatedBy: "\n")
        guard a.count * b.count <= maxMatrixCells else {
            return a.map(Line.removed) + b.map(Line.added)
        }
        // Tablica długości LCS od końca.
        var table = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                table[i][j] = a[i] == b[j] ? table[i + 1][j + 1] + 1 : max(table[i + 1][j], table[i][j + 1])
            }
        }
        var result: [Line] = []
        var i = 0, j = 0
        while i < a.count && j < b.count {
            if a[i] == b[j] {
                result.append(.same(a[i])); i += 1; j += 1
            } else if table[i + 1][j] >= table[i][j + 1] {
                result.append(.removed(a[i])); i += 1
            } else {
                result.append(.added(b[j])); j += 1
            }
        }
        result += a[i...].map(Line.removed) + b[j...].map(Line.added)
        return result
    }
}
