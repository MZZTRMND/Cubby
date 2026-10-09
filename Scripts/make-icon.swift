// Draws Cubby's app icon: a blue folder with a page inside on a light macOS icon tile, the
// same folder as on the desktop. Writes every iconset size to the folder given, for
// iconutil.
//
//   swift Scripts/make-icon.swift <out.iconset>
import SwiftUI
import AppKit

/// Measurements below are on a 1000-point tile; this maps them into the 1024 canvas,
/// where the standard macOS tile is 824 points, centered.
let unit: CGFloat = 0.824
func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: 100 + x * unit, y: 100 + y * unit) }

/// Same outlines as the app's FolderBackShape and FolderFrontShape.
func back(left: CGFloat, right: CGFloat, top: CGFloat, bottom: CGFloat) -> Path {
    let tabRadius = 50 * unit, tabHeight = 66 * unit, corner = 55 * unit
    let minX = p(left, 0).x, maxX = p(right, 0).x, minY = p(0, top).y, maxY = p(0, bottom).y
    let slopeTop = CGPoint(x: minX + (maxX - minX) * 0.485, y: minY)
    let slopeBottom = CGPoint(x: minX + (maxX - minX) * 0.54, y: minY + tabHeight)
    var path = Path()
    path.move(to: CGPoint(x: minX, y: minY + tabRadius))
    path.addArc(tangent1End: CGPoint(x: minX, y: minY), tangent2End: slopeTop, radius: tabRadius)
    path.addArc(tangent1End: slopeTop, tangent2End: slopeBottom, radius: tabRadius * 0.8)
    path.addArc(tangent1End: slopeBottom, tangent2End: CGPoint(x: maxX, y: slopeBottom.y), radius: tabRadius * 0.15)
    path.addArc(tangent1End: CGPoint(x: maxX, y: slopeBottom.y), tangent2End: CGPoint(x: maxX, y: maxY), radius: corner)
    path.addArc(tangent1End: CGPoint(x: maxX, y: maxY), tangent2End: CGPoint(x: minX, y: maxY), radius: corner)
    path.addArc(tangent1End: CGPoint(x: minX, y: maxY), tangent2End: CGPoint(x: minX, y: minY), radius: corner)
    path.closeSubpath()
    return path
}

func front(left: CGFloat, right: CGFloat, top: CGFloat, bottom: CGFloat, taper: CGFloat) -> Path {
    let topRadius = 30 * unit, bottomRadius = 55 * unit
    let topLeft = p(left, top), topRight = p(right, top)
    let bottomRight = p(right - taper, bottom), bottomLeft = p(left + taper, bottom)
    var path = Path()
    path.move(to: CGPoint(x: (topLeft.x + topRight.x) / 2, y: topLeft.y))
    path.addArc(tangent1End: topRight, tangent2End: bottomRight, radius: topRadius)
    path.addArc(tangent1End: bottomRight, tangent2End: bottomLeft, radius: bottomRadius)
    path.addArc(tangent1End: bottomLeft, tangent2End: topLeft, radius: bottomRadius)
    path.addArc(tangent1End: topLeft, tangent2End: topRight, radius: topRadius)
    path.closeSubpath()
    return path
}

struct Icon: View {
    var body: some View {
        Canvas { context, _ in
            let tile = Path(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824),
                            cornerRadius: 185, style: .continuous)
            var shadowed = context
            shadowed.addFilter(.shadow(color: .black.opacity(0.18), radius: 20, y: 10))
            shadowed.fill(tile, with: .color(Color(white: 0.965)))
            context.fill(tile, with: .linearGradient(
                Gradient(colors: [Color(white: 0.975), Color(white: 0.955)]),
                startPoint: p(0, 0), endPoint: p(0, 1000)))

            context.fill(back(left: 175, right: 825, top: 207, bottom: 700),
                         with: .color(Color(red: 0.18, green: 0.43, blue: 0.96)))

            let page = CGRect(origin: p(242, 341), size: CGSize(width: 516 * unit, height: 300 * unit))
            context.fill(Path(roundedRect: page, cornerRadius: 22 * unit, style: .continuous),
                         with: .color(Color(red: 0.95, green: 0.97, blue: 0.99)))

            let pocket = front(left: 145, right: 855, top: 408, bottom: 790, taper: 27)
            var dropped = context
            dropped.addFilter(.shadow(color: .black.opacity(0.14), radius: 28, y: 18))
            dropped.fill(pocket, with: .color(Color(red: 0.1, green: 0.6, blue: 0.94)))
            context.fill(pocket, with: .linearGradient(
                Gradient(colors: [Color(red: 0.29, green: 0.71, blue: 0.95), Color(red: 0.1, green: 0.6, blue: 0.94)]),
                startPoint: p(0, 408), endPoint: p(0, 790)))
            // The sides run a deeper blue than the middle.
            let edge = Color(red: 0.1, green: 0.55, blue: 0.93).opacity(0.55)
            context.fill(pocket, with: .linearGradient(
                Gradient(stops: [.init(color: edge, location: 0), .init(color: edge.opacity(0.4), location: 0.14),
                                 .init(color: edge.opacity(0), location: 0.38), .init(color: edge.opacity(0), location: 0.62),
                                 .init(color: edge.opacity(0.4), location: 0.86), .init(color: edge, location: 1)]),
                startPoint: p(145, 0), endPoint: p(855, 0)))
        }
        .frame(width: 1024, height: 1024)
    }
}

@MainActor func write(_ pixels: Int, to url: URL) {
    let renderer = ImageRenderer(content: Icon())
    renderer.scale = CGFloat(pixels) / 1024
    guard let image = renderer.cgImage else { fatalError("render failed") }
    let rep = NSBitmapImageRep(cgImage: image)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
MainActor.assumeIsolated {
    for size in [16, 32, 128, 256, 512] {
        write(size, to: out.appendingPathComponent("icon_\(size)x\(size).png"))
        write(size * 2, to: out.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
    }
}
