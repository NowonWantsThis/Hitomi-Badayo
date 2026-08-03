import Foundation

@MainActor
final class SourceResolverPlanJobCoordinator {
    let queueStore: QueueStore
    let jobStateService: SourceExecutionJobStateService
    let planExecutionService:
        SourceResolverPlanExecutionService

    init(
        queueStore: QueueStore,
        jobStateService: SourceExecutionJobStateService,
        planExecutionService:
            SourceResolverPlanExecutionService
    ) {
        self.queueStore = queueStore
        self.jobStateService = jobStateService
        self.planExecutionService = planExecutionService
    }

    func execute(
        _ plan: SourceResolverExecutionPlan,
        originalURL: URL,
        jobIndex: Int,
        persist: @MainActor () -> Void,
        ytDLPCanResolve: () -> Bool,
        downloadResolved:
            (ResolvedDownload, URL) async throws -> Void,
        downloadWithYTDLP:
            (URL) async throws -> Void
    ) async throws {
        updateJob(at: jobIndex) {
            $0 = jobStateService.resolving(
                $0,
                message: plan.statusMessage
            )
        }
        persist()

        try await planExecutionService.execute(
            plan,
            originalURL: originalURL,
            ytDLPCanResolve: ytDLPCanResolve,
            updateSourceURL: { sourceURLOverride in
                guard queueStore.jobs.indices
                    .contains(jobIndex),
                      queueStore.jobs[jobIndex].status !=
                        .cancelled else {
                    throw CancellationError()
                }
                updateJob(at: jobIndex) {
                    $0.source =
                        sourceURLOverride.absoluteString
                }
                persist()
            },
            downloadResolved: downloadResolved,
            downloadWithYTDLP: downloadWithYTDLP
        )
    }

    private func updateJob(
        at index: Int,
        _ update: (inout DownloadJob) -> Void
    ) {
        var jobs = queueStore.jobs
        update(&jobs[index])
        queueStore.replaceJobs(with: jobs)
    }
}
