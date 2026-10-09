import AppKit
import SwiftData
import UniformTypeIdentifiers

/// The one store both surfaces share. Views read items with `@Query`; all changes go
/// through here.
@MainActor @Observable
final class CubbyStore {
    enum SortOrder: String, CaseIterable, Identifiable {
        case dateAdded, name, kind

        var id: Self { self }
        var title: String {
            switch self {
            case .dateAdded: "Date Added"
            case .name: "Name"
            case .kind: "Kind"
            }
        }
    }

    let context: ModelContext

    /// How the open cubby's grid is ordered.
    var sortOrder: SortOrder {
        didSet { UserDefaults.standard.set(sortOrder.rawValue, forKey: "sortOrder") }
    }
    /// The item being dragged out of the open cubby, if any. Dropping it back onto the
    /// cubby does nothing.
    var draggedItemID: UUID?
    @ObservationIgnored private var pasteMonitor: Any?

    /// Dropped files from these folders are moved into the cubby instead of copied, so
    /// they disappear from there.
    let movableFolders: [URL]
    /// Moves a file to the Bin, so nothing of yours is lost.
    private let trash: (URL) -> Void

    init(
        context: ModelContext,
        movableFolders: [URL] = [URL.desktopDirectory],
        trash: @escaping (URL) -> Void = { try? FileManager.default.trashItem(at: $0, resultingItemURL: nil) }
    ) {
        self.context = context
        self.movableFolders = movableFolders
        self.trash = trash
        sortOrder = SortOrder(rawValue: UserDefaults.standard.string(forKey: "sortOrder") ?? "") ?? .dateAdded
        tidy()
        removeOrphanedFiles()
        installPasteMonitor()
    }

    // MARK: - Adding

    func paste(from pasteboard: NSPasteboard = .general) {
        add(ItemImporter.incoming(from: pasteboard))
    }

    /// Dropped files are moved off the Desktop; pasted ones are always copied.
    func drop(_ providers: [NSItemProvider]) {
        Task { add(await ItemImporter.incoming(from: providers), moveFiles: true) }
    }

    @discardableResult
    func add(_ incoming: [Incoming], moveFiles: Bool = false) -> Task<Void, Never> {
        Task {
            for item in incoming {
                switch item {
                case .text(let string): addString(string)
                case .url(let url): addLink(url)
                case .file(let url): await addFile(url, move: moveFiles && isInMovableFolder(url))
                case .image(let data, let type, let name): await addImage(data, type: type, name: name)
                }
            }
            try? context.save()
        }
    }

    private func isInMovableFolder(_ url: URL) -> Bool {
        let path = url.resolvingSymlinksInPath().path
        return movableFolders.contains { path.hasPrefix($0.resolvingSymlinksInPath().path + "/") }
    }

    private func addString(_ string: String) {
        let text = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let kind = ItemImporter.kind(of: text)
        if kind == .link, let url = ItemImporter.linkURL(text) { return addLink(url) }
        if moveExistingToTop(kind: kind, text: text) { return }
        context.insert(CubbyItem(kind: kind, text: text))
    }

    private func addLink(_ url: URL) {
        let text = url.absoluteString
        if moveExistingToTop(kind: .link, text: text) { return }
        let item = CubbyItem(kind: .link, text: text)
        context.insert(item)
        let id = item.id
        Task { [weak self] in
            let (title, favicon) = await LinkMetadata.fetch(url)
            // Look it up again: it may have been removed while the page loaded.
            guard let self, let item = self.item(withID: id) else { return }
            item.title = title
            item.favicon = favicon
            try? self.context.save()
        }
    }

