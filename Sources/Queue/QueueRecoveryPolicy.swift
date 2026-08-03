import Foundation

struct QueueRecoveryPolicy {
    static func restorePersistedJob(_ job: DownloadJob) -> DownloadJob {
        var restored = job
        if restored.status == .resolving || restored.status == .downloading {
            restored.title = restored.source
            restored.status = .queued
            restored.progress = 0
            restored.completed = 0
            restored.total = 0
            restored.message = "Restored after relaunch"
            restored.outputPath = ""
        }
        return restored
    }

    static func restoreCancelledRetrySnapshot(_ snapshot: DownloadJob) -> DownloadJob {
        var restored = snapshot
        if restored.message.trimmed.isEmpty {
            restored.message = "Retry cancelled; restored previous state"
        }
        return restored
    }

    static func isRetryableIncompleteJob(
        _ job: DownloadJob,
        isFolded: Bool
    ) -> Bool {
        guard job.status != .resolving,
              job.status != .downloading,
              !isFolded else {
            return false
        }
        if job.status == .failed || job.status == .cancelled {
            return true
        }
        return job.status == .finished &&
            job.total > 0 &&
            job.completed < job.total
    }
}
