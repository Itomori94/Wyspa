import SwiftUI
import UniformTypeIdentifiers
import WyspaCore
import WyspaUI

/// Graficzny edytor układu wyspy: strony, podgląd wyspy w skali, przeciąganie widżetów i dzielników.
struct BoardEditorView: View {
    static let previewWidth: CGFloat = 640

    @Bindable var settings: SettingsStore
    let registry: ModuleRegistry
    @State private var selectedPageID: UUID?
    @State private var problem: String?

    var body: some View {
        let board = registry.board
        let page = board.pages.first { $0.id == selectedPageID } ?? board.pages.first
        VStack(alignment: .leading, spacing: 14) {
            PageBar(board: board, selected: page?.id, registry: registry, select: { selectedPageID = $0 }, apply: apply)
            if let page {
                IslandPreview(page: page, board: board, settings: settings, registry: registry, apply: apply)
            } else {
                emptyBoard
            }
            Palette(registry: registry, board: board, apply: apply, removeWidget: { id in apply { board.removing(widget: id) } })
            footer
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var emptyBoard: some View {
        ContentUnavailableView("Wyspa nie ma jeszcze stron", systemImage: "rectangle.3.group",
                               description: Text("Dodaj stronę przyciskiem „+” i przeciągnij na nią widżety z listy poniżej."))
            .frame(height: 220)
    }

    private var footer: some View {
        HStack {
            if let problem {
                Label(problem, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            } else {
                Text("Wyspa „\(settings.islandSize.displayName)”. Rozmiar zmienisz w karcie Wyspa — szerokości widżetów skalują się razem z nią.")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
    }

    /// Każda zmiana układu przechodzi tędy: błąd pokazuje komunikat zamiast cicho nic nie zrobić.
    private func apply(_ change: () throws -> IslandBoard) {
        do {
            registry.setBoard(try change())
            withAnimation { problem = nil }
        } catch {
            let message = (error as? BoardError)?.message ?? error.localizedDescription
            withAnimation { problem = message }
        }
    }
}

// MARK: - Ładunki przeciągania

/// Co jest przeciągane w edytorze: moduł z palety, widżet z wyspy albo strona z paska.
enum EditorPayload {
    case module(String)
    case widget(UUID)
    case page(UUID)

    var text: String {
        switch self {
        case .module(let id): "module:\(id)"
        case .widget(let id): "widget:\(id.uuidString)"
        case .page(let id): "page:\(id.uuidString)"
        }
    }

    init?(_ text: String) {
        let parts = text.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        switch parts[0] {
        case "module": self = .module(parts[1])
        case "widget": guard let id = UUID(uuidString: parts[1]) else { return nil }; self = .widget(id)
        case "page": guard let id = UUID(uuidString: parts[1]) else { return nil }; self = .page(id)
        default: return nil
        }
    }
}

// MARK: - Pasek stron

private struct PageBar: View {
    let board: IslandBoard
    let selected: UUID?
    let registry: ModuleRegistry
    let select: (UUID) -> Void
    let apply: (() throws -> IslandBoard) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(board.pages.enumerated()), id: \.element.id) { index, page in
                PageChip(title: title(of: page), symbol: symbol(of: page), isSelected: page.id == selected,
                         select: { select(page.id) }, remove: { apply { board.removingPage(page.id) } })
                    .draggable(EditorPayload.page(page.id).text)
                    .dropDestination(for: String.self) { items, _ in
                        guard let payload = items.first.flatMap(EditorPayload.init) else { return false }
                        switch payload {
                        case .page(let id): apply { board.movingPage(id, to: index) }
                        case .widget(let id): apply { try board.moving(widget: id, toPage: page.id, at: .max, minimum: registry.minimumWidth(for:)) }
                        case .module(let id): apply { try board.inserting(moduleID: id, intoPage: page.id, at: .max, minimum: registry.minimumWidth(for:)) }
                        }
                        return true
                    }
            }
            addMenu
            Spacer()
        }
    }

    private var addMenu: some View {
        Menu {
            Button("Strona z widżetami") {
                let (next, id) = board.addingWidgetPage()
                apply { next }
                select(id)
            }
            let fullPages = registry.entries
                .filter { entry in
                    entry.isActive && entry.descriptor.providesPage
                        && !board.pages.contains { $0.content == .module(entry.id) }
                }
            if !fullPages.isEmpty {
                Divider()
                Section("Pełny widok modułu") {
                    ForEach(fullPages) { entry in
                        Button { apply { board.addingModulePage(entry.id) } } label: {
                            Label(entry.descriptor.name, systemImage: entry.descriptor.symbol)
                        }
                    }
                }
            }
        } label: {
            Label("Strona", systemImage: "plus")
        }
        .fixedSize()
        .help("Dodaj stronę")
    }

    private func title(of page: BoardPage) -> String {
        switch page.content {
        case .module(let id): registry.descriptor(for: id)?.name ?? id
        case .widgets(let widgets):
            widgets.isEmpty ? "Pusta strona" : widgets.compactMap { registry.descriptor(for: $0.moduleID)?.name }.joined(separator: " · ")
        }
    }

    private func symbol(of page: BoardPage) -> String {
        switch page.content {
        case .module(let id): registry.descriptor(for: id)?.symbol ?? "square"
        case .widgets: "rectangle.split.3x1"
        }
    }
}

private struct PageChip: View {
    let title: String
    let symbol: String
    let isSelected: Bool
    let select: () -> Void
    let remove: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
            Text(title.count > 32 ? title.prefix(31) + "…" : title).lineLimit(1)
            if isHovered {
                Button(action: remove) { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Usuń stronę")
            }
        }
        .font(.callout)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(isSelected ? Color.accentColor.opacity(0.25) : Color.primary.opacity(isHovered ? 0.1 : 0.05)))
        .overlay(Capsule().strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 1))
        .fixedSize()
        .contentShape(Capsule())
        .onTapGesture(perform: select)
        .onHover { isHovered = $0 }
        .help("Kliknij, żeby edytować. Przeciągnij, żeby zmienić kolejność stron.")
    }
}

