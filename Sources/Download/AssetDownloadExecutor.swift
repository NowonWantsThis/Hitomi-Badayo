import Foundation

struct AssetDownloadFailure: Error {
    var index: Int
    var asset: ResolvedAsset
    var underlying: Error
}

struct AssetDownloadResult {
    var assetIndex: Int? = nil
    var destination: URL? = nil
    var skippedFailure: AssetDownloadFailure? = nil
    var skippedExisting: Bool = false
}

struct AssetDownloadBatchProgress {
    var result: AssetDownloadResult
    var completedCount: Int
    var skippedFailureCount: Int
    var skippedExistingCount: Int
}

struct AssetDownloadBatchOutcome {
    var destinationsByAssetIndex: [Int: URL]
    var skippedFailureCount: Int
    var skippedExistingCount: Int
    var deferredGalleryFailure: AssetDownloadFailure?

    var orderedDestinations: [URL] {
        destinationsByAssetIndex
            .sorted { $0.key < $1.key }
            .map(\.value)
    }
}

struct AssetDownloadExecutionConfiguration {
    var maximumConcurrentDownloads: Int
    var remoteSegmentConcurrency: Int
    var hlsRateLimitNanoseconds: UInt64
    var continueHLSSegmentFailures: Bool
    var skipExistingDownloads: Bool
    var modificationDateSpacingBase: Date?
    var nativeTransferProgressHandler: HTTPDownloadProgressHandler?
}

struct AssetDownloadExecutionOperations {
    var outputFilename: (ResolvedAsset) -> String
    var originalModificationDate: (ResolvedAsset) -> Date?
    var existingSkippableURL: (ResolvedAsset, URL, Bool, String) -> URL?
    var download: (
        ResolvedAsset,
        URL,
        Int,
        HTTPDownloadProgressHandler?
    ) async throws -> URL
    var convertDownloadedImage: (URL, ResolvedAsset) throws -> Void
    var applyModificationDate: (Date, URL) throws -> Void
    var applyModificationDateSpacing: (URL, Date, Int) throws -> Void
}

struct AssetDownloadExecutor {
    typealias Operation = (Int, ResolvedAsset) async throws -> AssetDownloadResult
    typealias ProgressHandler = @MainActor (AssetDownloadBatchProgress) -> Void

    func execute(
        assets: [ResolvedAsset],
        to folder: URL,
        configuration: AssetDownloadExecutionConfiguration,
        operations: AssetDownloadExecutionOperations,
        onProgress: @escaping ProgressHandler
    ) async throws -> AssetDownloadBatchOutcome {
        let rateLimiter = AssetRequestRateLimiter(
            delayNanoseconds: configuration.hlsRateLimitNanoseconds
        )
        return try await execute(
            assets: assets,
            maximumConcurrentDownloads: configuration.maximumConcurrentDownloads,
            operation: { offset, asset in
                try await executeAsset(
                    asset,
                    index: offset,
                    folder: folder,
                    configuration: configuration,
                    operations: operations,
                    rateLimiter: rateLimiter
                )
            },
            onProgress: onProgress
        )
    }

    func execute(
        assets: [ResolvedAsset],
        maximumConcurrentDownloads: Int,
        operation: @escaping Operation,
        onProgress: @escaping ProgressHandler
    ) async throws -> AssetDownloadBatchOutcome {
        let limit = AsyncSemaphore(value: max(1, maximumConcurrentDownloads))
        var destinationsByAssetIndex: [Int: URL] = [:]
        var skippedFailureCount = 0
        var skippedExistingCount = 0
        var deferredGalleryFailure: AssetDownloadFailure?
        var completedCount = 0

        try await withThrowingTaskGroup(of: AssetDownloadResult.self) { group in
            for (offset, asset) in assets.enumerated() {
                group.addTask {
                    try Task.checkCancellation()
                    return try await limit.withPermit {
                        try await operation(offset, asset)
                    }
                }
            }

            for try await result in group {
                try Task.checkCancellation()
                completedCount += 1
                if let destination = result.destination,
                   let assetIndex = result.assetIndex {
                    destinationsByAssetIndex[assetIndex] = destination
                }
                if let failure = result.skippedFailure {
                    skippedFailureCount += 1
                    if Self.canDeferGalleryFailure(failure.asset),
                       deferredGalleryFailure == nil {
                        deferredGalleryFailure = failure
                    }
                }
                if result.skippedExisting {
                    skippedExistingCount += 1
                }

                await onProgress(AssetDownloadBatchProgress(
                    result: result,
                    completedCount: completedCount,
                    skippedFailureCount: skippedFailureCount,
                    skippedExistingCount: skippedExistingCount
                ))
            }
        }

        return AssetDownloadBatchOutcome(
            destinationsByAssetIndex: destinationsByAssetIndex,
            skippedFailureCount: skippedFailureCount,
            skippedExistingCount: skippedExistingCount,
            deferredGalleryFailure: deferredGalleryFailure
        )
    }

