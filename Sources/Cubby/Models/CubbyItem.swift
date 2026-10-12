import Foundation
import SwiftData

enum ItemKind: String, Codable {
    case color, link, image, screenshot, file, text
}

extension ItemKind {
    /// The order of the tabs in the open cubby.
    static let tabOrder: [ItemKind] = [.image, .screenshot, .file, .link, .color, .text]

    /// Screenshots are images in every way but their tab.
    var isImage: Bool { self == .image || self == .screenshot }

    var pluralTitle: String {
        switch self {
        case .image: "Images"
        case .screenshot: "Screenshots"
        case .file: "Files"
        case .link: "Links"
        case .color: "Colors"
        case .text: "Text"
        }
    }
}

@Model
final class CubbyItem {
    @Attribute(.unique) var id: UUID
    var kindRaw: String
    var addedAt: Date
    /// The color string, URL or snippet. For files and images, the file name.
    var text: String
    var title: String?
    var fileName: String?
    var fileSize: Int64
    /// Path of the copied file, relative to `AppPaths.files`.
    var storedPath: String?
    @Attribute(.externalStorage) var thumbnail: Data?
    @Attribute(.externalStorage) var favicon: Data?
    /// The user's own file, moved here from the Desktop rather than copied. It goes to
    /// the Trash when the item is removed.
    var isOriginal: Bool = false
    /// A name you gave a link, color or snippet, shown instead of its own. Files are
    /// renamed on disk instead.
    var name: String?
    /// A few words about why it's here.
    var note: String?

    init(id: UUID = UUID(), kind: ItemKind, text: String) {
        self.id = id
        self.kindRaw = kind.rawValue
        self.addedAt = .now
        self.text = text
        self.fileSize = 0
    }

    var kind: ItemKind { ItemKind(rawValue: kindRaw) ?? .text }

    var fileURL: URL? { storedPath.map { AppPaths.files.appending(path: $0) } }

    /// What the item is called under its preview.
    var label: String {
        if let name { return name }
        switch kind {
        case .link: return title ?? domain
        case .image, .screenshot, .file: return fileName ?? text
        case .color, .text: return text
        }
    }

    var domain: String {
        guard let host = URL(string: text)?.host(percentEncoded: false) else { return text }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