// MARK: - Podgląd wyspy

private struct IslandPreview: View {
    let page: BoardPage
    let board: IslandBoard
    let settings: SettingsStore
    let registry: ModuleRegistry
    let apply: (() throws -> IslandBoard) -> Void
    @State private var isTargeted = false

    private var islandSize: CGSize { settings.islandSize.expandedSize }
    private var scale: CGFloat { min(1, BoardEditorView.previewWidth / islandSize.width) }
    private var inset: CGFloat { IslandLayout.expandedTopRadius + IslandLayout.expandedContentInset }
    private var notchWidth: CGFloat { ScreenInfo.current().first(where: \.notch.isPhysical)?.notch.size.width ?? 190 }
    /// Wysokość pasa nagłówka (zegar, strony) nad zawartością strony.
    private let headerHeight: CGFloat = 42

    var body: some View {
        let width = islandSize.width * scale
        let height = islandSize.height * scale
        ZStack(alignment: .top) {
            // Fragment ekranu z paskiem menu, żeby było widać, gdzie wyspa wchodzi pod notch.
            LinearGradient(colors: [Color(white: 0.32), Color(white: 0.22)], startPoint: .top, endPoint: .bottom)
                .frame(height: height + 24)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            IslandShape(topRadius: IslandLayout.expandedTopRadius * scale, bottomRadius: 28 * scale)
                .fill(.black)
                .frame(width: width, height: height)
            header(width: width)
            content
                .padding(.horizontal, inset * scale)
                .padding(.top, headerHeight * scale)
                .padding(.bottom, 16 * scale)
                .frame(width: width, height: height, alignment: .top)
        }
        .frame(maxWidth: .infinity)
        .environment(\.colorScheme, .dark)
    }

    /// Nagłówek w podglądzie: zarys notcha pośrodku i miejsce na zegar i strony.
    private func header(width: CGFloat) -> some View {
        HStack {
            Text("12:00").font(.system(size: 15 * scale, weight: .semibold, design: .rounded)).foregroundStyle(.white.opacity(0.35))
            Spacer()
            Image(systemName: "ellipsis").foregroundStyle(.white.opacity(0.35))
        }
        .padding(.horizontal, inset * scale)
        .frame(width: width, height: headerHeight * scale)
        .overlay {
            RoundedRectangle(cornerRadius: 8 * scale)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .foregroundStyle(.white.opacity(0.25))
                .frame(width: notchWidth * scale, height: 32 * scale)
                .overlay(Text("notch").font(.system(size: 9)).foregroundStyle(.white.opacity(0.3)))
                .offset(y: -4 * scale)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch page.content {
        case .module(let id):
            ModulePagePreview(registry: registry, moduleID: id, scale: scale,
                              size: CGSize(width: islandSize.width - 2 * inset, height: islandSize.height - headerHeight - 16))
        case .widgets(let widgets):
            WidgetsPreview(page: page, widgets: widgets, board: board, registry: registry, scale: scale,
                           innerWidth: islandSize.width - 2 * inset,
                           innerHeight: islandSize.height - headerHeight - 16, apply: apply)
        }
    }
}

private struct ModulePagePreview: View {
    let registry: ModuleRegistry
    let moduleID: String
    let scale: CGFloat
    let size: CGSize

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let page = registry.pages.first(where: { page in
                if case .module = page.content { return page.moduleIDs == [moduleID] }
                return false
            }) {
                PageContentView(page: page)
                    .frame(width: size.width, height: size.height, alignment: .topLeading)
                    .scaleEffect(scale, anchor: .topLeading)
                    .frame(width: size.width * scale, height: size.height * scale, alignment: .topLeading)
                    .allowsHitTesting(false)
            }
            Label("Pełny widok: \(registry.descriptor(for: moduleID)?.name ?? moduleID)", systemImage: "rectangle.fill")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(.white.opacity(0.15)))
                .foregroundStyle(.white)
                .padding(6)
        }
    }
}

