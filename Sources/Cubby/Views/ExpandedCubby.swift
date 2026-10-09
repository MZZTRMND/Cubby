import SwiftUI

/// The open cubby: a glass card with the items in a grid, scrolling under a translucent
/// header and footer.
struct ExpandedCubby: View {
    let items: [CubbyItem]
    let isTargeted: Bool
    @Environment(CubbyStore.self) private var store
    @Environment(PanelController.self) private var panel

    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 40, style: .continuous)
        ScrollView {
            LazyVGrid(columns: Self.columns, spacing: 20) {
                ForEach(store.sorted(items)) { GridItemView(item: $0) }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .animation(PanelController.animation, value: store.sortOrder)
        }
        .scrollIndicators(.never)
        // The system's progressive blur where items scroll under the header and footer.
        .scrollEdgeEffectStyle(.soft, for: .vertical)
        .safeAreaBar(edge: .top) {
            header
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 8)
        }
        .safeAreaBar(edge: .bottom) {
            actions
                .padding(.horizontal, 8)
                .padding(.top, 8)
                .padding(.bottom, 16)
        }
        .frame(width: PanelController.expandedSize.width, height: PanelController.expandedSize.height)
        .clipShape(shape)
        .glassSurface(shape)
        .overlay {
            if isTargeted { shape.stroke(.tint, lineWidth: 2) }
        }
        .onAppear { store.tidy() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Cubby")
                .bold()
            Text(items.count, format: .number)
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(.fill.secondary, in: Capsule())
            Spacer()
            Button {
                panel.collapse()
            } label: {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Minimize")
        }
        .font(.title3)
    }

    private var actions: some View {
        HStack(spacing: 0) {
            ActionButton(title: "Clear", symbol: "trash") { panel.confirmClear() }
                .disabled(items.isEmpty)
            Menu {
                Picker("Sort By", selection: Bindable(store).sortOrder) {
                    ForEach(CubbyStore.SortOrder.allCases) { Text($0.title) }
                }
                .pickerStyle(.inline)
            } label: {
                ActionLabel(title: "Sort", symbol: "arrow.up.arrow.down")
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .frame(maxWidth: .infinity)
            ActionButton(title: "Upload", symbol: "arrow.up.doc") { panel.chooseFilesToAdd() }
        }
    }
}

/// An icon over a one-word label, like the actions along the bottom of a widget.
private struct ActionLabel: View {
    let title: String
    let symbol: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.title2)
                .frame(height: 28)
            Text(title)
                .font(.callout)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
}

private struct ActionButton: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ActionLabel(title: title, symbol: symbol)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }
}

/// An item in the grid: its preview with its name underneath. Click to open or copy,
/// right-click for more, drag to move it out.
private struct GridItemView: View {
    let item: CubbyItem
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
        .overlay {
            ItemInteraction(
                writer: { store.pasteboardWriter(for: item) },
                preview: { ImageRenderer(content: ItemGlyph(item: item, size: Self.iconSize, natural: true)).nsImage },
                movesOut: store.movesOut(item),
                menu: { menu },
                onClick: activate,
                onDragStart: { store.draggedItemID = item.id },
                onDragEnd: { store.dragEnded(item.id, delivered: $0) }
            )
        }
        .pointingHandCursor()
    }

    /// Files get the same menu as on the Desktop, plus Move to Desktop. Links, colors
    /// and text get a short one.
    private var menu: NSMenu {
        let menu = NSMenu()
        guard let url = item.fileURL else {
            if item.kind == .link { menu.addItem(ActionMenuItem("Open") { store.open(item) }) }
            menu.addItem(ActionMenuItem("Copy") { copy() })
            menu.addItem(.separator())
                menu.addItem(ActionMenuItem("Remove") { store.remove(item) })
            return menu
        }
        menu.addItem(ActionMenuItem("Open") { store.open(item) })
        menu.addItem(openWithMenu(for: url))
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem("Move to Desktop") { store.moveToDesktop(item) })
        menu.addItem(ActionMenuItem("Move to Bin") { store.moveToBin(item) })
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