    private func addFile(_ source: URL, move: Bool) async {
        // One of the cubby's own files dropped back onto it: nothing to add.
        let filesPath = AppPaths.files.resolvingSymlinksInPath().path + "/"
        guard !source.resolvingSymlinksInPath().path.hasPrefix(filesPath) else { return }

        let name = source.lastPathComponent
        let size = Self.size(of: source)
        let optionalName: String? = name
        var existing = FetchDescriptor<CubbyItem>(
            predicate: #Predicate { $0.fileName == optionalName && $0.fileSize == size }
        )
        existing.fetchLimit = 1
        if let item = try? context.fetch(existing).first {
            item.addedAt = .now
            return
        }

        let id = UUID()
        let destination = AppPaths.files.appending(path: id.uuidString).appending(path: name)
        let isImage = UTType(filenameExtension: source.pathExtension)?.conforms(to: .image) ?? false
        let result: (thumbnail: Data?, moved: Bool)? = try? await Task.detached {
            let fm = FileManager.default
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            var moved = false
            if move {
                do {
                    try fm.moveItem(at: source, to: destination)
                    moved = true
                } catch {
                    // Most likely no permission for the Desktop folder; keep a copy rather
                    // than losing the drop.
                    logger.error("move failed, copying instead: \(error.localizedDescription, privacy: .public)")
                }
            }
            if !moved { try fm.copyItem(at: source, to: destination) }
            return (isImage ? ImageData.thumbnail(of: destination) : nil, moved)
        }.value
        logger.notice("file \(name, privacy: .public): move=\(move) moved=\(result?.moved ?? false)")
        guard let (thumbnail, moved) = result else { return }

        let item = CubbyItem(id: id, kind: isImage ? .image : .file, text: name)
        item.fileName = name
        item.fileSize = size
        item.storedPath = "\(id.uuidString)/\(name)"
        item.thumbnail = thumbnail
        item.isOriginal = moved
        context.insert(item)
    }

    private func addImage(_ data: Data, type: UTType, name: String?) async {
        // Keep common formats as they are; convert the rest (mostly TIFF) to PNG.
        let keep = [UTType.png, .jpeg, .gif, .heic].contains(type)
        guard let data = keep ? data : ImageData.png(from: data) else { return }
        let ext = keep ? (type.preferredFilenameExtension ?? "png") : "png"
        let base = name.map { ($0 as NSString).deletingPathExtension } ?? "Image"
        let fileName = "\(base).\(ext)"

        let id = UUID()
        let destination = AppPaths.files.appending(path: id.uuidString).appending(path: fileName)
        let thumbnail: Data?? = try? await Task.detached {
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try data.write(to: destination)
            return ImageData.thumbnail(of: data)
        }.value
        guard let thumbnail else { return }

        let item = CubbyItem(id: id, kind: .image, text: fileName)
        item.fileName = fileName
        item.fileSize = Int64(data.count)
        item.storedPath = "\(id.uuidString)/\(fileName)"
        item.thumbnail = thumbnail
        context.insert(item)
    }

    /// Dropping something that's already on the cubby brings it back to the front instead.
    private func moveExistingToTop(kind: ItemKind, text: String) -> Bool {
        let kindRaw = kind.rawValue
        var existing = FetchDescriptor<CubbyItem>(
            predicate: #Predicate { $0.kindRaw == kindRaw && $0.text == text }
        )
        existing.fetchLimit = 1
        guard let item = try? context.fetch(existing).first else { return false }
        item.addedAt = .now
        return true
    }

    // MARK: - Order

    /// The items in the open cubby's grid order.
    func sorted(_ items: [CubbyItem]) -> [CubbyItem] {
        switch sortOrder {
        case .dateAdded:
            items.sorted { $0.addedAt > $1.addedAt }
        case .name:
            items.sorted { Self.name(of: $0).localizedStandardCompare(Self.name(of: $1)) == .orderedAscending }
        case .kind:
            items.sorted { (Self.kindOrder[$0.kind] ?? 0, $1.addedAt) < (Self.kindOrder[$1.kind] ?? 0, $0.addedAt) }
        }
    }

    private static let kindOrder: [ItemKind: Int] = [.image: 0, .file: 1, .link: 2, .color: 3, .text: 4]

    private static func name(of item: CubbyItem) -> String {
        item.fileName ?? item.title ?? item.text
    }

    // MARK: - Removing

    func remove(_ item: CubbyItem) {
        delete(item)
        try? context.save()
    }

    /// Moves every item's file to the Bin and empties the cubby. Ask first: this can't
    /// be undone from here.
    func clear() {
        for item in (try? context.fetch(FetchDescriptor<CubbyItem>())) ?? [] { delete(item, toBin: true) }
        try? context.save()
    }

    /// How many items Clear would remove.
    func clearableCount() -> Int {
        (try? context.fetchCount(FetchDescriptor<CubbyItem>())) ?? 0
    }

