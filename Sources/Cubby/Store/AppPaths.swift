import Foundation

/// Everything lives under Application Support/<bundle id>, so the test build and the
/// real app never share a store.
enum AppPaths {
    static let support: URL = {
        let own = URL.applicationSupportDirectory.appending(path: Bundle.main.bundleIdentifier ?? "com.cubby.app.dev")
        guard Demo.isOn else { return directory(own) }
        // The demo starts from nothing every time, beside the test build's own items.
        let demo = own.appending(path: "Demo")
        try? FileManager.default.removeItem(at: demo)
        return directory(demo)
    }()
    static let files: URL = directory(support.appending(path: "Files"))
    static var store: URL { support.appending(path: "Cubby.store") }

    private static func directory(_ url: URL) -> URL {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
