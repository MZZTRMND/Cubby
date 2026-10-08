import SwiftUI
import SwiftData

enum ItemFilter: String, CaseIterable, Identifiable {
    case all = "All", media = "Media", links = "Links", text = "Text"

    var id: Self { self }

    func matches(_ kind: ItemKind) -> Bool {
        switch self {
        case .all: true
        case .media: kind == .image || kind == .file || kind == .color
        case .links: kind == .link
        case .text: kind == .text
        }
    }
}

struct PopoverView: View {
    @Environment(ShelfStore.self) private var store
    @Query(sort: \ShelfItem.addedAt, order: .reverse) private var allItems: [ShelfItem]
    @State private var filter: ItemFilter = .all
    @State private var isTargeted = false

    private var items: [ShelfItem] { store.visible(allItems) }

    var body: some View {
        VStack(spacing: 12) {
            header
            DropZone(isTargeted: isTargeted)
            Picker("Filter", selection: $filter) {
                ForEach(ItemFilter.allCases) { Text($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(items.filter { filter.matches($0.kind) }) { ItemCard(item: $0) }
                }
            }
            .scrollIndicators(.never)
        }
        .padding(16)
        .frame(width: 320, height: 480)
        .onDrop(of: ItemImporter.dropTypes, isTargeted: $isTargeted) { providers in
            store.drop(providers)
            return true
        }
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
            Menu {
                Button("Quit Shelf") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .buttonStyle(.glass)
        .controlSize(.small)
    }
}
