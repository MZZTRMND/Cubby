import AppKit
import SwiftUI

/// The two slanted eyes from the app icon, on the folder's glass front. They pop open
/// when you hover the folder and follow the pointer wherever it goes: the pair slides
/// across the front toward it, turns to face it and leans its way, as if the folder
/// were turning its head. They blink at random, keep watching for a few seconds after
/// the pointer leaves, then close and fade.
struct FolderEyes: View {
    /// Hovered, or something is being dragged over the folder.
    let isAwake: Bool
    var scale: CGFloat = 1

    @State private var tracker = EyeTracker()
    /// 1 open, near 0 closed: the eyes squash to a line like a lid coming down.
    @State private var lid: CGFloat = 0.1
    @State private var isShown = false
    @State private var isClosing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How long they keep watching after the pointer leaves.
    private static let lingering: Duration = .seconds(5)
    /// How far the eyes lean, as in the icon, when looking all the way to one side.
    /// Looking right they lean back like the icon's; looking left, the other way.
    private static let maxTilt: Double = 20
    /// How far the pair slides from the front's center, looking all the way over.
    private static let travel = CGSize(width: 38, height: 16)
    /// How far the pair turns toward the pointer, in degrees.
    private static let maxTurn = CGSize(width: 38, height: 28)

    var body: some View {
        let look = tracker.look
        HStack(spacing: 9 * scale) {
            eye
            eye
        }
        // Turning to face the pointer: the far eye shrinks into the distance.
        .rotation3DEffect(.degrees(look.width * Self.maxTurn.width), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
        .rotation3DEffect(.degrees(-look.height * Self.maxTurn.height), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
        // Looking around: the pair slides toward the pointer, a little springy so it
        // overshoots and settles like a glance.
        .offset(x: look.width * Self.travel.width * scale, y: look.height * Self.travel.height * scale)
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.45, bounce: 0.4), value: look)
        .background(ScreenAnchor(tracker: tracker))
        .opacity(isShown ? 1 : 0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: isAwake) { await run() }
        .task(id: isShown) { await blinkWhileShown() }
        .onDisappear { tracker.stop() }
    }

    private var eye: some View {
        Capsule()
            .fill(.primary.opacity(0.78))
            .frame(width: 7 * scale, height: 19 * scale)
            .scaleEffect(x: 1, y: lid, anchor: .center)
            .rotationEffect(.degrees(-Self.maxTilt * tracker.look.width))
    }

    /// Opening while awake; watching a while, then closing, once not.
    private func run() async {
        if isAwake {
            tracker.start()
            open()
        } else {
            guard isShown else { return }
            try? await Task.sleep(for: Self.lingering)
            guard !Task.isCancelled else { return }
            await close()
        }
    }

    private func open() {
        isClosing = false
        if !isShown {
            lid = 0.1
            withAnimation(.easeOut(duration: 0.08)) { isShown = true }
        }
        // Wide open with a little bounce, as if surprised to see you.
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(duration: 0.38, bounce: 0.5)) { lid = 1 }
    }

    /// Blinks at random the whole time the eyes are out, lingering included: mostly
    /// single blinks, every so often a quick double, never on a beat.
    private func blinkWhileShown() async {
        guard isShown, !reduceMotion else { return }
        // Not straight after opening.
        try? await Task.sleep(for: .seconds(Double.random(in: 0.8...2.5)))
        while !Task.isCancelled {
            await blink()
            if Double.random(in: 0...1) < 0.25 {
                try? await Task.sleep(for: .milliseconds(140))
                await blink()
            }
            try? await Task.sleep(for: .seconds(Double.random(in: 1.2...5)))
        }
    }

    private func blink() async {
        guard !Task.isCancelled, lid > 0.9 else { return }
        withAnimation(.easeIn(duration: 0.07)) { lid = 0.1 }
        try? await Task.sleep(for: .milliseconds(90))
        // Closing for good wins over opening again.
        guard !Task.isCancelled, isShown, !isClosing else { return }
        withAnimation(.easeOut(duration: 0.12)) { lid = 1 }
    }

    /// The lids come down, then the closed eyes fade away.
    private func close() async {
        isClosing = true
        withAnimation(.easeIn(duration: 0.22)) { lid = 0.1 }
        try? await Task.sleep(for: .milliseconds(260))
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.25)) { isShown = false }
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }
        tracker.stop()
        tracker.look = .zero
    }
}

/// Where the pointer is from the eyes, anywhere on screen, as a direction up to 1 long.
/// Only runs while the eyes are showing.
@MainActor @Observable
final class EyeTracker {
    /// x right, y down, each -1...1; shorter when the pointer is close to the eyes.
    var look: CGSize = .zero
    @ObservationIgnored weak var anchor: NSView?
    @ObservationIgnored private var timer: Timer?

    /// How far the pointer has to be for the eyes to look all the way over.
    private static let fullReach: CGFloat = 260

    func start() {
        guard timer == nil else { return }
        update()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func update() {
        guard let anchor, let window = anchor.window else { return }
        let center = window.convertPoint(toScreen: anchor.convert(NSPoint(x: anchor.bounds.midX, y: anchor.bounds.midY),
                                                                   to: nil))
        let mouse = Pointer.location
        let dx = mouse.x - center.x
        let dy = mouse.y - center.y
        let distance = hypot(dx, dy)
        let reach = min(1, distance / Self.fullReach)
        // Screen y goes up, SwiftUI's goes down.
        let next = distance < 1 ? .zero : CGSize(width: dx / distance * reach, height: -dy / distance * reach)
        // Skip tiny changes, so a still pointer doesn't redraw anything.
        guard abs(next.width - look.width) > 0.01 || abs(next.height - look.height) > 0.01 else { return }
        look = next
    }
}

/// An invisible view behind the eyes, so the tracker knows where they are on screen.
private struct ScreenAnchor: NSViewRepresentable {
    let tracker: EyeTracker

    func makeNSView(context: Context) -> NSView {
        let view = PassThroughView()
        tracker.anchor = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        tracker.anchor = view
    }

    private final class PassThroughView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