    private static func canDeferGalleryFailure(_ asset: ResolvedAsset) -> Bool {
        asset.metadata["continue_asset_failures"] == "true"
    }

    private func executeAsset(
        _ asset: ResolvedAsset,
        index: Int,
        folder: URL,
        configuration: AssetDownloadExecutionConfiguration,
        operations: AssetDownloadExecutionOperations,
        rateLimiter: AssetRequestRateLimiter
    ) async throws -> AssetDownloadResult {
        let outputFilename = operations.outputFilename(asset)
        let assetModificationDate = operations.originalModificationDate(asset)
        if let existing = operations.existingSkippableURL(
            asset,
            folder,
            configuration.skipExistingDownloads,
            outputFilename
        ) {
            applyModificationDate(
                assetModificationDate,
                spacingBase: configuration.modificationDateSpacingBase,
                index: index,
                destination: existing,
                operations: operations
            )
            return AssetDownloadResult(
                assetIndex: index,
                destination: existing,
                skippedExisting: true
            )
        }

        let destination = AppPaths.uniqueFileURL(in: folder, filename: outputFilename)
        var downloadedDestination = destination
        do {
            if Self.usesM3U8RateLimit(asset) {
                try await rateLimiter.waitIfNeeded()
            }
            downloadedDestination = try await operations.download(
                asset,
                destination,
                configuration.remoteSegmentConcurrency,
                configuration.nativeTransferProgressHandler
            )
            try operations.convertDownloadedImage(downloadedDestination, asset)
            applyModificationDate(
                assetModificationDate,
                spacingBase: configuration.modificationDateSpacingBase,
                index: index,
                destination: downloadedDestination,
                operations: operations
            )
            return AssetDownloadResult(
                assetIndex: index,
                destination: downloadedDestination
            )
        } catch {
            try? FileManager.default.removeItem(at: destination)
            if downloadedDestination != destination {
                try? FileManager.default.removeItem(at: downloadedDestination)
            }
            let failure = AssetDownloadFailure(
                index: index + 1,
                asset: asset,
                underlying: error
            )
            if ((configuration.continueHLSSegmentFailures ||
                 asset.metadata["python_ignore_error"] == "true") &&
                Self.canContinueAfterHLSFailure(asset)) ||
                Self.canDeferGalleryFailure(asset) {
                return AssetDownloadResult(
                    assetIndex: index,
                    skippedFailure: failure
                )
            }
            throw failure
        }
    }

    private func applyModificationDate(
        _ date: Date?,
        spacingBase: Date?,
        index: Int,
        destination: URL,
        operations: AssetDownloadExecutionOperations
    ) {
        if let date {
            try? operations.applyModificationDate(date, destination)
        } else if let spacingBase {
            try? operations.applyModificationDateSpacing(destination, spacingBase, index)
        }
    }

    private static func usesM3U8RateLimit(_ asset: ResolvedAsset) -> Bool {
        let type = (asset.metadata["type"] ?? "").lowercased()
        let mediaType = (asset.metadata["media_type"] ?? "").lowercased()
        return type == "hls_segment" || type == "hls_map" ||
            mediaType == "hls_segment" || mediaType == "hls_map"
    }

    private static func canContinueAfterHLSFailure(_ asset: ResolvedAsset) -> Bool {
        let type = (asset.metadata["type"] ?? "").lowercased()
        let mediaType = (asset.metadata["media_type"] ?? "").lowercased()
        return type == "hls_segment" || mediaType == "hls_segment"
    }
}

private actor AssetRequestRateLimiter {
    private let delayNanoseconds: UInt64
    private var nextStartNanoseconds: UInt64 = DispatchTime.now().uptimeNanoseconds

    init(delayNanoseconds: UInt64) {
        self.delayNanoseconds = delayNanoseconds
    }

    func waitIfNeeded() async throws {
        guard delayNanoseconds > 0 else { return }
        let now = DispatchTime.now().uptimeNanoseconds
        if now < nextStartNanoseconds {
            try await Task.sleep(nanoseconds: nextStartNanoseconds - now)
            nextStartNanoseconds += delayNanoseconds
        } else {
            nextStartNanoseconds = now + delayNanoseconds
        }
    }
}
