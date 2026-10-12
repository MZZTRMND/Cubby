import SwiftUI
import SwiftData

/// The panel's content: the folder, or the card it opens into. The card grows out of
/// the folder's spot and shrinks back into it.
struct PanelView: View {
    @Environment(CubbyStore.self) private var store
    @Environment(PanelController.self) private var panel
    @Query(sort: \CubbyItem.addedAt, order: .reverse) private var allItems: [CubbyItem]
    @State private var isTargeted = false
    @State private var frontTop: CGFloat = .infinity

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if panel.mode == .expanded {
                    ExpandedCubby(items: allItems, isTargeted: isTargeted && store.draggedItemIDs.isEmpty)
                        .padding(PanelController.expandedInset)
                        .transition(.scale(scale: 0.25, anchor: folderAnchor(in: geometry.size))
                            .combined(with: .opacity))
                } else {
                    FolderIcon(items: allItems, isDropTarget: panel.mode == .dropTarget, isPinned: panel.isPinnedOnTop,
                               onFrontTop: { frontTop = $0 })
                        .onTapGesture { panel.expand() }
                        .contextMenu { FolderMenu() }
                        // Grabbing the papers above the front carries them all out;
                        // grabbing the front moves the folder.
                        .gesture(
                            DragGesture(minimumDistance: 4, coordinateSpace: .named(FolderIcon.space))
                                .onChanged { value in
                                    if value.startLocation.y < frontTop, !allItems.isEmpty {
                                        panel.beginDragOut(allItems)
                                    } else {
                                        panel.beginMove()
                                    }
                                }
                                .onEnded { _ in panel.endMove() }
                        )
                        .coordinateSpace(.named(FolderIcon.space))
                        // A wiggle once it lands in the middle for a drag; the inset leaves room.
                        .keyframeAnimator(initialValue: 0.0, trigger: panel.summonCount) { folder, degrees in
                            folder.rotationEffect(.degrees(degrees))
                        } keyframes: { _ in
                            for degrees in [-7.0, 6, -4, 2, 0] {
                                CubicKeyframe(degrees, duration: 0.084)
                            }
                        }
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
