import AppKit
import PDFKit
import SwiftUI

/// Pictures for the demo's photos, drawn rather than taken, so the video holds nothing
/// that belongs to anyone else.
enum DemoArt: String, CaseIterable {
    case sunset, mountains, beach, city, dunes, flowers

    var view: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            func rect(_ y0: Double, _ y1: Double) -> CGRect { CGRect(x: 0, y: h * y0, width: w, height: h * (y1 - y0)) }
            func gradient(_ colors: [Color], _ r: CGRect) {
                context.fill(Path(r), with: .linearGradient(Gradient(colors: colors), startPoint: CGPoint(x: 0, y: r.minY), endPoint: CGPoint(x: 0, y: r.maxY)))
            }
            func hills(_ points: [(Double, Double)], _ color: Color) {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: h))
                path.addLine(to: CGPoint(x: 0, y: h * points[0].1))
                for i in 1..<points.count {
                    let (x0, y0) = points[i - 1], (x1, y1) = points[i]
                    path.addQuadCurve(to: CGPoint(x: w * x1, y: h * y1), control: CGPoint(x: w * (x0 + x1) / 2, y: h * min(y0, y1) - h * 0.04))
                }
                path.addLine(to: CGPoint(x: w, y: h))
                path.closeSubpath()
                context.fill(path, with: .color(color))
            }
            func sun(_ x: Double, _ y: Double, _ r: Double, _ color: Color) {
                context.fill(Path(ellipseIn: CGRect(x: w * x - w * r, y: h * y - w * r, width: 2 * w * r, height: 2 * w * r)), with: .color(color))
            }
            switch self {
            case .sunset:
                gradient([Color(red: 0.36, green: 0.25, blue: 0.77), Color(red: 1, green: 0.44, blue: 0.49), Color(red: 1, green: 0.7, blue: 0.42)], rect(0, 1))
                sun(0.62, 0.6, 0.11, Color(red: 1, green: 0.88, blue: 0.54))
                hills([(0, 0.7), (0.4, 0.64), (0.75, 0.68), (1, 0.62)], Color(red: 0.23, green: 0.14, blue: 0.35))
                hills([(0, 0.84), (0.5, 0.78), (1, 0.8)], Color(red: 0.14, green: 0.09, blue: 0.23))
            case .mountains:
                gradient([Color(red: 0.29, green: 0.66, blue: 0.94), Color(red: 0.84, green: 0.94, blue: 1)], rect(0, 1))
                var peaks = Path()
                peaks.addLines([CGPoint(x: -w * 0.05, y: h * 0.82), CGPoint(x: w * 0.3, y: h * 0.28), CGPoint(x: w * 0.5, y: h * 0.58),
                                CGPoint(x: w * 0.7, y: h * 0.36), CGPoint(x: w * 1.05, y: h * 0.82)])
                context.fill(peaks, with: .color(Color(red: 0.35, green: 0.48, blue: 0.69)))
                var snow = Path()
                snow.addLines([CGPoint(x: w * 0.3, y: h * 0.28), CGPoint(x: w * 0.37, y: h * 0.4), CGPoint(x: w * 0.3, y: h * 0.37), CGPoint(x: w * 0.24, y: h * 0.4)])
                context.fill(snow, with: .color(.white))
                hills([(0, 0.8), (0.5, 0.74), (1, 0.82)], Color(red: 0.18, green: 0.36, blue: 0.29))
            case .beach:
                gradient([Color(red: 0.55, green: 0.85, blue: 1), Color(red: 0.8, green: 0.94, blue: 1)], rect(0, 0.55))
                gradient([Color(red: 0.05, green: 0.6, blue: 0.78), Color(red: 0.2, green: 0.75, blue: 0.82)], rect(0.5, 0.8))
                sun(0.8, 0.2, 0.07, Color(red: 1, green: 0.97, blue: 0.8))
                hills([(0, 0.76), (0.5, 0.7), (1, 0.78)], Color(red: 0.95, green: 0.85, blue: 0.64))
            case .city:
                gradient([Color(red: 0.08, green: 0.1, blue: 0.27), Color(red: 0.2, green: 0.2, blue: 0.45)], rect(0, 1))
                sun(0.78, 0.18, 0.05, Color(red: 0.96, green: 0.94, blue: 0.8))
                for (x, top, bw) in [(0.04, 0.42, 0.15), (0.21, 0.3, 0.13), (0.36, 0.5, 0.17), (0.55, 0.24, 0.13), (0.7, 0.46, 0.22)] {
                    context.fill(Path(CGRect(x: w * x, y: h * top, width: w * bw, height: h)), with: .color(Color(red: 0.18, green: 0.22, blue: 0.44)))
                    for row in 0..<8 {
                        let lit = (row + Int(x * 100)) % 3 != 0
                        context.fill(Path(CGRect(x: w * (x + 0.02), y: h * (top + 0.05 + Double(row) * 0.06), width: w * (bw - 0.04), height: h * 0.025)),
                                     with: .color(lit ? Color(red: 1, green: 0.84, blue: 0.42) : Color(red: 0.29, green: 0.34, blue: 0.6)))
                    }
                }
            case .dunes:
                gradient([Color(red: 1, green: 0.9, blue: 0.76), Color(red: 1, green: 0.82, blue: 0.66)], rect(0, 1))
                sun(0.3, 0.3, 0.1, Color(red: 1, green: 0.96, blue: 0.86))
                hills([(0, 0.62), (0.35, 0.48), (0.7, 0.6), (1, 0.54)], Color(red: 0.94, green: 0.66, blue: 0.41))
                hills([(0, 0.8), (0.4, 0.68), (1, 0.82)], Color(red: 0.85, green: 0.47, blue: 0.29))
            case .flowers:
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 1, green: 0.86, blue: 0.9)))
                for (x, y, color) in [(0.3, 0.4, Color(red: 1, green: 0.44, blue: 0.57)), (0.64, 0.56, Color(red: 1, green: 0.62, blue: 0.42)),
                                      (0.44, 0.76, Color(red: 0.78, green: 0.42, blue: 1))] {
                    for petal in 0..<5 {
                        var ctx = context
                        ctx.translateBy(x: w * x, y: h * y)
                        ctx.rotate(by: .degrees(Double(petal) * 72))
                        ctx.fill(Path(ellipseIn: CGRect(x: -w * 0.06, y: -w * 0.2, width: w * 0.12, height: w * 0.17)), with: .color(color))
                    }
                    sun(x, y, 0.045, Color(red: 1, green: 0.89, blue: 0.48))
                }
            }
        }
    }

    @MainActor func image(width: CGFloat, height: CGFloat) -> NSImage {
        let renderer = ImageRenderer(content: view.frame(width: width, height: height))
        renderer.scale = 2
        return renderer.nsImage ?? NSImage(size: NSSize(width: width, height: height))
    }
}

