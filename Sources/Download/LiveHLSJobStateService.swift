import Foundation

final class LiveHLSJobStateService {
    static let stopRequestedMetadataKey =
        "live_stop_requested"

    func starting(
        _ job: DownloadJob,
        playlistURL: URL,
        pollInterval: TimeInterval,
        timeout: TimeInterval
    ) -> DownloadJob {
        var updated = job
        updated.metadata["was_live"] = "true"
        updated.metadata["live_active"] = "true"
        updated.metadata["live_polling"] = "true"
        updated.metadata.removeValue(
            forKey: Self.stopRequestedMetadataKey
        )
        updated.metadata["live_playlist_url"] =
            playlistURL.absoluteString
        updated.metadata["live_poll_interval"] =
            numberString(pollInterval)
        updated.metadata["live_timeout"] =
            numberString(timeout)
        updated.metadata["live_recorded_duration"] = "0"
        updated.metadata["downloaded_bytes"] = "0"
        updated.metadata["transfer_active"] = "true"
        updated.metadata.removeValue(forKey: "total_bytes")
        updated.metadata.removeValue(
            forKey: "transfer_fraction"
        )
        updated.metadata.removeValue(forKey: "duration")
        updated.metadata.removeValue(
            forKey: "duration_seconds"
        )
        updated.progress = 0
        return updated
    }

    func preparingBatch(
        _ job: DownloadJob,
        count: Int,
        isInitialSnapshot: Bool
    ) -> DownloadJob {
        var updated = job
        if isInitialSnapshot {
            updated.total = count
        } else {
            updated.total += count
        }
        updated.message = "Recording live segments"
        return updated
    }

    func preparingAppend(
        _ job: DownloadJob
    ) -> DownloadJob {
        var updated = job
        updated.message = "Appending live segments"
        return updated
    }

    func recordingBatch(
        _ job: DownloadJob,
        segmentCount: Int,
        mediaCount: Int,
        recordedDuration: TimeInterval,
        outputBytes: Int64,
        speed: Int64,
        recordedAt: String,
        snapshotCount: Int
    ) -> DownloadJob {
        var updated = job
        updated.metadata["live_segment_count"] =
            String(segmentCount)
        updated.metadata["live_media_count"] =
            String(mediaCount)
        updated.metadata["live_recorded_duration"] =
            numberString(recordedDuration)
        updated.metadata["duration_seconds"] =
            numberString(recordedDuration)
        updated.metadata["downloaded_bytes"] =
            String(outputBytes)
        updated.metadata["transfer_active"] = "true"
        if speed > 0 {
            updated.metadata["speed_bytes_per_second"] =
                String(speed)
        }
        updated.metadata["last_transfer_at"] = recordedAt
        updated.metadata["live_snapshot_count"] =
            String(snapshotCount)
        updated.metadata.removeValue(
            forKey: "live_last_refresh_error"
        )
        updated.progress = 0
        return updated
    }

    func waitingForSegments(
        _ job: DownloadJob
    ) -> DownloadJob {
        var updated = job
        updated.message = "Waiting for live segments"
        updated.metadata.removeValue(
            forKey: "speed_bytes_per_second"
        )
        return updated
    }

    func recordingRefresh(
        _ job: DownloadJob,
        pollCount: Int,
        pollInterval: TimeInterval
    ) -> DownloadJob {
        var updated = job
        updated.metadata["live_poll_count"] =
            String(pollCount)
        updated.metadata["live_poll_interval"] =
            numberString(pollInterval)
        updated.metadata.removeValue(
            forKey: "live_last_refresh_error"
        )
        return updated
    }

    func recordingRefreshFailure(
        _ job: DownloadJob,
        pollCount: Int,
        errorText: String
    ) -> DownloadJob {
        var updated = job
        updated.metadata["live_poll_count"] =
            String(pollCount)
        updated.metadata["live_last_refresh_error"] =
            errorText
        updated.message =
            "Live playlist refresh failed; retrying"
        return updated
    }

    func finishingPolling(
        _ job: DownloadJob,
        reason: String,
        pollCount: Int,
        outputBytes: Int64,
        hasPartialOutput: Bool
    ) -> DownloadJob {
        terminalState(
            job,
            reason: reason,
            pollCount: pollCount,
            outputBytes: outputBytes,
            recordsPartialOutput: reason == "stopped",
            hasPartialOutput: hasPartialOutput
        )
    }

    func recordingFailure(
        _ job: DownloadJob,
        cancelled: Bool,
        pollCount: Int,
        outputBytes: Int64,
        hasPartialOutput: Bool
    ) -> DownloadJob {
        terminalState(
            job,
            reason: cancelled ? "cancelled" : "error",
            pollCount: pollCount,
            outputBytes: outputBytes,
            recordsPartialOutput: true,
            hasPartialOutput: hasPartialOutput
        )
    }

    private func terminalState(
        _ job: DownloadJob,
        reason: String,
        pollCount: Int,
        outputBytes: Int64,
        recordsPartialOutput: Bool,
        hasPartialOutput: Bool
    ) -> DownloadJob {
        var updated = job
        updated.metadata["live_active"] = "false"
        updated.metadata["live_polling"] = "false"
        updated.metadata["live_done"] = "true"
        updated.metadata["live_end_reason"] = reason
        updated = finalizingTransfer(
            updated,
            outputBytes: outputBytes
        )
        updated.metadata.removeValue(
            forKey: Self.stopRequestedMetadataKey
        )
        updated.metadata["live_poll_count"] =
            String(pollCount)
        if recordsPartialOutput {
            updated.metadata["live_partial_output"] =
                hasPartialOutput ? "true" : "false"
        }
        if reason == "stopped" {
            updated.message = "Finalizing recording"
        }
        return updated
    }

    private func finalizingTransfer(
        _ job: DownloadJob,
        outputBytes: Int64
    ) -> DownloadJob {
        var updated = job
        updated.metadata["transfer_active"] = "false"
        updated.metadata["downloaded_bytes"] =
            String(outputBytes)
        if outputBytes > 0 {
            updated.metadata["byte_count"] =
                String(outputBytes)
        }
        updated.metadata.removeValue(
            forKey: "speed_bytes_per_second"
        )
        if let recorded =
            updated.metadata[
                "live_recorded_duration"
            ]?.trimmed,
           !recorded.isEmpty {
            updated.metadata["duration_seconds"] = recorded
            updated.metadata["duration"] = recorded
        }
        return updated
    }

    private func numberString(
        _ value: Double
    ) -> String {
        var text = String(format: "%.3f", value)
        while text.contains(".") && text.last == "0" {
            text.removeLast()
        }
        if text.last == "." {
            text.removeLast()
        }
        return text
    }
}
