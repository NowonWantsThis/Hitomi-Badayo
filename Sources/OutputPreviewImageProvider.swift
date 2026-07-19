import AppKit
import Foundation
import ImageIO

@MainActor
final class OutputPreviewImageLoader: ObservableObject {
    @Published private(set) var image: NSImage?
    @Published private(set) var isLoading = true

    private var identity = ""
    private var generation = 0

    func load(_ file: OutputPreviewFile) async {
        let requestedIdentity = OutputPreviewImageProvider.cacheIdentity(for: file)
        if identity != requestedIdentity {
            image = nil
        }
        identity = requestedIdentity
        generation += 1
        let requestedGeneration = generation
        isLoading = true

        let loaded = await OutputPreviewImageProvider.image(for: file)
        guard !Task.isCancelled,
              identity == requestedIdentity,
              generation == requestedGeneration else { return }
        image = loaded
        isLoading = false
    }

    func unload() {
        generation += 1
        image = nil
        isLoading = false
    }

    func unloadAfterViewUpdate() {
        generation += 1
        let requestedGeneration = generation
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, self.generation == requestedGeneration else { return }
            self.image = nil
            self.isLoading = false
        }
    }
}

enum OutputPreviewImageProvider {
    static let maximumPixelSize = 2_048

    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 16
        cache.totalCostLimit = 64 * 1_024 * 1_024
        return cache
    }()

    static func cacheIdentity(for file: OutputPreviewFile) -> String {
        let sourcePath = file.isArchiveEntry ? file.containerPath : file.displayPath
        return "\(sourcePath)|\(file.relativePath)|\(file.byteCount)|\(file.modificationTime)"
    }

    static func image(for file: OutputPreviewFile) async -> NSImage? {
        guard file.isImage else { return nil }
        let identity = cacheIdentity(for: file)
        if let cached = cache.object(forKey: identity as NSString) {
            return cached
        }

        let loadTask = Task.detached(priority: .utility) {
            loadImage(for: file)
        }
        let loaded = await withTaskCancellationHandler {
            await loadTask.value
        } onCancel: {
            loadTask.cancel()
        }
        guard !Task.isCancelled, let loaded else { return nil }
        cache.setObject(loaded, forKey: identity as NSString, cost: imageCost(loaded))
        return loaded
    }

    static func purgeCache() {
        cache.removeAllObjects()
    }

    nonisolated static func loadImage(for file: OutputPreviewFile) -> NSImage? {
        guard !Task.isCancelled else { return nil }
        let data: Data
        do {
            if file.isArchiveEntry {
                data = try ZipArchiveReader.data(
                    forEntryNamed: file.relativePath,
                    in: URL(fileURLWithPath: file.containerPath)
                )
            } else {
                data = try Data(
                    contentsOf: URL(fileURLWithPath: file.displayPath),
                    options: [.mappedIfSafe]
                )
            }
        } catch {
            return nil
        }
        guard !Task.isCancelled else { return nil }
        let image = thumbnailImage(from: data, maximumPixelSize: maximumPixelSize)
        return Task.isCancelled ? nil : image
    }

    nonisolated static func thumbnailImage(from data: Data, maximumPixelSize: Int) -> NSImage? {
        guard !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maximumPixelSize),
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }

    private static func imageCost(_ image: NSImage) -> Int {
        let pixels = max(1, Int(image.size.width * image.size.height))
        return min(Int.max / 4, pixels * 4)
    }
}
