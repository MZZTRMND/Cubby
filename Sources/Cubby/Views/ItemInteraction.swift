import AppKit
import SwiftUI

/// Clicks, right-clicks and drags on an item in the open cubby, handled by AppKit. The
/// drag puts the files themselves on the pasteboard up front and only allows a move out
/// of the app (a copy while ⌥ is held), so Finder takes them the moment you let go.
struct ItemInteraction: NSViewRepresentable {
    /// One item in a drag: what goes on the pasteboard and how it looks.
    struct Piece {
        let writer: NSPasteboardWriting
        let image: NSImage?
    }

    /// Starts a drag: the pieces, the item under the pointer first, and whether they
    /// move out of the app rather than being copied.
    let drag: () -> (pieces: [Piece], movesOut: Bool)
    /// Right-click. The item can update the selection before building the menu.
    let menu: () -> NSMenu
    /// A click, with its modifier keys and click count (2 for a double-click).
    let onClick: (_ modifiers: NSEvent.ModifierFlags, _ clickCount: Int) -> Void
    /// The drag ended; true when the files left the cubby (moved, not copied).
    let onDragEnd: (_ delivered: Bool) -> Void

    func makeNSView(context: Context) -> InteractionView { InteractionView() }

    func updateNSView(_ view: InteractionView, context: Context) {
        view.interaction = self
    }

    final class InteractionView: NSView, NSDraggingSource {
        var interaction: ItemInteraction?
        private var mouseDown: NSEvent?
        private var isDragging = false
        private var movesOut = false

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            mouseDown = event
            isDragging = false
        }

        override func mouseDragged(with event: NSEvent) {
            guard let mouseDown, !isDragging, let interaction else { return }
            let dx = event.locationInWindow.x - mouseDown.locationInWindow.x
            let dy = event.locationInWindow.y - mouseDown.locationInWindow.y
            guard hypot(dx, dy) > 3 else { return }
            isDragging = true

            let (pieces, movesOut) = interaction.drag()
            self.movesOut = movesOut
            // The rest of a selection fans out behind the item under the pointer.
            let items = pieces.enumerated().map { index, piece in
                let item = NSDraggingItem(pasteboardWriter: piece.writer)
                let image = piece.image ?? NSImage(size: bounds.size)
                let step = CGFloat(index) * 6
                item.setDraggingFrame(NSRect(x: (bounds.width - image.size.width) / 2 + step,
                                             y: (bounds.height - image.size.height) / 2 - step,
                                             width: image.size.width, height: image.size.height),
                                      contents: image)
                return item
            }
            let session = beginDraggingSession(with: items, event: mouseDown, source: self)
            session.draggingFormation = .stack
        }

        /// The item that got the last click. AppKit counts quick clicks on two different
        /// items as a double-click, so a second click only counts as one on the same item.
        private static weak var lastClicked: InteractionView?

        override func mouseUp(with event: NSEvent) {
            if let mouseDown, !isDragging {
                let clickCount = Self.lastClicked === self ? mouseDown.clickCount : 1
                Self.lastClicked = self
                interaction?.onClick(mouseDown.modifierFlags.intersection(.deviceIndependentFlagsMask),
                                     clickCount)
            }
            mouseDown = nil
        }

        override func menu(for event: NSEvent) -> NSMenu? { interaction?.menu() }

        func draggingSession(_ session: NSDraggingSession,
                             sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            ItemDragSource.operationMask(for: context, movesOut: movesOut)
        }

        func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint,
                             operation: NSDragOperation) {
            interaction?.onDragEnd(ItemDragSource.leftCubby(operation))
        }
    }
}

/// The source for a drag that isn't started from an item in the card, such as taking
/// everything out of the folder. Same rules: outside the app, files move unless ⌥ copies.
final class ItemDragSource: NSObject, NSDraggingSource {
    private let movesOut: Bool
    private let onEnd: (_ delivered: Bool) -> Void

    init(movesOut: Bool, onEnd: @escaping (_ delivered: Bool) -> Void) {
        self.movesOut = movesOut
        self.onEnd = onEnd
    }

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        Self.operationMask(for: context, movesOut: movesOut)
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint,
                         operation: NSDragOperation) {
        onEnd(Self.leftCubby(operation))
    }

    /// Inside the cubby anything goes (it ignores its own items). Outside, files move,
    /// or are copied while ⌥ is held, as in Finder; AppKit asks again whenever the
    /// modifier keys change, so the pointer's green + comes and goes with ⌥.
    static func operationMask(for context: NSDraggingContext, movesOut: Bool) -> NSDragOperation {
        if context == .withinApplication { return [.copy, .move, .generic] }
        guard movesOut else { return .copy }
        return NSEvent.modifierFlags.contains(.option) ? .copy : .move
    }

    /// Whether the dragged files left the cubby: dropped somewhere, and not as a copy.
    static func leftCubby(_ operation: NSDragOperation) -> Bool {
        !operation.isEmpty && !operation.contains(.copy)
    }
}

/// A menu item that runs a closure.
final class ActionMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("not used") }

    @objc private func run() { handler() }
}
