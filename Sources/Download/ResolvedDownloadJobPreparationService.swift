import Foundation

final class ResolvedDownloadJobPreparationService {
    func preparing(
        _ job: DownloadJob,
        resolved: ResolvedDownload,
        previousMetadata: [String: String]
    ) -> DownloadJob {
        var prepared = job
        let range = job.rangeExpression.trimmed
        let rangeTotal = resolved.metadata["range_total"].flatMap(Int.init)

        prepared.title = resolved.title
        prepared.metadata = Self.resolvedMetadataPreservingRuntimeState(
            resolved.metadata,
            previous: previousMetadata
        )
        prepared.metadata.removeValue(
            forKey: "niconico_live_session_token"
        )
        prepared.resolvedFilenames = resolved.assets.map(\.filename)
        prepared.resolvedURLs = resolved.assets.map {
            $0.remoteURL.absoluteString
        }
        prepared.total = resolved.assets.count
        prepared.completed = 0
        prepared.progress = 0
        prepared.status = .downloading
        prepared.message = range.isEmpty
            ? "Downloading \(resolved.assets.count) files"
            : "Downloading \(resolved.assets.count) of \(rangeTotal ?? resolved.assets.count) files"
        prepared.recordMessage(prepared.message)
        return prepared
    }

    static func resolvedMetadataPreservingRuntimeState(
        _ resolved: [String: String],
        previous: [String: String]
    ) -> [String: String] {
        var metadata = resolved
        for key in [
            "auto_record",
            "original_direct_download",
            "pending_queue_removal",
            "pending_queue_output_deletion",
            "recording_retry_count",
            "recording_retry_last_error",
            "recording_retry_at",
            "python_native_fallback",
            "python_native_fallback_type",
            "python_native_fallback_plugin",
            "python_native_fallback_feature"
        ] {
            if let value = previous[key]?.trimmed, !value.isEmpty {
                metadata[key] = value
            }
        }
        if metadata["recording"] == nil,
           let value = previous["recording"]?.trimmed,
           !value.isEmpty {
            metadata["recording"] = value
        }
        let hookKeys = previous["python_hook_preserved_keys", default: ""]
            .split(separator: ",")
            .map { String($0).trimmed }
            .filter { !$0.isEmpty }
        for key in hookKeys {
            if let value = previous[key]?.trimmed, !value.isEmpty {
                metadata[key] = value
            }
        }
        if !hookKeys.isEmpty {
            metadata["python_hook_preserved_keys"] =
                hookKeys.joined(separator: ",")
        }
        for (key, value) in previous
        where key.hasPrefix("search_") && metadata[key] == nil {
            let trimmed = value.trimmed
            if !trimmed.isEmpty {
                metadata[key] = trimmed
            }
        }
        return DownloadMetadata.clean(metadata)
    }
}
