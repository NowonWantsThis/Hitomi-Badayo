import Foundation

struct ResolvedDownloadExecutionPreparation {
    var resolved: ResolvedDownload
    var root: URL
    var folderName: String
    var preparedJob: DownloadJob
}

@MainActor
final class ResolvedDownloadExecutionPreparationService {
    let rangeService: ResolvedDownloadRangeService
    let jobPreparationService:
        ResolvedDownloadJobPreparationService

    init(
        rangeService: ResolvedDownloadRangeService =
            ResolvedDownloadRangeService(),
        jobPreparationService:
            ResolvedDownloadJobPreparationService =
                ResolvedDownloadJobPreparationService()
    ) {
        self.rangeService = rangeService
        self.jobPreparationService = jobPreparationService
    }

    func prepare(
        job: DownloadJob,
        resolved initialResolved: ResolvedDownload,
        sourceURL: URL,
        previousMetadata: [String: String],
        applyHeaderRules: (ResolvedDownload) -> ResolvedDownload,
        outputRoot: (
            URL,
            [String: String]
        ) throws -> URL,
        folderName: (
            ResolvedDownload,
            URL
        ) -> String
    ) throws -> ResolvedDownloadExecutionPreparation {
        var resolved = applyHeaderRules(initialResolved)
        if resolved.metadata["niconico_live_session_token"] == nil,
           resolved.metadata["range_scope"] != "collection_items" {
            resolved = try rangeService.applying(
                job.rangeExpression,
                to: resolved
            )
        }
        resolved.metadata =
            QueueThumbnailProvider.metadataByAddingThumbnail(
                resolved.metadata,
                assets: resolved.assets
            )
        let root = try outputRoot(sourceURL, resolved.metadata)
        let plannedFolderName = folderName(resolved, sourceURL)
        let preparedJob = jobPreparationService.preparing(
            job,
            resolved: resolved,
            previousMetadata: previousMetadata
        )
        return ResolvedDownloadExecutionPreparation(
            resolved: resolved,
            root: root,
            folderName: plannedFolderName,
            preparedJob: preparedJob
        )
    }
}
