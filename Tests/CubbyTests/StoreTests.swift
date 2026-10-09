import AppKit
import Foundation
import SwiftData
import Testing
import UniformTypeIdentifiers
@testable import Cubby

/// Runs the store against an in-memory container, private pasteboards, a temporary
/// "Desktop" and a fake Trash, so none of the user's data, clipboard or Trash is touched.
@MainActor @Suite(.serialized)
struct StoreTests {
    @Test func usesItsOwnFolder() {
        #expect(!["com.cubby.app", "com.cubby.app.test"].contains(AppPaths.support.lastPathComponent))
    }

    let container: ModelContainer
    let store: CubbyStore
    let desktop: URL
    let trashed = Box<[URL]>([])

    final class Box<T> { var value: T; init(_ value: T) { self.value = value } }

    init() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: CubbyItem.self, configurations: config)
        desktop = FileManager.default.temporaryDirectory.appending(path: "cubby-desktop-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: desktop, withIntermediateDirectories: true)
        let trashed = trashed
        let bin = desktop.appending(path: ".Bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        store = CubbyStore(context: container.mainContext, movableFolders: [desktop]) { url in
            trashed.value.append(url)
            let binned = bin.appending(path: UUID().uuidString)
            return (try? FileManager.default.moveItem(at: url, to: binned)) != nil ? binned : nil
        }
    }

    private var items: [CubbyItem] {
        (try? store.context.fetch(FetchDescriptor<CubbyItem>(sortBy: [SortDescriptor(\.addedAt, order: .reverse)]))) ?? []
    }

    private func paste(_ write: (NSPasteboard) -> Void) async {
        let pasteboard = NSPasteboard(name: .init("cubby.tests.\(UUID().uuidString)"))
        pasteboard.clearContents()
        write(pasteboard)
        await store.add(ItemImporter.incoming(from: pasteboard)).value
        pasteboard.releaseGlobally()
    }

    @Test func pastedStringsAreClassifiedAndDeduplicated() async {
        await paste { $0.setString("  #3366ff\n", forType: .string) }
        await paste { $0.setString("hello there", forType: .string) }
        await paste { $0.setString("#3366ff", forType: .string) }
        #expect(items.map(\.kind) == [.color, .text])
        #expect(items.first?.text == "#3366ff")
    }

    @Test func filesAndImagesAreCopiedIntoTheContainer() async throws {
        let source = FileManager.default.temporaryDirectory.appending(path: "cubby-test-\(UUID().uuidString).txt")
        try "notes".write(to: source, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: source) }

        await paste { $0.writeObjects([source as NSURL]) }
        let png = try #require(NSImage(systemSymbolName: "star", accessibilityDescription: nil)?.tiffRepresentation)
        await paste { $0.setData(png, forType: .tiff) }

        #expect(items.map(\.kind) == [.image, .file])
        let file = try #require(items.last)
        #expect(file.fileName == source.lastPathComponent && file.fileSize == 5)
        let copy = try #require(file.fileURL)
        #expect(try String(contentsOf: copy, encoding: .utf8) == "notes")
        #expect(items.first?.thumbnail != nil && items.first?.fileName == "Image.png")

        for item in items { store.remove(item) }
        #expect(!FileManager.default.fileExists(atPath: copy.path))
    }

    @Test func clearMovesEveryFileToTheBin() async throws {
        let source = desktop.appending(path: "copy.txt")
        try "x".write(to: source, atomically: true, encoding: .utf8)
        await store.add([.file(source)]).value
        await paste { $0.setString("note", forType: .string) }
        #expect(store.clearableCount() == 2)

        let before = trashed.value.count
        store.clear()
        #expect(items.isEmpty)
        #expect(trashed.value.dropFirst(before).map(\.lastPathComponent) == ["copy.txt"])
    }

    @Test func dragOutHandsOverTheFileLinkOrText() async throws {
        await paste { $0.setString("https://apple.com", forType: .string) }
        await paste { $0.setString("#ff0000", forType: .string) }
        let source = desktop.appending(path: "drag.txt")
        try "x".write(to: source, atomically: true, encoding: .utf8)
        await store.add([.file(source)]).value

        #expect(items.map(store.movesOut) == [true, false, false])
        #expect(store.pasteboardWriter(for: items[0]) as? URL == items[0].fileURL)
        #expect(store.pasteboardWriter(for: items[1]) as? String == "#ff0000")
        #expect(store.pasteboardWriter(for: items[2]) as? URL == URL(string: "https://apple.com"))
        for item in items { store.remove(item) }
    }

    @Test func filesDroppedFromTheDesktopAreMovedAndTrashedOnRemove() async throws {
        let onDesktop = desktop.appending(path: "draft.txt")
        try "draft".write(to: onDesktop, atomically: true, encoding: .utf8)
        await store.add([.file(onDesktop)], moveFiles: true).value

        let item = try #require(items.first)
        #expect(!FileManager.default.fileExists(atPath: onDesktop.path))
        #expect(item.isOriginal)
        let stored = try #require(item.fileURL)
        #expect(try String(contentsOf: stored, encoding: .utf8) == "draft")

        let before = trashed.value.count
        store.remove(item)
        #expect(trashed.value.dropFirst(before).map(\.lastPathComponent) == ["draft.txt"])
        #expect(!FileManager.default.fileExists(atPath: stored.deletingLastPathComponent().path))
    }

    @Test func pastedAndNonDesktopFilesAreCopied() async throws {
        let onDesktop = desktop.appending(path: "keep.txt")
        try "keep".write(to: onDesktop, atomically: true, encoding: .utf8)
        await store.add([.file(onDesktop)], moveFiles: false).value
        #expect(FileManager.default.fileExists(atPath: onDesktop.path))
        #expect(items.first?.isOriginal == false)

        let elsewhere = FileManager.default.temporaryDirectory.appending(path: "cubby-elsewhere-\(UUID().uuidString).txt")
        try "x".write(to: elsewhere, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: elsewhere) }
        await store.add([.file(elsewhere)], moveFiles: true).value
        #expect(FileManager.default.fileExists(atPath: elsewhere.path))

        // Binning the cubby's copies leaves the originals where they were.
        for item in items { store.moveToBin(item) }
        #expect(FileManager.default.fileExists(atPath: onDesktop.path))
        #expect(FileManager.default.fileExists(atPath: elsewhere.path))
    }

    @Test func sortOrderArrangesTheGrid() async {
        await paste { $0.setString("banana", forType: .string) }
        await paste { $0.setString("#ff0000", forType: .string) }
        await paste { $0.setString("apple", forType: .string) }
        let original = store.sortOrder
        defer { store.sortOrder = original }

        store.sortOrder = .dateAdded
        #expect(store.sorted(items).map(\.text) == ["apple", "#ff0000", "banana"])
        store.sortOrder = .name
        #expect(store.sorted(items).map(\.text) == ["#ff0000", "apple", "banana"])
        store.sortOrder = .kind
        #expect(store.sorted(items).map(\.text) == ["#ff0000", "apple", "banana"])
    }

    @Test func commandAndShiftClickPickItemsAndSpacePreviewsThem() async throws {
        for name in ["a.txt", "b.txt", "c.txt", "d.txt"] {
            let url = desktop.appending(path: name)
            try Data(name.utf8).write(to: url)
            await store.add([.file(url)], moveFiles: false).value
        }
        await paste { $0.setString("note", forType: .string) }
        let order = store.allItems()
        let ids = order.map(\.id)

        store.select(ids[1], extending: false, in: ids)
        store.select(ids[3], extending: true, in: ids)
        #expect(store.selection == Set(ids[1...3]))
        store.select(ids[2], extending: false, in: ids)
        #expect(store.selection == [ids[1], ids[3]])

        // Space shows the selection, or the hovered item when it isn't selected; never text.
        #expect(store.quickLookURLs(in: order) == [order[1].fileURL, order[3].fileURL].compactMap { $0 })
        store.hoveredItemID = ids[4]
        #expect(store.quickLookURLs(in: order) == [order[4].fileURL].compactMap { $0 })
        store.hoveredItemID = ids[0]
        #expect(store.quickLookURLs(in: order).isEmpty)

        store.selectAll()
        #expect(store.selection == Set(ids))
        store.clearSelection()
        #expect(store.selection.isEmpty)
    }

    @Test func undoBringsBackWhatMoveToBinRemoveAndClearTookAway() async throws {
        let undo = UndoManager()
        undo.groupsByEvent = false
        store.undoManager = undo
        func step(_ action: () -> Void) { undo.beginUndoGrouping(); action(); undo.endUndoGrouping() }

        let source = desktop.appending(path: "keep.txt")
        try "kept".write(to: source, atomically: true, encoding: .utf8)
        await store.add([.file(source)], moveFiles: true).value
        await paste { $0.setString("a note", forType: .string) }
        let file = try #require(items.first { $0.kind == .file })
        let id = file.id, stored = try #require(file.fileURL)

        step { store.moveToBin(file) }
        #expect(items.count == 1)
        #expect(!FileManager.default.fileExists(atPath: stored.path))
        undo.undo()
        #expect(items.count == 2)
        let back = try #require(items.first { $0.id == id })
        #expect(back.isOriginal)
        #expect(try String(contentsOf: stored, encoding: .utf8) == "kept")
        undo.redo()
        #expect(items.count == 1)
        undo.undo()

        step { store.clear() }
        #expect(items.isEmpty)
        undo.undo()
        #expect(Set(items.map(\.text)) == ["keep.txt", "a note"])
        #expect(FileManager.default.fileExists(atPath: stored.path))
        #expect(undo.redoActionName == "Clear")
    }

    @Test func arrowKeysWalkTheGrid() async {
        // Five items in three columns:  0 1 2
        //                               3 4
        for text in ["e", "d", "c", "b", "a"] { await paste { $0.setString(text, forType: .string) } }
        let ids = store.allItems().map(\.id)
        func move(_ direction: CubbyStore.Direction, extending: Bool = false) {
            store.moveSelection(direction, columns: 3, extending: extending)
        }

        move(.right)
        #expect(store.selection == [ids[0]])
        move(.left)
        #expect(store.selection == [ids[0]])
        move(.down)
        #expect(store.selection == [ids[3]])
        move(.down)
        #expect(store.selection == [ids[3]])
        move(.up); move(.right); move(.right); move(.down)
        #expect(store.selection == [ids[4]])
        move(.left, extending: true)
        #expect(store.selection == [ids[3], ids[4]])
        move(.up, extending: true)
        #expect(store.selection == Set(ids[0...4]))

        // With nothing picked, the first arrow starts at the item under the pointer.
        store.clearSelection()
        store.hoveredItemID = ids[2]
        move(.down)
        #expect(store.selection == [ids[2]])
        #expect(store.hoveredItemID == nil)
    }

    @Test func aSelectionDraggedOutLeavesTogether() async throws {
        for name in ["one.txt", "two.txt"] {
            let url = desktop.appending(path: name)
            try Data(name.utf8).write(to: url)
            await store.add([.file(url)], moveFiles: false).value
        }
        let ids = items.map(\.id)
        store.selection = Set(ids)
        store.draggedItemIDs = Set(ids)
        store.dragEnded(ids, delivered: true)
        #expect(items.isEmpty)
        #expect(store.selection.isEmpty)
        #expect(store.draggedItemIDs.isEmpty)
    }

    @Test func itemsWhoseFileWasMovedAwayAreDropped() async throws {
        let source = desktop.appending(path: "gone.txt")
        try "x".write(to: source, atomically: true, encoding: .utf8)
        await store.add([.file(source)]).value
        let stored = try #require(items.first?.fileURL)
        try FileManager.default.removeItem(at: stored)
        store.tidy()
        #expect(items.isEmpty)
        #expect(store.missingNames == ["gone.txt"])
    }

    /// Finder hands files over as "a PNG file that can be opened in place", not as a URL.
    private func finderProvider(for url: URL, type: String) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.registerFileRepresentation(forTypeIdentifier: type, fileOptions: [.openInPlace], visibility: .all) { completion in
            completion(url, true, nil)
            return nil
        }
        return provider
    }

    @Test func imagesDraggedFromTheDesktopAreMovedNotSavedAsData() async throws {
        let onDesktop = desktop.appending(path: "photo.png")
        let png = try #require(ImageData.png(from: NSImage(systemSymbolName: "star", accessibilityDescription: nil)!.tiffRepresentation!))
        try png.write(to: onDesktop)

        let incoming = await ItemImporter.incoming(from: [finderProvider(for: onDesktop, type: "public.png")])
        await store.add(incoming, moveFiles: true).value

        let item = try #require(items.first)
        #expect(item.kind == .image && item.fileName == "photo.png" && item.isOriginal)
        #expect(item.thumbnail != nil)
        #expect(!FileManager.default.fileExists(atPath: onDesktop.path))
    }

    @Test func droppingACubbyFileBackOntoTheCubbyAddsNothing() async throws {
        let onDesktop = desktop.appending(path: "photo.png")
        let png = try #require(ImageData.png(from: NSImage(systemSymbolName: "star", accessibilityDescription: nil)!.tiffRepresentation!))
        try png.write(to: onDesktop)
        await store.add([.file(onDesktop)], moveFiles: true).value
        let stored = try #require(items.first?.fileURL)

        let incoming = await ItemImporter.incoming(from: [finderProvider(for: stored, type: "public.png")])
        await store.add(incoming, moveFiles: true).value
        #expect(items.count == 1)
        #expect(FileManager.default.fileExists(atPath: stored.path))
    }

    @Test func filesDraggedOutLeaveTheCubby() async throws {
        for name in ["moved.txt", "copied.txt", "cancelled.txt"] {
            let source = desktop.appending(path: name)
            try name.write(to: source, atomically: true, encoding: .utf8)
            await store.add([.file(source)]).value
        }
        let byName = Dictionary(uniqueKeysWithValues: items.map { ($0.fileName!, $0) })

        // Finder moves the file a moment after the drop; the item leaves at once anyway.
        store.dragEnded(byName["moved.txt"]!.id, delivered: true)
        #expect(!items.contains { $0.fileName == "moved.txt" })

        // A receiver that copied it: the item leaves at once, the leftover file later.
        let copied = byName["copied.txt"]!.fileURL!
        store.dragEnded(byName["copied.txt"]!.id, delivered: true)
        #expect(!items.contains { $0.fileName == "copied.txt" })
        #expect(FileManager.default.fileExists(atPath: copied.path))

        store.dragEnded(byName["cancelled.txt"]!.id, delivered: false)
        await paste { $0.setString("a note", forType: .string) }
        store.dragEnded(items.first { $0.kind == .text }!.id, delivered: true)

        try await Task.sleep(for: .seconds(3.3))
        #expect(!FileManager.default.fileExists(atPath: copied.deletingLastPathComponent().path))
        #expect(Set(items.compactMap(\.fileName)) == ["cancelled.txt"])
        #expect(items.contains { $0.kind == .text })
        for item in items { store.remove(item) }
    }

    private func addFile(_ name: String, contents: String = "x") async throws -> CubbyItem {
        let source = FileManager.default.temporaryDirectory.appending(path: "cubby-src-\(UUID().uuidString)").appending(path: name)
        try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: source, atomically: true, encoding: .utf8)
        await store.add([.file(source)]).value
        return try #require(items.first { $0.fileName == name })
    }

    @Test func moveToDesktopPutsTheFileBackUnderAFreeName() async throws {
        try "already here".write(to: desktop.appending(path: "report.txt"), atomically: true, encoding: .utf8)
        let item = try await addFile("report.txt", contents: "from the cubby")
        store.moveToDesktop(item)
        #expect(items.isEmpty)
        #expect(try String(contentsOf: desktop.appending(path: "report 2.txt"), encoding: .utf8) == "from the cubby")
    }

    @Test func renameDuplicateAndMoveToBin() async throws {
        let item = try await addFile("draft.txt", contents: "hello")
        #expect(store.rename(item, to: "final.txt"))
        #expect(item.fileName == "final.txt" && item.fileURL?.lastPathComponent == "final.txt")
        #expect(!store.rename(item, to: "bad/name"))

        store.duplicate(item)
        let copy = try #require(items.first { $0.fileName == "final copy.txt" })
        #expect(try String(contentsOf: copy.fileURL!, encoding: .utf8) == "hello")

        let before = trashed.value.count
        store.moveToBin(copy)
        #expect(trashed.value.dropFirst(before).map(\.lastPathComponent) == ["final copy.txt"])
        store.remove(item)
    }

    @Test func compressAddsAZipToTheCubby() async throws {
        let item = try await addFile("notes.txt", contents: String(repeating: "cubby ", count: 200))
        await store.compress(item).value
        let zip = try #require(items.first { $0.fileName == "notes.txt.zip" })
        #expect(zip.kind == .file && !zip.isOriginal && zip.fileSize > 0)
        for item in items { store.remove(item) }
    }
}
