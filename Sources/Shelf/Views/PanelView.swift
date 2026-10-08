import SwiftUI
import SwiftData

/// The panel's content. The window around it is resized by `PanelController`; each
/// state's content keeps its own width and is pinned to the trailing edge, so it's
/// revealed rather than squeezed while the window animates.
struct PanelView: View {
    @Environment(ShelfStore.self) private var store
    @Environment(PanelController.self) private var panel
    @Query(sort: \ShelfItem.addedAt, order: .reverse) private var allItems: [ShelfItem]
    @State private var isTargeted = false

    private var items: [ShelfItem] { store.visible(allItems) }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        ZStack(alignment: .trailing) {
            switch panel.mode {
            case .resting:
                RestingPill(items: items)
                    .onGeometryChange(for: CGSize.self, of: \.size) { panel.restingSize = $0 }
            case .dropTarget:
                DropTarget()
            case .expanded:
                ExpandedShelf(items: items)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        .clipShape(shape)
        .contentShape(shape)
        .onTapGesture { if panel.mode == .resting { panel.expand() } }
        .glassEffect(.regular, in: shape)
        .overlay {
            if isTargeted && panel.mode == .expanded {
                shape.strokeBorder(.tint, lineWidth: 2)
            }
        }
        .onDrop(of: ItemImporter.dropTypes, isTargeted: $isTargeted) { providers in
            store.drop(providers)
            panel.dropped()
            return true
        }
        .onChange(of: isTargeted) { _, targeted in
            targeted ? panel.dragEntered() : panel.dragExited()
        }
    }
}

/// The 3 newest items as small previews, plus the count.
private struct RestingPill: View {
    let items: [ShelfItem]

    var body: some View {
        VStack(spacing: 8) {
            if items.isEmpty {
                Image(systemName: "tray")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
            } else {
                ForEach(items.prefix(3)) { ItemGlyph(item: $0) }
                Text(items.count, format: .number)
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .fixedSize()
    }
}

private struct DropTarget: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.down").font(.title2)
            Text("Drop").font(.callout)
        }
        .foregroundStyle(.tint)
        .frame(width: PanelController.dropTargetSize.width)
        .frame(maxHeight: .infinity)
    }
}
