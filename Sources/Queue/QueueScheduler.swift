import Foundation

@MainActor
final class QueueScheduler {
    private(set) var activeOrderIDs: [UUID]?

    var hasActiveOrder: Bool {
        activeOrderIDs != nil
    }

    nonisolated static func normalizedTaskLimit(_ value: Int) -> Int {
        max(1, min(12, value))
    }

    nonisolated static func availableSlotCount(
        taskLimit: Int,
        runningCount: Int
    ) -> Int {
        max(0, normalizedTaskLimit(taskLimit) - max(0, runningCount))
    }

    func beginRun(jobs: [DownloadJob]) {
        activeOrderIDs = jobs.map(\.id)
    }

    func orderedIndices(for jobs: [DownloadJob]) -> [Int] {
        guard let activeOrderIDs else {
            return Array(jobs.indices)
        }

        var indexByID: [UUID: Int] = [:]
        indexByID.reserveCapacity(jobs.count)
        for index in jobs.indices {
            indexByID[jobs[index].id] = index
        }

        var seen = Set<UUID>()
        var ordered: [Int] = []
        ordered.reserveCapacity(jobs.count)
        for id in activeOrderIDs where seen.insert(id).inserted {
            if let index = indexByID[id] {
                ordered.append(index)
            }
        }
        for index in jobs.indices where seen.insert(jobs[index].id).inserted {
            ordered.append(index)
        }
        return ordered
    }

    func orderedJobs(from jobs: [DownloadJob]) -> [DownloadJob] {
        orderedIndices(for: jobs).map { jobs[$0] }
    }

    func nextQueuedIndex(
        in jobs: [DownloadJob],
        serialGroup: (DownloadJob) -> String? = { _ in nil }
    ) -> Int? {
        let activeSerialGroups = Set(jobs.compactMap { job -> String? in
            guard job.status == .resolving || job.status == .downloading else {
                return nil
            }
            return serialGroup(job)
        })

        return orderedIndices(for: jobs).reversed().first { index in
            let job = jobs[index]
            guard job.status == .queued else { return false }
            guard let group = serialGroup(job) else { return true }
            return !activeSerialGroups.contains(group)
        }
    }

    func registerInsertedJobsAtTop(
        _ newJobs: [DownloadJob],
        among jobs: [DownloadJob]
    ) {
        guard !newJobs.isEmpty else { return }
        if activeOrderIDs == nil {
            beginRun(jobs: jobs)
        }

        let existingOrder = orderedJobs(from: jobs)
        let newIDs = Set(newJobs.map(\.id))
        var updatedOrder = existingOrder.map(\.id).filter { !newIDs.contains($0) }
        let insertionIndex = existingOrder.firstIndex(where: { !$0.isPinned })
            ?? updatedOrder.endIndex
        updatedOrder.insert(contentsOf: newJobs.map(\.id), at: insertionIndex)
        activeOrderIDs = updatedOrder
    }

    func setActiveOrder(_ ids: [UUID]) {
        activeOrderIDs = ids
    }

    func removeJobs(withIDs ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        activeOrderIDs?.removeAll { ids.contains($0) }
    }

    func finishRun(reordering jobs: [DownloadJob]) -> [DownloadJob]? {
        guard activeOrderIDs != nil else { return nil }
        let ordered = orderedJobs(from: jobs)
        activeOrderIDs = nil
        return ordered
    }
}
