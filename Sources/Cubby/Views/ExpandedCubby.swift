import SwiftUI

/// The open cubby: a glass card with the items in a grid, scrolling under a translucent
/// header and footer.
struct ExpandedCubby: View {
    let items: [CubbyItem]
    let isTargeted: Bool
    @Environment(CubbyStore.self) private var store
    @Environment(PanelController.self) private var panel

    static let columnCount = 4
    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: columnCount)

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 40, style: .continuous)
        let sorted = store.shown(items)
        // Everything that sets up the scroll view stays inside the reader.
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: Self.columns, spacing: 8) {
                    ForEach(sorted) { item in
                        GridItemView(
                            item: item,
                            isSelected: store.selection.contains(item.id),
                            select: { store.select(item.id, extending: $0, in: sorted.map(\.id)) },
                            dragGroup: { dragGroup(for: item, in: sorted) }
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .animation(PanelController.animation, value: store.sortOrder)
            }
            .onChange(of: store.cursorID) { _, id in
                // Keep the item the arrow keys moved to in view.
                guard let id else { return }
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id) }
            }
            .scrollIndicators(.never)
            // Clicking between items clears the selection.
            .contentShape(Rectangle())
            .onTapGesture { store.clearSelection() }
            .overlay {
                if items.isEmpty { emptyState }
            }
            // The system's progressive blur where items scroll under the header and footer.
            .scrollEdgeEffectStyle(.soft, for: .vertical)
            .safeAreaBar(edge: .top) {
                VStack(spacing: 12) {
                    topBar
                    if !store.missingNames.isEmpty {
                        MissingNotice(names: store.missingNames) {
                            withAnimation(PanelController.animation) { store.missingNames = [] }
                        }
                        .padding(.horizontal, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 8)
                .animation(PanelController.animation, value: store.missingNames)
            }
        }
        .frame(width: PanelController.expandedSize.width, height: PanelController.expandedSize.height)
        .clipShape(shape)
        .glassSurface(shape)
        .overlay {
            if isTargeted { shape.stroke(.tint, lineWidth: 2) }
        }
        .onAppear { store.tidy() }
        // A tab whose last item left goes back to All.
        .onChange(of: kinds) { _, kinds in
            if let kind = store.kindFilter, !kinds.contains(kind) { store.kindFilter = nil }
        }
    }

    /// The kinds there are items of, in tab order. Empty kinds get no tab.
    private var kinds: [ItemKind] {
        let present = Set(items.map(\.kind))
        return ItemKind.tabOrder.filter(present.contains)
    }

    /// Dragging a selected item takes the whole selection along, the item under the
    /// pointer first; dragging any other item takes just that one.
    private func dragGroup(for item: CubbyItem, in sorted: [CubbyItem]) -> [CubbyItem] {
        guard store.selection.contains(item.id) else {
            store.clearSelection()
            return [item]
        }
        return [item] + sorted.filter { $0.id != item.id && store.selection.contains($0.id) }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 36, weight: .light))
                .padding(.bottom, 4)
            Text("Drop files, links or text here")
                .font(.headline)
            Text("or paste with \u{2318}V")
                .font(.callout)
        }
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .allowsHitTesting(false)
    }

    /// The tabs with their counts on the left, the close button on the right.
    private var topBar: some View {
        HStack(alignment: .center, spacing: 8) {
            if !items.isEmpty {
                KindTabs(
                    kinds: kinds,
                    total: items.count,
                    counts: Dictionary(grouping: items, by: \.kind).mapValues(\.count),
                    selection: Bindable(store).kindFilter
                )
            }
            Spacer(minLength: 0)
            CloseButton { panel.collapse() }
        }
    }
}

/// Says which items left the cubby on their own because their file was moved or deleted
/// outside it. Goes away on its own after a while, or with its close button.
private struct MissingNotice: View {
    let names: [String]
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.circle")
                .foregroundStyle(.secondary)
            Text(message)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Dismiss")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.fill.secondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .task(id: names) {
            try? await Task.sleep(for: .seconds(8))
            if !Task.isCancelled { dismiss() }
        }
    }

    private var message: String {
        if names.count == 1 {
            "\u{201C}\(names[0])\u{201D} is no longer here. Its file was moved or deleted outside Cubby."
        } else {
            "\(names.count) items are no longer here. Their files were moved or deleted outside Cubby."
        }
    }
}

