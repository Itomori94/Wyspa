import CoreGraphics

/// Plan prawej połowy nagłówka rozwiniętej wyspy: które zakładki widać, w jakim stylu,
/// czy jest menu „⋯” na pozostałe i czy mieści się skrzydło aktywności. Bez przewijania.
public struct TabStripPlan: Equatable, Sendable {
    public enum Style: Equatable, Sendable {
        case regular, compact

        public var buttonWidth: CGFloat { self == .regular ? 26 : 22 }
        public var spacing: CGFloat { self == .regular ? 4 : 2 }
    }

    public static let overflowButtonWidth: CGFloat = 26
    public static let wingSpacing: CGFloat = 10

    public let style: Style
    /// Indeksy zakładek pokazanych w pasku (w kolejności).
    public let visible: [Int]
    /// Indeksy zakładek w menu „⋯”.
    public let overflow: [Int]
    public let showsWing: Bool

    public static func make(tabCount: Int, selected: Int, available: CGFloat, wingWidth: CGFloat?) -> TabStripPlan {
        let all = Array(0..<max(tabCount, 0))
        // Jedna zakładka nie potrzebuje paska.
        guard tabCount > 1 else {
            let fitsWing = wingWidth.map { $0 <= available } ?? false
            return TabStripPlan(style: .regular, visible: [], overflow: [], showsWing: fitsWing)
        }
        // Kolejność prób: pełny pasek ze skrzydłem, kompaktowy ze skrzydłem, bez skrzydła.
        let attempts: [(Style, Bool)] = [(.regular, true), (.compact, true), (.regular, false), (.compact, false)]
        for (style, withWing) in attempts where withWing == false || wingWidth != nil {
            let wing = withWing ? (wingWidth ?? 0) + wingSpacing : 0
            if stripWidth(count: tabCount, style: style) + wing <= available {
                return TabStripPlan(style: style, visible: all, overflow: [], showsWing: withWing)
            }
        }
        // Nie mieści się wszystko: kompaktowe zakładki + menu „⋯”, bez skrzydła.
        let style = Style.compact
        var count = tabCount - 1
        while count > 1,
              stripWidth(count: count, style: style) + style.spacing + overflowButtonWidth > available {
            count -= 1
        }
        let clampedSelected = min(max(selected, 0), tabCount - 1)
        var visible = Array(all.prefix(count))
        // Wybrana zakładka jest zawsze widoczna: zastępuje ostatnią w pasku.
        if !visible.contains(clampedSelected), let last = visible.indices.last {
            visible[last] = clampedSelected
        }
        let overflow = all.filter { !visible.contains($0) }
        return TabStripPlan(style: style, visible: visible, overflow: overflow, showsWing: false)
    }

    /// Ile zakładek w danym stylu mieści się w szerokości (bez menu i skrzydła).
    public static func capacity(available: CGFloat, style: Style) -> Int {
        guard available >= style.buttonWidth else { return 0 }
        return Int((available + style.spacing) / (style.buttonWidth + style.spacing))
    }

    public static func stripWidth(count: Int, style: Style) -> CGFloat {
        guard count > 0 else { return 0 }
        return CGFloat(count) * style.buttonWidth + CGFloat(count - 1) * style.spacing
    }
}
