import SwiftUI
import WyspaUI

struct ShelfExpandedView: View {
    let module: ShelfModule
    @Environment(\.islandDropTarget) private var dropTarget

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                ShelfToolbar(module: module)
                StoreZone(module: module, isTargeted: dropTarget == ShelfModule.Zone.store)
            }
            AirDropZone(module: module, isTargeted: dropTarget == ShelfModule.Zone.airDrop)
        }
    }
}

private struct ShelfToolbar: View {
    let module: ShelfModule
    @State private var confirmingClear = false

    var body: some View {
        let count = module.items.count
        let selected = module.selection.selected.count
        HStack(spacing: 6) {
            if let problem = module.problem {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .lineLimit(1)
                    .onTapGesture(perform: module.dismissProblem)
            } else {
                Text(summary(count: count, selected: selected))
                    .foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
            if selected > 0 {
                ToolbarButton(symbol: "eye", label: "Podgląd") { module.quickLook() }
                ToolbarButton(symbol: "xmark.bin", label: "Usuń z półki") { module.remove(module.selection.selected) }
            }
            if count > 0 {
                if confirmingClear {
                    Button("Wyczyścić półkę?") {
                        module.removeAll()
                        confirmingClear = false
                    }
                    .buttonStyle(IslandCapsuleButtonStyle())
                    .tint(.red)
                    ToolbarButton(symbol: "xmark", label: "Anuluj") { confirmingClear = false }
                } else {
                    ToolbarButton(symbol: "trash", label: "Wyczyść półkę") { confirmingClear = true }
                }
            }
        }
        .font(.system(size: 11, weight: .medium))
        .frame(height: 22)
        .animation(.easeOut(duration: 0.15), value: confirmingClear)
    }

    private func summary(count: Int, selected: Int) -> String {
        guard count > 0 else { return "Półka" }
        let items = PolishPlural.format(count, one: "element", few: "elementy", many: "elementów")
        return selected > 0 ? "\(items) · zaznaczono \(selected)" : items
    }
}

private struct ToolbarButton: View {
    let symbol: String
    let label: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 24, height: 22)
                .background(Capsule().fill(.white.opacity(isHovered ? 0.16 : 0.07)))
        }
        .buttonStyle(IslandPressStyle())
        .onHover { isHovered = $0 }
        .help(label)
        .accessibilityLabel(label)
    }
}

private struct StoreZone: View {
    let module: ShelfModule
    let isTargeted: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.white.opacity(isTargeted ? 0.12 : 0.05))
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    .white.opacity(isTargeted ? 0.7 : 0.16),
                    style: StrokeStyle(lineWidth: isTargeted ? 1.5 : 1, dash: module.items.isEmpty ? [5, 4] : [])
                )
            if module.items.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "tray.and.arrow.down")
                        .font(.system(size: 20, weight: .medium))
                        .symbolEffect(.bounce, value: isTargeted)
                    Text("Upuść tu pliki, obrazy albo linki")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(.white.opacity(isTargeted ? 0.9 : 0.45))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 6) {
                        ForEach(module.items) { item in
                            ShelfTile(module: module, item: item, isSelected: module.selection.selected.contains(item.id))
                        }
                    }
                    .padding(.horizontal, 8)
                }
                .contentShape(Rectangle())
                .onTapGesture(perform: module.clearSelection)
            }
        }
        .scaleEffect(isTargeted ? 1.015 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isTargeted)
        .islandDropZone(ShelfModule.Zone.store)
    }
}

private struct AirDropZone: View {
    let module: ShelfModule
    let isTargeted: Bool
    @State private var isHovered = false

    var body: some View {
        let hasSelection = !module.selection.selected.isEmpty
        Button(action: module.airDropSelection) {
            VStack(spacing: 6) {
                Image(systemName: "airplayaudio")
                    .font(.system(size: 22, weight: .medium))
                    .symbolEffect(.pulse, isActive: isTargeted)
                Text(hasSelection ? "Wyślij zaznaczone" : "AirDrop")
                    .font(.system(size: 11, weight: .semibold))
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(isTargeted ? .white : .white.opacity(0.7))
            .frame(width: 86)
            .frame(maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.accentColor.opacity(isTargeted ? 0.55 : (isHovered && hasSelection ? 0.3 : 0.16)))
            )
        }
        .buttonStyle(IslandPressStyle())
        .disabled(!hasSelection && !isTargeted)
        .onHover { isHovered = $0 }
        .help("Upuść tu pliki albo zaznacz elementy na półce, żeby wysłać je przez AirDrop")
        .animation(.easeOut(duration: 0.15), value: isTargeted)
        .islandDropZone(ShelfModule.Zone.airDrop)
    }
}
