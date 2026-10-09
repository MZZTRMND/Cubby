import SwiftUI

/// The folder's back: rounded, with a tab along the top left whose edge bends down a
/// short slope into the lower top edge.
struct FolderBackShape: Shape {
    var cornerRadius: CGFloat = 11
    var tabRadius: CGFloat = 10
    var tabHeight: CGFloat = 13
    /// Where the slope starts and ends along the top, as fractions of the width.
    var slopeStart: CGFloat = 0.485
    var slopeEnd: CGFloat = 0.54

    func path(in rect: CGRect) -> Path {
        let slopeTop = CGPoint(x: rect.minX + rect.width * slopeStart, y: rect.minY)
        let slopeBottom = CGPoint(x: rect.minX + rect.width * slopeEnd, y: rect.minY + tabHeight)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + tabRadius))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY), tangent2End: slopeTop, radius: tabRadius)
        path.addArc(tangent1End: slopeTop, tangent2End: slopeBottom, radius: tabRadius * 0.8)
        path.addArc(tangent1End: slopeBottom, tangent2End: CGPoint(x: rect.maxX, y: slopeBottom.y),
                    radius: tabRadius * 0.15)
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: slopeBottom.y),
                    tangent2End: CGPoint(x: rect.maxX, y: rect.maxY), radius: cornerRadius)
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY),
                    tangent2End: CGPoint(x: rect.minX, y: rect.maxY), radius: cornerRadius)
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY),
                    tangent2End: CGPoint(x: rect.minX, y: rect.minY), radius: cornerRadius)
        path.closeSubpath()
        return path
    }
}

/// The folder's front: a pocket a little narrower at the bottom than the top, with small
/// rounded top corners and bigger bottom ones.
struct FolderFrontShape: Shape {
    var topRadius: CGFloat = 6
    var bottomRadius: CGFloat = 11
    /// How far in each bottom corner sits from the top one.
    var taper: CGFloat = 5.5

    func path(in rect: CGRect) -> Path {
        let topLeft = CGPoint(x: rect.minX, y: rect.minY)
        let topRight = CGPoint(x: rect.maxX, y: rect.minY)
        let bottomRight = CGPoint(x: rect.maxX - taper, y: rect.maxY)
        let bottomLeft = CGPoint(x: rect.minX + taper, y: rect.maxY)
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addArc(tangent1End: topRight, tangent2End: bottomRight, radius: topRadius)
        path.addArc(tangent1End: bottomRight, tangent2End: bottomLeft, radius: bottomRadius)
        path.addArc(tangent1End: bottomLeft, tangent2End: topLeft, radius: bottomRadius)
        path.addArc(tangent1End: topLeft, tangent2End: topRight, radius: topRadius)
        path.closeSubpath()
        return path
    }
}

extension EnvironmentValues {
    /// Offscreen renders can't draw Liquid Glass, so layout checks swap in a plain fill.
    @Entry var solidFolderSurface = false
}

private struct GlassSurface<S: Shape>: ViewModifier {
    let shape: S
    let glass: Glass
    @Environment(\.solidFolderSurface) private var isSolid

    func body(content: Content) -> some View {
        if isSolid {
            content.background(Color(white: 0.9).opacity(0.85), in: shape)
        } else {
            content.glassEffect(glass, in: shape)
        }
    }
}

extension View {
    /// A Liquid Glass surface in `shape`. `.clear` is more see-through than `.regular`.
    func glassSurface<S: Shape>(_ shape: S, glass: Glass = .regular) -> some View {
        modifier(GlassSurface(shape: shape, glass: glass))
    }
}

extension View {
    /// The pointing hand while the mouse is over this view. Set on every move, since the
    /// app in front would otherwise put its own cursor back.
    func pointingHandCursor() -> some View {
        onContinuousHover { phase in
            switch phase {
            case .active: NSCursor.pointingHand.set()
            case .ended: NSCursor.arrow.set()
            }
        }
    }
}
