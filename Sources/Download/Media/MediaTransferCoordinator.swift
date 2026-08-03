import Foundation

struct MediaTransferRequest {
    var assets: [ResolvedAsset]
    var folder: URL
    var jobID: UUID
    var jobSourceURL: URL?
    var jobMetadata: [String: String]
    var defaultConcurrency: Int
    var hlsRateLimitNanoseconds: UInt64
    var continueHLSSegmentFailures: Bool
    var skipExistingDownloads: Bool
    var imageConversionFormat: ImageConversionFormat
    var pythonRuntimePath: String
    var useYouTubeUploadModificationDate: Bool
    var modificationDateSpacingBase: Date?
    var nativeTransferProgressHandler: HTTPDownloadProgressHandler?
    var reportsNativeByteProgress: Bool
}

enum MediaTransferEvent {
    case skippedFailure(AssetDownloadFailure, total: Int)
    case progress(
        AssetDownloadBatchProgress,
        nativeDownloadedByteCount: Int64?
    )
    case failure(AssetDownloadFailure, total: Int)
    case deferredGalleryFailure(
        assetCount: Int,
        downloadedItemCount: Int,
        skippedFailureCount: Int
    )
    case applyingPythonSegmentTransform
    case skippedExisting(Int)
    case finishingNativeTransfer
}

@MainActor
final class MediaTransferCoordinator {
    let assetDownloadExecutor: AssetDownloadExecutor
    let assetTransferService: AssetTransferService
    let outputService: OutputService

    init(
        assetDownloadExecutor: AssetDownloadExecutor = AssetDownloadExecutor(),
        assetTransferService: AssetTransferService = AssetTransferService(),
        outputService: OutputService = OutputService()
    ) {
        self.assetDownloadExecutor = assetDownloadExecutor
        self.assetTransferService = assetTransferService
        self.outputService = outputService
    }

