import AppKit

/// The scripted demo, for recording the promo video. It only runs in the test build,
/// launched with `--demo` (see Scripts/record-demo.sh), and keeps its items in a folder
/// of its own that's wiped at every launch.
enum Demo {
    nonisolated static let isOn = ProcessInfo.processInfo.arguments.contains("--demo")
        && Bundle.main.bundleIdentifier == "com.cubby.app.test"

    /// The stage covers the screen at `.floating`; the folder sits above it, and the
    /// demo's pointer above everything.
    static let stageLevel = NSWindow.Level.floating
    static let panelLevel = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 2)
    static let overlayLevel = NSWindow.Level.screenSaver

    /// Posted between the recorder and the demo.
    static let ready = Notification.Name("com.cubby.demo.ready")
    static let go = Notification.Name("com.cubby.demo.go")
    static let finished = Notification.Name("com.cubby.demo.finished")
}

/// Where the pointer is: the real one, or the demo's while it plays.
enum Pointer {
    @MainActor static var override: NSPoint?
    @MainActor static var location: NSPoint { override ?? NSEvent.mouseLocation }
}
