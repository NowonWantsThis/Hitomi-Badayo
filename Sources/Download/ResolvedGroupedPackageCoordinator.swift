import Foundation

struct ResolvedGroupedPackageOperations {
    var ensureDirectory: (URL) throws -> Void
    var existingYouTubeOutputs:
        (
            URL,
            Set<String>
        ) -> [String: URL]
    var mergedMetadata:
        (
            [String: String],
            [String: String]
        ) -> [String: String]
    var templatedFileName:
        (
            String,
            String,
            URL,
            Int?,
            Int,
            [String: String],
            String?
        ) -> String
    var recordingFileNameTemplate: () -> String
    var shouldUseRecordingFileNameTemplate:
        (
            DownloadPackageMode,
            [String: String]
        ) -> Bool
    var uniqueOutput: (URL, String) -> URL
    var temporaryStreamFolder: (URL, Int) -> URL
    var removeTemporaryFolder: (URL) -> Void
    var downloadAssets:
        (
            [ResolvedAsset],
            URL
        ) async throws -> Void
    var downloadAndConcatenate:
        (
            [ResolvedAsset],
            URL,
            URL
        ) async throws -> Void
    var remuxGroupedHLS:
        (
            URL,
            [String: String]
        ) async throws -> URL
    var downloadGroupedMux:
        (
            [ResolvedAsset],
            [ResolvedAsset],
            URL,
            Int,
            Int,
            URL
        ) async throws -> Void
    var applyModificationDate:
        (
            URL,
            URL,
            [String: String]
        ) -> Void
    var writeGalleryInfo:
        (
            [String: String],
            URL,
            URL
        ) -> Void
    var archiveFolder:
        (
            URL,
            URL,
            [String: String]
        ) throws -> Void
    var persist: @MainActor () -> Void
    var complete: @MainActor () async -> Void
}

@MainActor
final class ResolvedGroupedPackageCoordinator {
    let queueStore: QueueStore
    let jobStateService: ResolvedPackageJobStateService

    init(
        queueStore: QueueStore,
        jobStateService: ResolvedPackageJobStateService
    ) {
        self.queueStore = queueStore
        self.jobStateService = jobStateService
    }

    func execute(
        _ resolved: ResolvedDownload,
        fileAssetIndexes: [Int],
        concatenations: [ResolvedConcatenationGroup],
        muxes: [ResolvedMuxGroup],
        root: URL,
        folderName: String,
        sourceURL: URL,
        jobIndex: Int,
        operations: ResolvedGroupedPackageOperations
    ) async throws {
        guard queueStore.jobs.indices.contains(jobIndex) else {
            return
        }
        try validatePlan(
            resolved,
            fileAssetIndexes: fileAssetIndexes,
            concatenations: concatenations,
            muxes: muxes
        )

        let folder = AppPaths.directoryURL(
            in: root,
            name: folderName
        )
        try operations.ensureDirectory(folder)
        var jobs = queueStore.jobs
        jobs[jobIndex] = jobStateService.preparingGroupedPackage(
            jobs[jobIndex],
            outputFolder: folder
        )
        queueStore.replaceJobs(with: jobs)
        operations.persist()

        let youtubeCollectionIDs = collectionItemIDs(
            in: resolved
        )
        let existingYouTubeOutputs =
            operations.existingYouTubeOutputs(
                folder,
                youtubeCollectionIDs
            )
        let ordinals = outputOrdinals(
            fileAssetIndexes: fileAssetIndexes,
            concatenations: concatenations,
            muxes: muxes
        )

        try await executeDirectFiles(
            resolved,
            fileAssetIndexes: fileAssetIndexes,
            fileOrdinals: ordinals.files,
            outputCount: ordinals.count,
            folder: folder,
            sourceURL: sourceURL,
            jobIndex: jobIndex,
            existingYouTubeOutputs: existingYouTubeOutputs,
            operations: operations
        )
        try await executeConcatenations(
            resolved,
            concatenations: concatenations,
            groupOrdinals: ordinals.concatenations,
            outputCount: ordinals.count,
            folder: folder,
            sourceURL: sourceURL,
            jobIndex: jobIndex,
            existingYouTubeOutputs: existingYouTubeOutputs,
            operations: operations
        )
        try await executeMuxes(
            resolved,
            muxes: muxes,
            muxOrdinals: ordinals.muxes,
            outputCount: ordinals.count,
            folder: folder,
            sourceURL: sourceURL,
            jobIndex: jobIndex,
            existingYouTubeOutputs: existingYouTubeOutputs,
            operations: operations
        )

        guard queueStore.jobs.indices.contains(jobIndex) else {
            return
        }
        operations.writeGalleryInfo(
            resolved.metadata,
            sourceURL,
            folder
        )
        try operations.archiveFolder(
            folder,
            sourceURL,
            resolved.metadata
        )
        jobs = queueStore.jobs
        jobs[jobIndex] = jobStateService.finishingFilePackage(
            jobs[jobIndex]
        )
        queueStore.replaceJobs(with: jobs)
        await operations.complete()
    }

