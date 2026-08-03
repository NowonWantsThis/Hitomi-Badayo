import Foundation

final class YTDLPJobStateService {
    func starting(
        _ job: DownloadJob,
        title: String,
        audioFormat: String?
    ) -> DownloadJob {
        var updated = job
        updated.title = title
        updated.total = 1
        updated.completed = 0
        updated.progress = 0
        updated.status = .downloading
        updated.message =
            audioFormat == nil
            ? "Running yt-dlp"
            : "Extracting MP3 audio"
        updated.metadata["tool"] = "yt-dlp"
        updated.metadata["handler"] = SiteRuleHandler.ytdlp.rawValue
        updated.metadata["ytdlp_active"] = "true"
        updated.metadata["transfer_active"] = "false"
        return updated
    }

    func clearingRuntimeState(_ job: DownloadJob) -> DownloadJob {
        var updated = job
        updated.metadata["ytdlp_active"] = "false"
        updated.metadata["transfer_active"] = "false"
        return updated
    }

    func finishing(
        _ job: DownloadJob,
        output: URL,
        metadata: [String: String],
        audioFormat: String?,
        wasInterrupted: Bool
    ) -> DownloadJob {
        var updated = job
        var completedMetadata = metadata
        if let audioFormat {
            completedMetadata["media_request"] = "audio"
            completedMetadata["audio_format"] = audioFormat
            completedMetadata["category"] = "audio"
        }

        updated.title = output.lastPathComponent
        updated.outputPath = output.path
        updated.metadata =
            ResolvedDownloadJobPreparationService
            .resolvedMetadataPreservingRuntimeState(
                completedMetadata,
                previous: job.metadata
            )
        updated.metadata["ytdlp_active"] = "false"
        updated.metadata["transfer_active"] = "false"

        if wasInterrupted {
            updated.metadata["was_live"] = "true"
            updated.metadata["live_active"] = "false"
            updated.metadata["live_polling"] = "false"
            updated.metadata["live_done"] = "true"
            updated.metadata["live_end_reason"] = "stopped"
            updated.metadata["live_partial_output"] = "true"
            updated.metadata.removeValue(
                forKey: "live_stop_requested"
            )
            updated.metadata.removeValue(
                forKey: "ytdlp_stop_requested"
            )
        }

        updated.completed = 1
        updated.progress = 1
        updated.status = .finished
        updated.message =
            wasInterrupted ? "Recording stopped" : "Done"
        return updated
    }
}
