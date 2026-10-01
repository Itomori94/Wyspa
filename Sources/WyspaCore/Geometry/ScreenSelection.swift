import CoreGraphics

/// Opis ekranu niezależny od AppKit, żeby wybór ekranów dało się testować.
public struct ScreenInfo: Equatable, Sendable, Identifiable {
    public let id: UInt32
    public let name: String
    public let frame: CGRect
    public let notch: NotchMetrics
    public let isMain: Bool

    public init(id: UInt32, name: String, frame: CGRect, notch: NotchMetrics, isMain: Bool) {
        self.id = id
        self.name = name
        self.frame = frame
        self.notch = notch
        self.isMain = isMain
    }
}

public enum ScreenSelection: String, CaseIterable, Codable, Sendable {
    case all
    case notched
    case main

    public var displayName: String {
        switch self {
        case .all: "Na wszystkich ekranach"
        case .notched: "Tylko na ekranie z notchem"
        case .main: "Tylko na ekranie głównym"
        }
    }

    /// Gdy żaden ekran nie ma notcha, `.notched` przechodzi na ekran główny.
    public func select(from screens: [ScreenInfo]) -> [ScreenInfo] {
        switch self {
        case .all:
            return screens
        case .notched:
            let notched = screens.filter(\.notch.isPhysical)
            return notched.isEmpty ? ScreenSelection.main.select(from: screens) : notched
        case .main:
            let main = screens.filter(\.isMain)
            return main.isEmpty ? Array(screens.prefix(1)) : main
        }
    }
}

/// Zachowanie wirtualnego notcha na ekranach bez fizycznego wycięcia.
public enum VirtualNotchMode: String, CaseIterable, Codable, Sendable {
    case always
    case whenActive

    public var displayName: String {
        switch self {
        case .always: "Zawsze widoczny"
        case .whenActive: "Tylko gdy coś się dzieje"
        }
    }
}
