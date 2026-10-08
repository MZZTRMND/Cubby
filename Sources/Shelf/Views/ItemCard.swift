import SwiftUI

/// A compact card for the popover's two-column grid.
struct ItemCard: View {
    let item: ShelfItem

    var body: some View {
        content
            .frame(maxWidth: .infinity, minHeight: 96, maxHeight: 96, alignment: .topLeading)
            .background(.fill.quaternary)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder private var content: some View {
        switch item.kind {
        case .color: color
        case .link: link
        case .image: image
        case .file: file
        case .text: text
        }
    }

    private var color: some View {
        VStack(spacing: 0) {
            Rectangle().fill(ColorParser.color(item.text) ?? .clear)
            Text(item.text)
                .font(.caption.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, minHeight: 28)
        }
    }

    private var link: some View {
        VStack(alignment: .leading, spacing: 4) {
            Group {
                if let data = item.favicon, let icon = NSImage(data: data) {
                    Image(nsImage: icon).resizable().clipShape(RoundedRectangle(cornerRadius: 4))
                } else {
                    Image(systemName: "globe").foregroundStyle(.secondary)
                }
            }
            .frame(width: 16, height: 16)
            Spacer(minLength: 0)
            Text(item.title ?? item.domain)
                .font(.callout)
                .lineLimit(2)
            if item.title != nil {
                Text(item.domain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(12)
    }

    @ViewBuilder private var image: some View {
        if let data = item.thumbnail, let thumbnail = NSImage(data: data) {
            Color.clear
                .overlay { Image(nsImage: thumbnail).resizable().scaledToFill() }
                .clipped()
        } else {
            file
        }
    }

    private var file: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let url = item.fileURL {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .frame(width: 32, height: 32)
            }
            Spacer(minLength: 0)
            Text(item.fileName ?? item.text)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(item.fileSize, format: .byteCount(style: .file))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
    }

    private var text: some View {
        Text(item.text)
            .font(.callout)
            .lineLimit(4)
            .padding(12)
    }
}
