import Foundation
import UniformTypeIdentifiers

/// Moduł przyjmujący przeciągane elementy (pliki, obrazy, linki).
///
/// Wyspa ma jeden cel upuszczania; moduł oznacza w swoim widoku strefy (`islandDropZone(_:)`)
/// o identyfikatorach z prefiksem `<id modułu>.` i dostaje upuszczenie razem z identyfikatorem strefy.
@MainActor
public protocol IslandDropHandling: IslandModule {
    static var acceptedDropTypes: [UTType] { get }

    /// `zoneID` = strefa pod kursorem albo nil, gdy upuszczono poza strefami (moduł wybiera domyślną).
    func performDrop(_ providers: [NSItemProvider], zoneID: String?) -> Bool
}

public enum DropZoneID {
    /// Moduł, do którego należy strefa (`"shelf.airdrop"` → `"shelf"`).
    public static func moduleID(of zoneID: String) -> String {
        String(zoneID.prefix { $0 != "." })
    }
}
