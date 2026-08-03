import AppKit
import Foundation
import ImageIO

struct StagedJobEditThumbnail {
    var pngData: Data
    var image: NSImage
}

final class JobEditThumbnailImageService {
    func stage(
        data: Data
    ) -> StagedJobEditThumbnail? {
        guard let pngData =
            normalizedPNGData(from: data),
          let image = NSImage(data: pngData) else {
            return nil
        }
        return StagedJobEditThumbnail(
            pngData: pngData,
            image: image
        )
    }

    func normalizedPNGData(
        from data: Data
    ) -> Data? {
        guard let source =
            CGImageSourceCreateWithData(
                data as CFData,
                nil
            ) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways:
                true,
            kCGImageSourceCreateThumbnailWithTransform:
                true,
            kCGImageSourceThumbnailMaxPixelSize:
                1_200,
            kCGImageSourceShouldCacheImmediately:
                true
        ]
        guard let image =
            CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                options as CFDictionary
            ) else {
            return nil
        }
        return NSBitmapImageRep(
            cgImage: image
        ).representation(
            using: .png,
            properties: [:]
        )
    }

    func pngData(
        from image: NSImage
    ) -> Data? {
        guard let tiff =
            image.tiffRepresentation,
          let representation =
            NSBitmapImageRep(data: tiff) else {
            return nil
        }
        return representation.representation(
            using: .png,
            properties: [:]
        )
    }
}
