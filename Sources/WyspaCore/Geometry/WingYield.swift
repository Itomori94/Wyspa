import CoreGraphics

/// Skrzydła zwiniętej wyspy leżą na pasku menu i zakrywają ikony obok notcha. Kursor nad skrzydłem = ktoś chce
/// sięgnąć do ikony pod nim: skrzydła chowają się do notcha, dopóki kursor jest na pasku menu w ich zasięgu.
public enum WingYield {
    /// Zapas wokół zasięgu skrzydeł, żeby drobny ruch przy krawędzi nie przywracał ich od razu.
    public static let returnMargin: CGFloat = 6

    /// Kursor w wyspie, ale obok notcha (nad skrzydłem). Nad samym notchem wyspa zachowuje się jak dotąd.
    public static func isOverWing(_ point: CGPoint, island: CGRect, notch: CGRect) -> Bool {
        island.contains(point) && (point.x < notch.minX || point.x > notch.maxX)
    }

    /// Skrzydła wracają, gdy kursor opuści pasek menu w ich zasięgu (zjedzie niżej albo odsunie się na bok).
    public static func shouldReturn(_ point: CGPoint, wingSpan: CGRect) -> Bool {
        !wingSpan.insetBy(dx: -returnMargin, dy: -returnMargin).contains(point)
    }
}
