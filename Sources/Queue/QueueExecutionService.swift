import Foundation

@MainActor
final class QueueExecutionService {
    typealias IsEnabled = @MainActor () -> Bool
    typealias NextJobID = @MainActor () -> UUID?
    typealias LaunchJob =
        @MainActor (UUID) -> Task<Void, Never>

    private let rescanDelayNanoseconds: UInt64

    init(
        rescanDelayNanoseconds: UInt64 =
            100_000_000
    ) {
        self.rescanDelayNanoseconds =
            rescanDelayNanoseconds
    }

    func runSequentially(
        isEnabled: @escaping IsEnabled,
        nextJobID: @escaping NextJobID,
        launchJob: @escaping LaunchJob
    ) async {
        while isEnabled(),
              let jobID = nextJobID() {
            if Task.isCancelled { return }
            let task = launchJob(jobID)
            await task.value
            if Task.isCancelled { return }
        }
    }

    func runConcurrently(
        taskLimit: Int,
        isEnabled: @escaping IsEnabled,
        reserveNextJobID:
            @escaping NextJobID,
        launchJob: @escaping LaunchJob
    ) async {
        await withTaskGroup(of: UUID?.self) {
            group in
            var runningCount = 0
            var rescanScheduled = false

            @MainActor
            func launchNextQueuedJob()
                async -> Bool {
                guard isEnabled(),
                      !Task.isCancelled,
                      let jobID =
                        reserveNextJobID() else {
                    return false
                }

                runningCount += 1
                let task = launchJob(jobID)
                group.addTask {
                    await task.value
                    return jobID
                }
                return true
            }

            func scheduleRescanIfNeeded() {
                guard runningCount > 0,
                      QueueScheduler
                        .availableSlotCount(
                            taskLimit: taskLimit,
                            runningCount:
                                runningCount
                        ) > 0,
                      !rescanScheduled,
                      !Task.isCancelled else {
                    return
                }
                rescanScheduled = true
                let delay =
                    rescanDelayNanoseconds
                group.addTask {
                    try? await Task.sleep(
                        nanoseconds: delay
                    )
                    return nil
                }
            }

            while QueueScheduler
                .availableSlotCount(
                    taskLimit: taskLimit,
                    runningCount: runningCount
                ) > 0 {
                guard
                    await launchNextQueuedJob()
                else {
                    break
                }
            }
            scheduleRescanIfNeeded()

            while runningCount > 0 {
                guard let event =
                    await group.next()
                else {
                    break
                }
                if event == nil {
                    rescanScheduled = false
                } else {
                    runningCount -= 1
                }

                if Task.isCancelled {
                    group.cancelAll()
                    break
                }

                while QueueScheduler
                    .availableSlotCount(
                        taskLimit: taskLimit,
                        runningCount:
                            runningCount
                    ) > 0 {
                    guard
                        await launchNextQueuedJob()
                    else {
                        break
                    }
                }
                scheduleRescanIfNeeded()
            }
            group.cancelAll()
        }
    }
}
