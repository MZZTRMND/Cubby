import AppKit
import SwiftData
import SwiftUI

/// Plays the demo: builds a stage over the whole screen (a wallpaper, files on it and a
/// few other apps' windows), then moves a pointer of its own through a script while the
/// real folder and card respond: the eyes follow it, things it drops really go in, the
/// card really opens. Only the stage and the pointer are pretend.
///
/// It waits for `Demo.go` from the recorder (or starts by itself with `-demoAutostart YES`),
/// writes the time each scene began to `markers.json` beside the recording, and posts
/// `Demo.finished` at the end.
@MainActor
final class DemoDirector {
    private let store: CubbyStore
    private let panel: PanelController
    private let state = DemoState()
    private let screen: NSRect
    private var backdrop: NSWindow?
    private var overlay: NSWindow?
    private var windows: [String: NSWindow] = [:]
    private var startTime: Double = 0
    private var markers: [[String: Any]] = []

    init(store: CubbyStore, panel: PanelController) {
        self.store = store
        self.panel = panel
        screen = (NSScreen.main ?? NSScreen.screens[0]).frame
    }

    func start() {
        Task { await run() }
    }

    // MARK: - Geometry, in screen points from the top left

    /// The middle of the stage. Everything is laid out around it, in a 1280×720 area the
    /// video crops to.
    private var c: CGPoint { CGPoint(x: screen.width / 2, y: screen.height / 2 + 40) }
    private func at(_ dx: CGFloat, _ dy: CGFloat) -> CGPoint { CGPoint(x: c.x + dx, y: c.y + dy) }
    private func appKit(_ p: CGPoint) -> NSPoint { NSPoint(x: screen.minX + p.x, y: screen.maxY - p.y) }
    private func appKit(_ r: CGRect) -> NSRect { NSRect(x: screen.minX + r.minX, y: screen.maxY - r.maxY, width: r.width, height: r.height) }
    private func topLeft(_ r: NSRect) -> CGRect { CGRect(x: r.minX - screen.minX, y: screen.maxY - r.maxY, width: r.width, height: r.height) }

    /// The folder's glass front, where things are dropped.
    private var folderMouth: CGPoint {
        let r = topLeft(panel.demoFrame)
        return CGPoint(x: r.midX, y: r.maxY - 80)
    }

    /// The open card, without the window's margin.
    private var card: CGRect { topLeft(panel.demoFrame).insetBy(dx: PanelController.expandedInset, dy: PanelController.expandedInset) }

    // MARK: - Setup

    private func run() async {
        NSApp.activate()
        DemoFiles.prepare()
        buildStage()
        panel.demoPlace(center: appKit(at(0, 40)))
        await seed()
        try? await Task.sleep(for: .seconds(1))
        await waitForGo()
        startTime = CACurrentMediaTime()
        await script()
        mark("end")
        try? await Task.sleep(for: .seconds(1))
        saveMarkers()
        DistributedNotificationCenter.default().postNotificationName(Demo.finished, object: nil, userInfo: nil, deliverImmediately: true)
    }

    private func buildStage() {
        let backdrop = NSWindow(contentRect: screen, styleMask: [.borderless], backing: .buffered, defer: false)
        backdrop.level = Demo.stageLevel
        backdrop.contentView = NSHostingView(rootView: DemoBackdrop().environment(state))
        backdrop.setFrame(screen, display: true)
        backdrop.orderFrontRegardless()
        self.backdrop = backdrop

        let overlay = NSWindow(contentRect: screen, styleMask: [.borderless], backing: .buffered, defer: false)
        overlay.level = Demo.overlayLevel
        overlay.isOpaque = false
        overlay.backgroundColor = .clear
        overlay.ignoresMouseEvents = true
        overlay.hasShadow = false
        overlay.contentView = NSHostingView(rootView: DemoOverlay().environment(state))
        overlay.setFrame(screen, display: true)
        overlay.orderFrontRegardless()
        self.overlay = overlay

        windows["moodboard"] = makeWindow(MoodboardContent(), frame: CGRect(origin: at(-580, -300), size: CGSize(width: 880, height: 560)))
        windows["browser"] = makeWindow(BrowserContent(), frame: CGRect(origin: at(-610, -310), size: CGSize(width: 1040, height: 600)))
        windows["notes"] = makeWindow(NotesContent(), frame: CGRect(origin: at(150, -260), size: CGSize(width: 470, height: 520)))
    }

