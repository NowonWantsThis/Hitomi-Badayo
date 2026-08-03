import Foundation

@MainActor
final class SourceResolverJobContextService {
    let queueStore: QueueStore
    let progressJobStateService:
        SourceResolverProgressJobStateService
    let authenticationDispatchService:
        SourceResolverAuthenticationDispatchService

    init(
        queueStore: QueueStore,
        progressJobStateService:
            SourceResolverProgressJobStateService,
        authenticationDispatchService:
            SourceResolverAuthenticationDispatchService
    ) {
        self.queueStore = queueStore
        self.progressJobStateService =
            progressJobStateService
        self.authenticationDispatchService =
            authenticationDispatchService
    }

    func makeContext(
        jobIndex: Int,
        language: AppInterfaceLanguage,
        persist:
            @escaping @MainActor () -> Void,
        authenticationActions:
            SourceResolverAuthenticationActions
    ) -> SourceResolverExecutionContext {
        let jobID = queueStore.jobs.indices
            .contains(jobIndex)
            ? queueStore.jobs[jobIndex].id
            : nil
        return SourceResolverExecutionContext(
            ensureActive: { [weak self] in
                guard let self,
                      self.queueStore.jobs.indices
                      .contains(jobIndex),
                      self.queueStore.jobs[jobIndex]
                      .status != .cancelled else {
                    throw CancellationError()
                }
            },
            reportStage: { [weak self] message in
                guard let self,
                      let jobID,
                      let currentIndex =
                        self.queueStore.jobs
                        .firstIndex(
                            where: {
                                $0.id == jobID
                            }
                        ),
                      self.queueStore.jobs[
                        currentIndex
                      ].status != .cancelled,
                      self.updateJob(
                        at: currentIndex,
                        {
                            $0.message = message
                        }
                      ) else {
                    return
                }
                persist()
            },
            reportCompletion: {
                [weak self] message in
                guard let self,
                      self.queueStore.jobs.indices
                      .contains(jobIndex),
                      self.queueStore.jobs[jobIndex]
                      .status != .cancelled,
                      self.updateJob(
                        at: jobIndex,
                        {
                            $0.message = message
                        }
                      ) else {
                    throw CancellationError()
                }
                persist()
            },
            reportProgress: {
                [weak self] progress in
                guard let self, let jobID else {
                    return
                }
                self.reportProgress(
                    progress,
                    jobID: jobID,
                    language: language,
                    persist: persist
                )
            },
            waitForAuthentication: {
                [weak self] request in
                guard let self else { return }
                await self
                    .waitForAuthentication(
                        request,
                        actions:
                            authenticationActions
                    )
            }
        )
    }

    func reportProgress(
        _ progress: SourceResolverExecutionProgress,
        jobID: UUID,
        language: AppInterfaceLanguage,
        persist: @MainActor () -> Void
    ) {
        guard let index = queueStore.jobs
            .firstIndex(where: { $0.id == jobID }),
              queueStore.jobs[index].status !=
                .cancelled else {
            return
        }
        let updated =
            progressJobStateService.applying(
                progress,
                to: queueStore.jobs[index],
                language: language
            )
        guard updateJob(
            at: index,
            { $0 = updated }
        ) else {
            return
        }
        persist()
    }

    func waitForAuthentication(
        _ request:
            SourceResolverAuthenticationRequest,
        actions:
            SourceResolverAuthenticationActions
    ) async {
        await authenticationDispatchService.wait(
            for: request,
            actions: actions
        )
    }

    private func updateJob(
        at index: Int,
        _ update: (inout DownloadJob) -> Void
    ) -> Bool {
        var jobs = queueStore.jobs
        guard jobs.indices.contains(index) else {
            return false
        }
        update(&jobs[index])
        queueStore.replaceJobs(with: jobs)
        return true
    }
}
