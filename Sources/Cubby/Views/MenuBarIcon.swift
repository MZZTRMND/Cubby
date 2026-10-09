import AppKit
import SwiftUI

/// The menu bar icon: the desktop folder drawn small, as a template image so macOS tints it
/// for light and dark menu bars.
enum MenuBarIcon {
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 19, height: 16), flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let back = FolderBackShape(cornerRadius: 2, tabRadius: 2, tabHeight: 2.5)
                .path(in: CGRect(x: 1.5, y: 1, width: 16, height: 12)).cgPath
            let front = FolderFrontShape(topRadius: 1.2, bottomRadius: 2.5, taper: 1)
                .path(in: CGRect(x: 0.5, y: 6, width: 18, height: 9)).cgPath
            context.addPath(back)
            context.fillPath()
            // A gap around the front, so it reads apart from the back.
            context.setBlendMode(.clear)
            context.setLineWidth(2.4)
            context.addPath(front)
            context.strokePath()
            context.setBlendMode(.normal)
            context.addPath(front)
            context.fillPath()
            return true
        }
        image.isTemplate = true
        return image
    }()
}
