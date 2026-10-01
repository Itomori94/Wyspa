import AppKit
import SwiftUI

struct ShelfTile: View {
    private static let thumbnailSide: CGFloat = 52

    let module: ShelfModule
    let item: ShelfItem
    let isSelected: Bool
    @State private var thumbnail: NSImage?
    @State private var isHovered = false

    var body: some View {
        let url = module.url(for: item)
        VStack(spacing: 4) {
            ZStack {
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(systemName: url == nil ? "questionmark.folder" : "doc")
                        .font(.system(size: 22))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .frame(width: Self.thumbnailSide, height: Self.thumbnailSide)
            .opacity(url == nil ? 0.4 : 1)
            Text(item.name)
                .font(.system(size: 9.5, weight: .medium))
                .lineLimit(2)
                .truncationMode(.middle)
                .multilineTextAlignment(.center)
                .frame(width: 66, height: 24, alignment: .top)
        }
        .padding(5)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.accentColor.opacity(isSelected ? 0.45 : 0))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.white.opacity(isHovered && !isSelected ? 0.08 : 0))
                )
        )
        .overlay(
            ShelfTileInteraction(
                onClick: { module.click(item.id, modifier: $0) },
                onOpen: { module.open(item.id) },
                dragURLs: { module.dragURLs(grabbing: item.id) },
                menu: { makeMenu() }
            )
        )
        .onHover { isHovered = $0 }
        .help(url?.path ?? "Oryginał niedostępny")
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .task(id: url) {
            guard let url else { return }
            thumbnail = await Thumbnails.shared.thumbnail(for: url, side: Self.thumbnailSide)
        }
    }

    private func makeMenu() -> NSMenu {
        let id = item.id
        return ClosureMenu.make([
            ("Otwórz", { module.open(id) }),
            ("Podgląd", { module.quickLook(grabbing: id) }),
            ("Pokaż w Finderze", { module.revealInFinder(id) }),
            nil,
            ("Zaznacz wszystko", { module.selectAll() }),
            ("Usuń z półki", { module.remove(module.selection.dragSet(grabbing: id)) }),
        ])
    }
}

/// Menu kontekstowe z akcjami jako domknięciami (nil = separator).
@MainActor
enum ClosureMenu {
    static func make(_ entries: [(String, () -> Void)?]) -> NSMenu {
        let menu = NSMenu()
        for entry in entries {
            guard let (title, action) = entry else {
                menu.addItem(.separator())
                continue
            }
            let item = NSMenuItem(title: title, action: #selector(ClosureMenuItemTarget.invoke(_:)), keyEquivalent: "")
            let target = ClosureMenuItemTarget(action: action)
            item.target = target
            item.representedObject = target // menu nie trzyma celu, więc trzymamy go w elemencie
            menu.addItem(item)
        }
        return menu
    }
}

final class ClosureMenuItemTarget: NSObject {
    private let action: () -> Void
    init(action: @escaping () -> Void) { self.action = action }
    @objc func invoke(_ sender: Any?) { action() }
}
