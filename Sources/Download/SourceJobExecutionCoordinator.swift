import Foundation

@MainActor
final class SourceJobExecutionCoordinator {
    let requestFactory: SourceJobExecutionRequestFactory
    let pipeline: SourceJobExecutionPipeline

    init(
        requestFactory: SourceJobExecutionRequestFactory,
        pipeline: SourceJobExecutionPipeline
    ) {
        self.requestFactory = requestFactory
        self.pipeline = pipeline
    }

    func execute(
        job: DownloadJob,
        testingResolvedDownloadAvailable: Bool,
        pawchiveSiteAddresses: [String],
        pythonPluginAllowed: Bool,
        capabilities: () -> SourceJobExecutionCapabilities,
        actions: () -> SourceJobExecutionActions,
        prepare: () async throws -> Void = {},
        isManuallyFinished: () -> Bool,
        handleFailure: (
            Error,
            DownloadExecutionFailureDisposition
        ) -> Void
    ) async {
        let request = requestFactory.makeRequest(
            job: job,
            testingResolvedDownloadAvailable:
                testingResolvedDownloadAvailable,
            pawchiveSiteAddresses: pawchiveSiteAddresses,
            pythonPluginAllowed: pythonPluginAllowed
        )
        let outcome = await pipeline.execute(
            request,
            capabilities: capabilities(),
            actions: actions(),
            prepare: prepare
        )
        guard case .failed(let error, let disposition) = outcome,
              !isManuallyFinished() else {
            return
        }
        handleFailure(error, disposition)
    }
}