    private func makeWindow<V: View>(_ content: V, frame: CGRect) -> NSWindow {
        // Room around it for the shadow, which the chrome draws itself.
        let outer = frame.insetBy(dx: -40, dy: -40)
        let window = NSWindow(contentRect: appKit(outer), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.level = Demo.stageLevel
        window.contentView = NSHostingView(rootView: DemoChrome { content }.environment(state))
        window.setFrame(appKit(outer), display: true)
        return window
    }

    private func show(_ name: String) {
        guard let window = windows[name] else { return }
        window.alphaValue = 1
        window.orderFrontRegardless()
    }

    private func hide(_ name: String) {
        windows[name]?.orderOut(nil)
    }

    /// The files on the desktop, and a few things already in the folder.
    private func seed() async {
        let files: [(String, URL, CGPoint)] = [
            ("sunset", DemoFiles.jpeg(.sunset, named: "Sunset at the coast.jpg"), at(-470, -220)),
            ("budget", DemoFiles.pdf(named: "Trip budget.pdf", title: "Trip budget",
                                     lines: ["Train  €84", "Cabin, two nights  €260", "Food  €120", "Boat tour  €45"]), at(-530, 20)),
            ("lake", DemoFiles.jpeg(.mountains, named: "Mountain lake.jpg"), at(-450, 250)),
            ("city", DemoFiles.jpeg(.city, named: "Night walk.jpg"), at(470, -220)),
            ("deck", DemoFiles.pdf(named: "Pitch deck.pdf", title: "Cubby", lines: ["A little folder", "for your desktop"]), at(530, 10)),
            ("dunes", DemoFiles.jpeg(.dunes, named: "Sunset dunes.jpg", portrait: true), at(460, 250)),
        ]
        state.icons = files.map { id, url, center in
            DemoState.DeskIcon(id: id, name: url.lastPathComponent, url: url, image: NSWorkspace.shared.icon(forFile: url.path), center: center)
        }
        // Finder shows pictures as thumbnails.
        for i in state.icons.indices where state.icons[i].url.pathExtension == "jpg" {
            if let picture = NSImage(contentsOf: state.icons[i].url) { state.icons[i] = withImage(state.icons[i], picture) }
        }
        let beach = DemoFiles.jpeg(.beach, named: "Beach day.jpg")
        let flowers = DemoFiles.jpeg(.flowers, named: "Flowers.jpg", portrait: true)
        await store.add([.file(flowers)]).value
        await store.add([.text("#7A5CFA")]).value
        await store.add([.file(beach)]).value
    }

    private func withImage(_ icon: DemoState.DeskIcon, _ image: NSImage) -> DemoState.DeskIcon {
        DemoState.DeskIcon(id: icon.id, name: icon.name, url: icon.url, image: image, center: icon.center)
    }

    private func waitForGo() async {
        if UserDefaults.standard.bool(forKey: "demoAutostart") { return }
        DistributedNotificationCenter.default().postNotificationName(Demo.ready, object: nil, userInfo: nil, deliverImmediately: true)
        var started = false
        let token = DistributedNotificationCenter.default().addObserver(forName: Demo.go, object: nil, queue: .main) { _ in
            started = true
        }
        // Without a recorder the stage would cover the screen for good, so give up after a while.
        for _ in 0..<400 where !started {
            try? await Task.sleep(for: .milliseconds(100))
        }
        DistributedNotificationCenter.default().removeObserver(token)
        if !started { NSApp.terminate(nil) }
    }

    private func mark(_ scene: String) {
        markers.append(["scene": scene, "time": CACurrentMediaTime() - startTime])
    }

    private func saveMarkers() {
        let url = AppPaths.support.appending(path: "markers.json")
        if let data = try? JSONSerialization.data(withJSONObject: markers, options: [.prettyPrinted]) {
            try? data.write(to: url)
        }
    }

    // MARK: - Moving things

    private func wait(_ seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    /// Runs `update` with 0…1 for `duration` seconds, by the clock, so it's smooth however
    /// the frames fall.
    private func tween(_ duration: Double, _ update: (Double) -> Void) async {
        let start = CACurrentMediaTime()
        while true {
            let t = min(1, (CACurrentMediaTime() - start) / duration)
            update(t)
            if t >= 1 { break }
            try? await Task.sleep(for: .milliseconds(6))
        }
    }

    private static func ease(_ t: Double) -> Double {
        // Quick to start, long to settle, like a hand.
        t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
    }

    private func setPointer(_ p: CGPoint) {
        state.pointer = p
        Pointer.override = appKit(p)
    }

    /// Moves the pointer along a gentle curve. `along` is called with each new spot.
    private func move(to target: CGPoint, _ duration: Double, bend: CGFloat = 0.12, along: ((CGPoint) -> Void)? = nil) async {
        let from = state.pointer
        let dx = target.x - from.x, dy = target.y - from.y
        let control = CGPoint(x: from.x + dx / 2 - dy * bend, y: from.y + dy / 2 + dx * bend)
        await tween(duration) { t in
            let e = Self.ease(t)
            let u = 1 - e
            let p = CGPoint(x: u * u * from.x + 2 * u * e * control.x + e * e * target.x,
                            y: u * u * from.y + 2 * u * e * control.y + e * e * target.y)
            setPointer(p)
            along?(p)
        }
    }

    private func click() async {
        state.isPressed = true
        await wait(0.12)
        state.isPressed = false
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }

    /// Picks up a desktop file, carries it to the folder and drops it in.
    private func dragIcon(_ id: String, speed: Double = 1) async {
        guard let index = state.icons.firstIndex(where: { $0.id == id }) else { return }
        let icon = state.icons[index]
        await move(to: icon.center, 0.75 / speed)
        state.selectedIcon = id
        state.isPressed = true
        await wait(0.15 / speed)
        state.ghost = icon.image
        state.ghostSize = CGSize(width: 80, height: 80)
        state.ghostOpacity = 0.75
        await carry(to: folderMouth, 0.9 / speed)
        await drop([.file(icon.url)])
        state.icons[index].isGone = true
        state.selectedIcon = nil
    }

    /// Carries what's under the pointer to `target`; the folder lights up as it gets close.
    private func carry(to target: CGPoint, _ duration: Double) async {
        var entered = false
        await move(to: target, duration) { [self] p in
            if !entered, distance(p, folderMouth) < 150 {
                entered = true
                panel.dragEntered()
            }
        }
        if !entered { panel.dragEntered() }
        await wait(0.18)
    }

    private func drop(_ incoming: [Incoming]) async {
        state.isPressed = false
        state.ghost = nil
        store.add(incoming)
        panel.dropped()
    }

    // MARK: - The script

    private func script() async {
        setPointer(at(700, 420))

        // 1. Meet Cubby: the pointer comes by, the folder wakes up and watches it.
        mark("meet")
        await wait(1.2)
        await move(to: at(260, 120), 1.0)
        panel.demoHover(true)
        state.cursor = .hand
        await move(to: at(60, 10), 0.8)
        state.cursor = .arrow
        panel.demoHover(false)
        // Around the folder, so the eyes follow it all the way round.
        let center = at(0, 0)
        await tween(3.2) { t in
            let angle = -0.3 + t * 2 * .pi
            setPointer(CGPoint(x: center.x + cos(angle) * 300, y: center.y + sin(angle) * 190 - 30))
        }
        await move(to: at(240, -60), 0.6)
        await wait(1.0)

        // 2. Takes anything: the desktop's files go in one by one.
        mark("takes")
        await dragIcon("sunset")
        await wait(0.5)
        await dragIcon("city", speed: 1.15)
        await wait(0.3)
        await dragIcon("budget", speed: 1.3)
        await dragIcon("dunes", speed: 1.4)
        await dragIcon("lake", speed: 1.5)
        await dragIcon("deck", speed: 1.6)
        await move(to: at(280, 120), 0.8)
        await wait(2.0)

        // 3. Catches screenshots.
        mark("screenshots")
        panel.demoPlace(center: appKit(at(470, 210)))
        show("moodboard")
        setPointer(at(-120, 120))
        await wait(1.0)
        let (shotURL, shotImage) = DemoFiles.screenshot(of: MoodboardContent(), size: CGSize(width: 880, height: 560), named: "Screenshot 2026-11-11 at 10.42.png")
        state.showsPointer = false
        await tween(0.35) { t in state.flash = t < 0.2 ? t / 0.2 * 0.7 : 0.7 * (1 - (t - 0.2) / 0.8) }
        state.flash = 0
        state.shot = shotImage
        state.shotScale = 1
        state.shotOpacity = 1
        let rest = at(480, -70)
        await tween(0.45) { t in
            let e = 1 - pow(1 - t, 3)
            state.shotCenter = CGPoint(x: rest.x + (1 - e) * 500, y: rest.y)
        }
        await wait(1.2)
        let mouth = folderMouth
        var caught = false
        await tween(0.7) { [self] t in
            let e = Self.ease(t)
            state.shotCenter = CGPoint(x: rest.x + (mouth.x - rest.x) * e, y: rest.y + (mouth.y - rest.y) * e - 160 * 4 * e * (1 - e))
            state.shotScale = 1 - 0.75 * e
            state.shotOpacity = t > 0.85 ? (1 - t) / 0.15 : 1
            if !caught, t > 0.8 {
                caught = true
                store.addScreenshot(shotURL)
                panel.caught()
            }
        }
        state.shot = nil
        state.showsPointer = true
        await wait(2.2)

        // 4. Comes to you: a drag from the browser, a shake, and the folder pops up by it.
        mark("summon")
        hide("moodboard")
        show("browser")
        panel.demoPlace(center: appKit(at(1050, 560)))
        setPointer(at(420, 300))
        await wait(0.8)
        let photo = at(-610 + 40 + 230, -310 + 52 + 36 + 172)
        await move(to: photo, 0.8)
        state.isPressed = true
        await wait(0.2)
        state.ghost = DemoArt.sunset.image(width: 230, height: 172)
        state.ghostSize = CGSize(width: 230, height: 172)
        state.ghostOpacity = 0.8
        await move(to: at(330, -40), 0.8)
        let shakeAt = state.pointer
        var summoned = false
        await tween(0.75) { [self] t in
            let swing = sin(t * .pi * 6) * 85 * sin(t * .pi)
            setPointer(CGPoint(x: shakeAt.x + swing, y: shakeAt.y + sin(t * .pi * 11) * 6))
            if !summoned, t > 0.72 {
                summoned = true
                panel.demoSummon()
            }
        }
        await wait(0.7)
        state.ghostSize = CGSize(width: 150, height: 112)
        await carry(to: folderMouth, 0.6)
        await drop([.file(DemoFiles.jpeg(.sunset, named: "Sunset by the sea.jpg"))])
        panel.demoLower()
        await move(to: at(380, 140), 0.6)
        await wait(1.5)

        // 4b. Links, words and colors, from the same page.
        mark("more")
        panel.demoPlace(center: appKit(at(470, 220)))
        await wait(0.6)
        let address = at(-610 + 520, -310 + 26)
        await move(to: address, 0.8)
        state.isPressed = true
        await wait(0.15)
        state.ghost = NSImage(systemSymbolName: "link", accessibilityDescription: nil)
        state.ghostSize = CGSize(width: 34, height: 34)
        state.ghostOpacity = 0.9
        await carry(to: folderMouth, 0.8)
        await drop([.url(URL(string: "https://www.apple.com/")!)])
        await wait(0.4)

        let quote = at(-610 + 40 + 460 + 32 + 150, -310 + 52 + 36 + 70)
        state.selectsText = true
        await move(to: quote, 0.7)
        state.isPressed = true
        await wait(0.15)
        state.ghost = NSImage(systemSymbolName: "text.alignleft", accessibilityDescription: nil)
        state.ghostSize = CGSize(width: 34, height: 34)
        await carry(to: folderMouth, 0.75)
        await drop([.text(BrowserContent.quote)])
        state.selectsText = false
        await wait(0.4)

        let swatch = at(-610 + 40 + 460 + 32 + 17, -310 + 52 + 36 + 238)
        await move(to: swatch, 0.7)
        state.isPressed = true
        await wait(0.15)
        state.ghost = NSImage(size: NSSize(width: 34, height: 34), flipped: false) { rect in
            NSColor(srgbRed: 1, green: 0.42, blue: 0.37, alpha: 1).setFill()
            NSBezierPath(ovalIn: rect).fill()
            return true
        }
        state.ghostSize = CGSize(width: 34, height: 34)
        await carry(to: folderMouth, 0.7)
        await drop([.text("#FF6B5E")])
        await move(to: at(330, 60), 0.6)
        await wait(1.8)

        // 5. Opens into a card: tabs, then typing to find.
        mark("card")
        hide("browser")
        panel.demoPlace(center: appKit(at(-230, 40)))
        setPointer(at(200, 300))
        await wait(0.8)
        let folder = topLeft(panel.demoFrame)
        await move(to: CGPoint(x: folder.midX, y: folder.maxY - 70), 0.8)
        state.cursor = .hand
        panel.demoHover(true)
        await wait(0.5)
        await click()
        panel.expand()
        state.cursor = .arrow
        await wait(1.3)
        // Where the tabs are, measured from a recording.
        for (kind, x) in [(ItemKind.image, 0.23), (.link, 0.71), (nil, 0.08)] as [(ItemKind?, Double)] {
            await move(to: CGPoint(x: card.minX + card.width * x, y: card.minY + 32), 0.6)
            await click()
            withAnimation(PanelController.animation) { store.kindFilter = kind }
            await wait(1.1)
        }
        await move(to: at(-60, 330), 0.6)
        for letter in "sunset" {
            store.searchText.append(letter)
            await wait(0.13)
        }
        await wait(1.6)
        store.searchText = ""
        await wait(0.8)

        // 6. Gives it back: an item dragged out of the card into a note.
        mark("giveback")
        show("notes")
        await wait(0.6)
        let shown = store.shownItems()
        if let index = shown.firstIndex(where: { $0.fileName == "Mountain lake.jpg" }) {
            let item = shown[index]
            let cellWidth = (card.width - 32 - 24) / 4
            let cell = CGPoint(x: card.minX + 16 + cellWidth * (CGFloat(index % 4) + 0.5) + 8 * CGFloat(index % 4),
                               y: card.minY + 84 + 118 * (CGFloat(index / 4) + 0.5))
            await move(to: cell, 0.8)
            state.isPressed = true
            await wait(0.15)
            let renderer = ImageRenderer(content: ItemGlyph(item: item, size: 96, natural: true))
            renderer.scale = 2
            state.ghost = renderer.nsImage
            state.ghostSize = CGSize(width: 96, height: 96)
            state.ghostOpacity = 0.85
            await move(to: at(385, 70), 1.0)
            state.isPressed = false
            state.ghost = nil
            state.notesImage = item.fileURL.flatMap { NSImage(contentsOf: $0) }
        }
        await wait(1.2)
        await move(to: at(60, 320), 0.7)
        await click()
        panel.collapse()
        await wait(1.0)
        hide("notes")

        // 7. A last look.
        mark("outro")
        panel.demoPlace(center: appKit(at(0, 40)))
        await wait(0.6)
        await move(to: at(-200, -60), 0.9)
        panel.demoHover(true)
        await move(to: at(200, -40), 1.2)
        await move(to: at(0, -160), 0.8)
        panel.demoHover(false)
        await move(to: at(300, 420), 0.8)
        state.showsPointer = false
        await wait(4.0)
    }
}
