import CoreGraphics

/// Geometry of the open shelf's free canvas. Positions are item centers in canvas
/// coordinates; new items fill a grid of slots, then the user can move them anywhere.
enum CanvasLayout {
    static let width: CGFloat = 384
    static let cell = CGSize(width: 96, height: 96)
    static let iconSize: CGFloat = 48

    private static var columns: Int { Int(width / cell.width) }

    static func slot(_ index: Int) -> CGPoint {
        CGPoint(x: cell.width * (CGFloat(index % columns) + 0.5),
                y: cell.height * (CGFloat(index / columns) + 0.5))
    }

    /// The first grid slot not already covered by an item.
    static func firstFreeSlot(avoiding taken: [CGPoint]) -> CGPoint {
        var index = 0
        while true {
            let slot = slot(index)
            let isTaken = taken.contains {
                abs($0.x - slot.x) < cell.width * 0.6 && abs($0.y - slot.y) < cell.height * 0.6
            }
            if !isTaken { return slot }
            index += 1
        }
    }

    /// Keeps a dropped position fully inside the canvas.
    static func clamp(_ point: CGPoint) -> CGPoint {
        CGPoint(x: min(max(point.x, cell.width / 2), width - cell.width / 2),
                y: max(point.y, cell.height / 2))
    }
}
