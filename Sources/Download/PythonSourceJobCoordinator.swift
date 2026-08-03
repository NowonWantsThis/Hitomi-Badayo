import Foundation

@MainActor
final class PythonSourceJobCoordinator {
    let queueStore: QueueStore
    let jobStateService: SourceExecutionJobStateService
    let executionService: PythonPluginExecutionService
    let nativeDelegationCoordinator:
        PythonNativeDelegationCoordinator

    init(
        queueStore: QueueStore,
        jobStateService: SourceExecutionJobStateService,
        executionService: PythonPluginExecutionService,
        nativeDelegationCoordinator:
            PythonNativeDelegationCoordinator
    ) {
        self.queueStore = queueStore
        self.jobStateService = jobStateService
        self.executionService = executionService
        self.nativeDelegationCoordinator =
            nativeDelegationCoordinator
    }

    func execute(
        _ match: PythonSourceExecutionMatch,
        sourceURL: URL,
        headers: HTTPRequestOptions,
        jobIndex: Int,
        configuredPythonPath: String,
        persist: @MainActor () -> Void,
        downloadResolved:
            (ResolvedDownload, URL) async throws -> Void,
        executeNativeResolver:
            () async -> Void
    ) async throws {
        updateJob(at: jobIndex) {
            $0 = jobStateService.resolving(
                $0,
                message:
                    "Running \(match.plugin.title)"
            )
        }
        persist()

        try await executionService.execute(
            match,
            sourceURL: sourceURL,
            headers: headers,
            configuredPythonPath:
                configuredPythonPath,
            downloadResolved: downloadResolved,
            delegateToNativeResolver: { feature in
                guard queueStore.jobs.indices
                      .contains(jobIndex) else {
                    return
                }
                let jobID =
                    queueStore.jobs[jobIndex].id
                await nativeDelegationCoordinator
                    .withNativeResolver(jobID: jobID) {
                        updateJob(at: jobIndex) {
                            $0 = jobStateService
                                .delegatingPythonToNative(
                                    $0,
                                    match: match,
                                    feature: feature
                                )
                        }
                        persist()
                        await executeNativeResolver()
                    }
            }
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
