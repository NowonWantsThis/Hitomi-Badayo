import Foundation

final class ResolvedPackageJobStateService {
    func preparingFilePackage(
        _ job: DownloadJob,
        resolvedFilenames: [String],
        outputFolder: URL
    ) -> DownloadJob {
        var updated = job
        updated.resolvedFilenames = resolvedFilenames
        updated.outputPath = outputFolder.path
        return updated
    }

    func recordingTextMerge(
        _ job: DownloadJob,
        output: URL,
        inputCount: Int
    ) -> DownloadJob {
        var updated = job
        updated.metadata["text_merge_output"] = output.path
        updated.metadata["text_merge_filename"] =
            output.lastPathComponent
        updated.metadata["text_merge_count"] =
            String(inputCount)
        updated.metadata["postprocess"] = "text-merge"
        return updated
    }

    func finishingFilePackage(
        _ job: DownloadJob
    ) -> DownloadJob {
        var updated = job
        updated.status = .finished
        updated.progress = 1
        updated.message = "Done"
        return updated
    }

    func preparingGroupedPackage(
        _ job: DownloadJob,
        outputFolder: URL
    ) -> DownloadJob {
        var updated = job
        updated.outputPath = outputFolder.path
        return updated
    }

    func recordingReusedYouTubeOutput(
        _ job: DownloadJob,
        id: String,
        output: URL,
        assetCount: Int
    ) -> DownloadJob {
        var updated = job
        let reusedCount =
            (
                Int(
                    updated.metadata[
                        "youtube_reused_existing_outputs"
                    ] ?? ""
                ) ?? 0
            ) + 1
        var reusedIDs = Set(
            updated.metadata[
                "youtube_reused_video_ids",
                default: ""
            ]
            .split(separator: ",")
            .map(String.init)
        )
        reusedIDs.insert(id)
        updated.completed = min(
            updated.total,
            updated.completed + max(1, assetCount)
        )
        updated.progress =
            Double(updated.completed) /
            Double(max(1, updated.total))
        updated.metadata[
            "youtube_reused_existing_outputs"
        ] = String(reusedCount)
        updated.metadata["youtube_reused_video_ids"] =
            reusedIDs.sorted().joined(separator: ",")
        updated.metadata["skipped_existing_files"] =
            String(reusedCount)
        updated.metadata["skip_reason"] =
            "youtube_collection_video_id"
        updated.metadata["last_reused_existing_output"] =
            output.path
        updated.message =
            "Reused \(reusedCount) existing YouTube file" +
            (reusedCount == 1 ? "" : "s")
        return updated
    }

    func preparingGroupedDirectFiles(
        _ job: DownloadJob,
        count: Int
    ) -> DownloadJob {
        var updated = job
        updated.message =
            "Downloading \(count) file" +
            (count == 1 ? "" : "s")
        return updated
    }

    func preparingGroupedStream(
        _ job: DownloadJob,
        index: Int,
        total: Int
    ) -> DownloadJob {
        updatingMessage(
            job,
            to: "Downloading stream \(index) / \(total)"
        )
    }

    func preparingGroupedDASHVideo(
        _ job: DownloadJob,
        index: Int,
        total: Int
    ) -> DownloadJob {
        updatingMessage(
            job,
            to: "Downloading DASH video \(index) / \(total)"
        )
    }

    func preparingGroupedDASHAudio(
        _ job: DownloadJob,
        index: Int,
        total: Int
    ) -> DownloadJob {
        updatingMessage(
            job,
            to: "Downloading DASH audio \(index) / \(total)"
        )
    }

    func preparingGroupedDASHFinalization(
        _ job: DownloadJob,
        index: Int,
        total: Int,
        transcoding: Bool
    ) -> DownloadJob {
        updatingMessage(
            job,
            to:
                transcoding
                ? "Muxing and transcoding \(index) / \(total)"
                : "Muxing audio and video \(index) / \(total)"
        )
    }

    func recordingGroupedDASHCompletion(
        _ job: DownloadJob,
        transcoding: Bool
    ) -> DownloadJob {
        var updated = job
        let previousCount =
            Int(
                updated.metadata[
                    "muxed_output_count"
                ] ?? "0"
            ) ?? 0
        updated.metadata["muxed_output_count"] =
            String(previousCount + 1)
        updated.metadata["postprocess"] =
            transcoding
            ? "ffmpeg-transcode"
            : "ffmpeg-mux"
        if transcoding {
            updated.metadata["transcoded"] = "true"
        }
        return updated
    }

    func preparingGroupedHLSFinalization(
        _ job: DownloadJob,
        transcoding: Bool
    ) -> DownloadJob {
        updatingMessage(
            job,
            to:
                transcoding
                ? "Transcoding HLS stream"
                : "Remuxing HLS stream"
        )
    }

