import Foundation

struct DownloadQueueRunOutcome: Equatable {
    var finished: Int
    var failed: Int

    var hasResults: Bool {
        finished + failed > 0
    }
}

@MainActor
final class DownloadCoordinator {
    private var runningJobTasks: [UUID: Task<Void, Never>] = [:]
    private var scheduledRetryTasks: [UUID: Task<Void, Never>] = [:]
    private var processingJobIDs: Set<UUID> = []
    private var completionAlertedJobIDs: Set<UUID> = []
    private var queueRunFinishedJobIDs: Set<UUID> = []
    private var queueRunFailedJobIDs: Set<UUID> = []
    private var retrySnapshots: [UUID: DownloadJob] = [:]

    var hasProcessingJobs: Bool {
        !processingJobIDs.isEmpty
    }

    var runningJobCount: Int {
        runningJobTasks.count
    }

    var processingJobCount: Int {
        processingJobIDs.count
    }

    var scheduledRetryTaskCount: Int {
        scheduledRetryTasks.count
    }

    func hasRunningTask(for jobID: UUID) -> Bool {
        runningJobTasks[jobID] != nil
    }

    func isProcessing(_ jobID: UUID) -> Bool {
        processingJobIDs.contains(jobID)
    }

    func isActive(_ jobID: UUID) -> Bool {
        isProcessing(jobID) || hasRunningTask(for: jobID)
    }

    func hasScheduledRetryTask(for jobID: UUID) -> Bool {
        scheduledRetryTasks[jobID] != nil
    }

    func processingJobsAreDisjoint(with jobIDs: Set<UUID>) -> Bool {
        processingJobIDs.isDisjoint(with: jobIDs)
    }

    func resetOutcome(for jobID: UUID) {
        completionAlertedJobIDs.remove(jobID)
        queueRunFinishedJobIDs.remove(jobID)
        queueRunFailedJobIDs.remove(jobID)
    }

    func markJobFailed(_ jobID: UUID) {
        queueRunFailedJobIDs.insert(jobID)
    }

    @discardableResult
    func beginJobCompletion(_ jobID: UUID) -> Bool {
        guard completionAlertedJobIDs.insert(jobID).inserted else {
            return false
        }
        queueRunFinishedJobIDs.insert(jobID)
        return true
    }

    func clearCompletionAlert(for jobID: UUID) {
        completionAlertedJobIDs.remove(jobID)
    }

    var queueRunOutcome: DownloadQueueRunOutcome {
        DownloadQueueRunOutcome(
            finished: queueRunFinishedJobIDs.count,
            failed: queueRunFailedJobIDs.subtracting(queueRunFinishedJobIDs).count
        )
    }

    func resetQueueRunOutcome() {
        queueRunFinishedJobIDs.removeAll()
        queueRunFailedJobIDs.removeAll()
    }

    func storeRetrySnapshot(_ job: DownloadJob) {
        retrySnapshots[job.id] = job
    }

    func retrySnapshot(for jobID: UUID) -> DownloadJob? {
        retrySnapshots[jobID]
    }

    @discardableResult
    func removeRetrySnapshot(for jobID: UUID) -> DownloadJob? {
        retrySnapshots.removeValue(forKey: jobID)
    }

    @discardableResult
    func launchJob(
        id: UUID,
        operation: @escaping @MainActor () async -> Void,
        onFinish: @escaping @MainActor () -> Void = {}
    ) -> Task<Void, Never> {
        runningJobTasks[id]?.cancel()
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            self.processingJobIDs.insert(id)
            defer {
                self.processingJobIDs.remove(id)
                self.runningJobTasks.removeValue(forKey: id)
                onFinish()
            }
            await operation()
        }
        runningJobTasks[id] = task
        return task
    }

    @discardableResult
    func cancelJob(_ jobID: UUID) -> Bool {
        guard let task = runningJobTasks[jobID] else { return false }
        task.cancel()
        return true
    }

    @discardableResult
    func cancelAllJobs() -> Int {
        let tasks = Array(runningJobTasks.values)
        tasks.forEach { $0.cancel() }
        return tasks.count
    }

    @discardableResult
    func scheduleRetryTask(
        id: UUID,
        operation: @escaping @MainActor () async -> Void
    ) -> Task<Void, Never> {
        scheduledRetryTasks.removeValue(forKey: id)?.cancel()
        let task = Task { @MainActor in
            await operation()
        }
        scheduledRetryTasks[id] = task
        return task
    }

    @discardableResult
    func cancelScheduledRetryTask(_ jobID: UUID) -> Bool {
        guard let task = scheduledRetryTasks.removeValue(forKey: jobID) else {
            return false
        }
        task.cancel()
        return true
    }

    @discardableResult
    func cancelAllScheduledRetryTasks() -> Int {
        let tasks = Array(scheduledRetryTasks.values)
        tasks.forEach { $0.cancel() }
        scheduledRetryTasks.removeAll()
        return tasks.count
    }

    deinit {
        runningJobTasks.values.forEach { $0.cancel() }
        scheduledRetryTasks.values.forEach { $0.cancel() }
    }
}
