import Foundation

enum SourceJobStartHookOutcome {
    case prepared(DownloadJob)
    case failed(DownloadExecutionFailureDisposition)
}

@MainActor
final class SourceJobStartHookPipeline {
    let jobApplicationService:
        PythonHookJobApplicationService
    let failurePolicy:
        DownloadExecutionFailurePolicy

    init(
        jobApplicationService:
            PythonHookJobApplicationService,
        failurePolicy:
            DownloadExecutionFailurePolicy
    ) {
        self.jobApplicationService =
            jobApplicationService
        self.failurePolicy = failurePolicy
    }

    func prepare(
        _ job: DownloadJob,
        runHooks:
            @MainActor (
                PythonHookContext
            ) async throws -> PythonHookContext
    ) async -> SourceJobStartHookOutcome {
        do {
            let sourceURL =
                URL(string: job.source.trimmed)
            let initialContext =
                PythonScriptBridge.hookContext(
                    job: job,
                    sourceURL: sourceURL
                )
            let hookedContext =
                try await runHooks(initialContext)
            return .prepared(
                jobApplicationService.applying(
                    hookedContext,
                    to: job
                )
            )
        } catch {
            return .failed(
                failurePolicy.disposition(for: error)
            )
        }
    }
}