private struct WidgetsPreview: View {
    private static let coordinateSpace = "widgetsPreview"

    let page: BoardPage
    let widgets: [BoardWidget]
    let board: IslandBoard
    let registry: ModuleRegistry
    let scale: CGFloat
    let innerWidth: CGFloat
    let innerHeight: CGFloat
    let apply: (() throws -> IslandBoard) -> Void
    @State private var dropIndex: Int?
    /// Szkic układu w trakcie przeciągania dzielnika: rysowany od razu, zapisywany dopiero po puszczeniu.
    @State private var draft: IslandBoard?
    @State private var draggedDivider: Int?

    private var shown: [BoardWidget] {
        draft?.pages.first { $0.id == page.id }?.widgets ?? widgets
    }

    private var gap: CGFloat { WidgetRow.dividerSpacing }
    private var unit: CGFloat { max(0, innerWidth - CGFloat(max(shown.count - 1, 0)) * gap) / CGFloat(WidgetWidth.totalUnits) }

    var body: some View {
        let shown = shown
        HStack(spacing: 0) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, widget in
                if index > 0 { divider(after: index - 1) }
                WidgetCard(widget: widget, registry: registry, scale: scale,
                           realSize: CGSize(width: unit * CGFloat(widget.width.units), height: innerHeight),
                           isDropBefore: dropIndex == index,
                           showsWidth: draggedDivider.map { $0 == index || $0 + 1 == index } ?? false,
                           remove: { apply { board.removing(widget: widget.id) } })
            }
            if shown.isEmpty {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    .foregroundStyle(.white.opacity(dropIndex == nil ? 0.3 : 0.8))
                    .overlay(Text("Przeciągnij tu widżety z listy poniżej").font(.callout).foregroundStyle(.white.opacity(0.6)))
            } else if dropIndex == shown.count {
                Capsule().fill(Color.accentColor).frame(width: 3).padding(.vertical, 6)
            }
            Spacer(minLength: 0)
        }
        .frame(height: innerHeight * scale)
        .coordinateSpace(.named(Self.coordinateSpace))
        .dropDestination(for: String.self) { items, location in
            defer { dropIndex = nil }
            guard let payload = items.first.flatMap(EditorPayload.init) else { return false }
            let index = insertionIndex(at: location.x)
            switch payload {
            case .module(let id):
                apply { try board.inserting(moduleID: id, intoPage: page.id, at: index, minimum: registry.minimumWidth(for:)) }
            case .widget(let id):
                apply { try board.moving(widget: id, toPage: page.id, at: index, minimum: registry.minimumWidth(for:)) }
            case .page:
                return false
            }
            return true
        } isTargeted: { targeted in
            if !targeted { dropIndex = nil }
        }
    }

    /// Miejsce wstawienia: liczba widżetów, których środek leży na lewo od kursora.
    private func insertionIndex(at x: CGFloat) -> Int {
        var position: CGFloat = 0
        for (index, widget) in widgets.enumerated() {
            let width = unit * CGFloat(widget.width.units) * scale
            if x < position + width / 2 { return index }
            position += width + gap * scale
        }
        return widgets.count
    }

    /// Dzielnik z uchwytem: płynna zmiana szerokości sąsiednich widżetów.
    ///
    /// Przesunięcie liczone we współrzędnych całego wiersza (dzielnik sam się przesuwa, więc jego własne
    /// współrzędne dawałyby skaczący punkt odniesienia), a układ zapisywany raz, po puszczeniu.
    private func divider(after index: Int) -> some View {
        ZStack {
            Capsule().fill(.white.opacity(draggedDivider == index ? 0.4 : 0.18)).frame(width: 2).padding(.vertical, 10)
            Capsule().fill(.white.opacity(draggedDivider == index ? 1 : 0.85)).frame(width: 6, height: 26)
        }
        .frame(width: gap * scale)
        .contentShape(Rectangle())
        .onHover { inside in inside ? NSCursor.resizeLeftRight.push() : NSCursor.pop() }
        .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .named(Self.coordinateSpace))
            .onChanged { value in
                draggedDivider = index
                let delta = Int((value.translation.width / (unit * scale)).rounded())
                draft = try? board.movingDivider(onPage: page.id, after: index, by: delta, minimum: registry.minimumWidth(for:))
            }
            .onEnded { _ in
                if let draft { apply { draft } }
                draft = nil
                draggedDivider = nil
            })
        .help("Przeciągnij, żeby zmienić szerokość widżetów")
    }
}