/// A round Liquid Glass button that closes the card back into the folder, like the
/// + button in StickyToDo's header: it grows a little under the pointer.
private struct CloseButton: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 18, weight: .medium))
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .controlSize(.extraLarge)
        .help("Close")
        .accessibilityLabel("Close")
        .scaleEffect(isHovered ? 1.1 : 1)
        .animation(.spring(response: 0.28, dampingFraction: 0.7), value: isHovered)
        .onHover { isHovered = $0 }
        .pointingHandCursor()
    }
}

/// A row of pills, one per kind of item, after All, each with how many there are. Native
/// Liquid Glass button styles do the styling: `.glass` at rest, `.glassProminent` in the
/// accent color when chosen, the same as the category tabs in StickyToDo. When every
/// kind is there and the row doesn't fit, it falls back to smaller pills.
private struct KindTabs: View {
    let kinds: [ItemKind]
    let total: Int
    let counts: [ItemKind: Int]
    @Binding var selection: ItemKind?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row.controlSize(.regular)
            row.controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var row: some View {
        HStack(spacing: 6) {
            tab("All", count: total, kind: nil)
            ForEach(kinds, id: \.self) { tab($0.pluralTitle, count: counts[$0] ?? 0, kind: $0) }
        }
        .fixedSize()
    }

    @ViewBuilder
    private func tab(_ title: String, count: Int, kind: ItemKind?) -> some View {
        let isSelected = selection == kind
        let choose = { withAnimation(.easeInOut(duration: 0.12)) { selection = kind } }
        let label = HStack(spacing: 4) {
            Text(title)
            Text(count, format: .number)
                .monospacedDigit()
                .opacity(0.55)
        }
        Group {
            if isSelected {
                Button(action: choose) { label }
                    .buttonStyle(.glassProminent)
            } else {
                Button(action: choose) { label }
                    .buttonStyle(.glass)
            }
        }
        .buttonBorderShape(.capsule)
        .font(.system(size: 13))
        .lineLimit(1)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .pointingHandCursor()
    }
}

/// An item in the grid: its preview with its name underneath. Click to open or copy,
/// right-click for more, drag to move it out.
private struct GridItemView: View {
    let item: CubbyItem
    let isSelected: Bool
    /// ⌘- or ⇧-click; true extends the selection as a range.
    let select: (_ extending: Bool) -> Void
    let dragGroup: () -> [CubbyItem]
    @Environment(CubbyStore.self) private var store
    @Environment(PanelController.self) private var panel
    @State private var showsCopied = false

    private static let iconSize: CGFloat = 72

