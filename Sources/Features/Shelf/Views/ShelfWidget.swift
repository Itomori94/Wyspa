import SwiftUI
import WyspaCore
import WyspaUI

/// Mała półka: strefa upuszczania z liczbą elementów i ostatnimi plikami; pełna półka na osobnej stronie.
struct ShelfWidget: View {
    let module: ShelfModule
    @Environment(\.islandDropTarget) private var dropTarget

    var body: some View {
        let isTargeted = dropTarget == ShelfModule.Zone.store
        VStack(spacing: 6) {
            Image(systemName: module.items.isEmpty ? "tray" : "tray.full")
                .font(.system(size: 22, weight: .medium))
                .symbolEffect(.bounce, value: isTargeted)
            Text(module.items.isEmpty ? "Upuść pliki" : PolishPlural.format(module.items.count, one: "element", few: "elementy", many: "elementów"))
                .font(.system(size: 11, weight: .semibold))
            if let latest = module.items.last {
                Text(latest.name).font(.system(size: 9.5)).foregroundStyle(.white.opacity(0.45)).lineLimit(1).truncationMode(.middle)
            }
        }
        .foregroundStyle(.white.opacity(isTargeted ? 1 : 0.75))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(isTargeted ? 0.7 : 0.18), style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
                .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(isTargeted ? 0.12 : 0.03)))
        )
        .islandDropZone(ShelfModule.Zone.store)
        .onTapGesture { module.quickLook() }
    }
}
