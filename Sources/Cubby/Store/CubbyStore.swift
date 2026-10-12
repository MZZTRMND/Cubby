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
    /// The items being dragged out of the open cubby, if any. Dropping them back onto the
    /// cubby does nothing.
    var draggedItemIDs: Set<UUID> = []
    /// The tab the open cubby is on: one kind of item, or everything.
    var kindFilter: ItemKind? {
        didSet { if kindFilter != oldValue { clearSelection() } }
    }
    /// What's been typed in the open cubby to find items by name. While it's set, the
    /// grid shows matches from every tab.
    var searchText = "" {
        didSet { if searchText != oldValue { clearSelection() } }
    }
    var isSearching: Bool { !searchText.isEmpty }
    /// Items picked with ⌘- or ⇧-click in the open cubby.
    var selection: Set<UUID> = []
    /// Where a ⇧-click range starts.
    @ObservationIgnored private var selectionAnchor: UUID?
    /// The item the arrow keys move from: the last one clicked or arrowed to. The grid
    /// scrolls to keep it in view.
    private(set) var cursorID: UUID?
    /// Items `tidy()` dropped because their file was gone, by name, until the open
    /// cubby has told you about them.
    var missingNames: [String] = []
    /// The item under the pointer in the open cubby, for Space.
    @ObservationIgnored var hoveredItemID: UUID?
    @ObservationIgnored private var pasteMonitor: Any?

    /// Dropped files from these folders are moved into the cubby instead of copied, so
    /// they disappear from there.
    let movableFolders: [URL]
    /// Moves a file to the Bin, so nothing of yours is lost, and says where it went.
    private let trash: (URL) -> URL?
    /// Takes Move to Bin, Remove and Clear back with ⌘Z. The panel hands in its window's.
    @ObservationIgnored var undoManager: UndoManager?

    init(
        context: ModelContext,
        movableFolders: [URL] = [URL.desktopDirectory],
        trash: @escaping (URL) -> URL? = { url in
            var binned: NSURL?
            try? FileManager.default.trashItem(at: url, resultingItemURL: &binned)
            return binned as URL?
        }
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
        // Whatever comes in should be seen arriving, whatever tab you're on.
        kindFilter = nil
        searchText = ""
        return Task {
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

    /// A screenshot caught from the screenshot folder: always moved in, like a drop from
    /// the Desktop, without switching the open cubby's tab.
    @discardableResult
    func addScreenshot(_ url: URL) -> Task<Void, Never> {
        Task {
            await addFile(url, move: true)
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

    /// The items under the chosen tab, or matching the search, in grid order.
    func shown(_ items: [CubbyItem]) -> [CubbyItem] {
        if isSearching { return sorted(items.filter { Self.matches($0, searchText) }) }
        return sorted(kindFilter.map { kind in items.filter { $0.kind == kind } } ?? items)
    }

    /// Whether any of the item's names contain `query`, ignoring case and accents.
    static func matches(_ item: CubbyItem, _ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        let names = [item.name, item.note, item.fileName, item.title, item.text, item.kind == .link ? item.domain : nil]
        return names.contains { $0?.localizedStandardContains(query) == true }
    }

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
        item.name ?? item.fileName ?? item.title ?? item.text
    }

    // MARK: - Removing

    func remove(_ item: CubbyItem) {
        moveToBin([item], actionName: "Remove")
    }

    /// Moves everything under the current tab to the Bin. ⌘Z brings it all back.
    func clear() {
        moveToBin(shownItems(), actionName: "Clear")
    }

    func moveToBin(_ item: CubbyItem) {
        moveToBin([item], actionName: "Move to Bin")
    }

    /// An item taken out of the cubby, kept so Undo can put it back, file and all.
    private struct Removed {
        let id: UUID
        let kindRaw: String
        let addedAt: Date
        let text: String
        let title: String?
        let fileName: String?
        let fileSize: Int64
        let storedPath: String?
        let thumbnail: Data?
        let favicon: Data?
        let isOriginal: Bool
        let name: String?
        let note: String?
        /// Where the file went in the Bin.
        let binned: URL?
    }

    /// Moves the items' files to the Bin and takes them out of the cubby, as one step
    /// that Undo takes back.
    func moveToBin(_ items: [CubbyItem], actionName: String) {
        guard !items.isEmpty else { return }
        let removed = items.map { item in
            var binned: URL?
            if let url = item.fileURL, FileManager.default.fileExists(atPath: url.path) { binned = trash(url) }
            try? FileManager.default.removeItem(at: AppPaths.files.appending(path: item.id.uuidString))
            let record = Removed(
                id: item.id, kindRaw: item.kindRaw, addedAt: item.addedAt, text: item.text, title: item.title,
                fileName: item.fileName, fileSize: item.fileSize, storedPath: item.storedPath,
                thumbnail: item.thumbnail, favicon: item.favicon, isOriginal: item.isOriginal,
                name: item.name, note: item.note, binned: binned
            )
            context.delete(item)
            return record
        }
        try? context.save()
        selection.subtract(removed.map(\.id))
        undoManager?.registerUndo(withTarget: self) { $0.restore(removed, actionName: actionName) }
        undoManager?.setActionName(actionName)
    }

    /// Undo: brings the items back, their files out of the Bin. An item whose file has
    /// left the Bin since stays gone.
    private func restore(_ removed: [Removed], actionName: String) {
        let fm = FileManager.default
        var restored: [UUID] = []
        for record in removed {
            if let storedPath = record.storedPath {
                guard let binned = record.binned, fm.fileExists(atPath: binned.path) else { continue }
                let destination = AppPaths.files.appending(path: storedPath)
                do {
                    try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try fm.moveItem(at: binned, to: destination)
                } catch {
                    logger.error("restore from Bin failed: \(error.localizedDescription, privacy: .public)")
                    continue
                }
            }
            let item = CubbyItem(id: record.id, kind: ItemKind(rawValue: record.kindRaw) ?? .text, text: record.text)
            item.addedAt = record.addedAt
            item.title = record.title
            item.fileName = record.fileName
            item.fileSize = record.fileSize
            item.storedPath = record.storedPath
            item.thumbnail = record.thumbnail
            item.favicon = record.favicon
            item.isOriginal = record.isOriginal
            item.name = record.name
            item.note = record.note
            context.insert(item)
            restored.append(record.id)
        }
        try? context.save()
        // Redo removes them again.
        undoManager?.registerUndo(withTarget: self) { store in
            store.moveToBin(restored.compactMap { store.item(withID: $0) }, actionName: actionName)
        }
        undoManager?.setActionName(actionName)
    }

    /// How many items Clear would remove.
    func clearableCount() -> Int {
        shownItems().count
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
        missingNames += missing.map { $0.fileName ?? $0.text }
        for item in missing { delete(item) }
        try? context.save()
    }

    /// Copies are deleted and your own moved files go to the Bin.
    private func delete(_ item: CubbyItem) {
        if item.storedPath != nil {
            if item.isOriginal, let url = item.fileURL, FileManager.default.fileExists(atPath: url.path) {
                _ = trash(url)
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
                _ = trash(file)
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
    func dragEnded(_ ids: [UUID], delivered: Bool) {
        draggedItemIDs = []
        for id in ids { dragEnded(id, delivered: delivered) }
        selection.subtract(ids)
    }

    func dragEnded(_ id: UUID, delivered: Bool) {
        draggedItemIDs.remove(id)
        guard delivered, let item = item(withID: id), let url = item.fileURL else { return }
        let folder = AppPaths.files.appending(path: item.id.uuidString)
        let isOriginal = item.isOriginal
        context.delete(item)
        try? context.save()
        Task { [trash] in
            try? await Task.sleep(for: .seconds(3))
            if FileManager.default.fileExists(atPath: url.path) {
                if isOriginal { _ = trash(url) } else { try? FileManager.default.removeItem(at: url) }
            }
            try? FileManager.default.removeItem(at: folder)
        }
    }

    // MARK: - Selection

    /// ⌘-click adds or removes one item; ⇧-click adds everything between the last
    /// picked item and this one, in grid order.
    func select(_ id: UUID, extending: Bool, in order: [UUID]) {
        if extending, let anchor = selectionAnchor,
           let from = order.firstIndex(of: anchor), let to = order.firstIndex(of: id) {
            selection.formUnion(order[min(from, to)...max(from, to)])
            return
        }
        if selection.remove(id) == nil { selection.insert(id) }
        selectionAnchor = id
        cursorID = id
    }

    enum Direction { case left, right, up, down }

    /// Arrow keys: move to the neighbouring item in a grid `columns` wide, selecting just
    /// it, or with `extending` (⇧), selecting everything from the anchor to it. With
    /// nothing picked yet, the first arrow picks the item under the pointer or the first.
    func moveSelection(_ direction: Direction, columns: Int, extending: Bool) {
        let order = shownItems().map(\.id)
        guard !order.isEmpty else { return }
        let target: UUID
        if let cursor = cursorID, let index = order.firstIndex(of: cursor) {
            let lastRow = (order.count - 1) / columns
            let next = switch direction {
            case .left: max(index - 1, 0)
            case .right: min(index + 1, order.count - 1)
            case .up: index >= columns ? index - columns : index
            // Into the row below, or its last item when that row is shorter.
            case .down: index / columns < lastRow ? min(index + columns, order.count - 1) : index
            }
            target = order[next]
        } else {
            target = hoveredItemID.flatMap { order.contains($0) ? $0 : nil } ?? order[0]
        }
        // The pointer stays put while you use the keys; Space should follow the keys.
        hoveredItemID = nil
        if extending, let anchor = selectionAnchor ?? cursorID,
           let from = order.firstIndex(of: anchor), let to = order.firstIndex(of: target) {
            selectionAnchor = anchor
            selection = Set(order[min(from, to)...max(from, to)])
        } else {
            selection = [target]
            selectionAnchor = target
        }
        cursorID = target
    }

    /// The selected items in grid order.
    func selectedItems() -> [CubbyItem] {
        shownItems().filter { selection.contains($0.id) }
    }

    func selectAll() {
        selection = Set(shownItems().map(\.id))
    }

    func clearSelection() {
        selection = []
        selectionAnchor = nil
        cursorID = nil
    }

    /// What Space previews: the item under the pointer, or the selection when the
    /// pointer is over one of the selected items or over nothing. Only files and images.
    func quickLookURLs(in order: [CubbyItem]) -> [URL] {
        let picked: [CubbyItem]
        if let hovered = hoveredItemID, !selection.contains(hovered) {
            picked = order.filter { $0.id == hovered }
        } else {
            picked = order.filter { selection.contains($0.id) }
        }
        return picked.compactMap(\.fileURL)
    }

    // MARK: - Item actions

    /// The items the open cubby shows, under the chosen tab, in grid order.
    func shownItems() -> [CubbyItem] {
        shown((try? context.fetch(FetchDescriptor<CubbyItem>())) ?? [])
    }

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

    /// Copies a color written another way, such as rgb() or SwiftUI.
    func copy(_ item: CubbyItem, as format: ColorFormat) {
        guard let color = ColorParser.parse(item.text) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(format.string(for: color), forType: .string)
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

    /// Takes the files off the cubby and puts them back on the Desktop, renamed like Finder
    /// would ("name 2.ext") if something there has the same name.
    func moveToDesktop(_ items: [CubbyItem]) {
        for item in items {
            guard let url = item.fileURL else { continue }
            let destination = Self.unusedURL(for: url.lastPathComponent, in: desktop)
            do {
                try FileManager.default.moveItem(at: url, to: destination)
            } catch {
                logger.error("move to Desktop failed: \(error.localizedDescription, privacy: .public)")
                continue
            }
            try? FileManager.default.removeItem(at: AppPaths.files.appending(path: item.id.uuidString))
            selection.remove(item.id)
            context.delete(item)
        }
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

    /// Zips several items' files into one "Archive.zip" on the cubby, like Finder's
    /// Compress with more than one item selected.
    @discardableResult
    func compress(_ items: [CubbyItem]) -> Task<Void, Never> {
        let urls = items.compactMap(\.fileURL)
        guard urls.count > 1 else { return items.first.map { compress($0) } ?? Task {} }
        return Task {
            let work = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            let zip = work.appending(path: "Archive.zip")
            let succeeded = await Task.detached {
                let fm = FileManager.default
                let folder = work.appending(path: "Archive")
                do {
                    try fm.createDirectory(at: folder, withIntermediateDirectories: true)
                    for url in urls {
                        try fm.copyItem(at: url, to: Self.unusedURL(for: url.lastPathComponent, in: folder))
                    }
                } catch { return false }
                let ditto = Process()
                ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                ditto.arguments = ["-c", "-k", "--sequesterRsrc", folder.path, zip.path]
                guard (try? ditto.run()) != nil else { return false }
                ditto.waitUntilExit()
                return ditto.terminationStatus == 0
            }.value
            if succeeded { await addFile(zip, move: false) }
            try? FileManager.default.removeItem(at: work)
            try? context.save()
        }
    }

    /// The formats Convert offers.
    static let imageFormats: [UTType] = [.jpeg, .png, .heic]

    /// Saves each image as `type`, as a new item next to it, like Finder's Convert Image.
    @discardableResult
    func convert(_ items: [CubbyItem], to type: UTType) -> Task<Void, Never> {
        let ext = type == .jpeg ? "jpg" : type.preferredFilenameExtension ?? "png"
        return transformImages(items) { url in
            let base = url.deletingPathExtension().lastPathComponent
            return (ImageData.convert(url, to: type), "\(base).\(ext)")
        }
    }

    /// Saves each image at half its width and height, as a new item next to it.
    @discardableResult
    func shrink(_ items: [CubbyItem]) -> Task<Void, Never> {
        transformImages(items) { url in
            let type = UTType(filenameExtension: url.pathExtension) ?? .png
            // Formats ImageIO can read but not write come out as PNG.
            let writable = (CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []).contains(type.identifier)
            let format = writable ? type : .png
            let base = url.deletingPathExtension().lastPathComponent
            let ext = writable ? url.pathExtension : "png"
            return (ImageData.convert(url, to: format, scale: 0.5), "\(base) small.\(ext)")
        }
    }

    private func transformImages(_ items: [CubbyItem],
                                 _ transform: @escaping @Sendable (URL) -> (Data?, String)) -> Task<Void, Never> {
        let urls = items.filter { $0.kind == .image }.compactMap(\.fileURL)
        return Task {
            for url in urls {
                let work = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
                let output: URL? = await Task.detached {
                    let (data, name) = transform(url)
                    guard let data else { return nil }
                    let output = work.appending(path: name)
                    try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
                    return (try? data.write(to: output)) != nil ? output : nil
                }.value
                if let output { await addFile(output, move: false) }
                try? FileManager.default.removeItem(at: work)
            }
            try? context.save()
        }
    }

    /// Names a link, color or snippet; an empty name brings back its own. Files are
    /// renamed with `rename(_:to:)`.
    func setName(_ item: CubbyItem, to newName: String) {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        item.name = name.isEmpty ? nil : name
        try? context.save()
    }

    /// An empty note removes it.
    func setNote(_ item: CubbyItem, to newNote: String) {
        let note = newNote.trimmingCharacters(in: .whitespacesAndNewlines)
        item.note = note.isEmpty ? nil : note
        try? context.save()
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
    private nonisolated static func unusedURL(for name: String, in folder: URL) -> URL {
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
