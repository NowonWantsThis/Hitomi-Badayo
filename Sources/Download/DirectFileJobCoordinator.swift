import Foundation

@MainActor
final class DirectFileJobCoordinator {
    let queueStore: QueueStore
    let jobStateService: SourceExecutionJobStateService

    init(
        queueStore: QueueStore,
        jobStateService: SourceExecutionJobStateService
    ) {
        self.queueStore = queueStore
        self.jobStateService = jobStateService
    }

    func execute(
        _ url: URL,
        jobIndex: Int,
        persist: @MainActor () -> Void,
        download: (URL) async throws -> Void
    ) async throws {
        var jobs = queueStore.jobs
        jobs[jobIndex] =
            jobStateService.resolving(
                jobs[jobIndex],
                message:
                    "Preparing direct download"
            )
        queueStore.replaceJobs(with: jobs)
        persist()
        try await download(url)
    }
}
