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

    /// Transparent space around the content, for shadows and items rising out of the folder.
    static let inset: CGFloat = 16
    /// The open card, without the inset.
    static let expandedSize = CGSize(width: 380, height: 440)
    static let animation = Animation.spring(duration: 0.45, bounce: 0.2)

    init(store: CubbyStore, container: ModelContainer) {
        self.store = store
        defaults.register(defaults: ["panelShown": true, "folderX": 0.92, "folderY": 0.5])
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
        panel.onCancel = { [weak self] in self?.collapse() }
        store.undoManager = panel.undoManager
        installKeyMonitor()

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
    /// and ⌘Z / ⇧⌘Z undo and redo.
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
            switch (event.keyCode, flags) {
            case (49, []): // Space
                if quickLook.isShown { quickLook.close() } else { self.refreshQuickLook() }
            case (36, []), (76, []), (125, .command): // Return, Enter, ⌘↓
                guard event.window === self.panel else { return event }
                for item in self.store.selectedItems() { self.store.open(item) }
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
        let urls = store.quickLookURLs(in: store.allItems())
        urls.isEmpty ? QuickLook.shared.close() : QuickLook.shared.show(urls)
    }

    func dragEntered() {
        collapseTask?.cancel()
        if mode == .resting { withAnimation(Self.animation) { mode = .dropTarget } }
    }

    func dragExited() {
        if mode == .dropTarget { collapse(after: .milliseconds(300)) }
    }

    func dropped() {
        if mode == .dropTarget { collapse(after: .milliseconds(500)) }
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

    /// Asks before Clear moves everything to the Bin.
    func confirmClear() {
        let count = store.clearableCount()
        guard count > 0 else { return }
        let alert = NSAlert()
        alert.messageText = "Clear the cubby?"
        alert.informativeText = count == 1
            ? "1 item will be moved to the Bin. You can undo this with \u{2318}Z."
            : "\(count) items will be moved to the Bin. You can undo this with \u{2318}Z."
        alert.addButton(withTitle: "Move to Bin").hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        if run(alert) == .alertFirstButtonReturn { store.clear() }
    }

    /// Asks for a new name, with the part before the extension selected, as in Finder.
    func rename(_ item: CubbyItem) {
        guard let name = item.fileName else { return }
        let field = NSTextField(string: name)
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        let alert = NSAlert()
        alert.messageText = "Rename"
        alert.accessoryView = field
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        DispatchQueue.main.async {
            let base = (name as NSString).deletingPathExtension
            field.currentEditor()?.selectedRange = NSRange(location: 0, length: (base as NSString).length)
        }
        if run(alert) == .alertFirstButtonReturn { store.rename(item, to: field.stringValue) }
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

    // MARK: - Layout

    private var screen: NSScreen? {
        NSScreen.screens.first { $0.displayID == displayID } ?? NSScreen.main
    }

    private func placeFolder() {
        guard mode != .expanded else { return }
        panel.setFrame(restingFrame(), display: true)
    }

    private func restingFrame() -> NSRect {
        guard let visible = screen?.visibleFrame else { return NSRect(origin: .zero, size: restingSize) }
        let center = CGPoint(x: visible.minX + position.x * visible.width,
                             y: visible.minY + position.y * visible.height)
        return Self.rect(of: restingSize, centeredAt: center, in: visible)
    }

    private func expandedFrame(around folder: NSRect) -> NSRect {
        let size = CGSize(width: Self.expandedSize.width + 2 * Self.inset,
                          height: Self.expandedSize.height + 2 * Self.inset)
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
