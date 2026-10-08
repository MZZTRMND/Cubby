import AppKit
import Foundation
import SwiftData
import Testing
import UniformTypeIdentifiers
@testable import Shelf

/// Runs the store against an in-memory container, private pasteboards, a temporary
/// "Desktop" and a fake Trash, so none of the user's data, clipboard or Trash is touched.
@MainActor @Suite(.serialized)
struct StoreTests {
    @Test func usesItsOwnFolder() {
        #expect(!["com.shelf.app", "com.shelf.app.test"].contains(AppPaths.support.lastPathComponent))
    }

    let container: ModelContainer
    let store: ShelfStore
    let desktop: URL
    let trashed = Box<[URL]>([])

    final class Box<T> { var value: T; init(_ value: T) { self.value = value } }

    init() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: ShelfItem.self, configurations: config)
        desktop = FileManager.default.temporaryDirectory.appending(path: "shelf-desktop-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: desktop, withIntermediateDirectories: true)
        let trashed = trashed
        store = ShelfStore(context: container.mainContext, movableFolders: [desktop]) { url in
            trashed.value.append(url)
            try? FileManager.default.removeItem(at: url)
        }
    }

    private var items: [ShelfItem] {
        let all = (try? store.context.fetch(FetchDescriptor<ShelfItem>(sortBy: [SortDescriptor(\.addedAt, order: .reverse)]))) ?? []
        return store.visible(all)
    }

    private func paste(_ write: (NSPasteboard) -> Void) async {
        let pasteboard = NSPasteboard(name: .init("shelf.tests.\(UUID().uuidString)"))
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
        let source = FileManager.default.temporaryDirectory.appending(path: "shelf-test-\(UUID().uuidString).txt")
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

    @Test func clearCanBeUndone() async {
        await paste { $0.setString("one", forType: .string) }
        await paste { $0.setString("two", forType: .string) }
        store.clear()
        #expect(items.isEmpty && store.canUndoClear)
        store.undoClear()
        #expect(items.count == 2)
    }

    @Test func pinnedItemsSurviveClear() async {
        await paste { $0.setString("keep", forType: .string) }
        await paste { $0.setString("other", forType: .string) }
        store.togglePin(items.first { $0.text == "keep" }!)
        store.clear()
        #expect(items.map(\.text) == ["keep"])
        store.undoClear()
    }

    @Test func dragOutHandsOverTheFileLinkOrText() async throws {
        await paste { $0.setString("https://apple.com", forType: .string) }
        await paste { $0.setString("#ff0000", forType: .string) }
        let source = desktop.appending(path: "drag.txt")
        try "x".write(to: source, atomically: true, encoding: .utf8)
        await store.add([.file(source)]).value

        let drags = items.map(ShelfDragItem.init)
        #expect(drags.map(\.movesOut) == [true, false, false])
        #expect(drags[0].url == items[0].fileURL)
        #expect(drags[2].url == URL(string: "https://apple.com"))

        func types(_ drag: ShelfDragItem) -> [UTType] {
            let provider = NSItemProvider()
            provider.register(drag)
            return provider.registeredContentTypes
        }
        #expect(types(drags[0]).contains { $0.conforms(to: .fileURL) })
        #expect(!types(drags[0]).contains { $0.conforms(to: .plainText) })
        #expect(types(drags[1]).contains { $0.conforms(to: .plainText) })
        #expect(types(drags[2]).contains { $0.conforms(to: .url) })
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

        let elsewhere = FileManager.default.temporaryDirectory.appending(path: "shelf-elsewhere-\(UUID().uuidString).txt")
        try "x".write(to: elsewhere, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: elsewhere) }
        await store.add([.file(elsewhere)], moveFiles: true).value
        #expect(FileManager.default.fileExists(atPath: elsewhere.path))

        let before = trashed.value.count
        for item in items { store.remove(item) }
        #expect(trashed.value.count == before)
    }

    @Test func itemsFillCanvasSlotsAndLandWhereDropped() async {
        await paste { $0.setString("a", forType: .string) }
        await paste { $0.setString("b", forType: .string) }
        await store.add([.text("c")], at: CGPoint(x: 1000, y: 300)).value

        let byText = Dictionary(uniqueKeysWithValues: items.map { ($0.text, $0.canvasPosition) })
        #expect(byText["a"] == CanvasLayout.slot(0))
        #expect(byText["b"] == CanvasLayout.slot(1))
        #expect(byText["c"] == CGPoint(x: CanvasLayout.width - CanvasLayout.cell.width / 2, y: 300))

        let a = items.first { $0.text == "a" }!
        store.move(a.id, to: CGPoint(x: -20, y: -20))
        #expect(a.canvasPosition == CGPoint(x: CanvasLayout.cell.width / 2, y: CanvasLayout.cell.height / 2))
        await paste { $0.setString("d", forType: .string) }
        #expect(items.first { $0.text == "d" }?.canvasPosition == CanvasLayout.slot(2))
    }

    @Test func itemsWhoseFileWasMovedAwayAreDropped() async throws {
        let source = desktop.appending(path: "gone.txt")
        try "x".write(to: source, atomically: true, encoding: .utf8)
        await store.add([.file(source)]).value
        let stored = try #require(items.first?.fileURL)
        try FileManager.default.removeItem(at: stored)
        store.tidy()
        #expect(items.isEmpty)
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

    @Test func draggingAnIconBackOntoTheShelfMovesItInsteadOfCopying() async throws {
        let onDesktop = desktop.appending(path: "photo.png")
        let png = try #require(ImageData.png(from: NSImage(systemSymbolName: "star", accessibilityDescription: nil)!.tiffRepresentation!))
        try png.write(to: onDesktop)
        await store.add([.file(onDesktop)], moveFiles: true).value
        let item = try #require(items.first)
        let stored = try #require(item.fileURL)

        let incoming = await ItemImporter.incoming(from: [finderProvider(for: stored, type: "public.png")])
        await store.add(incoming, moveFiles: true, at: CGPoint(x: 200, y: 300)).value
        #expect(items.count == 1)
        #expect(item.canvasPosition == CGPoint(x: 200, y: 300))
        #expect(FileManager.default.fileExists(atPath: stored.path))
    }
}
