import AppKit
import Quartz
import SwiftUI
import SwiftData

/// Owns the desktop panel: a folder you can put anywhere on the desktop, which opens into
/// a card. It's an ordinary window: it takes focus when clicked and other windows can
/// cover it. The window is only ever resized in one step; all the motion is SwiftUI
/// animation inside it, which keeps it fluid.
@MainActor @Observable
final class PanelController {
    enum Mode { case resting, dropTarget, expanded }

    enum Theme: String, CaseIterable, Identifiable {
        case system, light, dark

        var id: Self { self }
        var title: String { rawValue.capitalized }
        var appearance: NSAppearance? {
            switch self {
            case .system: nil
            case .light: NSAppearance(named: .aqua)
            case .dark: NSAppearance(named: .darkAqua)
            }
        }
    }

    private(set) var mode: Mode = .resting

    /// Where the folder sits relative to the window's center. Zero while resting; while
    /// open, the window grows around the card and this keeps the folder where it was on
    /// screen, so the card can grow out of it and shrink back into it.
    private(set) var folderOffset: CGSize = .zero

    /// The folder's natural size including the inset, reported by SwiftUI.
    var restingSize = CGSize(width: 168, height: 172) {
        didSet { if restingSize != oldValue, mode != .expanded, !isMoving { placeFolder() } }
    }

    var isShown: Bool {
        didSet {
            defaults.set(isShown, forKey: "panelShown")
            isShown ? panel.orderFrontRegardless() : panel.orderOut(nil)
        }
    }

    /// Above every other window and on every desktop, instead of an ordinary window.
    var isPinnedOnTop: Bool {
        didSet {
            defaults.set(isPinnedOnTop, forKey: "pinnedOnTop")
            applyPinning()
        }
    }

    /// Light or dark for the whole app, or following the system.
    var theme: Theme {
        didSet {
            defaults.set(theme.rawValue, forKey: "theme")
            NSApp.appearance = theme.appearance
        }
    }

    /// The folder's center as a fraction of the screen's visible area, so it survives
    /// resolution changes.
    @ObservationIgnored private var position: CGPoint
    @ObservationIgnored private var displayID: Int

    @ObservationIgnored private let store: CubbyStore
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private let panel = CubbyPanel()
    @ObservationIgnored private var collapseTask: Task<Void, Never>?
    @ObservationIgnored private var isMoving = false
    @ObservationIgnored private var keyMonitor: Any?
    /// While a dialog is up, losing focus mustn't close the card.
    @ObservationIgnored private var isPresentingDialog = false
    /// Lifted above other windows while something is dragged in another app.
    @ObservationIgnored private var isRaisedForDrag = false
    /// The drag carrying everything out of the folder, while it lasts.
    @ObservationIgnored private var dragOutSource: ItemDragSource?
    @ObservationIgnored private lazy var dimmer = DimWindow()
    @ObservationIgnored private var lowerTask: Task<Void, Never>?


    /// Transparent space around the content, for shadows and items rising out of the folder.
    static let inset: CGFloat = 16
    /// The same around the open card, wide enough for the glass's own soft shadow.
    static let expandedInset: CGFloat = 40
    /// The open card, without the inset.
    static let expandedSize = CGSize(width: 440, height: 440)
    static let animation = Animation.spring(duration: 0.45, bounce: 0.2)

