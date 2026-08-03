import Foundation

@MainActor
final class GenericPageJobCoordinator {
    let queueStore: QueueStore
    let jobStateService: SourceExecutionJobStateService
    let executionService: GenericPageExecutionService

    init(
        queueStore: QueueStore,
        jobStateService: SourceExecutionJobStateService,
        executionService: GenericPageExecutionService
    ) {
        self.queueStore = queueStore
        self.jobStateService = jobStateService
        self.executionService = executionService
    }

    func execute(
        url: URL,
        headers: HTTPRequestOptions,
        jobIndex: Int,
        persist: @MainActor () -> Void,
        downloadResolved:
            (ResolvedDownload, URL) async throws -> Void,
        downloadDirect: (URL) async throws -> Void
    ) async throws {
        try await executionService.execute(
            url: url,
            headers: headers,
            reportStatus: { message in
                var jobs = queueStore.jobs
                jobs[jobIndex] =
                    jobStateService.resolving(
                        jobs[jobIndex],
                        message: message
                    )
                queueStore.replaceJobs(with: jobs)
                persist()
            },
            downloadResolved: downloadResolved,
            downloadDirect: downloadDirect
        )
    }
}
