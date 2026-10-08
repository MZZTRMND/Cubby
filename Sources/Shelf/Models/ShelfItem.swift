import Foundation
import SwiftData

enum ItemKind: String, Codable {
    case color, link, image, file, text
}

@Model
final class ShelfItem {
    @Attribute(.unique) var id: UUID
    var kindRaw: String
    var addedAt: Date
    var isPinned: Bool
    /// The color string, URL or snippet. For files and images, the file name.
    var text: String
    var title: String?
    var fileName: String?
    var fileSize: Int64
    /// Path of the copied file, relative to `AppPaths.files`.
    var storedPath: String?
    @Attribute(.externalStorage) var thumbnail: Data?
    @Attribute(.externalStorage) var favicon: Data?

    init(id: UUID = UUID(), kind: ItemKind, text: String) {
        self.id = id
        self.kindRaw = kind.rawValue
        self.addedAt = .now
        self.isPinned = false
        self.text = text
        self.fileSize = 0
    }

    var kind: ItemKind { ItemKind(rawValue: kindRaw) ?? .text }

    var fileURL: URL? { storedPath.map { AppPaths.files.appending(path: $0) } }

    var domain: String {
        guard let host = URL(string: text)?.host(percentEncoded: false) else { return text }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