    /// Drops items whose file is gone, e.g. moved out to Finder. Runs at launch and when
    /// the cubby opens.
    func tidy() {
        let withFiles = FetchDescriptor<CubbyItem>(predicate: #Predicate { $0.storedPath != nil })
        let missing = ((try? context.fetch(withFiles)) ?? []).filter {
            guard let url = $0.fileURL else { return false }
            return !FileManager.default.fileExists(atPath: url.path)
        }
        guard !missing.isEmpty else { return }
        for item in missing { delete(item) }
        try? context.save()
    }

    /// Copies are deleted and your own moved files go to the Bin; with `toBin`, every
    /// file goes to the Bin.
    private func delete(_ item: CubbyItem, toBin: Bool = false) {
        if item.storedPath != nil {
            if item.isOriginal || toBin, let url = item.fileURL, FileManager.default.fileExists(atPath: url.path) {
                trash(url)
            }
            try? FileManager.default.removeItem(at: AppPaths.files.appending(path: item.id.uuidString))
        }
        context.delete(item)
    }

    /// Cleans up file folders whose item no longer exists, e.g. after a crash. They might
    /// hold a moved original, so their contents go to the Bin.
    private func removeOrphanedFiles() {
        let items = (try? context.fetch(FetchDescriptor<CubbyItem>())) ?? []
        let kept = Set(items.map(\.id.uuidString))
        let fm = FileManager.default
        let folders = (try? fm.contentsOfDirectory(at: AppPaths.files, includingPropertiesForKeys: nil)) ?? []
        for folder in folders where !kept.contains(folder.lastPathComponent) {
            for file in (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [] {
                trash(file)
            }
            try? fm.removeItem(at: folder)
        }
    }

    // MARK: - Dragging out

    /// What dragging the item out puts on the drag pasteboard, written up front so the
    /// receiver gets it the moment you let go: the file itself, the link, or the text.
    func pasteboardWriter(for item: CubbyItem) -> NSPasteboardWriting {
        switch item.kind {
        case .file, .image:
            if let url = item.fileURL { return url as NSURL }
        case .link:
            if let url = URL(string: item.text) { return url as NSURL }
        case .color, .text:
            break
        }
        return item.text as NSString
    }

    /// Files leave the cubby like they'd leave a folder; links and text are copied.
    func movesOut(_ item: CubbyItem) -> Bool { item.fileURL != nil }

    /// A drag from the cubby ended. A file delivered anywhere outside the cubby leaves it
    /// the moment it's dropped. Finder finishes moving the file a moment later; if the
    /// receiver copied it instead, the cubby's leftover copy is cleaned up once the copy
    /// has had time to finish.
    func dragEnded(_ id: UUID, delivered: Bool) {
        draggedItemID = nil
        guard delivered, let item = item(withID: id), let url = item.fileURL else { return }
        let folder = AppPaths.files.appending(path: item.id.uuidString)
        let isOriginal = item.isOriginal
        context.delete(item)
        try? context.save()
        Task { [trash] in
            try? await Task.sleep(for: .seconds(3))
            if FileManager.default.fileExists(atPath: url.path) {
                if isOriginal { trash(url) } else { try? FileManager.default.removeItem(at: url) }
            }
            try? FileManager.default.removeItem(at: folder)
        }
    }

    // MARK: - Item actions

    private func item(withID id: UUID) -> CubbyItem? {
        var match = FetchDescriptor<CubbyItem>(predicate: #Predicate { $0.id == id })
        match.fetchLimit = 1
        return try? context.fetch(match).first
    }

    /// Files, images and links open in their default app; there's nothing to open for
    /// colors and text.
    func open(_ item: CubbyItem) {
        switch item.kind {
        case .file, .image:
            if let url = item.fileURL { NSWorkspace.shared.open(url) }
        case .link:
            if let url = URL(string: item.text) { NSWorkspace.shared.open(url) }
        case .color, .text:
            break
        }
    }

    /// Copies the item as its native type: the file, the URL, or the string.
    func copy(_ item: CubbyItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        switch item.kind {
        case .file, .image:
            if let url = item.fileURL { pasteboard.writeObjects([url as NSURL]) }
        case .link:
            if let url = URL(string: item.text) { pasteboard.writeObjects([url as NSURL]) }
            pasteboard.setString(item.text, forType: .string)
        case .color, .text:
            pasteboard.setString(item.text, forType: .string)
        }
    }

    func revealInFinder(_ item: CubbyItem) {
        guard let url = item.fileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - File actions, as on the Desktop

    /// Where Move to Desktop puts files: the first folder drops are moved from.
    private var desktop: URL { movableFolders.first ?? URL.desktopDirectory }

    func open(_ item: CubbyItem, withApplicationAt app: URL) {
        guard let url = item.fileURL else { return }
        NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }

    /// Takes the file off the cubby and puts it back on the Desktop, renamed like Finder
    /// would ("name 2.ext") if something there has the same name.
    func moveToDesktop(_ item: CubbyItem) {
        guard let url = item.fileURL else { return }
        let destination = Self.unusedURL(for: url.lastPathComponent, in: desktop)
        do {
            try FileManager.default.moveItem(at: url, to: destination)
        } catch {
            logger.error("move to Desktop failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        try? FileManager.default.removeItem(at: AppPaths.files.appending(path: item.id.uuidString))
        context.delete(item)
        try? context.save()
    }

    func moveToBin(_ item: CubbyItem) {
        delete(item, toBin: true)
        try? context.save()
    }

    /// Renames the file. Returns false if the name can't be used.
    @discardableResult
    func rename(_ item: CubbyItem, to newName: String) -> Bool {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = item.fileURL, !name.isEmpty, !name.contains("/"), name != url.lastPathComponent
        else { return false }
        let destination = url.deletingLastPathComponent().appending(path: name)
        guard (try? FileManager.default.moveItem(at: url, to: destination)) != nil else { return false }
        item.fileName = name
        item.text = name
        item.storedPath = "\(item.id.uuidString)/\(name)"
        try? context.save()
        return true
    }

    /// A copy next to it on the cubby, named like Finder's ("name copy.ext").
    func duplicate(_ item: CubbyItem) {
        guard let url = item.fileURL else { return }
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        let name = ext.isEmpty ? "\(base) copy" : "\(base) copy.\(ext)"
        let id = UUID()
        let destination = AppPaths.files.appending(path: id.uuidString).appending(path: name)
        do {
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: url, to: destination)
        } catch { return }
        let copy = CubbyItem(id: id, kind: item.kind, text: name)
        copy.fileName = name
        copy.fileSize = item.fileSize
        copy.storedPath = "\(id.uuidString)/\(name)"
        copy.thumbnail = item.thumbnail
        context.insert(copy)
        try? context.save()
    }

    /// Zips the file or folder into a new item on the cubby, like Finder's Compress.
    @discardableResult
    func compress(_ item: CubbyItem) -> Task<Void, Never> {
        Task {
            guard let url = item.fileURL else { return }
            let zip = FileManager.default.temporaryDirectory
                .appending(path: UUID().uuidString)
                .appending(path: url.lastPathComponent + ".zip")
            let succeeded = await Task.detached {
                try? FileManager.default.createDirectory(at: zip.deletingLastPathComponent(), withIntermediateDirectories: true)
                let ditto = Process()
                ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                ditto.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", url.path, zip.path]
                guard (try? ditto.run()) != nil else { return false }
                ditto.waitUntilExit()
                return ditto.terminationStatus == 0
            }.value
            guard succeeded else { return }
            // Added as the cubby's own copy, not one of your originals.
            await addFile(zip, move: false)
            try? FileManager.default.removeItem(at: zip.deletingLastPathComponent())
            try? context.save()
        }
    }

    /// Opens Finder's Get Info window for the file.
    func showInfo(_ item: CubbyItem) {
        guard let url = item.fileURL else { return }
        let path = url.path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "Finder"
            activate
            open information window of (POSIX file "\(path)" as alias)
        end tell
        """
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
        if let error { logger.error("Get Info failed: \(error, privacy: .public)") }
    }

    /// `name` in `folder`, or "name 2", "name 3"… if it's taken.
    private static func unusedURL(for name: String, in folder: URL) -> URL {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = folder.appending(path: name)
        var number = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appending(path: ext.isEmpty ? "\(base) \(number)" : "\(base) \(number).\(ext)")
            number += 1
        }
        return candidate
    }

    // MARK: - Paste

    /// ⌘V anywhere in Cubby's windows, unless a text field is being edited.
    private func installPasteMonitor() {
        pasteMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                  event.charactersIgnoringModifiers == "v",
                  !(event.window?.firstResponder is NSText)
            else { return event }
            self?.paste()
            return nil
        }
    }

    // MARK: - Helpers

    private nonisolated static func size(of url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileSizeKey, .isDirectoryKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return 0 }
        guard values.isDirectory == true else { return Int64(values.fileSize ?? 0) }
        let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys))
        var total: Int64 = 0
        while let child = enumerator?.nextObject() as? URL {
            total += Int64((try? child.resourceValues(forKeys: keys))?.fileSize ?? 0)
        }
        return total
    }
}
