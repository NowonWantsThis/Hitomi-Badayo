import Foundation

struct SourceJobExecutionRequestFactory {
    static let directDownloadOverrideMetadataKey =
        "original_direct_download"

    func makeRequest(
        job: DownloadJob,
        testingResolvedDownloadAvailable: Bool,
        pawchiveSiteAddresses: [String],
        pythonPluginAllowed: Bool
    ) -> SourceJobExecutionRequest {
        SourceJobExecutionRequest(
            source: job.source,
            directDownloadOverride:
                job.metadata[
                    Self.directDownloadOverrideMetadataKey
                ]?.trimmed.lowercased() == "file",
            originalInputType:
                job.metadata[OriginalInputType.metadataKey].flatMap {
                    OriginalInputType(rawValue: $0.lowercased())
                },
            testingResolvedDownloadAvailable:
                testingResolvedDownloadAvailable,
            pawchiveSiteAddresses: pawchiveSiteAddresses,
            isAudioExtractionRequest:
                job.metadata["media_request"]?.lowercased() == "audio",
            pythonPluginAllowed: pythonPluginAllowed
        )
    }
}
