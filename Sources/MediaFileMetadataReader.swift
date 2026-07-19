import AVFoundation
import AppKit
import CoreMedia
import Foundation
import QuickLookThumbnailing

enum MediaFileMetadataReader {
    static let supportedExtensions: Set<String> = [
        "mp4", "m4v", "mov", "webm", "mkv", "avi", "wmv", "flv",
        "mp3", "m4a", "aac", "flac", "wav", "ogg", "opus"
    ]
    static let supportedThumbnailExtensions: Set<String> = [
        "mp4", "m4v", "mov", "webm", "mkv", "avi", "wmv", "flv", "ts"
    ]

    static func canReadDuration(for url: URL) -> Bool {
        guard url.isFileURL else { return false }
        return supportedExtensions.contains(url.pathExtension.lowercased())
    }

    static func durationSeconds(for url: URL) async -> Double? {
        guard canReadDuration(for: url) else { return nil }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            return nil
        }

        let asset = AVURLAsset(url: url)
        do {
            let duration = try await asset.load(.duration)
            let seconds = CMTimeGetSeconds(duration)
            guard seconds.isFinite, seconds > 0 else { return nil }
            return seconds
        } catch {
            return nil
        }
    }

    static func thumbnailJPEGData(for url: URL, maxPixelSize: CGFloat = 360) async -> Data? {
        guard url.isFileURL,
              supportedThumbnailExtensions.contains(url.pathExtension.lowercased()) else {
            return nil
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            return nil
        }

        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPixelSize, height: maxPixelSize)
        generator.requestedTimeToleranceBefore = .positiveInfinity
        generator.requestedTimeToleranceAfter = .positiveInfinity

        let duration = try? await asset.load(.duration)
        let seconds = duration.map(CMTimeGetSeconds) ?? 0
        for thumbnailTime in thumbnailTimes(durationSeconds: seconds) {
            if let data = await thumbnailJPEGData(from: generator, at: thumbnailTime) {
                return data
            }
        }
        return await quickLookThumbnailJPEGData(for: url, maxPixelSize: maxPixelSize)
    }

    static func metadataByAddingDuration(
        to metadata: [String: String],
        seconds: Double?,
        source: String = "local-file"
    ) -> [String: String] {
        guard let seconds, seconds.isFinite, seconds > 0 else {
            return DownloadMetadata.clean(metadata)
        }

        var updated = metadata
        if updated["duration_seconds"]?.trimmed.isEmpty ?? true {
            updated["duration_seconds"] = compactNumber(seconds)
        }
        if updated["duration"]?.trimmed.isEmpty ?? true {
            updated["duration"] = compactNumber(seconds)
        }
        if updated["duration_source"]?.trimmed.isEmpty ?? true {
            updated["duration_source"] = source
        }
        return DownloadMetadata.clean(updated)
    }

    private static func compactNumber(_ value: Double) -> String {
        guard value.isFinite else { return "" }
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(format: "%.3f", value)
            .replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\.$"#, with: "", options: .regularExpression)
    }

    private static func thumbnailTimes(durationSeconds: Double) -> [CMTime] {
        let zero = CMTime.zero
        guard durationSeconds.isFinite, durationSeconds > 0 else {
            return [zero]
        }
        let preferred = min(max(durationSeconds * 0.08, 0.15), min(durationSeconds, 3.0))
        let fallback = min(durationSeconds, 1.0)
        var seen = Set<Int64>()
        return [preferred, 0, fallback].compactMap { seconds in
            let time = CMTime(seconds: seconds, preferredTimescale: 600)
            guard seen.insert(time.value).inserted else { return nil }
            return time
        }
    }

    private static func quickLookThumbnailJPEGData(for url: URL, maxPixelSize: CGFloat) async -> Data? {
        let size = CGSize(width: maxPixelSize, height: maxPixelSize)
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: size,
            scale: NSScreen.main?.backingScaleFactor ?? 2,
            representationTypes: .thumbnail
        )

        return await withCheckedContinuation { continuation in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
                guard let image = representation?.cgImage else {
                    continuation.resume(returning: nil)
                    return
                }
                let bitmap = NSBitmapImageRep(cgImage: image)
                continuation.resume(
                    returning: bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.78])
                )
            }
        }
    }

    private static func thumbnailJPEGData(from generator: AVAssetImageGenerator, at time: CMTime) async -> Data? {
        await withCheckedContinuation { continuation in
            generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { _, image, _, result, _ in
                guard result == .succeeded, let image else {
                    continuation.resume(returning: nil)
                    return
                }
                let bitmap = NSBitmapImageRep(cgImage: image)
                continuation.resume(
                    returning: bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.78])
                )
            }
        }
    }
}
