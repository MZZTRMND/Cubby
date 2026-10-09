import AppKit

/// A borderless window that behaves like any other: clicking it brings Cubby forward, and
/// other windows can cover it. Dropping onto it doesn't take focus, as with any window.
final class CubbyPanel: NSPanel {
    var onCancel: (() -> Void)?
    /// The press that started the current drag, which `performDrag(with:)` needs.
    private(set) var lastMouseDown: NSEvent?

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        backgroundColor = .clear
        isOpaque = false
        // The system shadow is computed from the window's shape and goes stale while the
        // panel animates between sizes, leaving dark corners. The glass draws its own edge.
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown { lastMouseDown = event }
        super.sendEvent(event)
    }

    /// Esc.
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}
