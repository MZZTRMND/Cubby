import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Downscaled PNG thumbnails, and PNG conversion for pasted image data.
enum ImageData {
    static func thumbnail(of url: URL, maxPixel: Int = 400) -> Data? {
        CGImageSourceCreateWithURL(url as CFURL, nil).flatMap { thumbnail($0, maxPixel: maxPixel) }
    }

    static func thumbnail(of data: Data, maxPixel: Int = 400) -> Data? {
        CGImageSourceCreateWithData(data as CFData, nil).flatMap { thumbnail($0, maxPixel: maxPixel) }
    }

    static func png(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        return png(image)
    }

    private static func thumbnail(_ source: CGImageSource, maxPixel: Int) -> Data? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary).flatMap(png)
    }

    private static func png(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}
