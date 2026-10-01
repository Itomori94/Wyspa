import Foundation
import Observation

/// Ustawienia aplikacji w UserDefaults. Każda zmiana zapisuje się od razu i jest obserwowalna.
@MainActor
@Observable
public final class SettingsStore {
    public enum Limits {
        public static let hoverDelay: ClosedRange<Double> = 0...1.5
        public static let collapseDelay: ClosedRange<Double> = 0...3
    }

    enum Key {
        static let expandOnHover = "island.expandOnHover"
        static let hoverDelay = "island.hoverDelay"
        static let collapseDelay = "island.collapseDelay"
        static let islandSize = "island.size"
        static let hapticsEnabled = "island.haptics"
        static let screenSelection = "screens.selection"
        static let virtualNotchMode = "screens.virtualNotch"
        static let toggleShortcut = "shortcut.toggle"
        static let enabledModules = "modules.enabled"
    }

    @ObservationIgnored private let defaults: UserDefaults

    public var expandOnHover: Bool { didSet { defaults.set(expandOnHover, forKey: Key.expandOnHover) } }
    public var hoverDelay: Double { didSet { defaults.set(hoverDelay, forKey: Key.hoverDelay) } }
    public var collapseDelay: Double { didSet { defaults.set(collapseDelay, forKey: Key.collapseDelay) } }
    public var hapticsEnabled: Bool { didSet { defaults.set(hapticsEnabled, forKey: Key.hapticsEnabled) } }
    public var islandSize: IslandSize { didSet { defaults.set(islandSize.rawValue, forKey: Key.islandSize) } }
    public var screenSelection: ScreenSelection {
        didSet { defaults.set(screenSelection.rawValue, forKey: Key.screenSelection) }
    }
    public var virtualNotchMode: VirtualNotchMode {
        didSet { defaults.set(virtualNotchMode.rawValue, forKey: Key.virtualNotchMode) }
    }
    /// nil = skrót wyłączony.
    public var toggleShortcut: HotkeyShortcut? {
        didSet { Self.write(toggleShortcut, key: Key.toggleShortcut, to: defaults) }
    }
    public private(set) var enabledModules: Set<String> {
        didSet { defaults.set(enabledModules.sorted(), forKey: Key.enabledModules) }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        expandOnHover = defaults.object(forKey: Key.expandOnHover) as? Bool ?? true
        hoverDelay = Self.clamped(defaults.object(forKey: Key.hoverDelay) as? Double ?? 0.15, to: Limits.hoverDelay)
        collapseDelay = Self.clamped(
            defaults.object(forKey: Key.collapseDelay) as? Double ?? 0.35, to: Limits.collapseDelay
        )
        hapticsEnabled = defaults.object(forKey: Key.hapticsEnabled) as? Bool ?? true
        islandSize = defaults.string(forKey: Key.islandSize).flatMap(IslandSize.init) ?? .medium
        screenSelection = defaults.string(forKey: Key.screenSelection).flatMap(ScreenSelection.init) ?? .all
        virtualNotchMode = defaults.string(forKey: Key.virtualNotchMode).flatMap(VirtualNotchMode.init) ?? .whenActive
        toggleShortcut = defaults.object(forKey: Key.toggleShortcut) == nil
            ? .defaultToggle
            : Self.read(HotkeyShortcut.self, key: Key.toggleShortcut, from: defaults)
        enabledModules = Set(defaults.stringArray(forKey: Key.enabledModules) ?? [])
    }

    public func isModuleEnabled(_ id: String) -> Bool {
        enabledModules.contains(id)
    }

    public func setModule(_ id: String, enabled: Bool) {
        enabledModules = enabled ? enabledModules.union([id]) : enabledModules.subtracting([id])
    }

    public func islandConfig(hidesWhenIdle: Bool) -> IslandConfig {
        IslandConfig(
            expandOnHover: expandOnHover,
            hoverDelay: hoverDelay,
            collapseDelay: collapseDelay,
            hidesWhenIdle: hidesWhenIdle
        )
    }

    /// Ustawienia jednego modułu w osobnej przestrzeni kluczy.
    public func moduleSettings(for moduleID: String) -> ModuleSettings {
        ModuleSettings(moduleID: moduleID, defaults: defaults)
    }

    static func clamped(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }

    private static func read<T: Decodable>(_ type: T.Type, key: String, from defaults: UserDefaults) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func write<T: Encodable>(_ value: T?, key: String, to defaults: UserDefaults) {
        // Pusty Data oznacza świadome wyłączenie (odróżnia od braku klucza = wartość domyślna).
        let data = value.flatMap { try? JSONEncoder().encode($0) } ?? Data()
        defaults.set(data, forKey: key)
    }
}

/// Klucze modułu mają prefiks `module.<id>.`, więc moduły nie kolidują ze sobą.
public struct ModuleSettings: @unchecked Sendable {
    private let prefix: String
    private let defaults: UserDefaults

    init(moduleID: String, defaults: UserDefaults) {
        self.prefix = "module.\(moduleID)."
        self.defaults = defaults
    }

    public func value<T: Codable>(_ key: String, default fallback: T) -> T {
        guard let data = defaults.data(forKey: prefix + key),
              let decoded = try? JSONDecoder().decode(T.self, from: data)
        else { return fallback }
        return decoded
    }

    public func set<T: Codable>(_ value: T, for key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: prefix + key)
    }
}
