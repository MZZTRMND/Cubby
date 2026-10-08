import AppKit

/// A borderless, non-activating floating panel: dropping onto it or clicking it never
/// pulls focus away from the app you're working in.
final class ShelfPanel: NSPanel {
    var onCancel: (() -> Void)?

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        backgroundColor = .clear
        isOpaque = false
        // The system shadow is computed from the window's shape and goes stale while the
        // panel animates between sizes, leaving dark corners. The glass draws its own edge.
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Esc.
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}
