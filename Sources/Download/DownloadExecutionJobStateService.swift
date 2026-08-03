import Foundation

final class DownloadExecutionJobStateService {
    func cancelling(
        _ job: DownloadJob
    ) -> DownloadJob {
        var updated = job
        updated.status = .cancelled
        updated.message = "Cancelled"
        updated.recordMessage(updated.message)
        return updated
    }

    func failing(
        _ job: DownloadJob,
        message: String,
        reaction: String? = nil
    ) -> DownloadJob {
        var updated = job
        updated.status = .failed
        updated.message = message
        updated.recordMessage(message)
        updated.metadata["last_error"] = message
        if let reaction = JobDisplayReaction(
            metadataValue: reaction
        ) {
            updated.metadata["reaction"] = reaction.rawValue
        }
        return updated
    }

    func queuingRecordingRetry(
        _ job: DownloadJob,
        nextRetryCount: Int,
        maximumRetryCount: Int,
        errorText: String,
        retryTimestamp: String
    ) -> DownloadJob {
        var updated = job
        updated.title = updated.source
        updated.status = .queued
        updated.progress = 0
        updated.completed = 0
        updated.total = 0
        updated.message =
            "Retrying recording (\(nextRetryCount) / " +
            "\(maximumRetryCount))"
        updated.outputPath = ""
        updated.metadata["recording_retry_count"] =
            String(nextRetryCount)
        updated.metadata["recording_retry_last_error"] =
            errorText
        updated.metadata["recording_retry_at"] =
            retryTimestamp
        updated.metadata["last_error"] = errorText
        return updated
    }

    func recordingRetryCount(
        from metadata: [String: String]
    ) -> Int {
        max(
            0,
            Int(
                metadata[
                    "recording_retry_count"
                ]?.trimmed ?? ""
            ) ?? 0
        )
    }
}
