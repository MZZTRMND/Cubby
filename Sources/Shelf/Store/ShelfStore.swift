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
    @ObservationIgnored private var removalTask: Task<Void, Never>?
    @ObservationIgnored private var pasteMonitor: Any?

    init(context: ModelContext) {
        self.context = context
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

    func drop(_ providers: [NSItemProvider]) {
        Task { add(await ItemImporter.incoming(from: providers)) }
    }

    @discardableResult
    func add(_ incoming: [Incoming]) -> Task<Void, Never> {
        Task {
            for item in incoming {
                switch item {
                case .text(let string): addString(string)
                case .url(let url): addLink(url)
                case .file(let url): await addFile(url)
                case .image(let data, let type, let name): await addImage(data, type: type, name: name)
                }
            }
            try? context.save()
        }
    }

    private func addString(_ string: String) {
        let text = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let kind = ItemImporter.kind(of: text)
        if kind == .link, let url = ItemImporter.linkURL(text) { return addLink(url) }
        if moveExistingToTop(kind: kind, text: text) { return }
        context.insert(ShelfItem(kind: kind, text: text))
    }

    private func addLink(_ url: URL) {
        let text = url.absoluteString
        if moveExistingToTop(kind: .link, text: text) { return }
        let item = ShelfItem(kind: .link, text: text)
        context.insert(item)
        Task {
            let (title, favicon) = await LinkMetadata.fetch(url)
            guard !item.isDeleted else { return }
            item.title = title
            item.favicon = favicon
            try? context.save()
        }
    }

    private func addFile(_ source: URL) async {
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
        let thumbnail: Data?? = try? await Task.detached {
            let fm = FileManager.default
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: source, to: destination)
            return isImage ? ImageData.thumbnail(of: destination) : nil
        }.value
        guard let thumbnail else { return }

        let item = ShelfItem(id: id, kind: isImage ? .image : .file, text: name)
        item.fileName = name
        item.fileSize = size
        item.storedPath = "\(id.uuidString)/\(name)"
        item.thumbnail = thumbnail
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

        let item = ShelfItem(id: id, kind: .image, text: fileName)
        item.fileName = fileName
        item.fileSize = Int64(data.count)
        item.storedPath = "\(id.uuidString)/\(fileName)"
        item.thumbnail = thumbnail
        context.insert(item)
    }

    /// Dropping something that's already on the shelf moves it to the top instead.
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

    private func delete(_ item: ShelfItem) {
        if item.storedPath != nil {
            try? FileManager.default.removeItem(at: AppPaths.files.appending(path: item.id.uuidString))
        }
        context.delete(item)
    }

    /// Deletes copied files whose item no longer exists, e.g. after a crash mid-clear.
    private func removeOrphanedFiles() {
        let items = (try? context.fetch(FetchDescriptor<ShelfItem>())) ?? []
        let kept = Set(items.map(\.id.uuidString))
        let folders = (try? FileManager.default.contentsOfDirectory(
            at: AppPaths.files, includingPropertiesForKeys: nil
        )) ?? []
        for folder in folders where !kept.contains(folder.lastPathComponent) {
            try? FileManager.default.removeItem(at: folder)
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