/// The files the demo drops in, made fresh in the demo's own folder.
@MainActor
enum DemoFiles {
    static let folder = AppPaths.support.appending(path: "Desk")

    static func jpeg(_ art: DemoArt, named name: String, portrait: Bool = false) -> URL {
        let url = folder.appending(path: name)
        let image = art.image(width: portrait ? 900 : 1200, height: portrait ? 1200 : 900)
        if let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
           let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) {
            try? data.write(to: url)
        }
        return url
    }

    /// A PDF with a page of real text, so its icon shows the page.
    static func pdf(named name: String, title: String, lines: [String]) -> URL {
        let url = folder.appending(path: name)
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else { return url }
        context.beginPDFPage(nil)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        (title as NSString).draw(at: NSPoint(x: 60, y: 700), withAttributes: [.font: NSFont.boldSystemFont(ofSize: 34)])
        for (i, line) in lines.enumerated() {
            (line as NSString).draw(at: NSPoint(x: 60, y: 640 - CGFloat(i) * 30),
                                    withAttributes: [.font: NSFont.systemFont(ofSize: 17), .foregroundColor: NSColor.darkGray])
        }
        context.setFillColor(NSColor.systemRed.cgColor)
        context.fill(CGRect(x: 60, y: 300, width: 492, height: 6))
        NSGraphicsContext.restoreGraphicsState()
        context.endPDFPage()
        context.closePDF()
        return url
    }

    /// A screenshot of `view`, marked the way macOS marks its own, so Cubby files it under
    /// Screenshots.
    static func screenshot<V: View>(of view: V, size: CGSize, named name: String) -> (URL, NSImage) {
        let url = folder.appending(path: name)
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = 2
        let image = renderer.nsImage ?? NSImage(size: size)
        if let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
           let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: url)
            let mark: [UInt8] = Array("bplist00\u{9}\u{8}\0\0\0\0\0\0\u{1}\u{1}\0\0\0\0\0\0\0\u{1}\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\u{9}".utf8)
            setxattr(url.path, "com.apple.metadata:kMDItemIsScreenCapture", mark, mark.count, 0, 0)
        }
        return (url, image)
    }

    static func prepare() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }
}
