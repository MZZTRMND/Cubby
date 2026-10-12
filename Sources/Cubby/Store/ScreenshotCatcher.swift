import Foundation

/// Watches the folder macOS saves screenshots to and moves each new screenshot into the
/// cubby, so they stop piling up on the Desktop. Screenshots are recognised by the mark
/// macOS puts on them (`kMDItemIsScreenCapture`), not by name, so other files arriving
/// there are left alone, and so is everything that was there before.
@MainActor
final class ScreenshotCatcher {
    static let enabledKey = "catchScreenshots"

    /// Called with each new screenshot.
    var onCatch: ((URL) -> Void)?

    private var folder: URL?
    private var source: DispatchSourceFileSystemObject?
    /// Files that were already there, or have been handled, so each is looked at once.
    private var seen: Set<String> = []
    private var scanTask: Task<Void, Never>?

    init() {
        update()
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
    }

    /// Starts or stops watching to match the setting, and follows the screenshot folder
    /// if it was changed in the Screenshot app.
    private func update() {
        let enabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        let wanted = enabled ? Self.screenshotFolder() : nil
        guard wanted?.standardizedFileURL != folder?.standardizedFileURL else { return }
        stop()
        if let wanted { start(wanted) }
    }

    private func start(_ folder: URL) {
        let descriptor = open(folder.path, O_EVTONLY)
        guard descriptor >= 0 else {
            logger.error("can't watch screenshot folder \(folder.path, privacy: .public)")
            return
        }
        self.folder = folder
        seen = Set(Self.contents(of: folder).map(\.lastPathComponent))
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: .write, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.scheduleScan() }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        self.source = source
        logger.notice("catching screenshots in \(folder.path, privacy: .public)")
    }

    private func stop() {
        source?.cancel()
        source = nil
        folder = nil
        scanTask?.cancel()
    }

    /// The folder changed. macOS writes a screenshot under a hidden name and renames it
    /// when done, so wait a moment for things to settle before looking.
    private func scheduleScan() {
        scanTask?.cancel()
        scanTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            scan()
        }
    }

    private func scan() {
        guard let folder else { return }
        for url in Self.contents(of: folder) where !seen.contains(url.lastPathComponent) {
            // Hidden files are screenshots still being written; look again once renamed.
            guard !url.lastPathComponent.hasPrefix(".") else { continue }
            seen.insert(url.lastPathComponent)
            if Self.isScreenshot(url) { onCatch?(url) }
        }
        // Forget names that have left, so a new file with the same name is noticed.
        seen.formIntersection(Self.contents(of: folder).map(\.lastPathComponent))
    }

    private static func contents(of folder: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
    }

    static func isScreenshot(_ url: URL) -> Bool {
        getxattr(url.path, "com.apple.metadata:kMDItemIsScreenCapture", nil, 0, 0, 0) >= 0
    }

    /// Where the Screenshot app saves: the folder picked in its Options menu, or the Desktop.
    static func screenshotFolder() -> URL {
        if let path = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location") {
            let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
                return url
            }
        }
        return URL.desktopDirectory
    }
}
