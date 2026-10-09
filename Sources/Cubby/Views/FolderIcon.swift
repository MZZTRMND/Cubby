import SwiftUI

/// The resting cubby: a folder shaped like the app icon's, with its newest items standing
/// inside in front of a page, behind a frosted glass front. Hovering it, or
/// dragging something over it, slides the items up out of the folder; the folder itself
/// never changes.
struct FolderIcon: View {
    let items: [CubbyItem]
    let isDropTarget: Bool
    /// Pin on Top is on: a pushpin sticks in the back's corner.
    var isPinned = false
    @State private var isHovered = false
    /// Bumped once the pin has landed after Pin on Top is turned on, to wiggle it.
    @State private var pinWiggles = 0

    /// Set in Settings: the whole folder, and the items on top of that.
    @AppStorage(Self.folderScaleKey) private var folderScale = Self.defaultFolderScale
    @AppStorage(Self.itemScaleKey) private var itemScale = 1.0

    static let folderScaleKey = "folderScale"
    static let itemScaleKey = "itemScale"
    static let folderScaleRange: ClosedRange<Double> = 0.75...1.5
    static let defaultFolderScale = 1.2
    /// Narrower, so items never get wider than the folder.
    static let itemScaleRange: ClosedRange<Double> = 0.6...1.25

    private var isOpen: Bool { isHovered || isDropTarget }

    // Measurements at 100%, taken from the app icon; everything below is scaled from these.
    /// The front's width along its top, its widest part.
    private static let width: CGFloat = 144
    /// The back, from the top of its tab down to just above the front's bottom.
    private static let backSize = CGSize(width: 132, height: 104)
    private static let tabHeight: CGFloat = 13
    private static let pageSize = CGSize(width: 105, height: 77)
    /// How far below the back's top edge, under the tab, the items' tops sit at rest.
    private static let depth: CGFloat = 15
    private static let frontHeight: CGFloat = 78
    private static let itemSize: CGFloat = 64
    /// How far the items slide up when the folder opens.
    private static let rise: CGFloat = 22

    /// Up to eight items in a loose pile, as if tossed in, the newest in front. When the
    /// folder opens they rise by slightly different amounts, spread apart and tilt more.
    private static let spots: [(x: CGFloat, y: CGFloat, angle: Double)] = [
        (-3, 2, -4), (14, -4, 9), (-16, -2, -11), (6, -10, 5),
        (-8, -12, -6), (20, 4, 14), (-22, 6, -15), (2, -16, 2),
    ]
    private static let fanSpread: CGFloat = 1.4
    private static let fanTilt: Double = 1.5
    /// On top of `rise`, so the items don't all come up level.
    private static let extraRise: [CGFloat] = [0, 4, 8]