    func recordingGroupedHLSCompletion(
        _ job: DownloadJob,
        transcoding: Bool
    ) -> DownloadJob {
        var updated = job
        let previousCount =
            Int(
                updated.metadata[
                    "remuxed_stream_count"
                ] ?? "0"
            ) ?? 0
        updated.metadata["remuxed_stream_count"] =
            String(previousCount + 1)
        updated.metadata["postprocess"] =
            transcoding
            ? "ffmpeg-transcode"
            : "ffmpeg-remux"
        if transcoding {
            updated.metadata["transcoded"] = "true"
        }
        return updated
    }

    func preparingHLSFinalization(
        _ job: DownloadJob,
        transcoding: Bool
    ) -> DownloadJob {
        updatingMessage(
            job,
            to:
                transcoding
                ? "Transcoding HLS to MP4"
                : "Remuxing HLS to MP4"
        )
    }

    func recordingHLSCompletion(
        _ job: DownloadJob,
        output: URL,
        options: FFmpegTranscodeOptions
    ) -> DownloadJob {
        var updated = job
        updated.outputPath = output.path
        updated.metadata = remuxedHLSMetadata(
            updated.metadata,
            output: output,
            options: options
        )
        return updated
    }

    func preparingConcatenation(
        _ job: DownloadJob,
        output: URL
    ) -> DownloadJob {
        var updated = job
        updated.outputPath = output.path
        updated.resolvedFilenames = [
            output.lastPathComponent
        ]
        return updated
    }

    func finishingConcatenation(
        _ job: DownloadJob,
        output: URL
    ) -> DownloadJob {
        var updated = job
        let recordingWasStopped =
            updated.metadata["live_end_reason"] == "stopped"
        updated.status = .finished
        updated.progress = 1
        updated.message =
            recordingWasStopped ? "Recording stopped" : "Done"
        updated.outputPath = output.path
        return updated
    }

    func preparingDASHMux(
        _ job: DownloadJob,
        output: URL
    ) -> DownloadJob {
        var updated = job
        updated.outputPath = output.path
        updated.message = "Downloading DASH video"
        return updated
    }

    func preparingDASHAudio(
        _ job: DownloadJob
    ) -> DownloadJob {
        var updated = job
        updated.message = "Downloading DASH audio"
        return updated
    }

    func preparingDASHFinalization(
        _ job: DownloadJob,
        transcoding: Bool
    ) -> DownloadJob {
        var updated = job
        updated.message =
            transcoding
            ? "Muxing and transcoding audio/video"
            : "Muxing audio and video"
        return updated
    }

    func finishingDASHMux(
        _ job: DownloadJob,
        output: URL,
        options: FFmpegTranscodeOptions
    ) -> DownloadJob {
        var updated = job
        updated.status = .finished
        updated.progress = 1
        updated.message = "Done"
        updated.metadata = muxedDASHMetadata(
            updated.metadata,
            output: output,
            options: options
        )
        return updated
    }

    private func muxedDASHMetadata(
        _ metadata: [String: String],
        output: URL,
        options: FFmpegTranscodeOptions
    ) -> [String: String] {
        var updated = metadata
        if let format = updated["format"],
           format != "mp4" {
            updated["source_format"] = format
        }
        updated["basename"] =
            output.deletingPathExtension().lastPathComponent
        updated["container"] = "mp4"
        updated["ext"] = "mp4"
        updated["filename"] = output.lastPathComponent
        updated["format"] = "mp4"
        updated["muxed"] = "true"
        if options.enabled {
            updated["postprocess"] = "ffmpeg-transcode"
            updated["transcoded"] = "true"
            for (key, value) in options.metadata {
                updated[key] = value
            }
        } else {
            updated["postprocess"] = "ffmpeg-mux"
        }
        return DownloadMetadata.clean(updated)
    }

    private func remuxedHLSMetadata(
        _ metadata: [String: String],
        output: URL,
        options: FFmpegTranscodeOptions
    ) -> [String: String] {
        var updated = metadata
        updated["basename"] =
            output.deletingPathExtension().lastPathComponent
        updated["container"] = "mp4"
        updated["ext"] = "mp4"
        updated["filename"] = output.lastPathComponent
        updated["format"] = "mp4"
        updated["remuxed"] = "true"
        if options.enabled {
            updated["postprocess"] = "ffmpeg-transcode"
            updated["transcoded"] = "true"
            for (key, value) in options.metadata {
                updated[key] = value
            }
        } else {
            updated["postprocess"] = "ffmpeg-remux"
        }
        return DownloadMetadata.clean(updated)
    }

    private func updatingMessage(
        _ job: DownloadJob,
        to message: String
    ) -> DownloadJob {
        var updated = job
        updated.message = message
        return updated
    }
}
