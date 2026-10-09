import AppKit
import SwiftUI

/// Clicks, right-clicks and drags on an item in the open cubby, handled by AppKit. The
/// drag puts the file itself on the pasteboard up front and only allows a move out of
/// the app, so Finder takes the file the moment you let go.
struct ItemInteraction: NSViewRepresentable {
    let writer: () -> NSPasteboardWriting
    let preview: () -> NSImage?
    let movesOut: Bool
    let menu: () -> NSMenu
    let onClick: () -> Void
    let onDragStart: () -> Void
    let onDragEnd: (_ delivered: Bool) -> Void

    func makeNSView(context: Context) -> InteractionView { InteractionView() }

    func updateNSView(_ view: InteractionView, context: Context) {
        view.interaction = self
    }

    final class InteractionView: NSView, NSDraggingSource {
        var interaction: ItemInteraction?
        private var mouseDown: NSEvent?
        private var isDragging = false

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

            let item = NSDraggingItem(pasteboardWriter: interaction.writer())
            let image = interaction.preview() ?? NSImage(size: bounds.size)
            item.setDraggingFrame(NSRect(x: (bounds.width - image.size.width) / 2,
                                         y: (bounds.height - image.size.height) / 2,
                                         width: image.size.width, height: image.size.height),
                                  contents: image)
            interaction.onDragStart()
            beginDraggingSession(with: [item], event: mouseDown, source: self)
        }

        override func mouseUp(with event: NSEvent) {
            if mouseDown != nil, !isDragging { interaction?.onClick() }
            mouseDown = nil
        }

        override func menu(for event: NSEvent) -> NSMenu? { interaction?.menu() }

        func draggingSession(_ session: NSDraggingSession,
                             sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            // Inside the cubby anything goes (it ignores its own items); outside, files
            // can only be moved.
            if context == .withinApplication { return [.copy, .move, .generic] }
            return interaction?.movesOut == true ? .move : .copy
        }

        func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint,
                             operation: NSDragOperation) {
            interaction?.onDragEnd(!operation.isEmpty)
        }
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