    private func validatePlan(
        _ resolved: ResolvedDownload,
        fileAssetIndexes: [Int],
        concatenations: [ResolvedConcatenationGroup],
        muxes: [ResolvedMuxGroup]
    ) throws {
        let groupedIndexes = concatenations.flatMap(\.assetIndexes)
        let muxedIndexes = muxes.flatMap {
            $0.videoAssetIndexes + $0.audioAssetIndexes
        }
        let claimedIndexes =
            fileAssetIndexes + groupedIndexes + muxedIndexes
        guard !concatenations.isEmpty || !muxes.isEmpty,
              concatenations.allSatisfy({ !$0.assetIndexes.isEmpty }),
              muxes.allSatisfy({
                  !$0.videoAssetIndexes.isEmpty &&
                      !$0.audioAssetIndexes.isEmpty
              }),
              claimedIndexes.count == resolved.assets.count,
              Set(claimedIndexes).count == resolved.assets.count,
              claimedIndexes.allSatisfy({
                  resolved.assets.indices.contains($0)
              }) else {
            throw NativeDownloadError.unsupported(
                "Invalid grouped stream download plan."
            )
        }
    }

    private func collectionItemIDs(
        in resolved: ResolvedDownload
    ) -> Set<String> {
        guard resolved.metadata["extractor"] ==
            "youtube_collection_native" else {
            return []
        }
        return Set(
            resolved.assets.compactMap { asset in
                let id = asset.metadata[
                    "collection_item_id"
                ]?.trimmed ?? ""
                return id.isEmpty ? nil : id
            }
        )
    }

    private func outputOrdinals(
        fileAssetIndexes: [Int],
        concatenations: [ResolvedConcatenationGroup],
        muxes: [ResolvedMuxGroup]
    ) -> (
        files: [Int: Int],
        concatenations: [Int: Int],
        muxes: [Int: Int],
        count: Int
    ) {
        var outputs:
            [(
                firstAssetIndex: Int,
                fileAssetIndex: Int?,
                concatenationIndex: Int?,
                muxIndex: Int?
            )] = fileAssetIndexes.map {
                ($0, $0, nil, nil)
            }
        outputs.append(
            contentsOf:
                concatenations.enumerated().compactMap {
                    index,
                    group in
                    guard let first = group.assetIndexes.first else {
                        return nil
                    }
                    return (first, nil, index, nil)
                }
        )
        outputs.append(
            contentsOf:
                muxes.enumerated().compactMap {
                    index,
                    group in
                    guard let first =
                        (
                            group.videoAssetIndexes +
                                group.audioAssetIndexes
                        ).min() else {
                        return nil
                    }
                    return (first, nil, nil, index)
                }
        )
        outputs.sort {
            $0.firstAssetIndex < $1.firstAssetIndex
        }

        var fileOrdinals: [Int: Int] = [:]
        var concatenationOrdinals: [Int: Int] = [:]
        var muxOrdinals: [Int: Int] = [:]
        for (offset, output) in outputs.enumerated() {
            if let index = output.fileAssetIndex {
                fileOrdinals[index] = offset + 1
            } else if let index = output.concatenationIndex {
                concatenationOrdinals[index] = offset + 1
            } else if let index = output.muxIndex {
                muxOrdinals[index] = offset + 1
            }
        }
        return (
            fileOrdinals,
            concatenationOrdinals,
            muxOrdinals,
            outputs.count
        )
    }

