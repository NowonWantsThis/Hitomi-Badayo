import Foundation

struct ResolvedConcatenationPackageOperations {
    var temporaryFolder: (URL, String) -> URL
    var ensureDirectory: (URL) throws -> Void
    var mergedMetadata:
        (
            [String: String],
            [String: String]
        ) -> [String: String]
    var templatedOutputName:
        (
            String,
            String,
            URL,
            Int,
            [String: String],
            DownloadPackageMode
        ) -> String
    var uniqueOutput: (URL, String) -> URL
    var shouldPollLiveHLS: (ResolvedDownload) -> Bool
    var downloadLiveHLS:
        (
            ResolvedDownload,
            URL,
            URL
        ) async throws -> Void
    var downloadAndConcatenate:
        (
            [ResolvedAsset],
            URL,
            URL
        ) async throws -> Void
    var remuxHLS:
        (
            URL,
            ResolvedDownload
        ) async throws -> URL
    var applyModificationDate:
        (
            URL,
            URL,
            [String: String]
        ) -> Void
    var persist: @MainActor () -> Void
    var complete: @MainActor () async -> Void
}

@MainActor
final class ResolvedConcatenationPackageCoordinator {
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
        outputFilename: String,
        root: URL,
        folderName: String,
        sourceURL: URL,
        jobIndex: Int,
        operations: ResolvedConcatenationPackageOperations
    ) async throws {
        let folder = operations.temporaryFolder(
            root,
            folderName
        )
        try operations.ensureDirectory(folder)
        let outputMetadata = operations.mergedMetadata(
            resolved.metadata,
            resolved.assets.first?.metadata ?? [:]
        )
        let outputName = operations.templatedOutputName(
            outputFilename,
            resolved.title,
            sourceURL,
            resolved.assets.count,
            outputMetadata,
            resolved.packageMode
        )
        let output = operations.uniqueOutput(root, outputName)

        var jobs = queueStore.jobs
        jobs[jobIndex] = jobStateService.preparingConcatenation(
            jobs[jobIndex],
            output: output
        )
        queueStore.replaceJobs(with: jobs)
        operations.persist()

        if operations.shouldPollLiveHLS(resolved) {
            try await operations.downloadLiveHLS(
                resolved,
                folder,
                output
            )
        } else {
            try await operations.downloadAndConcatenate(
                resolved.assets,
                folder,
                output
            )
        }

        let finalOutput = try await operations.remuxHLS(
            output,
            resolved
        )
        operations.applyModificationDate(
            finalOutput,
            sourceURL,
            resolved.metadata
        )

        guard queueStore.jobs.indices.contains(jobIndex) else {
            return
        }
        jobs = queueStore.jobs
        jobs[jobIndex] = jobStateService.finishingConcatenation(
            jobs[jobIndex],
            output: finalOutput
        )
        queueStore.replaceJobs(with: jobs)
        await operations.complete()
    }
}
