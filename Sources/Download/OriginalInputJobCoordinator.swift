import Foundation

@MainActor
final class OriginalInputJobCoordinator {
    let queueStore: QueueStore
    let jobStateService: SourceExecutionJobStateService
    let executionService: OriginalInputExecutionService

    init(
        queueStore: QueueStore,
        jobStateService: SourceExecutionJobStateService,
        executionService: OriginalInputExecutionService
    ) {
        self.queueStore = queueStore
        self.jobStateService = jobStateService
        self.executionService = executionService
    }

    func execute(
        _ type: OriginalInputType,
        url: URL,
        headers: HTTPRequestOptions,
        options: OriginalInputExecutionOptions,
        context: SourceResolverExecutionContext,
        jobIndex: Int,
        persist: @MainActor () -> Void,
        downloadResolved:
            (ResolvedDownload, URL) async throws -> Void
    ) async throws {
        try await executionService.execute(
            type,
            url: url,
            headers: headers,
            options: options,
            context: context,
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
            downloadResolved: downloadResolved
        )
    }
}
