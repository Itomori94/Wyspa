import Foundation

/// Bezpieczne ładowanie funkcji z prywatnych frameworków (`dlopen` + `dlsym`).
///
/// Zwraca nil, gdy framework albo symbol zniknie w nowej wersji macOS; wywołujący wyłącza wtedy funkcję.
public enum PrivateSymbol {
    public static func load<Function>(_ symbol: String, from path: String, as type: Function.Type) -> Function? {
        guard let handle = dlopen(path, RTLD_NOW | RTLD_LOCAL) else {
            Log.logger("private-api").error("Brak biblioteki \(path, privacy: .public)")
            return nil
        }
        guard let pointer = dlsym(handle, symbol) else {
            Log.logger("private-api").error("Brak symbolu \(symbol, privacy: .public) w \(path, privacy: .public)")
            return nil
        }
        return unsafeBitCast(pointer, to: type)
    }
}
