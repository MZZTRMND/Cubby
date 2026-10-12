import SwiftUI
import UniformTypeIdentifiers

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
                if items.isEmpty {
                    emptyState
                } else if sorted.isEmpty, store.isSearching {
                    noMatches
                }
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

    private var noMatches: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32, weight: .light))
                .padding(.bottom, 4)
            Text("Nothing called \u{201C}\(store.searchText)\u{201D}")
                .font(.headline)
                .lineLimit(2)
        }
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 32)
        .allowsHitTesting(false)
    }

    /// The tabs with their counts on the left, or what's been typed while finding; the
    /// close button on the right.
    private var topBar: some View {
        HStack(alignment: .center, spacing: 8) {
            if store.isSearching {
                SearchPill(text: store.searchText) { store.searchText = "" }
                    .transition(.blurReplace)
            } else if !items.isEmpty {
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
        .animation(.easeInOut(duration: 0.15), value: store.isSearching)
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

/// What's been typed to find items, with a blinking caret, in a glass pill like the tabs
/// it stands in for. The button clears it, as Esc does.
private struct SearchPill: View {
    let text: String
    let clear: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            HStack(spacing: 1) {
                Text(text)
                    .lineLimit(1)
                    .truncationMode(.head)
                Caret()
            }
            Button(action: clear) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Clear")
            .accessibilityLabel("Clear")
            .pointingHandCursor()
        }
        .font(.system(size: 13))
        .padding(.horizontal, 12)
        .frame(height: 30)
        .glassSurface(Capsule())
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct Caret: View {
    @State private var isOn = true

    var body: some View {
        Rectangle()
            .fill(.tint)
            .frame(width: 1.5, height: 15)
            .opacity(isOn ? 1 : 0)
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(530))
                    isOn.toggle()
                }
            }
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
            // Every kind there at once: small pills that scroll sideways.
            ScrollView(.horizontal) { row.controlSize(.small).padding(.vertical, 4) }
                .scrollIndicators(.never)
                .padding(.vertical, -4)
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
            VStack(spacing: 1) {
                Text(showsCopied ? "Copied" : item.label)
                    .font(.callout)
                    .foregroundStyle(showsCopied ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let note = item.note {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .padding(.horizontal, 4)
        }
        .help(item.note ?? "")
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background {
            if isSelected {
                // Glass with a light wash of blue.
                Color.clear.glassSurface(RoundedRectangle(cornerRadius: 16, style: .continuous),
                                         glass: .regular.tint(.blue.opacity(0.1)))
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

    /// Files get the same menu as on the Desktop, plus Move to Desktop and, for images,
    /// Quick Actions. Links, colors and text get a short one.
    private var menu: NSMenu {
        let menu = NSMenu()
        guard let url = item.fileURL else {
            if item.kind == .link { menu.addItem(ActionMenuItem("Open") { store.open(item) }) }
            menu.addItem(ActionMenuItem("Copy") { copy() })
            if item.kind == .color, let copyAs = copyAsMenu { menu.addItem(copyAs) }
            menu.addItem(shareItem)
            menu.addItem(.separator())
            menu.addItem(ActionMenuItem("Rename…") { panel.rename(item) })
            menu.addItem(noteItem)
            menu.addItem(.separator())
            menu.addItem(removeGroupItem ?? ActionMenuItem("Remove") { store.remove(item) })
            return menu
        }
        let files = group.filter { $0.fileURL != nil }
        menu.addItem(ActionMenuItem("Open") { store.open(item) })
        menu.addItem(openWithMenu(for: url))
        menu.addItem(.separator())
        menu.addItem(moveGroupToDesktopItem ?? ActionMenuItem("Move to Desktop") { store.moveToDesktop([item]) })
        menu.addItem(removeGroupItem ?? ActionMenuItem("Move to Bin") { store.moveToBin(item) })
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem("Get Info") { store.showInfo(item) })
        menu.addItem(ActionMenuItem("Rename…") { panel.rename(item) })
        menu.addItem(noteItem)
        menu.addItem(files.count > 1
            ? ActionMenuItem("Compress \(files.count) Items") { store.compress(files) }
            : ActionMenuItem("Compress \u{201C}\(url.lastPathComponent)\u{201D}") { store.compress(item) })
        menu.addItem(ActionMenuItem("Duplicate") { store.duplicate(item) })
        menu.addItem(ActionMenuItem("Quick Look") { QuickLook.shared.show(url) })
        if let quickActions = quickActionsMenu { menu.addItem(quickActions) }
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem("Copy") { copy() })
        menu.addItem(shareItem)
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem("Show in Finder") { store.revealInFinder(item) })
        return menu
    }

    private var noteItem: NSMenuItem {
        ActionMenuItem(item.note == nil ? "Add Note…" : "Edit Note…") { panel.editNote(item) }
    }

    /// Share, with AirDrop among the rest, for the whole selection when this item is in it.
    private var shareItem: NSMenuItem {
        let things: [Any] = group.map { item in
            if let url = item.fileURL { return url }
            if item.kind == .link, let url = URL(string: item.text) { return url }
            return item.text
        }
        return NSSharingServicePicker(items: things).standardShareMenuItem
    }

    /// The color written each way it can be copied; picking one copies it.
    private var copyAsMenu: NSMenuItem? {
        guard let color = ColorParser.parse(item.text) else { return nil }
        let submenu = NSMenu()
        for format in ColorFormat.allCases {
            let menuItem = ActionMenuItem(format.string(for: color)) {
                store.copy(item, as: format)
                showCopied()
            }
            menuItem.subtitle = format.rawValue
            submenu.addItem(menuItem)
        }
        let menuItem = NSMenuItem(title: "Copy As", action: nil, keyEquivalent: "")
        menuItem.submenu = submenu
        return menuItem
    }

    /// Convert and shrink the images in the selection, each into a new item, like
    /// Finder's Quick Actions.
    private var quickActionsMenu: NSMenuItem? {
        let images = group.filter { $0.kind.isImage && $0.fileURL != nil }
        guard !images.isEmpty else { return nil }
        let several = images.count > 1
        let submenu = NSMenu()
        for format in CubbyStore.imageFormats {
            let name = format == .jpeg ? "JPEG" : (format.preferredFilenameExtension ?? "").uppercased()
            // Converting a single image to its own format would only make a copy.
            if !several, UTType(filenameExtension: images[0].fileURL!.pathExtension) == format { continue }
            submenu.addItem(ActionMenuItem(several ? "Convert \(images.count) Images to \(name)" : "Convert to \(name)") {
                store.convert(images, to: format)
            })
        }
        submenu.addItem(.separator())
        submenu.addItem(ActionMenuItem(several ? "Make \(images.count) Images Smaller" : "Make Smaller") {
            store.shrink(images)
        })
        let menuItem = NSMenuItem(title: "Quick Actions", action: nil, keyEquivalent: "")
        menuItem.submenu = submenu
        return menuItem
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
        case .file, .image, .screenshot, .link: store.open(item)
        case .color, .text: copy()
        }
    }

    private func copy() {
        store.copy(item)
        showCopied()
    }

    private func showCopied() {
        withAnimation(.easeOut(duration: 0.15)) { showsCopied = true }
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            withAnimation(.easeOut(duration: 0.3)) { showsCopied = false }
        }
    }
}
