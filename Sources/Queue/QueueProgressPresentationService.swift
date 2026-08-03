import Foundation

struct QueueProgressPresentationSnapshot: Equatable {
    let activeJobs: [DownloadJob]
    let visibleJobs: [DownloadJob]
    let completedUnits: Int
    let totalUnits: Int
    let fraction: Double
    let statusText: String
}

enum QueueProgressPresentationService {
    static func snapshot(
        jobs: [DownloadJob]
    ) -> QueueProgressPresentationSnapshot {
        let activeJobs = jobs.filter {
            $0.status == .resolving || $0.status == .downloading
        }
        let visibleJobs = activeJobs.isEmpty
            ? Array(jobs.filter { $0.status != .finished }.prefix(12))
            : activeJobs
        let aggregate = jobs.reduce(
            into: (completed: 0, total: 0)
        ) { result, job in
            let jobUnits = units(for: job)
            result.completed += jobUnits.completed
            result.total += jobUnits.total
        }
        let fraction = aggregate.total > 0
            ? min(
                1,
                max(
                    0,
                    Double(aggregate.completed) / Double(aggregate.total)
                )
            )
            : 0
        let statusText: String
        if jobs.isEmpty {
            statusText = "No tasks"
        } else {
            let percent = Int((fraction * 100).rounded())
            let finishedCount = jobs.filter { $0.status == .finished }.count
            statusText =
                "\(percent)% [\(aggregate.completed)/\(aggregate.total)] · " +
                "\(activeJobs.count) active · " +
                "\(finishedCount)/\(jobs.count) finished"
        }

        return QueueProgressPresentationSnapshot(
            activeJobs: activeJobs,
            visibleJobs: visibleJobs,
            completedUnits: aggregate.completed,
            totalUnits: aggregate.total,
            fraction: fraction,
            statusText: statusText
        )
    }

    static func units(
        for job: DownloadJob
    ) -> (completed: Int, total: Int) {
        let total = max(1, job.total)
        switch job.status {
        case .finished, .failed, .cancelled:
            return (total, total)
        case .queued, .resolving:
            return (0, total)
        case .downloading:
            let clampedProgress = max(0, min(1, job.progress))
            let progressCompleted = Int(
                (clampedProgress * Double(total)).rounded(.down)
            )
            return (
                min(total, max(0, max(job.completed, progressCompleted))),
                total
            )
        }
    }
}
