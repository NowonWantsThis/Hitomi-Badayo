import Foundation

final class AssetDownloadJobStateService {
    func recordingFailure(
        _ failure: AssetDownloadFailure,
        total: Int,
        in job: DownloadJob
    ) -> DownloadJob {
        var updated = job
        let message = AppLocalization.errorText(
            failure.underlying
        )
        let segmentIndex = displaySegmentIndex(
            for: failure
        )
        let segmentTotal = displaySegmentTotal(
            for: failure,
            fallbackTotal: total,
            job: job
        )
        updated.metadata["last_error"] = message
        updated.metadata["failed_segment_index"] =
            String(segmentIndex)
        updated.metadata["failed_segment_total"] =
            String(segmentTotal)
        updated.metadata["failed_segment_filename"] =
            failure.asset.filename
        updated.metadata["failed_segment_url"] =
            failure.asset.remoteURL.absoluteString
        updated.message =
            "Segment \(segmentIndex) / \(segmentTotal) failed"
        return updated
    }

    func recordingSkippedFailure(
        _ failure: AssetDownloadFailure,
        total: Int,
        in job: DownloadJob
    ) -> DownloadJob {
        var updated = job
        let message = AppLocalization.errorText(
            failure.underlying
        )
        let segmentIndex = displaySegmentIndex(
            for: failure
        )
        let segmentTotal = displaySegmentTotal(
            for: failure,
            fallbackTotal: total,
            job: job
        )
        updated.metadata["last_error"] = message
        updated.metadata["skipped_segment_count"] = String(
            (
                Int(
                    updated.metadata[
                        "skipped_segment_count"
                    ] ?? "0"
                ) ?? 0
            ) + 1
        )
        updated.metadata["skipped_segment_total"] =
            String(segmentTotal)
        appendMetadataListValue(
            key: "skipped_segment_indexes",
            value: String(segmentIndex),
            metadata: &updated.metadata
        )
        appendMetadataListValue(
            key: "skipped_segment_filenames",
            value: failure.asset.filename,
            metadata: &updated.metadata
        )
        appendMetadataListValue(
            key: "skipped_segment_urls",
            value: failure.asset.remoteURL.absoluteString,
            metadata: &updated.metadata
        )
        return updated
    }

    func applyingProgress(
        to job: DownloadJob,
        skippedExisting: Int,
        skippedFailures: Int,
        nativeDownloadedByteCount: Int64?
    ) -> DownloadJob {
        var updated = job
        if let downloadedBytes =
            nativeDownloadedByteCount {
            updated.metadata["downloaded_bytes"] =
                String(downloadedBytes)
            updated.metadata["total_bytes"] =
                updated.metadata["total_bytes"] ??
                String(downloadedBytes)
            updated.metadata["byte_count"] =
                String(downloadedBytes)
            updated.metadata["transfer_fraction"] = "1"
        }
        updated.completed += 1
        updated.progress =
            Double(updated.completed) /
            Double(max(1, updated.total))
        updated.message = Self.progressMessage(
            completed: updated.completed,
            total: updated.total,
            skippedExisting: skippedExisting,
            skippedFailures: skippedFailures
        )
        return updated
    }

    func recordingDeferredGalleryFailure(
        in job: DownloadJob,
        assetCount: Int,
        downloadedItemCount: Int,
        skippedFailureCount: Int
    ) -> DownloadJob {
        var updated = job
        updated.metadata["incomplete_gallery"] = "true"
        updated.metadata["incomplete_file_count"] =
            String(skippedFailureCount)
        updated.metadata["downloaded_file_count"] =
            String(downloadedItemCount)
        updated.metadata["failed_file_count"] =
            String(skippedFailureCount)
        updated.metadata["successful_file_count"] =
            String(downloadedItemCount)
        updated.metadata["total_file_count"] =
            String(assetCount)
        return updated
    }

    func recordingSkippedExisting(
        _ count: Int,
        in job: DownloadJob
    ) -> DownloadJob {
        var updated = job
        updated.metadata["skipped_existing_files"] =
            String(count)
        updated.metadata["skip_reason"] =
            "existing_output_files"
        return updated
    }

    func finishingNativeTransfer(
        _ job: DownloadJob
    ) -> DownloadJob {
        var updated = job
        updated.metadata["transfer_active"] = "false"
        if updated.metadata["byte_count"] == nil,
           let total = updated.metadata["total_bytes"] {
            updated.metadata["byte_count"] = total
        }
        return updated
    }

    static func progressMessage(
        completed: Int,
        total: Int,
        skippedExisting: Int,
        skippedFailures: Int
    ) -> String {
        var suffixes: [String] = []
        if skippedExisting > 0 {
            suffixes.append(
                "\(skippedExisting) existing"
            )
        }
        if skippedFailures > 0 {
            suffixes.append(
                "\(skippedFailures) skipped"
            )
        }
        let base = "\(completed) / \(total)"
        return suffixes.isEmpty
            ? base
            : "\(base), \(suffixes.joined(separator: ", "))"
    }

    private func displaySegmentIndex(
        for failure: AssetDownloadFailure
    ) -> Int {
        if let segmentNumber = Int(
            failure.asset.metadata[
                "segment_number"
            ] ?? ""
        ),
        segmentNumber > 0 {
            return segmentNumber
        }
        return failure.index
    }

    private func displaySegmentTotal(
        for failure: AssetDownloadFailure,
        fallbackTotal: Int,
        job: DownloadJob
    ) -> Int {
        if let segmentTotal = Int(
            failure.asset.metadata[
                "segment_total"
            ] ?? ""
        ),
        segmentTotal > 0 {
            return segmentTotal
        }
        if let jobSegmentCount = Int(
            job.metadata["segment_count"] ?? ""
        ),
        jobSegmentCount > 0,
        Self.canContinueAfterHLSFailure(
            failure.asset
        ) {
            return jobSegmentCount
        }
        return fallbackTotal
    }

    private func appendMetadataListValue(
        key: String,
        value: String,
        metadata: inout [String: String]
    ) {
        guard !value.trimmed.isEmpty else {
            return
        }
        let previous = metadata[key]?.trimmed
        metadata[key] = previous?.isEmpty == false
            ? "\(previous!), \(value)"
            : value
    }

    private static func canContinueAfterHLSFailure(
        _ asset: ResolvedAsset
    ) -> Bool {
        let type =
            (asset.metadata["type"] ?? "").lowercased()
        let mediaType =
            (asset.metadata["media_type"] ?? "")
            .lowercased()
        return type == "hls_segment" ||
            mediaType == "hls_segment"
    }
}
