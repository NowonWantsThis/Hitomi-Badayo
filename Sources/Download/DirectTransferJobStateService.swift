import Foundation

final class DirectTransferJobStateService {
    func preparingDirectTransfer(
        _ job: DownloadJob,
        title: String,
        metadata: [String: String],
        output: URL
    ) -> DownloadJob {
        preparingTransfer(
            job,
            title: title,
            metadata: metadata,
            total: 1,
            message: "Downloading file",
            output: output
        )
    }

    func restoringDirectTransfer(
        _ job: DownloadJob,
        title: String,
        metadata: [String: String],
        output: URL
    ) -> DownloadJob {
        var updated = preparingDirectTransfer(
            job,
            title: title,
            metadata: metadata,
            output: output
        )
        updated.progress = 0
        return updated
    }

    func preparingLocalFileTransfer(
        _ job: DownloadJob,
        title: String,
        metadata: [String: String],
        output: URL
    ) -> DownloadJob {
        preparingTransfer(
            job,
            title: title,
            metadata: metadata,
            total: 1,
            message: "Copying local file",
            output: output
        )
    }

    func preparingLocalFolderTransfer(
        _ job: DownloadJob,
        title: String,
        metadata: [String: String],
        output: URL,
        fileCount: Int
    ) -> DownloadJob {
        preparingTransfer(
            job,
            title: title,
            metadata: metadata,
            total: fileCount,
            message: "Copying local folder",
            output: output
        )
    }

    func preparingLocalHTMLScan(
        _ job: DownloadJob
    ) -> DownloadJob {
        var updated = job
        updated.status = .resolving
        updated.message = "Scanning local HTML media"
        return updated
    }

    func finishingTransfer(
        _ job: DownloadJob,
        title: String? = nil,
        output: URL? = nil,
        metadata: [String: String],
        completed: Int
    ) -> DownloadJob {
        var updated = job
        if let title {
            updated.title = title
        }
        if let output {
            updated.outputPath = output.path
        }
        updated.metadata =
            ResolvedDownloadJobPreparationService
            .resolvedMetadataPreservingRuntimeState(
                metadata,
                previous: job.metadata
            )
        updated.completed = completed
        updated.progress = 1
        updated.status = .finished
        updated.message = "Done"
        return updated
    }

    func skippingExistingOutput(
        _ job: DownloadJob,
        output: URL,
        metadata: [String: String],
        byteCount: Int?
    ) -> DownloadJob {
        var completedMetadata = metadata
        completedMetadata["skipped_existing_file"] = "true"
        completedMetadata["skip_reason"] =
            "existing_output_file"
        completedMetadata["filename"] =
            output.lastPathComponent
        completedMetadata["basename"] =
            output.deletingPathExtension().lastPathComponent
        completedMetadata["ext"] =
            output.pathExtension.lowercased()
        completedMetadata["byte_count"] =
            byteCount.map(String.init) ??
            completedMetadata["byte_count"] ??
            ""

        var updated = job
        updated.title = output.lastPathComponent
        updated.metadata =
            ResolvedDownloadJobPreparationService
            .resolvedMetadataPreservingRuntimeState(
                DownloadMetadata.clean(completedMetadata),
                previous: job.metadata
            )
        updated.total = 1
        updated.completed = 1
        updated.progress = 1
        updated.status = .finished
        updated.message = "Skipped existing file"
        updated.outputPath = output.path
        return updated
    }

    func preparingSegmentedTransfer(
        _ job: DownloadJob,
        output: URL,
        segmentCount: Int
    ) -> DownloadJob {
        var updated = job
        updated.title = output.lastPathComponent
        updated.outputPath = output.path
        updated.total = segmentCount
        updated.completed = 0
        updated.progress = 0
        updated.message =
            "Downloading 0 / \(segmentCount) parts"
        return updated
    }

    func recordingSegmentCompletion(
        _ job: DownloadJob
    ) -> DownloadJob {
        var updated = job
        updated.completed += 1
        updated.progress =
            Double(updated.completed) /
            Double(max(1, updated.total))
        updated.message =
            "Downloading \(updated.completed) / " +
            "\(updated.total) parts"
        return updated
    }

    func preparingSegmentJoin(
        _ job: DownloadJob
    ) -> DownloadJob {
        var updated = job
        updated.message = "Joining parts"
        return updated
    }

    private func preparingTransfer(
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
        updated.status = .downloading
        updated.message = message
        updated.outputPath = output.path
        return updated
    }
}
