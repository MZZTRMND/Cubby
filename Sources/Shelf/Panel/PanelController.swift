import AppKit
import SwiftUI
import SwiftData

/// Owns the desktop panel and moves it between its three states. The panel is one
/// window that changes size, docked to the left or right edge of a screen.
@MainActor @Observable
final class PanelController {
    enum Mode { case resting, dropTarget, expanded }
    enum Edge: String { case left, right }

    private(set) var mode: Mode = .resting
    private(set) var edge: Edge

    /// The resting pill's natural size, reported by SwiftUI as items come and go.
    var restingSize = CGSize(width: 56, height: 56) {
        didSet { if mode == .resting, restingSize != oldValue, moveStart == nil { layout() } }
    }

    var isShown: Bool {
        didSet {
            defaults.set(isShown, forKey: "panelShown")
            isShown ? panel.orderFrontRegardless() : panel.orderOut(nil)
        }
    }

    /// Off: the panel sits at normal window level, so other windows can cover it.
    var keepOnTop: Bool {
        didSet {
            defaults.set(keepOnTop, forKey: "keepOnTop")
            panel.level = keepOnTop ? .floating : .normal
        }
    }

    /// Where the pill's center sits along the edge, from 0 (bottom) to 1 (top) of the
    /// screen's visible area. Stored as a fraction so it survives resolution changes.
    @ObservationIgnored private var position: Double
    @ObservationIgnored private var displayID: Int

    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private let panel = ShelfPanel()
    @ObservationIgnored private var collapseTask: Task<Void, Never>?
    @ObservationIgnored private var moveStart: (mouse: NSPoint, origin: NSPoint)?

    private static let margin: CGFloat = 8
    static let expandedSize = CGSize(width: 320, height: 520)
    static let dropTargetSize = CGSize(width: 136, height: 160)

    init(store: ShelfStore, container: ModelContainer) {
        defaults.register(defaults: [
            "panelShown": true, "keepOnTop": true, "dockEdge": Edge.right.rawValue, "dockPosition": 0.5,
        ])
        isShown = defaults.bool(forKey: "panelShown")
        keepOnTop = defaults.bool(forKey: "keepOnTop")
        edge = Edge(rawValue: defaults.string(forKey: "dockEdge") ?? "") ?? .right
        position = defaults.double(forKey: "dockPosition")
        displayID = defaults.integer(forKey: "dockDisplay")

        let hosting = NSHostingView(
            rootView: PanelView()
                .environment(store)
                .environment(self)
                .modelContainer(container)
        )
        hosting.sizingOptions = []
        panel.contentView = hosting
        panel.level = keepOnTop ? .floating : .normal
        panel.onCancel = { [weak self] in self?.collapse() }

        let center = NotificationCenter.default
        center.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if self?.mode == .expanded { self?.collapse() } }
        }
        // Displays added, removed or rearranged: dock again, falling back to the main screen.
        center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.layout(animated: false) }
        }
    }

    func showAtLaunch() {
        layout(animated: false)
        if isShown { panel.orderFrontRegardless() }
    }

    // MARK: - State changes

    func expand() {
        collapseTask?.cancel()
        setMode(.expanded)
        panel.makeKey()
    }

    func collapse() {
        collapseTask?.cancel()
        guard mode != .resting else { return }
        handBackKeyboard()
        setMode(.resting)
    }

    func dragEntered() {
        collapseTask?.cancel()
        if mode == .resting { setMode(.dropTarget) }
    }

    func dragExited() {
        if mode == .dropTarget { collapse(after: .milliseconds(300)) }
    }

    func dropped() {
        if mode == .dropTarget { collapse(after: .milliseconds(400)) }
    }

    private func collapse(after delay: Duration) {
        collapseTask?.cancel()
        collapseTask = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            collapse()
        }
    }

    private func setMode(_ newMode: Mode) {
        guard newMode != mode else { return }
        mode = newMode
        layout()
    }

    /// A key panel would keep receiving your typing; give it back to the app you were in.
    private func handBackKeyboard() {
        guard panel.isKeyWindow else { return }
        panel.orderOut(nil)
        panel.orderFrontRegardless()
    }

    // MARK: - Moving

    /// Follows the mouse while the resting pill is dragged. Uses screen coordinates, since
    /// the view's own coordinates move with the window.
    func moveWithMouse() {
        guard mode == .resting else { return }
        let mouse = NSEvent.mouseLocation
        guard let start = moveStart else {
            moveStart = (mouse, panel.frame.origin)
            return
        }
        panel.setFrameOrigin(NSPoint(x: start.origin.x + mouse.x - start.mouse.x,
                                     y: start.origin.y + mouse.y - start.mouse.y))
    }

    /// Snaps to the nearest left or right edge of the screen the pill was dropped on,
    /// keeping its height.
    func endMove() {
        guard moveStart != nil else { return }
        moveStart = nil
        let frame = panel.frame
        let center = NSPoint(x: frame.midX, y: frame.midY)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(center) }) ?? panel.screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            edge = center.x < visible.midX ? .left : .right
            position = min(max((center.y - visible.minY) / visible.height, 0), 1)
            displayID = screen.displayID
            defaults.set(edge.rawValue, forKey: "dockEdge")
            defaults.set(position, forKey: "dockPosition")
            defaults.set(displayID, forKey: "dockDisplay")
        }
        layout()
        handBackKeyboard()
    }

    // MARK: - Layout

    private var screen: NSScreen? {
        NSScreen.screens.first { $0.displayID == displayID } ?? NSScreen.main
    }

    private func layout(animated: Bool = true) {
        let frame = frame(for: mode)
        guard animated, panel.isVisible else {
            panel.setFrame(frame, display: true)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(frame, display: true)
        } completionHandler: { [panel] in
            panel.invalidateShadow()
        }
    }

    private func frame(for mode: Mode) -> NSRect {
        let size = switch mode {
        case .resting: restingSize
        case .dropTarget: CGSize(
            width: Self.dropTargetSize.width,
            height: max(restingSize.height, Self.dropTargetSize.height)
        )
        case .expanded: Self.expandedSize
        }
        guard let visible = screen?.visibleFrame else { return NSRect(origin: .zero, size: size) }
        let margin = Self.margin
        let height = min(size.height, visible.height - 2 * margin)
        let centerY = visible.minY + position * visible.height
        let y = min(max(centerY - height / 2, visible.minY + margin), visible.maxY - margin - height)
        let x = edge == .left ? visible.minX + margin : visible.maxX - margin - size.width
        return NSRect(x: x, y: y, width: size.width, height: height)
    }
}

private extension NSScreen {
    var displayID: Int {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.intValue ?? 0
    }
}
