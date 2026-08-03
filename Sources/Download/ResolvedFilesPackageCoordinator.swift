import Foundation

struct ResolvedFilesPackageOperations {
    var templatedAssets:
        (
            [ResolvedAsset],
            String,
            URL,
            [String: String]
        ) -> [ResolvedAsset]
    var shouldSpaceOriginalModificationDates:
        (
            URL,
            [String: String],
            [[String: String]]
        ) -> Bool
    var currentDate: () -> Date
    var ensureDirectory: (URL) throws -> Void
    var downloadAssets:
        (
            [ResolvedAsset],
            URL,
            Date?
        ) async throws -> [URL]
    var writeMergedText:
        (
            ResolvedTextMergePlan,
            [URL],
            URL
        ) throws -> URL
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
final class ResolvedFilesPackageCoordinator {
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
        root: URL,
        folderName: String,
        sourceURL: URL,
        jobIndex: Int,
        operations: ResolvedFilesPackageOperations
    ) async throws {
        let assets = operations.templatedAssets(
            resolved.assets,
            resolved.title,
            sourceURL,
            resolved.metadata
        )
        let modificationDateSpacingBase =
            operations.shouldSpaceOriginalModificationDates(
                sourceURL,
                resolved.metadata,
                assets.map(\.metadata)
            )
            ? operations.currentDate()
            : nil
        let folder = AppPaths.directoryURL(
            in: root,
            name: folderName
        )
        try operations.ensureDirectory(folder)

        var jobs = queueStore.jobs
        jobs[jobIndex] = jobStateService.preparingFilePackage(
            jobs[jobIndex],
            resolvedFilenames: assets.map(\.filename),
            outputFolder: folder
        )
        queueStore.replaceJobs(with: jobs)
        operations.persist()

        let downloadedAssets = try await operations.downloadAssets(
            assets,
            folder,
            modificationDateSpacingBase
        )
        guard queueStore.jobs.indices.contains(jobIndex) else {
            return
        }

        if let plan = resolved.textMergePlan {
            let merged = try operations.writeMergedText(
                plan,
                downloadedAssets,
                folder
            )
            jobs = queueStore.jobs
            jobs[jobIndex] = jobStateService.recordingTextMerge(
                jobs[jobIndex],
                output: merged,
                inputCount: downloadedAssets.count
            )
            queueStore.replaceJobs(with: jobs)
            operations.persist()
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

        guard queueStore.jobs.indices.contains(jobIndex) else {
            return
        }
        jobs = queueStore.jobs
        jobs[jobIndex] = jobStateService.finishingFilePackage(
            jobs[jobIndex]
        )
        queueStore.replaceJobs(with: jobs)
        await operations.complete()
    }
}
