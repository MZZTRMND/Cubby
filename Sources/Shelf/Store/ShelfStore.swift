import AppKit
import SwiftData
import UniformTypeIdentifiers

/// The one store both surfaces share. Views read items with `@Query`; all changes go
/// through here.
@MainActor @Observable
final class ShelfStore {
    let context: ModelContext

    /// Items hidden by Clear but not yet deleted, so Clear can be undone.
    private(set) var pendingRemoval: Set<UUID> = []
    /// The item being dragged from the open shelf, if any. A drop back onto the canvas
    /// just moves its icon.
    var draggedItemID: UUID?
    @ObservationIgnored private var removalTask: Task<Void, Never>?
    @ObservationIgnored private var pasteMonitor: Any?
    /// Where the next inserted item goes on the canvas, e.g. where it was dropped.
    @ObservationIgnored private var nextPlacement: CGPoint?

    /// Dropped files from these folders are moved into the shelf instead of copied, so
    /// they disappear from there.
    let movableFolders: [URL]
    /// Removes a moved original. The Trash by default, so nothing of yours is lost.
    private let trash: (URL) -> Void

    init(
        context: ModelContext,
        movableFolders: [URL] = [URL.desktopDirectory],
        trash: @escaping (URL) -> Void = { try? FileManager.default.trashItem(at: $0, resultingItemURL: nil) }
    ) {
        self.context = context
        self.movableFolders = movableFolders
        self.trash = trash
        tidy()
        removeOrphanedFiles()
        installPasteMonitor()
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.commitRemoval() }
        }
    }

    func visible(_ items: [ShelfItem]) -> [ShelfItem] {
        pendingRemoval.isEmpty ? items : items.filter { !pendingRemoval.contains($0.id) }
    }

    // MARK: - Adding

    func paste(from pasteboard: NSPasteboard = .general) {
        add(ItemImporter.incoming(from: pasteboard))
    }

    /// Dropped files are moved off the Desktop; pasted ones are always copied.
    func drop(_ providers: [NSItemProvider], at point: CGPoint? = nil) {
        Task { add(await ItemImporter.incoming(from: providers), moveFiles: true, at: point) }
    }

    @discardableResult
    func add(_ incoming: [Incoming], moveFiles: Bool = false, at point: CGPoint? = nil) -> Task<Void, Never> {
        Task {
            nextPlacement = point.map(CanvasLayout.clamp)
            for item in incoming {
                switch item {
                case .text(let string): addString(string)
                case .url(let url): addLink(url)
                case .file(let url): await addFile(url, move: moveFiles && isInMovableFolder(url))
                case .image(let data, let type, let name): await addImage(data, type: type, name: name)
                }
            }
            nextPlacement = nil
            try? context.save()
        }
    }

    private func insert(_ item: ShelfItem) {
        item.canvasPosition = nextPlacement ?? CanvasLayout.firstFreeSlot(avoiding: canvasPositions())
        nextPlacement = nil
        context.insert(item)
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
        insert(ShelfItem(kind: kind, text: text))
    }

    private func addLink(_ url: URL) {
        let text = url.absoluteString
        if moveExistingToTop(kind: .link, text: text) { return }
        let item = ShelfItem(kind: .link, text: text)
        insert(item)
        Task {
            let (title, favicon) = await LinkMetadata.fetch(url)
            guard !item.isDeleted else { return }
            item.title = title
            item.favicon = favicon
            try? context.save()
        }
    }

    private func addFile(_ source: URL, move: Bool) async {
        // One of the shelf's own files, dragged around the canvas: just move its icon.
        let filesPath = AppPaths.files.resolvingSymlinksInPath().path + "/"
        let sourcePath = source.resolvingSymlinksInPath().path
        if sourcePath.hasPrefix(filesPath) {
            let folder = sourcePath.dropFirst(filesPath.count).split(separator: "/").first.map(String.init)
            if let id = folder.flatMap(UUID.init), let item = item(withID: id) { bump(item) }
            return
        }

        let name = source.lastPathComponent
        let size = Self.size(of: source)
        let optionalName: String? = name
        var existing = FetchDescriptor<ShelfItem>(
            predicate: #Predicate { $0.fileName == optionalName && $0.fileSize == size }
        )
        existing.fetchLimit = 1
        if let item = try? context.fetch(existing).first {
            bump(item)
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

        let item = ShelfItem(id: id, kind: isImage ? .image : .file, text: name)
        item.fileName = name
        item.fileSize = size
        item.storedPath = "\(id.uuidString)/\(name)"
        item.thumbnail = thumbnail
        item.isOriginal = moved
        insert(item)
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

        let item = ShelfItem(id: id, kind: .image, text: fileName)
        item.fileName = fileName
        item.fileSize = Int64(data.count)
        item.storedPath = "\(id.uuidString)/\(fileName)"
        item.thumbnail = thumbnail
        insert(item)
    }

    /// Dropping something that's already on the shelf brings it back to the front instead.
    private func moveExistingToTop(kind: ItemKind, text: String) -> Bool {
        let kindRaw = kind.rawValue
        var existing = FetchDescriptor<ShelfItem>(
            predicate: #Predicate { $0.kindRaw == kindRaw && $0.text == text }
        )
        existing.fetchLimit = 1
        guard let item = try? context.fetch(existing).first else { return false }
        bump(item)
        return true
    }

    private func bump(_ item: ShelfItem) {
        item.addedAt = .now
        pendingRemoval.remove(item.id)
        if let point = nextPlacement {
            item.canvasPosition = point
            nextPlacement = nil
        }
    }

    // MARK: - Removing

    var canUndoClear: Bool { !pendingRemoval.isEmpty }

    /// Hides unpinned items for a few seconds so Clear can be undone, then deletes them.
    func clear() {
        commitRemoval()
        let unpinned = FetchDescriptor<ShelfItem>(predicate: #Predicate { !$0.isPinned })
        let ids = ((try? context.fetch(unpinned)) ?? []).map(\.id)
        guard !ids.isEmpty else { return }
        pendingRemoval = Set(ids)
        removalTask = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            commitRemoval()
        }
    }

    func undoClear() {
        removalTask?.cancel()
        removalTask = nil
        pendingRemoval = []
    }

    func remove(_ item: ShelfItem) {
        delete(item)
        try? context.save()
    }

    /// Drops items whose file is gone, e.g. moved out to Finder. Runs at launch, when the
    /// shelf opens and after a drag out.
    func tidy() {
        let withFiles = FetchDescriptor<ShelfItem>(predicate: #Predicate { $0.storedPath != nil })
        let missing = ((try? context.fetch(withFiles)) ?? []).filter {
            guard let url = $0.fileURL else { return false }
            return !FileManager.default.fileExists(atPath: url.path)
        }
        guard !missing.isEmpty else { return }
        for item in missing { delete(item) }
        try? context.save()
    }

    /// The receiving app finishes moving the file a moment after the drop, so look again
    /// shortly after.
    func tidyAfterDragOut() {
        tidy()
        Task {
            try? await Task.sleep(for: .seconds(1))
            tidy()
        }
    }

    // MARK: - Canvas

    private func canvasPositions() -> [CGPoint] {
        ((try? context.fetch(FetchDescriptor<ShelfItem>())) ?? []).compactMap(\.canvasPosition)
    }

    /// Gives a canvas slot to items that don't have one yet (added before the canvas).
    func placeUnplaced() {
        let unplaced = FetchDescriptor<ShelfItem>(
            predicate: #Predicate { $0.canvasX == nil },
            sortBy: [SortDescriptor(\.addedAt, order: .reverse)]
        )
        let items = (try? context.fetch(unplaced)) ?? []
        guard !items.isEmpty else { return }
        var taken = canvasPositions()
        for item in items {
            let slot = CanvasLayout.firstFreeSlot(avoiding: taken)
            item.canvasPosition = slot
            taken.append(slot)
        }
        try? context.save()
    }

    func move(_ id: UUID, to point: CGPoint) {
        guard let item = item(withID: id) else { return }
        item.canvasPosition = CanvasLayout.clamp(point)
        try? context.save()
    }

    private func item(withID id: UUID) -> ShelfItem? {
        var match = FetchDescriptor<ShelfItem>(predicate: #Predicate { $0.id == id })
        match.fetchLimit = 1
        return try? context.fetch(match).first
    }

    // MARK: - Item actions

    /// Files, images and links open in their default app; there's nothing to open for
    /// colors and text.
    func open(_ item: ShelfItem) {
        switch item.kind {
        case .file, .image:
            if let url = item.fileURL { NSWorkspace.shared.open(url) }
        case .link:
            if let url = URL(string: item.text) { NSWorkspace.shared.open(url) }
        case .color, .text:
            break
        }
    }

    func togglePin(_ item: ShelfItem) {
        item.isPinned.toggle()
        try? context.save()
    }

    /// Copies the item as its native type: the file, the URL, or the string.
    func copy(_ item: ShelfItem) {
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

    func revealInFinder(_ item: ShelfItem) {
        guard let url = item.fileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func commitRemoval() {
        removalTask?.cancel()
        removalTask = nil
        guard !pendingRemoval.isEmpty else { return }
        let ids = Array(pendingRemoval)
        let pending = FetchDescriptor<ShelfItem>(predicate: #Predicate { ids.contains($0.id) })
        for item in (try? context.fetch(pending)) ?? [] { delete(item) }
        pendingRemoval = []
        try? context.save()
    }

    /// Copies are deleted; your own moved files go to the Trash.
    private func delete(_ item: ShelfItem) {
        if item.storedPath != nil {
            let folder = AppPaths.files.appending(path: item.id.uuidString)
            if item.isOriginal, let url = item.fileURL, FileManager.default.fileExists(atPath: url.path) {
                trash(url)
            }
            try? FileManager.default.removeItem(at: folder)
        }
        context.delete(item)
    }

    /// Cleans up file folders whose item no longer exists, e.g. after a crash mid-clear.
    /// They might hold a moved original, so their contents go to the Trash.
    private func removeOrphanedFiles() {
        let items = (try? context.fetch(FetchDescriptor<ShelfItem>())) ?? []
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

    // MARK: - Paste

    /// ⌘V anywhere in Shelf's windows, unless a text field is being edited.
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