    private func executeDirectFiles(
        _ resolved: ResolvedDownload,
        fileAssetIndexes: [Int],
        fileOrdinals: [Int: Int],
        outputCount: Int,
        folder: URL,
        sourceURL: URL,
        jobIndex: Int,
        existingYouTubeOutputs: [String: URL],
        operations: ResolvedGroupedPackageOperations
    ) async throws {
        guard !fileAssetIndexes.isEmpty else {
            return
        }
        let directAssets = fileAssetIndexes.map {
            assetIndex -> ResolvedAsset in
            var asset = resolved.assets[assetIndex]
            let metadata = operations.mergedMetadata(
                resolved.metadata,
                asset.metadata
            )
            asset.filename = operations.templatedFileName(
                asset.filename,
                resolved.title,
                sourceURL,
                fileOrdinals[assetIndex],
                outputCount,
                metadata,
                nil
            )
            return asset
        }

        var pendingAssets: [ResolvedAsset] = []
        for asset in directAssets {
            let id = asset.metadata[
                "collection_item_id"
            ]?.trimmed ?? ""
            if let existing = existingYouTubeOutputs[id],
               !id.isEmpty {
                operations.applyModificationDate(
                    existing,
                    sourceURL,
                    resolved.metadata.merging(asset.metadata) {
                        _,
                        assetValue in assetValue
                    }
                )
                recordReusedOutput(
                    id: id,
                    output: existing,
                    assetCount: 1,
                    jobIndex: jobIndex,
                    persist: operations.persist
                )
            } else {
                pendingAssets.append(asset)
            }
        }
        guard !pendingAssets.isEmpty else {
            return
        }

        var jobs = queueStore.jobs
        jobs[jobIndex] = jobStateService.preparingGroupedDirectFiles(
            jobs[jobIndex],
            count: pendingAssets.count
        )
        queueStore.replaceJobs(with: jobs)
        operations.persist()
        try await operations.downloadAssets(
            pendingAssets,
            folder
        )
    }

    private func executeConcatenations(
        _ resolved: ResolvedDownload,
        concatenations: [ResolvedConcatenationGroup],
        groupOrdinals: [Int: Int],
        outputCount: Int,
        folder: URL,
        sourceURL: URL,
        jobIndex: Int,
        existingYouTubeOutputs: [String: URL],
        operations: ResolvedGroupedPackageOperations
    ) async throws {
        for (groupIndex, group) in concatenations.enumerated() {
            try Task.checkCancellation()
            guard queueStore.jobs.indices.contains(jobIndex) else {
                return
            }
            let streamAssets = group.assetIndexes.map {
                resolved.assets[$0]
            }
            let groupMetadata = DownloadMetadata.clean(
                resolved.metadata.merging(group.metadata) {
                    _,
                    groupValue in groupValue
                }
            )
            let collectionItemID = groupMetadata[
                "collection_item_id"
            ]?.trimmed ?? ""
            if let existing =
                existingYouTubeOutputs[collectionItemID],
               !collectionItemID.isEmpty {
                operations.applyModificationDate(
                    existing,
                    sourceURL,
                    groupMetadata
                )
                recordReusedOutput(
                    id: collectionItemID,
                    output: existing,
                    assetCount: group.assetIndexes.count,
                    jobIndex: jobIndex,
                    persist: operations.persist
                )
                continue
            }

            let outputMetadata = operations.mergedMetadata(
                groupMetadata,
                streamAssets.first?.metadata ?? [:]
            )
            let recordingTemplate =
                operations.recordingFileNameTemplate().trimmed
            let templateOverride =
                operations.shouldUseRecordingFileNameTemplate(
                    .concatenate(
                        outputFilename: group.outputFilename
                    ),
                    groupMetadata
                ) && !recordingTemplate.isEmpty
                ? recordingTemplate
                : nil
            let outputName = operations.templatedFileName(
                group.outputFilename,
                resolved.title,
                sourceURL,
                groupOrdinals[groupIndex],
                outputCount,
                outputMetadata,
                templateOverride
            )
            let output = operations.uniqueOutput(
                folder,
                outputName
            )
            let tempFolder = operations.temporaryStreamFolder(
                folder,
                groupIndex
            )
            try operations.ensureDirectory(tempFolder)
            defer {
                operations.removeTemporaryFolder(tempFolder)
            }

            var jobs = queueStore.jobs
            jobs[jobIndex] = jobStateService.preparingGroupedStream(
                jobs[jobIndex],
                index: groupIndex + 1,
                total: concatenations.count
            )
            queueStore.replaceJobs(with: jobs)
            operations.persist()
            try await operations.downloadAndConcatenate(
                streamAssets,
                tempFolder,
                output
            )
            let finalOutput =
                try await operations.remuxGroupedHLS(
                    output,
                    groupMetadata
                )
            operations.applyModificationDate(
                finalOutput,
                sourceURL,
                groupMetadata
            )
        }
    }

