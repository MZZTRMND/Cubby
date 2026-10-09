import SwiftUI
import SwiftData

/// The panel's content: the folder, or the card it opens into. The card grows out of
/// the folder's spot and shrinks back into it.
struct PanelView: View {
    @Environment(CubbyStore.self) private var store
    @Environment(PanelController.self) private var panel
    @Query(sort: \CubbyItem.addedAt, order: .reverse) private var allItems: [CubbyItem]
    @State private var isTargeted = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if panel.mode == .expanded {
                    ExpandedCubby(items: allItems, isTargeted: isTargeted && store.draggedItemIDs.isEmpty)
                        .padding(PanelController.inset)
                        .transition(.scale(scale: 0.25, anchor: folderAnchor(in: geometry.size))
                            .combined(with: .opacity))
                } else {
                    FolderIcon(items: allItems, isDropTarget: panel.mode == .dropTarget, isPinned: panel.isPinnedOnTop)
                        .onTapGesture { panel.expand() }
                        .contextMenu { FolderMenu() }
                        .gesture(
                            DragGesture(minimumDistance: 4)
                                .onChanged { _ in panel.beginMove() }
                                .onEnded { _ in panel.endMove() }
                        )
                        .padding(PanelController.inset)
                        .onGeometryChange(for: CGSize.self, of: \.size) { panel.restingSize = $0 }
                        .offset(panel.folderOffset)
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        // Items dragged from the cubby itself are ignored.
        .onDrop(of: ItemImporter.dropTypes, isTargeted: $isTargeted) { providers in
            guard store.draggedItemIDs.isEmpty else { return false }
            store.drop(providers)
            panel.dropped()
            return true
        }
        .onChange(of: isTargeted) { _, targeted in
            targeted ? panel.dragEntered() : panel.dragExited()
        }
    }

    /// Right-clicking the folder.
    private struct FolderMenu: View {
        @Environment(PanelController.self) private var panel

        var body: some View {
            @Bindable var panel = panel
            Toggle("Pin on Top", isOn: $panel.isPinnedOnTop)
            Divider()
            Button("Quit Cubby") { NSApp.terminate(nil) }
        }
    }

    /// Where the folder sits in the window, so the card grows out of it.
    private func folderAnchor(in size: CGSize) -> UnitPoint {
        guard size.width > 0, size.height > 0 else { return .center }
        return UnitPoint(x: 0.5 + panel.folderOffset.width / size.width,
                         y: 0.5 + panel.folderOffset.height / size.height)
    }
}
