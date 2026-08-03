import Foundation

enum SourceJobExecutionOutcome {
    case succeeded
    case failed(
        error: Error,
        disposition: DownloadExecutionFailureDisposition
    )
}

@MainActor
final class SourceJobExecutionPipeline {
    let executor: any SourceJobExecuting
    let failurePolicy: DownloadExecutionFailurePolicy

    init(
        executor: any SourceJobExecuting,
        failurePolicy: DownloadExecutionFailurePolicy
    ) {
        self.executor = executor
        self.failurePolicy = failurePolicy
    }

    func execute(
        _ request: SourceJobExecutionRequest,
        capabilities: SourceJobExecutionCapabilities,
        actions: SourceJobExecutionActions,
        prepare: () async throws -> Void = {}
    ) async -> SourceJobExecutionOutcome {
        do {
            try await prepare()
            try await executor.execute(
                request,
                capabilities: capabilities,
                actions: actions
            )
            return .succeeded
        } catch {
            return .failed(
                error: error,
                disposition:
                    failurePolicy.disposition(for: error)
            )
        }
    }
}