    /// White in light mode, and a gray a little lighter than the back in dark mode.
    private static let pageColor = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor(white: 0.36, alpha: 1) : .white
    })

    private var scale: CGFloat { CGFloat(folderScale) }
    private var itemSize: CGFloat { Self.itemSize * scale * CGFloat(itemScale) }
    private var backSize: CGSize { CGSize(width: Self.backSize.width * scale, height: Self.backSize.height * scale) }

    var body: some View {
        let front = FolderFrontShape(topRadius: 6 * scale, bottomRadius: 11 * scale, taper: 5.5 * scale)
        ZStack(alignment: .bottom) {
            FolderBackShape(cornerRadius: 11 * scale, tabRadius: 10 * scale, tabHeight: Self.tabHeight * scale)
                // System colors, so the folder follows light and dark mode.
                .fill(Color(nsColor: .underPageBackgroundColor))
                .fill(Color(nsColor: .tertiarySystemFill))
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                .frame(width: backSize.width, height: backSize.height)
                .padding(.bottom, 4 * scale)
            RoundedRectangle(cornerRadius: 4.5 * scale, style: .continuous)
                .fill(Self.pageColor)
                .strokeBorder(Color(nsColor: .separatorColor))
                .frame(width: Self.pageSize.width * scale, height: Self.pageSize.height * scale)
                .padding(.bottom, 11 * scale)
            papers
            Color.clear
                .frame(width: Self.width * scale, height: Self.frontHeight * scale)
                // Clear glass, so the items and page show through more.
                .glassSurface(front, glass: .clear)
        }
        // Room above the back for the items to slide into.
        .frame(width: Self.width * scale, height: (Self.backSize.height + 4 + Self.rise) * scale, alignment: .bottom)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .pointingHandCursor()
        // Above the items, so they never cover it as they slide up. It sits in the back's
        // top right corner, which is inset from the front's and below the room for the items.
        .overlay(alignment: .topTrailing) {
            if isPinned {
                PushPin(size: 20 * scale, wiggles: pinWiggles)
                    .offset(x: (-(Self.width - Self.backSize.width) / 2 - 6) * scale,
                            y: (Self.rise + Self.tabHeight - 17) * scale)
                    .transition(.asymmetric(
                        insertion: .modifier(active: PinDrop(progress: 0), identity: PinDrop(progress: 1)),
                        removal: .scale(scale: 0.4).combined(with: .opacity)))
            }
        }
        .animation(PanelController.animation, value: isOpen)
        // Bouncy, so the pin lands with a little overshoot.
        .animation(.spring(duration: 0.55, bounce: 0.45), value: isPinned)
        .onChange(of: isPinned) { _, pinned in
            guard pinned else { return }
            Task {
                try? await Task.sleep(for: .milliseconds(450))
                pinWiggles += 1
            }
        }
        // Room around the folder for the items as they fan out, tilt and cast shadows on
        // hover, so the window's edge never cuts them. Outside the hover area above.
        .padding(.horizontal, fanRoom)
        .padding(.top, 10 * scale)
    }

    /// How far the outermost fanned item, tilted, reaches past the folder's side.
    private var fanRoom: CGFloat {
        let reach = Self.spots.map { spot in
            let angle = abs(spot.angle * Self.fanTilt) * .pi / 180
            // Leaning on its bottom edge, the top corner swings out by the item's height.
            return abs(spot.x) * Self.fanSpread + Self.itemSize / 2 * cos(angle) + Self.itemSize * sin(angle) + 6
        }.max() ?? 0
        return max(0, reach * CGFloat(itemScale) - Self.width / 2) * scale + 4
    }

    private var papers: some View {
        let shown = Array(items.prefix(Self.spots.count).enumerated())
        // The fan spreads with the items, so bigger items don't crowd each other.
        let spread = scale * CGFloat(itemScale)
        return ZStack(alignment: .bottom) {
            // Back to front, so the newest sits on top.
            ForEach(shown.reversed(), id: \.element.id) { index, item in
                let spot = Self.spots[index]
                ItemGlyph(item: item, size: itemSize, natural: true)
                    .rotationEffect(.degrees(spot.angle * (isOpen ? Self.fanTilt : 1)), anchor: .bottom)
                    .offset(x: spot.x * spread * (isOpen ? Self.fanSpread : 1),
                            y: (spot.y - (isOpen ? Self.rise + Self.extraRise[index % 3] : 0)) * scale)
                    // A small stagger, so they slide up one after another.
                    .animation(PanelController.animation.delay(Double(index) * 0.015), value: isOpen)
            }
        }
        // At rest their tops sit just under the back's top edge, whatever their size.
        .padding(.bottom, (Self.backSize.height + 4 - Self.depth) * scale - itemSize)
    }
}

/// A red pushpin, tilted as if pressed into the folder. It wiggles whenever `wiggles`
/// changes.
private struct PushPin: View {
    let size: CGFloat
    let wiggles: Int

    var body: some View {
        Image(systemName: "pin.fill")
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(.red.gradient)
            .symbolEffect(.wiggle, value: wiggles)
            .rotationEffect(.degrees(35))
            .shadow(color: .black.opacity(0.3), radius: 1.5, x: 1, y: 2)
            .allowsHitTesting(false)
    }
}

/// The pin falling in: from above, bigger and spun back, to resting in place.
private struct PinDrop: ViewModifier {
    let progress: CGFloat

    func body(content: Content) -> some View {
        let rest = 1 - progress
        content
            .scaleEffect(1 + rest * 0.6)
            .rotationEffect(.degrees(-50 * rest))
            .offset(y: -40 * rest)
            .opacity(min(1, progress * 3))
    }
}
