import CoreTransferable
import Foundation

/// What dragging an icon off the shelf hands over: the stored file itself (so Finder can
/// move it out), the link, or the text.
struct ShelfDragItem: Transferable, Identifiable {
    let id: UUID
    let url: URL?
    let text: String

    init(_ item: ShelfItem) {
        id = item.id
        text = item.text
        switch item.kind {
        case .file, .image: url = item.fileURL
        case .link: url = URL(string: item.text)
        case .color, .text: url = nil
        }
    }

    /// Files leave the shelf like they would leave a folder; links and text are copied.
    var movesOut: Bool { url?.isFileURL == true }

    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(exporting: { (item: ShelfDragItem) in
            guard let url = item.url else { throw CocoaError(.fileNoSuchFile) }
            return url
        })
        .exportingCondition { $0.url != nil }
        ProxyRepresentation(exporting: \.text)
            .exportingCondition { $0.url?.isFileURL != true }
    }
}
