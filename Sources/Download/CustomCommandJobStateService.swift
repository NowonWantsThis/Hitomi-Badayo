import Foundation

final class CustomCommandJobStateService {
    func starting(
        _ job: DownloadJob,
        ruleName: String
    ) -> DownloadJob {
        var updated = job
        updated.title = ruleName
        updated.total = 1
        updated.completed = 0
        updated.progress = 0
        updated.status = .downloading
        updated.message = "Running \(ruleName)"
        return updated
    }

    func preparingRemoteAssets(
        _ job: DownloadJob,
        title: String,
        metadata: [String: String],
        total: Int,
        message: String,
        output: URL
    ) -> DownloadJob {
        var updated = job
        updated.title = title
        updated.metadata =
            ResolvedDownloadJobPreparationService
            .resolvedMetadataPreservingRuntimeState(
                metadata,
                previous: job.metadata
            )
        updated.total = total
        updated.completed = 0
        updated.progress = 0
        updated.message = message
        updated.outputPath = output.path
        return updated
    }

    func updatingMessage(
        _ job: DownloadJob,
        message: String
    ) -> DownloadJob {
        var updated = job
        updated.message = message
        return updated
    }

    func finishing(
        _ job: DownloadJob,
        title: String,
        output: URL,
        metadata: [String: String]
    ) -> DownloadJob {
        var updated = job
        updated.title = title
        updated.outputPath = output.path
        updated.metadata =
            ResolvedDownloadJobPreparationService
            .resolvedMetadataPreservingRuntimeState(
                metadata,
                previous: job.metadata
            )
        updated.completed = 1
        updated.progress = 1
        updated.status = .finished
        updated.message = "Done"
        return updated
    }
}