private struct WidgetCard: View {
    let widget: BoardWidget
    let registry: ModuleRegistry
    let scale: CGFloat
    let realSize: CGSize
    let isDropBefore: Bool
    /// Procent szerokości pokazywany w trakcie przeciągania sąsiedniego dzielnika.
    let showsWidth: Bool
    let remove: () -> Void
    @State private var isHovered = false

    var body: some View {
        let descriptor = registry.descriptor(for: widget.moduleID)
        ZStack(alignment: .topTrailing) {
            Group {
                if let view = registry.widgetView(for: widget.moduleID) {
                    view
                        .frame(width: realSize.width, height: realSize.height, alignment: .topLeading)
                        .scaleEffect(scale, anchor: .topLeading)
                        .frame(width: realSize.width * scale, height: realSize.height * scale, alignment: .topLeading)
                        .allowsHitTesting(false)
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: descriptor?.symbol ?? "square").font(.title2)
                        Text("\(descriptor?.name ?? widget.moduleID) — włącz moduł").font(.caption)
                    }
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(width: realSize.width * scale, height: realSize.height * scale)
                }
            }
            .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(isHovered ? 0.08 : 0.03)))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(isHovered || showsWidth ? 0.5 : 0.12), lineWidth: 1))
            .overlay {
                if showsWidth {
                    Text("\(Int((widget.width.fraction * 100).rounded()))%")
                        .font(.caption.weight(.bold)).monospacedDigit()
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(.black.opacity(0.75)))
                }
            }

            if isHovered && !showsWidth {
                Button(action: remove) {
                    Image(systemName: "xmark.circle.fill").font(.title3)
                        .symbolRenderingMode(.palette).foregroundStyle(.white, .black.opacity(0.7))
                }
                .buttonStyle(.plain)
                .help("Usuń z wyspy")
                .padding(6)
            }
        }
        .overlay(alignment: .leading) {
            if isDropBefore { Capsule().fill(Color.accentColor).frame(width: 3).offset(x: -6) }
        }
        .draggable(EditorPayload.widget(widget.id).text) {
            Label(descriptor?.name ?? widget.moduleID, systemImage: descriptor?.symbol ?? "square")
                .padding(8).background(.regularMaterial, in: Capsule())
        }
        .onHover { isHovered = $0 }
    }
}

// MARK: - Paleta

private struct Palette: View {
    let registry: ModuleRegistry
    let board: IslandBoard
    let apply: (() throws -> IslandBoard) -> Void
    let removeWidget: (UUID) -> Void
    @State private var isTargeted = false

    var body: some View {
        let entries = registry.entries.filter { $0.descriptor.widgetMinWidth != nil }
        VStack(alignment: .leading, spacing: 8) {
            Text("Widżety — przeciągnij na wyspę. Przeciągnij widżet z wyspy tutaj, żeby go usunąć.")
                .font(.caption)
                .foregroundStyle(.secondary)
            FlowLayout(spacing: 6) {
                ForEach(entries) { entry in
                    PaletteChip(entry: entry, isPlaced: board.contains(moduleID: entry.id))
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(isTargeted ? 0.12 : 0.04)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(isTargeted ? Color.red.opacity(0.6) : .clear, lineWidth: 1.5))
        .dropDestination(for: String.self) { items, _ in
            guard case .widget(let id) = items.first.flatMap(EditorPayload.init) else { return false }
            removeWidget(id)
            return true
        } isTargeted: { isTargeted = $0 }
    }
}

private struct PaletteChip: View {
    let entry: ModuleEntry
    let isPlaced: Bool

    var body: some View {
        let chip = HStack(spacing: 6) {
            Image(systemName: entry.descriptor.symbol)
            Text(entry.descriptor.name)
            if isPlaced { Image(systemName: "checkmark").font(.caption2).foregroundStyle(.secondary) }
        }
        .font(.callout)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.primary.opacity(entry.isActive ? 0.08 : 0.03)))
        .foregroundStyle(entry.isActive ? .primary : .tertiary)

        if entry.isActive {
            chip
                .draggable(EditorPayload.module(entry.id).text) { chip }
                .help("Przeciągnij na stronę wyspy")
        } else {
            chip.help("Włącz moduł „\(entry.descriptor.name)” w karcie Moduły")
        }
    }
}

/// Prosty układ zawijający elementy do kolejnych wierszy.
private struct FlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth.isFinite ? maxWidth : x, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