    init(store: CubbyStore, container: ModelContainer) {
        self.store = store
        defaults.register(defaults: ["panelShown": true, "folderX": 0.92, "folderY": 0.5, DragSummon.key: DragSummon.shake.rawValue])
        isShown = defaults.bool(forKey: "panelShown")
        isPinnedOnTop = defaults.bool(forKey: "pinnedOnTop")
        theme = Theme(rawValue: defaults.string(forKey: "theme") ?? "") ?? .system
        position = CGPoint(x: defaults.double(forKey: "folderX"), y: defaults.double(forKey: "folderY"))
        displayID = defaults.integer(forKey: "folderDisplay")

        let hosting = NSHostingView(
            rootView: PanelView()
                .environment(store)
                .environment(self)
                .modelContainer(container)
        )
        hosting.sizingOptions = []
        panel.contentView = hosting
        panel.onCancel = { [weak self] in
            // Esc clears what's been typed first, then closes the card.
            guard let self else { return }
            if self.store.isSearching { self.store.searchText = "" } else { self.collapse() }
        }
        store.undoManager = panel.undoManager
        installKeyMonitor()
        installDragWatcher()

        let center = NotificationCenter.default
        center.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.mode == .expanded, !self.isPresentingDialog else { return }
                // Focus moving to another of Cubby's windows, like Quick Look or Settings,
                // keeps the card open; only clicking away from Cubby closes it.
                DispatchQueue.main.async {
                    if NSApp.isActive, let key = NSApp.keyWindow, key !== self.panel { return }
                    self.collapse()
                }
            }
        }
        // Displays added, removed or rearranged: put the folder back on a screen.
        center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.mode == .expanded { self.collapse() } else { self.placeFolder() }
            }
        }
    }

    func showAtLaunch() {
        NSApp.appearance = theme.appearance
        applyPinning()
        placeFolder()
        if isShown { panel.orderFrontRegardless() }
    }

    private func applyPinning() {
        panel.level = isPinnedOnTop ? .floating : .normal
        panel.collectionBehavior = isPinnedOnTop ? [.canJoinAllSpaces, .fullScreenAuxiliary] : []
    }

    // MARK: - State changes

    func expand() {
        collapseTask?.cancel()
        guard mode != .expanded else { return }
        let folder = restingFrame()
        let card = expandedFrame(around: folder)
        // Grow the window in one step, keeping the folder where it is on screen, then let
        // SwiftUI grow the card out of it.
        resize(to: card, folderOffset: CGSize(width: folder.midX - card.midX, height: card.midY - folder.midY))
        withAnimation(Self.animation) { mode = .expanded }
        panel.makeKey()
    }

    func collapse() {
        collapseTask?.cancel()
        guard mode != .resting else { return }
        let wasExpanded = mode == .expanded
        store.clearSelection()
        store.searchText = ""
        store.hoveredItemID = nil
        // You've seen the notice about missing files once the card has been open.
        if wasExpanded { store.missingNames = [] }
        withAnimation(Self.animation, completionCriteria: .removed) {
            mode = .resting
        } completion: { [weak self] in
            // Once the card has shrunk back into the folder, fit the window to the folder.
            guard let self, wasExpanded, self.mode == .resting else { return }
            self.resize(to: self.restingFrame(), folderOffset: .zero)
        }
    }

    /// Keys for the open card: the arrows move the selection (⇧ extends it), Return
    /// or ⌘↓ opens it, Space toggles Quick Look, as in Finder, ⌘A selects everything,
    /// Delete or ⌘Delete moves it to the Bin, and ⌘Z / ⇧⌘Z undo and redo.
    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.mode == .expanded,
                  event.window === self.panel || event.window is QLPreviewPanel,
                  !(event.window?.firstResponder is NSText)
            else { return event }
            // Arrow keys always carry these two.
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                .subtracting([.numericPad, .function])
            let quickLook = QuickLook.shared

            if let direction = Self.direction(of: event), flags.isEmpty || flags == .shift {
                // Quick Look steps through several previewed files itself.
                if event.window is QLPreviewPanel, quickLook.count > 1 { return event }
                self.store.moveSelection(direction, columns: ExpandedCubby.columnCount, extending: flags == .shift)
                if quickLook.isShown { self.refreshQuickLook() }
                return nil
            }
            if self.typeToFind(event, flags: flags) { return nil }
            switch (event.keyCode, flags) {
            case (49, []): // Space
                if quickLook.isShown { quickLook.close() } else { self.refreshQuickLook() }
            case (36, []), (76, []), (125, .command): // Return, Enter, ⌘↓
                guard event.window === self.panel else { return event }
                // While finding, with nothing picked, the first match opens.
                let picked = self.store.selectedItems()
                let items = picked.isEmpty && self.store.isSearching ? Array(self.store.shownItems().prefix(1)) : picked
                for item in items { self.store.open(item) }
            // Delete, Forward Delete, ⌘Delete. While finding, plain Delete takes a
            // letter back instead (handled above).
            case (51, []), (117, []), (51, .command):
                guard event.window === self.panel, !self.store.selection.isEmpty else { return event }
                QuickLook.shared.close()
                self.store.binSelection()
            case (0, .command): // ⌘A
                guard event.window === self.panel else { return event }
                self.store.selectAll()
            case (6, .command): // ⌘Z
                guard event.window === self.panel else { return event }
                self.panel.undoManager?.undo()
            case (6, [.command, .shift]): // ⇧⌘Z
                guard event.window === self.panel else { return event }
                self.panel.undoManager?.redo()
            default:
                return event
            }
            return nil
        }
    }

    /// Typing in the open card finds items by name, and Delete takes a letter back. Space
    /// stays Quick Look, except in the middle of a name with nothing selected.
    private func typeToFind(_ event: NSEvent, flags: NSEvent.ModifierFlags) -> Bool {
        guard event.window === panel, flags.subtracting(.shift).isEmpty else { return false }
        if event.keyCode == 51 { // Delete
            guard store.isSearching else { return false }
            store.searchText.removeLast()
            return true
        }
        guard let typed = event.characters, !typed.isEmpty,
              typed.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) && $0.value < 0xF700 })
        else { return false }
        if typed == " ", !store.isSearching || !store.selection.isEmpty { return false }
        QuickLook.shared.close()
        store.searchText += typed
        return true
    }

    private static func direction(of event: NSEvent) -> CubbyStore.Direction? {
        switch event.keyCode {
        case 123: .left
        case 124: .right
        case 125: .down
        case 126: .up
        default: nil
        }
    }

    /// Previews what Space would, or closes Quick Look when that's nothing.
    private func refreshQuickLook() {
        let urls = store.quickLookURLs(in: store.shownItems())
        urls.isEmpty ? QuickLook.shared.close() : QuickLook.shared.show(urls)
    }

    func dragEntered() {
        // Its own items coming back over it.
        guard store.draggedItemIDs.isEmpty else { return }
        collapseTask?.cancel()
        if mode == .resting { withAnimation(Self.animation) { mode = .dropTarget } }
    }

    func dragExited() {
        if mode == .dropTarget { collapse(after: .milliseconds(300)) }
    }

    func dropped() {
        if mode == .dropTarget { collapse(after: .milliseconds(500)) }
    }

    /// A screenshot was caught: the folder opens for a moment, as if it had been dropped in.
    func caught() {
        guard mode == .resting else { return }
        withAnimation(Self.animation) { mode = .dropTarget }
        collapse(after: .milliseconds(900))
    }

    private func collapse(after delay: Duration) {
        collapseTask?.cancel()
        collapseTask = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            collapse()
        }
    }

    /// Resizes the window and moves the folder inside it in the same frame, so nothing
    /// visibly jumps.
    private func resize(to frame: NSRect, folderOffset offset: CGSize) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { folderOffset = offset }
        panel.setFrame(frame, display: false)
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.displayIfNeeded()
    }

    /// Asks before Clear moves everything under the current tab to the Bin.
    func confirmClear() {
        let count = store.clearableCount()
        guard count > 0 else { return }
        let alert = NSAlert()
        alert.messageText = store.isSearching
            ? "Clear the items matching \u{201C}\(store.searchText)\u{201D}?"
            : store.kindFilter.map { "Clear \($0.pluralTitle)?" } ?? "Clear the cubby?"
        alert.informativeText = count == 1
            ? "1 item will be moved to the Bin. You can undo this with \u{2318}Z."
            : "\(count) items will be moved to the Bin. You can undo this with \u{2318}Z."
        alert.addButton(withTitle: "Move to Bin").hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        if run(alert) == .alertFirstButtonReturn { store.clear() }
    }

    /// Asks for a new name. A file is renamed on disk, with the part before the extension
    /// selected, as in Finder; anything else gets a name of its own, and an empty one
    /// brings back what it was called before.
    func rename(_ item: CubbyItem) {
        let isFile = item.fileURL != nil
        let name = isFile ? item.fileName ?? item.text : item.label
        let field = NSTextField(string: name)
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        let alert = NSAlert()
        alert.messageText = "Rename"
        if !isFile, item.name != nil { alert.informativeText = "Leave it empty to go back to the original name." }
        alert.accessoryView = field
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        DispatchQueue.main.async {
            let base = isFile ? (name as NSString).deletingPathExtension : name
            field.currentEditor()?.selectedRange = NSRange(location: 0, length: (base as NSString).length)
        }
        guard run(alert) == .alertFirstButtonReturn else { return }
        if isFile { store.rename(item, to: field.stringValue) } else { store.setName(item, to: field.stringValue) }
    }

    /// Asks for a few words to keep with the item. An empty note removes it.
    func editNote(_ item: CubbyItem) {
        let field = NSTextField(string: item.note ?? "")
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 64)
        field.placeholderString = "Why it's here, what it's for…"
        field.usesSingleLineMode = false
        field.cell?.wraps = true
        field.cell?.isScrollable = false
        let alert = NSAlert()
        alert.messageText = item.note == nil ? "Add Note" : "Edit Note"
        alert.informativeText = "For \u{201C}\(item.label)\u{201D}"
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        if run(alert) == .alertFirstButtonReturn { store.setNote(item, to: field.stringValue) }
    }

    /// Runs a modal alert without the card closing behind it.
    private func run(_ alert: NSAlert) -> NSApplication.ModalResponse {
        isPresentingDialog = true
        NSApp.activate()
        let response = alert.runModal()
        isPresentingDialog = false
        if mode == .expanded { panel.makeKey() }
        return response
    }

    /// Picks files to add, as if they'd been dropped on the cubby.
    func chooseFilesToAdd() {
        isPresentingDialog = true
        let dialog = NSOpenPanel()
        dialog.allowsMultipleSelection = true
        dialog.canChooseDirectories = true
        dialog.prompt = "Add"
        NSApp.activate()
        dialog.begin { [weak self] response in
            guard let self else { return }
            self.isPresentingDialog = false
            if response == .OK {
                self.store.add(dialog.urls.map { .file($0) }, moveFiles: true)
            }
            self.panel.makeKey()
        }
    }

    // MARK: - Moving

    /// Hands the drag to the window server, as a title bar drag does, so holding the
    /// folder at the screen's edge carries it to the next desktop like any other window.
    func beginMove() {
        guard mode != .expanded, !isMoving, let press = panel.lastMouseDown else { return }
        isMoving = true
        panel.performDrag(with: press)
        // The window server keeps the mouse-up to itself, so wait for the button instead.
        Task { [weak self] in
            while NSEvent.pressedMouseButtons & 1 != 0 {
                try? await Task.sleep(for: .milliseconds(30))
            }
            self?.endMove()
        }
    }

    /// Leaves the folder where it was dropped, nudged fully onto the screen.
    func endMove() {
        guard isMoving else { return }
        isMoving = false
        let frame = panel.frame
        let center = NSPoint(x: frame.midX, y: frame.midY)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(center) }) ?? panel.screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            position = CGPoint(x: min(max((center.x - visible.minX) / visible.width, 0), 1),
                               y: min(max((center.y - visible.minY) / visible.height, 0), 1))
            displayID = screen.displayID
            defaults.set(position.x, forKey: "folderX")
            defaults.set(position.y, forKey: "folderY")
            defaults.set(displayID, forKey: "folderDisplay")
        }
        placeFolder()
    }

    // MARK: - Dragging everything out

    /// Grabbing the papers in the folder carries every item out at once, as if they'd all
    /// been selected in the card: files move out, links and text are copied.
    func beginDragOut(_ items: [CubbyItem]) {
        guard mode != .expanded, !isMoving, dragOutSource == nil, !items.isEmpty,
              let press = panel.lastMouseDown, let view = panel.contentView
        else { return }
        let ordered = store.sorted(items)
        store.draggedItemIDs = Set(ordered.map(\.id))
        let source = ItemDragSource(movesOut: ordered.contains { store.movesOut($0) }) { [weak self] delivered in
            guard let self else { return }
            self.store.dragEnded(ordered.map(\.id), delivered: delivered)
            self.dragOutSource = nil
        }
        dragOutSource = source
        let point = view.convert(press.locationInWindow, from: nil)
        let pieces = ordered.enumerated().map { index, item in
            let piece = NSDraggingItem(pasteboardWriter: store.pasteboardWriter(for: item))
            let image = ImageRenderer(content: ItemGlyph(item: item, size: 64, natural: true)).nsImage
                ?? NSImage(size: NSSize(width: 64, height: 64))
            // The first few fan out under the pointer; the rest stack behind them.
            let step = CGFloat(min(index, 4)) * 6
            piece.setDraggingFrame(NSRect(x: point.x - image.size.width / 2 + step,
                                          y: point.y - image.size.height / 2 - step,
                                          width: image.size.width, height: image.size.height),
                                   contents: image)
            return piece
        }
        let session = view.beginDraggingSession(with: pieces, event: press, source: source)
        session.draggingFormation = .stack
    }

    // MARK: - Coming forward for drags

    /// Watches for drags starting in other apps. A press that puts something on the drag
    /// pasteboard is a drag of files, links or text, not a window being moved, so the
    /// folder comes to the middle of the screen you're on, over a dimmed screen, to take
    /// it, and goes back to its spot afterwards. Watching mouse presses in other apps
    /// needs no special permission.
    private func installDragWatcher() {
        NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            MainActor.assumeIsolated { self?.watchForDrag() }
        }
    }

    /// With When Shaken, the drag alone isn't enough: the folder waits for a quick shake
    /// of the pointer, so ordinary drags between Finder windows leave it be.
    private func watchForDrag() {
        let summon = DragSummon(rawValue: defaults.string(forKey: DragSummon.key) ?? "") ?? .shake
        guard summon != .never, !isRaisedForDrag, isShown, mode == .resting, !isMoving else { return }
        let start = NSPasteboard(name: .drag).changeCount
        Task { [weak self] in
            var shake = ShakeDetector()
            var isDragging = false
            while NSEvent.pressedMouseButtons & 1 != 0 {
                // Shakes are quick, so look often once a drag is under way.
                try? await Task.sleep(for: .milliseconds(isDragging && summon == .shake ? 15 : 50))
                guard let self else { return }
                guard !self.isRaisedForDrag else { continue }
                isDragging = isDragging || NSPasteboard(name: .drag).changeCount != start
                guard isDragging else { continue }
                if summon == .always || shake.add(x: NSEvent.mouseLocation.x, at: ProcessInfo.processInfo.systemUptime) {
                    self.raiseForDrag()
                }
            }
            self?.lowerAfterDrag()
        }
    }

    private func raiseForDrag() {
        lowerTask?.cancel()
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? screen
        else { return }
        isRaisedForDrag = true
        dimmer.fadeIn(on: screen)
        // Just above the veil, and on whichever desktop you're on.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let visible = screen.visibleFrame
        slide(to: Self.rect(of: panel.frame.size, centeredAt: CGPoint(x: visible.midX, y: visible.midY), in: visible))
        panel.orderFrontRegardless()
    }

    /// Back to its own spot once the drag is over, after a moment to see a drop land.
    private func lowerAfterDrag() {
        guard isRaisedForDrag else { return }
        lowerTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard let self, !Task.isCancelled else { return }
            self.isRaisedForDrag = false
            self.dimmer.fadeOut()
            self.applyPinning()
            if self.mode != .expanded { self.slide(to: self.restingFrame()) }
        }
    }

    private func slide(to frame: NSRect) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.35
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(frame, display: true)
        }
    }

    // MARK: - Layout

    private var screen: NSScreen? {
        NSScreen.screens.first { $0.displayID == displayID } ?? NSScreen.main
    }

    private func placeFolder() {
        guard mode != .expanded, !isRaisedForDrag else { return }
        panel.setFrame(restingFrame(), display: true)
    }

    private func restingFrame() -> NSRect {
        guard let visible = screen?.visibleFrame else { return NSRect(origin: .zero, size: restingSize) }
        let center = CGPoint(x: visible.minX + position.x * visible.width,
                             y: visible.minY + position.y * visible.height)
        return Self.rect(of: restingSize, centeredAt: center, in: visible)
    }

    private func expandedFrame(around folder: NSRect) -> NSRect {
        let size = CGSize(width: Self.expandedSize.width + 2 * Self.expandedInset,
                          height: Self.expandedSize.height + 2 * Self.expandedInset)
        let visible = screen?.visibleFrame ?? folder
        return Self.rect(of: size, centeredAt: CGPoint(x: folder.midX, y: folder.midY), in: visible)
    }

    /// A rect of `size` centered on `center`, moved as needed to stay inside `bounds`.
    private static func rect(of size: CGSize, centeredAt center: CGPoint, in bounds: NSRect) -> NSRect {
        let width = min(size.width, bounds.width), height = min(size.height, bounds.height)
        let x = min(max(center.x - width / 2, bounds.minX), bounds.maxX - width)
        let y = min(max(center.y - height / 2, bounds.minY), bounds.maxY - height)
        return NSRect(x: x, y: y, width: width, height: height)
    }
}

private extension NSScreen {
    var displayID: Int {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.intValue ?? 0
    }
}
