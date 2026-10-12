import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Downscaled PNG thumbnails, PNG conversion for pasted image data, and the image Quick
/// Actions.
enum ImageData {
    /// The image at `url` as `type`, scaled by `scale`, keeping its orientation and color
    /// profile. JPEG and HEIC are saved at high quality.
    static func convert(_ url: URL, to type: UTType, scale: Double = 1) -> Data? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, Int((Double(max(width, height)) * scale).rounded())),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

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
