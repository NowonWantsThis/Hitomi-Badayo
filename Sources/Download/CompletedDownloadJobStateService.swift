import Foundation

final class CompletedDownloadJobStateService {
    func recordingCompletionMessage(
        _ job: DownloadJob
    ) -> DownloadJob {
        var updated = job
        updated.recordMessage(updated.message)
        return updated
    }

    func recordingCompletionTimestamp(
        _ job: DownloadJob,
        completedAt: String
    ) -> DownloadJob {
        var updated = job
        updated.metadata["download_completed_at"] =
            completedAt
        return updated
    }

    func applyingResolvedFilenames(
        _ filenames: [String],
        to job: DownloadJob
    ) -> DownloadJob {
        var updated = job
        updated.resolvedFilenames = filenames
        return updated
    }

    func applyingLocalOutputByteCount(
        _ byteCount: Int64,
        to job: DownloadJob
    ) -> DownloadJob {
        var updated = job
        updated.metadata["byte_count"] =
            String(byteCount)
        updated.metadata["total_bytes"] =
            String(byteCount)
        updated.metadata["size_source"] = "local-output"
        return updated
    }

    func markingFinishedManually(
        _ job: DownloadJob,
        pausedActive: Bool,
        completedAt: String
    ) -> DownloadJob {
        var updated = job
        let total = max(
            1,
            updated.total,
            updated.completed
        )
        updated.status = .finished
        updated.progress = 1
        updated.completed = total
        updated.total = total
        updated.message = "Marked finished manually"
        updated.metadata.removeValue(forKey: "last_error")
        updated.metadata["manual_completion"] = "true"
        if pausedActive {
            updated.metadata["aria2_runtime_paused"] =
                "false"
        }
        updated.metadata["manual_completed_at"] =
            completedAt
        return updated
    }
}
