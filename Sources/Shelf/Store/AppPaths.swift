import Foundation

/// Everything lives under Application Support/<bundle id>, so the test build and the
/// real app never share a store.
enum AppPaths {
    static let support: URL = directory(
        URL.applicationSupportDirectory.appending(path: Bundle.main.bundleIdentifier ?? "com.shelf.app.dev")
    )
    static let files: URL = directory(support.appending(path: "Files"))
    static var store: URL { support.appending(path: "Shelf.store") }

    private static func directory(_ url: URL) -> URL {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
