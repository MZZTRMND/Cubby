import SwiftUI

/// A small square preview of an item: the swatch, thumbnail, favicon or file icon.
struct ItemGlyph: View {
    let item: ShelfItem
    var size: CGFloat = 32

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        content
            .frame(width: size, height: size)
            .clipShape(shape)
            .overlay {
                if item.kind == .color || item.kind == .image && item.thumbnail != nil {
                    shape.strokeBorder(.separator)
                }
            }
    }

    @ViewBuilder private var content: some View {
        switch item.kind {
        case .color:
            Rectangle().fill(ColorParser.color(item.text) ?? .clear)
        case .image:
            if let data = item.thumbnail, let image = NSImage(data: data) {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                fileIcon
            }
        case .file:
            fileIcon
        case .link:
            if let data = item.favicon, let icon = NSImage(data: data) {
                Image(nsImage: icon)
                    .resizable()
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .padding(8)
                    .background(.fill.tertiary)
            } else {
                symbol("globe")
            }
        case .text:
            symbol("text.alignleft")
        }
    }

    @ViewBuilder private var fileIcon: some View {
        if let url = item.fileURL {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable()
        } else {
            symbol("doc")
        }
    }

    private func symbol(_ name: String) -> some View {
        Image(systemName: name)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.fill.tertiary)
    }
}
