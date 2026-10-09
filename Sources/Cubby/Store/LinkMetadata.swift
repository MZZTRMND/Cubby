import Foundation
import LinkPresentation

@MainActor
enum LinkMetadata {
    static func fetch(_ url: URL) async -> (title: String?, favicon: Data?) {
        let provider = LPMetadataProvider()
        provider.timeout = 10
        guard let metadata = try? await provider.startFetchingMetadata(for: url) else { return (nil, nil) }
        var favicon: Data?
        if let icon = metadata.iconProvider, let data = await icon.loadImageData() {
            favicon = ImageData.thumbnail(of: data, maxPixel: 64)
        }
        return (metadata.title, favicon)
    }
}
