import Combine
import Foundation

struct QueueStoreSnapshot: Equatable {
    var jobs: [DownloadJob]
    var queueGroups: [QueueGroup]
}

@MainActor
final class QueueStore: ObservableObject {
    @Published private(set) var jobs: [DownloadJob]
    @Published private(set) var queueGroups: [QueueGroup]
    @Published private(set) var queueFilterBookmarks: [QueueFilterBookmark]
    @Published private(set) var isRunning: Bool
    @Published private(set) var isQueueEnabled: Bool

    init(
        jobs: [DownloadJob] = [],
        queueGroups: [QueueGroup] = [],
        queueFilterBookmarks: [QueueFilterBookmark] = [],
        isRunning: Bool = false,
        isQueueEnabled: Bool = true
    ) {
        self.jobs = jobs
        self.queueGroups = queueGroups
        self.queueFilterBookmarks = queueFilterBookmarks
        self.isRunning = isRunning
        self.isQueueEnabled = isQueueEnabled
    }

    func setRunning(_ isRunning: Bool) {
        self.isRunning = isRunning
    }

    func setQueueEnabled(_ isQueueEnabled: Bool) {
        self.isQueueEnabled = isQueueEnabled
    }

    func persistenceSnapshot(
        orderedJobs: [DownloadJob]? = nil
    ) -> QueueStoreSnapshot {
        QueueStoreSnapshot(
            jobs: orderedJobs ?? jobs,
            queueGroups: queueGroups
        )
    }

    func replace(with snapshot: QueueStoreSnapshot) {
        jobs = snapshot.jobs
        queueGroups = snapshot.queueGroups
    }

    func replaceJobs(with replacement: [DownloadJob]) {
        jobs = replacement
    }

    func replaceQueueGroups(with replacement: [QueueGroup]) {
        queueGroups = replacement
    }

    func replaceQueueFilterBookmarks(
        with replacement: [QueueFilterBookmark]
    ) {
        queueFilterBookmarks = replacement
    }

    @discardableResult
    func upsertQueueFilterBookmark(
        title: String,
        query: String
    ) -> Bool {
        let normalizedQuery = query.lowercased()
        if let index = queueFilterBookmarks.firstIndex(where: {
            $0.query.lowercased() == normalizedQuery
        }) {
            queueFilterBookmarks[index].title = title
            queueFilterBookmarks[index].query = query
            return true
        }
        queueFilterBookmarks.insert(
            QueueFilterBookmark(title: title, query: query),
            at: 0
        )
        return false
    }

    @discardableResult
    func removeQueueFilterBookmark(id: UUID) -> Bool {
        let previousCount = queueFilterBookmarks.count
        queueFilterBookmarks.removeAll { $0.id == id }
        return queueFilterBookmarks.count != previousCount
    }

    func insertQueueGroups(
        _ newGroups: [QueueGroup],
        at requestedIndex: Int
    ) {
        guard !newGroups.isEmpty else { return }
        let insertionIndex = min(max(0, requestedIndex), queueGroups.endIndex)
        queueGroups.insert(contentsOf: newGroups, at: insertionIndex)
    }

    func appendQueueGroup(_ group: QueueGroup) {
        queueGroups.append(group)
    }

    @discardableResult
    func updateQueueGroup(
        id: UUID,
        _ update: (inout QueueGroup) -> Void
    ) -> QueueGroup? {
        guard let index = queueGroups.firstIndex(where: { $0.id == id }) else {
            return nil
        }
        var group = queueGroups[index]
        update(&group)
        queueGroups[index] = group
        return group
    }

    @discardableResult
    func removeQueueGroups(withIDs ids: Set<UUID>) -> [QueueGroup] {
        guard !ids.isEmpty else { return [] }
        let removedGroups = queueGroups.filter { ids.contains($0.id) }
        guard !removedGroups.isEmpty else { return [] }
        queueGroups.removeAll { ids.contains($0.id) }
        return removedGroups
    }

    @discardableResult
    func updateJob(
        id: UUID,
        _ update: (inout DownloadJob) -> Void
    ) -> Bool {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else {
            return false
        }
        var job = jobs[index]
        update(&job)
        jobs[index] = job
        return true
    }

    @discardableResult
    func updateJob(
        at index: Int,
        _ update: (inout DownloadJob) -> Void
    ) -> DownloadJob? {
        guard jobs.indices.contains(index) else { return nil }
        var job = jobs[index]
        update(&job)
        jobs[index] = job
        return job
    }

    @discardableResult
    func replaceJob(
        at index: Int,
        with replacement: DownloadJob
    ) -> Bool {
        guard jobs.indices.contains(index) else { return false }
        jobs[index] = replacement
        return true
    }

    @discardableResult
    func updateJobs(
        withIDs ids: Set<UUID>,
        _ update: (inout DownloadJob) -> Void
    ) -> Int {
        guard !ids.isEmpty else { return 0 }
        var updatedJobs = jobs
        var updateCount = 0
        for index in updatedJobs.indices where ids.contains(updatedJobs[index].id) {
            update(&updatedJobs[index])
            updateCount += 1
        }
        guard updateCount > 0 else { return 0 }
        jobs = updatedJobs
        return updateCount
    }

    func insertJobs(
        _ newJobs: [DownloadJob],
        at requestedIndex: Int
    ) {
        guard !newJobs.isEmpty else { return }
        let insertionIndex = min(max(0, requestedIndex), jobs.endIndex)
        jobs.insert(contentsOf: newJobs, at: insertionIndex)
    }

    @discardableResult
    func removeJobs(withIDs ids: Set<UUID>) -> [DownloadJob] {
        guard !ids.isEmpty else { return [] }
        let removedJobs = jobs.filter { ids.contains($0.id) }
        guard !removedJobs.isEmpty else { return [] }
        jobs.removeAll { ids.contains($0.id) }
        return removedJobs
    }
}
