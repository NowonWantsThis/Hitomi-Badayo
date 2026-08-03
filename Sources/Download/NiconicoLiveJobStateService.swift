import Foundation

final class NiconicoLiveJobStateService {
    func starting(
        _ job: DownloadJob,
        output: URL,
        transcoding: Bool,
        startedAt: String
    ) -> DownloadJob {
        var updated = job
        updated.outputPath = output.path
        updated.message =
            transcoding
            ? "Recording and transcoding Niconico Live"
            : "Recording Niconico Live"
        updated.metadata["live_active"] = "true"
        updated.metadata["live_recording"] = "true"
        updated.metadata["live_started_at"] = startedAt
        return updated
    }

    func recordingFailure(
        _ job: DownloadJob,
        cancelled: Bool,
        hasPartialOutput: Bool
    ) -> DownloadJob {
        var updated = job
        updated.metadata["live_active"] = "false"
        updated.metadata["live_recording"] = "false"
        updated.metadata["live_done"] = "true"
        updated.metadata["live_end_reason"] =
            cancelled ? "cancelled" : "error"
        updated.metadata["live_partial_output"] =
            hasPartialOutput ? "true" : "false"
        return updated
    }

    func finishing(
        _ job: DownloadJob,
        output: URL,
        hadSeparateAudio: Bool,
        options: FFmpegTranscodeOptions,
        byteCount: Int?
    ) -> DownloadJob {
        var updated = job
        updated.status = .finished
        updated.completed = max(1, updated.total)
        updated.progress = 1
        updated.message = "Done"
        updated.outputPath = output.path
        updated.metadata = completedMetadata(
            updated.metadata,
            output: output,
            hadSeparateAudio: hadSeparateAudio,
            options: options,
            byteCount: byteCount
        )
        return updated
    }

    private func completedMetadata(
        _ metadata: [String: String],
        output: URL,
        hadSeparateAudio: Bool,
        options: FFmpegTranscodeOptions,
        byteCount: Int?
    ) -> [String: String] {
        var updated = metadata
        updated.removeValue(
            forKey: "niconico_live_session_token"
        )
        updated["live_active"] = "false"
        updated["live_recording"] = "false"
        updated["live_done"] = "true"
        updated["live_end_reason"] = "stream_ended"
        updated["live_partial_output"] = "false"
        updated["filename"] = output.lastPathComponent
        updated["format"] =
            output.pathExtension.lowercased()
        updated["media_format"] =
            output.pathExtension.lowercased()
        updated["postprocess"] =
            hadSeparateAudio
            ? "ffmpeg-live-mux"
            : "ffmpeg-live-record"
        updated["muxed"] =
            hadSeparateAudio ? "true" : "false"
        if let byteCount {
            updated["bytes"] = String(byteCount)
            updated["size"] = String(byteCount)
        }
        if options.enabled {
            updated["transcoded"] = "true"
            for (key, value) in options.metadata {
                updated[key] = value
            }
        }
        return DownloadMetadata.clean(updated)
    }
}