    func execute(
        _ request: MediaTransferRequest,
        onEvent: @escaping (MediaTransferEvent) -> Void
    ) async throws -> [URL] {
        let assets = request.assets
        let maximumConcurrentDownloads = MediaTransferPolicy
            .maximumConcurrency(
                defaultValue: request.defaultConcurrency,
                assets: assets
            )
        let remoteSegmentConcurrency = max(
            1,
            min(24, request.defaultConcurrency)
        )
        let shouldApplyYouTubeUploadDate =
            request.useYouTubeUploadModificationDate &&
            request.jobSourceURL.map {
                YTDLPBridge.isYouTubeSource(
                    $0,
                    metadata: request.jobMetadata
                )
            } == true

        defer {
            if request.reportsNativeByteProgress {
                onEvent(.finishingNativeTransfer)
            }
        }

        let configuration = AssetDownloadExecutionConfiguration(
            maximumConcurrentDownloads: maximumConcurrentDownloads,
            remoteSegmentConcurrency: remoteSegmentConcurrency,
            hlsRateLimitNanoseconds: request.hlsRateLimitNanoseconds,
            continueHLSSegmentFailures:
                request.continueHLSSegmentFailures,
            skipExistingDownloads: request.skipExistingDownloads,
            modificationDateSpacingBase:
                request.modificationDateSpacingBase,
            nativeTransferProgressHandler:
                request.nativeTransferProgressHandler
        )
        let operations = AssetDownloadExecutionOperations(
            outputFilename: { asset in
                self.outputService.outputFilename(
                    for: asset,
                    imageConversionFormat: request.imageConversionFormat
                )
            },
            originalModificationDate: { asset in
                MediaTransferPolicy.originalModificationDate(for: asset) ??
                    (shouldApplyYouTubeUploadDate
                        ? YTDLPBridge.youtubeUploadModificationDate(
                            from: request.jobMetadata.merging(
                                asset.metadata
                            ) { _, assetValue in assetValue }
                        )
                        : nil)
            },
            existingSkippableURL: {
                asset,
                folder,
                skipDuplicates,
                outputFilename in
                MediaTransferPolicy.existingSkippableURL(
                    asset,
                    in: folder,
                    skipDuplicates: skipDuplicates,
                    outputFilename: outputFilename
                )
            },
            download: {
                asset,
                destination,
                segmentConcurrency,
                progressHandler in
                try await self.assetTransferService.download(
                    asset,
                    to: destination,
                    remoteSegmentConcurrency: segmentConcurrency,
                    progressHandler: progressHandler
                )
            },
            convertDownloadedImage: { destination, asset in
                try self.outputService.convertDownloadedImageIfNeeded(
                    at: destination,
                    asset: asset,
                    format: request.imageConversionFormat
                )
            },
            applyModificationDate: { date, destination in
                try MediaTransferPolicy.applyModificationDate(
                    date,
                    to: destination
                )
            },
            applyModificationDateSpacing: {
                destination,
                baseDate,
                index in
                try MediaTransferPolicy
                    .applyOriginalModificationDateSpacing(
                        to: destination,
                        baseDate: baseDate,
                        index: index
                    )
            }
        )

        let outcome: AssetDownloadBatchOutcome
        do {
            outcome = try await assetDownloadExecutor.execute(
                assets: assets,
                to: request.folder,
                configuration: configuration,
                operations: operations,
                onProgress: { progress in
                    if let failure = progress.result.skippedFailure {
                        onEvent(
                            .skippedFailure(
                                failure,
                                total: assets.count
                            )
                        )
                    }
                    let byteCount: Int64?
                    if request.reportsNativeByteProgress,
                       let destination = progress.result.destination {
                        byteCount = MediaFileInspection.byteCount(
                            destination
                        )
                    } else {
                        byteCount = nil
                    }
                    onEvent(
                        .progress(
                            progress,
                            nativeDownloadedByteCount: byteCount
                        )
                    )
                }
            )
        } catch let failure as AssetDownloadFailure {
            onEvent(.failure(failure, total: assets.count))
            throw failure.underlying
        }

        let downloadedItemsByAssetIndex = outcome
            .destinationsByAssetIndex
        let downloadedItems = outcome.orderedDestinations
        if let deferredGalleryFailure = outcome.deferredGalleryFailure {
            onEvent(
                .failure(
                    deferredGalleryFailure,
                    total: assets.count
                )
            )
            onEvent(
                .deferredGalleryFailure(
                    assetCount: assets.count,
                    downloadedItemCount: downloadedItems.count,
                    skippedFailureCount: outcome.skippedFailureCount
                )
            )
            throw deferredGalleryFailure.underlying
        }

        let decoratedAssets = assets.enumerated().compactMap {
            index,
            asset -> (Int, PythonSegmentDecorator)? in
            guard let decorator = asset.pythonSegmentDecorator,
                  downloadedItemsByAssetIndex[index] != nil else {
                return nil
            }
            return (index, decorator)
        }
        let decoratorGroups = Dictionary(
            grouping: decoratedAssets,
            by: { $0.1 }
        )
        for (decorator, entries) in decoratorGroups {
            let paths = entries
                .sorted { $0.0 < $1.0 }
                .compactMap { downloadedItemsByAssetIndex[$0.0] }
            guard !paths.isEmpty else { continue }
            onEvent(.applyingPythonSegmentTransform)
            try await PythonScriptBridge(
                configuredPythonPath: request.pythonRuntimePath
            ).decorateSegments(paths, using: decorator)
        }

        if outcome.skippedExistingCount > 0 {
            onEvent(.skippedExisting(outcome.skippedExistingCount))
        }
        if downloadedItems.isEmpty && !assets.isEmpty {
            throw NativeDownloadError.noFiles
        }
        return downloadedItemsByAssetIndex
            .sorted { $0.key < $1.key }
            .map(\.value)
    }
}
