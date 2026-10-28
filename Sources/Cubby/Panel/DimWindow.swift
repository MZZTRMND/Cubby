import AppKit

/// A dark veil over a whole screen, under the folder while it waits by the pointer for a
/// drag. Clicks and drags go straight through it to whatever is underneath.
final class DimWindow: NSWindow {
    private var isVisibleForDrag = false

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: true)
        backgroundColor = NSColor.black.withAlphaComponent(0.35)
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        alphaValue = 0
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func fadeIn(on screen: NSScreen) {
        isVisibleForDrag = true
        setFrame(screen.frame, display: false)
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            animator().alphaValue = 1
        }
    }

    func fadeOut() {
        isVisibleForDrag = false
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                // Unless it was faded in again meanwhile.
                guard let self, !self.isVisibleForDrag else { return }
                self.orderOut(nil)
            }
        }
    }
}
