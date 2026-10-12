import SwiftUI

/// A square preview of an item: the swatch, thumbnail, favicon or file icon.
struct ItemGlyph: View {
    let item: CubbyItem
    var size: CGFloat = 32
    /// Shows the item as an object rather than a tile: photos with a white border, file
    /// icons as they are, and everything opaque with a soft shadow.
    var natural = false

    var body: some View {
        if natural && item.kind == .file {
            fileIcon.frame(width: size, height: size)
        } else if natural && item.kind.isImage, let data = item.thumbnail, let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .padding(size * 0.04)
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.06, style: .continuous))
                .shadow(color: .black.opacity(0.2), radius: size * 0.05, y: size * 0.02)
                .frame(width: size, height: size)
        } else if natural {
            // Like paper: light in dark mode too.
            tile
                .environment(\.colorScheme, .light)
                .shadow(color: .black.opacity(0.2), radius: size * 0.05, y: size * 0.02)
        } else {
            tile
        }
    }

    private var tile: some View {
        let shape = RoundedRectangle(cornerRadius: size / 4, style: .continuous)
        return content
            .frame(width: size, height: size)
            .clipShape(shape)
            .overlay {
                if item.kind == .color || item.kind == .text || item.kind.isImage && item.thumbnail != nil {
                    shape.strokeBorder(.separator)
                }
            }
    }

    @ViewBuilder private var content: some View {
        switch item.kind {
        case .color:
            Rectangle().fill(ColorParser.color(item.text) ?? .clear)
        case .image, .screenshot:
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
                    .clipShape(RoundedRectangle(cornerRadius: size / 8))
                    .padding(size / 4)
                    .background(tileBackground)
            } else {
                symbol("globe")
            }
        case .text:
            if size >= 48 {
                // Big enough to show the words themselves, like a note.
                Text(item.text)
                    .font(.system(size: size / 8))
                    .lineLimit(5)
                    .padding(size / 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(Color(nsColor: .textBackgroundColor))
            } else {
                symbol("text.alignleft")
            }
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
            .font(.system(size: size * 0.4))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(tileBackground)
    }

    private var tileBackground: AnyShapeStyle {
        natural ? AnyShapeStyle(Color(nsColor: .textBackgroundColor)) : AnyShapeStyle(.fill.tertiary)
    }
}