    private func executeMuxes(
        _ resolved: ResolvedDownload,
        muxes: [ResolvedMuxGroup],
        muxOrdinals: [Int: Int],
        outputCount: Int,
        folder: URL,
        sourceURL: URL,
        jobIndex: Int,
        existingYouTubeOutputs: [String: URL],
        operations: ResolvedGroupedPackageOperations
    ) async throws {
        for (muxIndex, group) in muxes.enumerated() {
            try Task.checkCancellation()
            guard queueStore.jobs.indices.contains(jobIndex) else {
                return
            }
            let videoAssets = group.videoAssetIndexes.map {
                resolved.assets[$0]
            }
            let audioAssets = group.audioAssetIndexes.map {
                resolved.assets[$0]
            }
            let groupMetadata = DownloadMetadata.clean(
                resolved.metadata.merging(group.metadata) {
                    _,
                    groupValue in groupValue
                }
            )
            let collectionItemID = groupMetadata[
                "collection_item_id"
            ]?.trimmed ?? ""
            if let existing =
                existingYouTubeOutputs[collectionItemID],
               !collectionItemID.isEmpty {
                operations.applyModificationDate(
                    existing,
                    sourceURL,
                    groupMetadata
                )
                recordReusedOutput(
                    id: collectionItemID,
                    output: existing,
                    assetCount:
                        group.videoAssetIndexes.count +
                        group.audioAssetIndexes.count,
                    jobIndex: jobIndex,
                    persist: operations.persist
                )
                continue
            }

            let outputMetadata = operations.mergedMetadata(
                groupMetadata,
                videoAssets.first?.metadata ??
                    audioAssets.first?.metadata ??
                    [:]
            )
            let outputName = operations.templatedFileName(
                group.outputFilename,
                resolved.title,
                sourceURL,
                muxOrdinals[muxIndex],
                outputCount,
                outputMetadata,
                nil
            )
            let output = operations.uniqueOutput(
                folder,
                outputName
            )
            try await operations.downloadGroupedMux(
                videoAssets,
                audioAssets,
                output,
                muxIndex,
                muxes.count,
                folder
            )
            operations.applyModificationDate(
                output,
                sourceURL,
                groupMetadata
            )
        }
    }

    private func recordReusedOutput(
        id: String,
        output: URL,
        assetCount: Int,
        jobIndex: Int,
        persist: @MainActor () -> Void
    ) {
        guard queueStore.jobs.indices.contains(jobIndex) else {
            return
        }
        var jobs = queueStore.jobs
        jobs[jobIndex] = jobStateService.recordingReusedYouTubeOutput(
            jobs[jobIndex],
            id: id,
            output: output,
            assetCount: assetCount
        )
        queueStore.replaceJobs(with: jobs)
        persist()
    }
}
