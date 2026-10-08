import AppKit
import SwiftUI
import SwiftData

/// Owns the desktop panel and moves it between its three states. The panel is one
/// window that changes size, always anchored to the right edge of the screen.
@MainActor @Observable
final class PanelController {
    enum Mode { case resting, dropTarget, expanded }

    private(set) var mode: Mode = .resting

    /// The resting pill's natural size, reported by SwiftUI as items come and go.
    var restingSize = CGSize(width: 56, height: 56) {
        didSet { if mode == .resting, restingSize != oldValue { layout() } }
    }

    var isShown: Bool {
        didSet {
            UserDefaults.standard.set(isShown, forKey: "panelShown")
            isShown ? panel.orderFrontRegardless() : panel.orderOut(nil)
        }
    }

    /// Off: the panel sits at normal window level, so other windows can cover it.
    var keepOnTop: Bool {
        didSet {
            UserDefaults.standard.set(keepOnTop, forKey: "keepOnTop")
            panel.level = keepOnTop ? .floating : .normal
        }
    }

    @ObservationIgnored private let panel = ShelfPanel()
    @ObservationIgnored private var collapseTask: Task<Void, Never>?

    private static let margin: CGFloat = 8
    static let expandedSize = CGSize(width: 320, height: 520)
    static let dropTargetSize = CGSize(width: 136, height: 160)

    init(store: ShelfStore, container: ModelContainer) {
        UserDefaults.standard.register(defaults: ["panelShown": true, "keepOnTop": true])
        isShown = UserDefaults.standard.bool(forKey: "panelShown")
        keepOnTop = UserDefaults.standard.bool(forKey: "keepOnTop")

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
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { if self?.mode == .expanded { self?.collapse() } }
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
        if panel.isKeyWindow {
            // Hand the keyboard back to whatever app you were using.
            panel.orderOut(nil)
            panel.orderFrontRegardless()
        }
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

    // MARK: - Layout

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
        guard let visible = (panel.screen ?? NSScreen.main)?.visibleFrame else {
            return NSRect(origin: .zero, size: size)
        }
        let margin = Self.margin
        let height = min(size.height, visible.height - 2 * margin)
        let y = min(max(visible.midY - height / 2, visible.minY + margin), visible.maxY - margin - height)
        return NSRect(x: visible.maxX - margin - size.width, y: y, width: size.width, height: height)
    }
}
