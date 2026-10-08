import AppKit
import Foundation
import SwiftData
import Testing
@testable import Shelf

/// Runs the store against an in-memory container and private pasteboards, so neither
/// the real store nor the user's clipboard is touched.
@MainActor @Suite(.serialized)
struct StoreTests {
    @Test func usesItsOwnFolder() {
        #expect(!["com.shelf.app", "com.shelf.app.test"].contains(AppPaths.support.lastPathComponent))
    }

    let container: ModelContainer
    let store: ShelfStore

    init() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: ShelfItem.self, configurations: config)
        store = ShelfStore(context: container.mainContext)
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
}
