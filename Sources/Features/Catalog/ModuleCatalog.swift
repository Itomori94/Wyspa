import WyspaCore
import WyspaMedia
import WyspaShelf

/// Jedyne miejsce rejestracji modułów. Nowy moduł = nowy target w Sources/Features i jedna linia tutaj.
public enum ModuleCatalog {
    @MainActor
    public static let all: [any IslandModule.Type] = [
        MediaModule.self,
        ShelfModule.self,
    ]
}
