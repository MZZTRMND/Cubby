import AppKit
import OSLog
import UniformTypeIdentifiers

let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.shelf.app.dev", category: "import")

/// Something dropped or pasted, before it becomes a `ShelfItem`.
enum Incoming {
    case file(URL)
    case image(Data, UTType, name: String?)
    case url(URL)
    case text(String)
}

/// Reads drops and the pasteboard. Preference order: files, image data, URLs, text.
enum ItemImporter {
    static let dropTypes: [UTType] = [.fileURL, .image, .url, .text]

    static func incoming(from pasteboard: NSPasteboard) -> [Incoming] {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            return urls.map { .file($0) }
        }
        for type in [UTType.png, .jpeg, .gif, .heic, .tiff] {
            if let data = pasteboard.data(forType: NSPasteboard.PasteboardType(type.identifier)) {
                return [.image(data, type, name: nil)]
            }
        }
        if pasteboard.availableType(from: [.URL]) != nil,
           let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL], !urls.isEmpty {
            return urls.map { .url($0) }
        }
        if let string = pasteboard.string(forType: .string) {
            return [.text(string)]
        }
        return []
    }

    static func incoming(from providers: [NSItemProvider]) async -> [Incoming] {
        var result: [Incoming] = []
        for provider in providers {
            if let item = await incoming(from: provider) { result.append(item) }
        }
        return result
    }

    private static func incoming(from provider: NSItemProvider) async -> Incoming? {
        logger.notice("drop types: \(provider.registeredTypeIdentifiers, privacy: .public)")
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
           let url = await provider.loadURL(.fileURL) {
            return .file(url)
        }
        // Finder usually hands over "a PNG file" rather than a file URL. Asking for the
        // original in place gets the real file, so it can be moved off the Desktop.
        if let url = await provider.loadOriginalFile() {
            return .file(url)
        }
        if let type = provider.registeredContentTypes.first(where: { $0.conforms(to: .image) }),
           let data = await provider.loadData(type) {
            return .image(data, type, name: provider.suggestedName)
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
           let url = await provider.loadURL(.url) {
            return url.isFileURL ? .file(url) : .url(url)
        }
        if provider.canLoadObject(ofClass: String.self) {
            return await withCheckedContinuation { continuation in
                _ = provider.loadObject(ofClass: String.self) { string, _ in
                    continuation.resume(returning: string.map { .text($0) })
                }
            }
        }
        return nil
    }

    /// What a pasted or dropped string should become.
    static func kind(of string: String) -> ItemKind {
        if ColorParser.parse(string) != nil { return .color }
        if linkURL(string) != nil { return .link }
        return .text
    }

    static func linkURL(_ string: String) -> URL? {
        guard !string.contains(where: \.isWhitespace),
              let url = URL(string: string),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              url.host() != nil
        else { return nil }
        return url
    }
}

extension NSItemProvider {
    func loadData(_ type: UTType) async -> Data? {
        await withCheckedContinuation { continuation in
            _ = loadDataRepresentation(for: type) { data, _ in continuation.resume(returning: data) }
        }
    }

    func loadImageData() async -> Data? {
        await loadData(registeredContentTypes.first { $0.conforms(to: .image) } ?? .image)
    }

    /// The original file behind the item when it can be opened in place, as with a file
    /// dragged from Finder. Nil when the item is only data, such as an image from a web page.
    func loadOriginalFile() async -> URL? {
        guard let type = registeredContentTypes.first else { return nil }
        return await withCheckedContinuation { continuation in
            _ = loadInPlaceFileRepresentation(forTypeIdentifier: type.identifier) { url, isInPlace, _ in
                continuation.resume(returning: isInPlace ? url : nil)
            }
        }
    }

    func loadURL(_ type: UTType) async -> URL? {
        guard let data = await loadData(type), let url = URL(dataRepresentation: data, relativeTo: nil)
        else { return nil }
        // Finder can hand over file reference URLs (file:///.file/id=…).
        return url.isFileURL ? (url as NSURL).filePathURL ?? url : url
    }
}
