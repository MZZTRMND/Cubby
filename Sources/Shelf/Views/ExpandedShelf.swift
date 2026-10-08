import SwiftUI

/// The open shelf: a header and a free canvas where items sit wherever you put them.
struct ExpandedShelf: View {
    let items: [ShelfItem]
    @Environment(ShelfStore.self) private var store
    @Environment(PanelController.self) private var panel
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 12) {
            header
                .padding(.horizontal, 16)
            ScrollView {
                ZStack(alignment: .topLeading) {
                    // At least as tall as the visible area, so you can drop anywhere.
                    Color.clear.containerRelativeFrame(.vertical)
                    Color.clear.frame(height: contentHeight)
                    // Oldest first, so newer items draw on top where they overlap.
                    ForEach(items.reversed()) { item in
                        CanvasIcon(item: item)
                            .position(item.canvasPosition ?? CanvasLayout.slot(0))
                    }
                }
                .frame(width: CanvasLayout.width)
                .contentShape(Rectangle())
                .onDrop(of: ItemImporter.dropTypes, delegate: CanvasDrop(store: store, isTargeted: $isTargeted))
            }
            .scrollIndicators(.never)
        }
        .padding(.vertical, 16)
        .frame(width: PanelController.expandedSize.width)
        .frame(maxHeight: .infinity)
        .overlay {
            if isTargeted {
                RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(.tint, lineWidth: 2)
            }
        }
        .onAppear {
            store.tidy()
            store.placeUnplaced()
        }
    }

    private var contentHeight: CGFloat {
        (items.compactMap { $0.canvasPosition?.y }.max() ?? 0) + CanvasLayout.cell.height / 2
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Shelf").font(.headline)
            Text(items.count, format: .number)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Spacer()
            if store.canUndoClear {
                Button("Undo") { store.undoClear() }
            } else {
                Button("Clear") { store.clear() }
                    .disabled(!items.contains { !$0.isPinned })
            }
            Button {
                panel.collapse()
            } label: {
                Image(systemName: panel.edge == .left ? "chevron.left" : "chevron.right")
            }
            .help("Collapse")
        }
        .buttonStyle(.glass)
        .controlSize(.small)
    }
}

/// Drops on the canvas: a shelf item is moved to where it's dropped; anything else is
/// added there.
private struct CanvasDrop: DropDelegate {
    let store: ShelfStore
    @Binding var isTargeted: Bool

    func dropEntered(info: DropInfo) {
        isTargeted = store.draggedItemID == nil
    }

    func dropExited(info: DropInfo) {
        isTargeted = false
    }

    func performDrop(info: DropInfo) -> Bool {
        isTargeted = false
        if let id = store.draggedItemID {
            store.move(id, to: info.location)
        } else {
            store.drop(info.itemProviders(for: ItemImporter.dropTypes), at: info.location)
        }
        return true
    }
}

/// An item on the canvas: its preview with a short name underneath, like a desktop icon.
private struct CanvasIcon: View {
    let item: ShelfItem
    @Environment(ShelfStore.self) private var store
    @State private var showsCopied = false

    var body: some View {
        VStack(spacing: 4) {
            ItemGlyph(item: item, size: CanvasLayout.iconSize)
                .overlay(alignment: .topTrailing) {
                    if item.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 16, height: 16)
                            .background(.tint, in: Circle())
                            .offset(x: 4, y: -4)
                    }
                }
            Text(showsCopied ? "Copied" : label)
                .font(.caption)
                .foregroundStyle(showsCopied ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                .lineLimit(2)
                .truncationMode(.middle)
                .multilineTextAlignment(.center)
                .frame(width: CanvasLayout.cell.width - 8)
        }
        .contentShape(Rectangle())
        .onTapGesture { activate() }
        .draggable(ShelfDragItem.self, id: \.id, item: ShelfDragItem(item))
        .dragConfiguration(dragConfiguration)
        .onDragSessionUpdated { session in
            switch session.phase {
            case .initial, .active:
                store.draggedItemID = item.id
            case .ended, .dataTransferCompleted:
                store.draggedItemID = nil
                store.tidyAfterDragOut()
            @unknown default:
                break
            }
        }
        .contextMenu {
            Button(item.isPinned ? "Unpin" : "Pin") { store.togglePin(item) }
            Button("Copy") { copy() }
            if item.fileURL != nil {
                Button("Reveal in Finder") { store.revealInFinder(item) }
            }
            Divider()
            Button("Remove") { store.remove(item) }
        }
    }

    /// Files can only be moved out, so Finder takes them off the shelf like out of a
    /// folder. Links and text are copied. Inside the shelf, anything goes.
    private var dragConfiguration: DragConfiguration {
        DragConfiguration(
            operationsWithinApp: .init(allowCopy: true, allowMove: true),
            operationsOutsideApp: ShelfDragItem(item).movesOut
                ? .init(allowCopy: false, allowMove: true)
                : .init(allowCopy: true)
        )
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