    var body: some View {
        VStack(spacing: 8) {
            ItemGlyph(item: item, size: Self.iconSize, natural: true)
            Text(showsCopied ? "Copied" : label)
                .font(.callout)
                .foregroundStyle(showsCopied ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background {
            if isSelected {
                Color.clear.glassSurface(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .overlay {
            ItemInteraction(
                drag: startDrag,
                menu: { rightClicked(); return menu },
                onClick: click,
                onDragEnd: { store.dragEnded(Array(store.draggedItemIDs), delivered: $0) }
            )
        }
        .onHover { inside in
            if inside {
                store.hoveredItemID = item.id
            } else if store.hoveredItemID == item.id {
                store.hoveredItemID = nil
            }
        }
        .pointingHandCursor()
    }

    /// Right-clicking an item that isn't selected selects just it, as in Finder; one
    /// that is keeps the selection.
    private func rightClicked() {
        guard !store.selection.contains(item.id) else { return }
        store.clearSelection()
        select(false)
    }

    /// The selected items when this one is among several, for Move to Bin and Remove.
    private var group: [CubbyItem] {
        store.selection.contains(item.id) && store.selection.count > 1 ? store.selectedItems() : [item]
    }

    /// One item for the whole group when several are selected.
    private var removeGroupItem: NSMenuItem? {
        let group = group
        guard group.count > 1 else { return nil }
        let hasFiles = group.contains { $0.fileURL != nil }
        let title = hasFiles ? "Move \(group.count) Items to Bin" : "Remove \(group.count) Items"
        return ActionMenuItem(title) { store.moveToBin(group, actionName: hasFiles ? "Move to Bin" : "Remove") }
    }

    /// Move to Desktop for every file in the selection when several are selected.
    private var moveGroupToDesktopItem: NSMenuItem? {
        let files = group.filter { $0.fileURL != nil }
        guard files.count > 1 else { return nil }
        return ActionMenuItem("Move \(files.count) Items to Desktop") { store.moveToDesktop(files) }
    }

    /// Files get the same menu as on the Desktop, plus Move to Desktop. Links, colors
    /// and text get a short one.
    private var menu: NSMenu {
        let menu = NSMenu()
        guard let url = item.fileURL else {
            if item.kind == .link { menu.addItem(ActionMenuItem("Open") { store.open(item) }) }
            menu.addItem(ActionMenuItem("Copy") { copy() })
            menu.addItem(.separator())
            menu.addItem(removeGroupItem ?? ActionMenuItem("Remove") { store.remove(item) })
            return menu
        }
        menu.addItem(ActionMenuItem("Open") { store.open(item) })
        menu.addItem(openWithMenu(for: url))
        menu.addItem(.separator())
        menu.addItem(moveGroupToDesktopItem ?? ActionMenuItem("Move to Desktop") { store.moveToDesktop([item]) })
        menu.addItem(removeGroupItem ?? ActionMenuItem("Move to Bin") { store.moveToBin(item) })
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem("Get Info") { store.showInfo(item) })
        menu.addItem(ActionMenuItem("Rename…") { panel.rename(item) })
        menu.addItem(ActionMenuItem("Compress \u{201C}\(url.lastPathComponent)\u{201D}") { store.compress(item) })
        menu.addItem(ActionMenuItem("Duplicate") { store.duplicate(item) })
        menu.addItem(ActionMenuItem("Quick Look") { QuickLook.shared.show(url) })
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem("Copy") { copy() })
        menu.addItem(NSSharingServicePicker(items: [url]).standardShareMenuItem)
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem("Show in Finder") { store.revealInFinder(item) })
        return menu
    }

    /// The apps that can open the file, the default first, as in Finder.
    private func openWithMenu(for url: URL) -> NSMenuItem {
        let submenu = NSMenu()
        let defaultApp = NSWorkspace.shared.urlForApplication(toOpen: url)
        let others = NSWorkspace.shared.urlsForApplications(toOpen: url).filter { $0 != defaultApp }
        func appItem(_ app: URL, isDefault: Bool) -> NSMenuItem {
            let name = (FileManager.default.displayName(atPath: app.path) as NSString).deletingPathExtension
            let menuItem = ActionMenuItem(isDefault ? "\(name) (default)" : name) {
                store.open(item, withApplicationAt: app)
            }
            let icon = NSWorkspace.shared.icon(forFile: app.path)
            icon.size = NSSize(width: 16, height: 16)
            menuItem.image = icon
            return menuItem
        }
        if let defaultApp {
            submenu.addItem(appItem(defaultApp, isDefault: true))
            if !others.isEmpty { submenu.addItem(.separator()) }
        }
        for app in others { submenu.addItem(appItem(app, isDefault: false)) }
        let menuItem = NSMenuItem(title: "Open With", action: nil, keyEquivalent: "")
        menuItem.submenu = submenu
        return menuItem
    }

    private var label: String {
        switch item.kind {
        case .link: item.title ?? item.domain
        case .image, .file: item.fileName ?? item.text
        case .color, .text: item.text
        }
    }

    /// A plain click opens or copies; ⌘ or ⇧ picks the item instead.
    private func click(_ modifiers: NSEvent.ModifierFlags) {
        if modifiers.contains(.command) || modifiers.contains(.shift) {
            select(modifiers.contains(.shift))
        } else {
            store.clearSelection()
            activate()
        }
    }

    private func startDrag() -> (pieces: [ItemInteraction.Piece], movesOut: Bool) {
        let group = dragGroup()
        store.draggedItemIDs = Set(group.map(\.id))
        let pieces = group.map { item in
            ItemInteraction.Piece(
                writer: store.pasteboardWriter(for: item),
                image: ImageRenderer(content: ItemGlyph(item: item, size: Self.iconSize, natural: true)).nsImage
            )
        }
        return (pieces, group.contains { store.movesOut($0) })
    }

    /// Files, images and links open; colors and text are copied.
    private func activate() {
        switch item.kind {
        case .file, .image, .link: store.open(item)
        case .color, .text: copy()
        }
    }

    private func copy() {
        store.copy(item)
        withAnimation(.easeOut(duration: 0.15)) { showsCopied = true }
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            withAnimation(.easeOut(duration: 0.3)) { showsCopied = false }
        }
    }
}
