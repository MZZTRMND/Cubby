import SwiftUI

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

/// The full view: header, filter and a single-column list.
struct ExpandedShelf: View {
    let items: [ShelfItem]
    @Environment(ShelfStore.self) private var store
    @State private var filter: ItemFilter = .all

    var body: some View {
        VStack(spacing: 12) {
            header
            Picker("Filter", selection: $filter) {
                ForEach(ItemFilter.allCases) { Text($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(items.filter { filter.matches($0.kind) }) { ItemRow(item: $0) }
                }
            }
            .scrollIndicators(.never)
        }
        .padding(16)
        .frame(width: PanelController.expandedSize.width)
        .frame(maxHeight: .infinity)
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
        }
        .buttonStyle(.glass)
        .controlSize(.small)
    }
}

struct ItemRow: View {
    let item: ShelfItem

    var body: some View {
        HStack(spacing: 12) {
            ItemGlyph(item: item)
            VStack(alignment: .leading, spacing: 2) {
                Text(primary)
                    .font(item.kind == .color ? .callout.monospaced() : .callout)
                    .lineLimit(item.kind == .text ? 3 : 1)
                    .truncationMode(item.kind == .file || item.kind == .image ? .middle : .tail)
                if let secondary {
                    Text(secondary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(8)
    }

    private var primary: String {
        switch item.kind {
        case .link: item.title ?? item.domain
        case .image, .file: item.fileName ?? item.text
        case .color, .text: item.text
        }
    }

    private var secondary: String? {
        switch item.kind {
        case .link: item.title == nil ? nil : item.domain
        case .image, .file: item.fileSize.formatted(.byteCount(style: .file))
        case .color, .text: nil
        }
    }
}
