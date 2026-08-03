import Foundation

final class Aria2JobStateService {
    func starting(
        _ job: DownloadJob,
        title: String,
        options: Aria2Options,
        hasRPCSession: Bool
    ) -> DownloadJob {
        var updated = job
        updated.title = title.isEmpty ? "Torrent" : title
        updated.total = 1
        updated.completed = 0
        updated.progress = 0
        updated.status = .downloading
        updated.message = "Running aria2c"
        updated.metadata["tool"] = "aria2c"
        updated.metadata["handler"] = "aria2"
        updated.metadata["aria2_runtime_paused"] = "false"
        updated.metadata["aria2_runtime_rpc"] =
            hasRPCSession ? "true" : "false"
        updated.metadata["selected_files"] = options.selectedFiles
        updated.metadata["runtime_selected_files"] =
            options.selectedFiles
        updated.metadata["max_download_limit"] =
            options.maxDownloadLimit
        updated.metadata["max_upload_limit"] =
            options.maxUploadLimit
        updated.metadata["runtime_max_download_limit"] =
            options.maxDownloadLimit
        updated.metadata["runtime_max_upload_limit"] =
            options.maxUploadLimit
        updated.metadata["seed_time_minutes"] =
            options.seedTimeMinutes
        updated.metadata["seed_ratio"] = options.seedRatio
        updated.metadata["runtime_seed_time_minutes"] =
            options.seedTimeMinutes
        updated.metadata["runtime_seed_ratio"] = options.seedRatio
        return updated
    }

    func finishing(
        _ job: DownloadJob,
        output: URL,
        metadata baseMetadata: [String: String],
        options: Aria2Options
    ) -> DownloadJob {
        let runtimeDownloadLimit =
            job.metadata["runtime_max_download_limit"] ??
            options.maxDownloadLimit
        let runtimeUploadLimit =
            job.metadata["runtime_max_upload_limit"] ??
            options.maxUploadLimit
        let runtimeSelectedFiles =
            job.metadata["runtime_selected_files"] ??
            options.selectedFiles
        let runtimeSeedTime =
            job.metadata["runtime_seed_time_minutes"] ??
            options.seedTimeMinutes
        let runtimeSeedRatio =
            job.metadata["runtime_seed_ratio"] ??
            options.seedRatio
        let runtimeSeedError =
            job.metadata["aria2_runtime_seed_error"] ?? ""
        let previewFileCount =
            job.metadata["aria2_file_count"] ?? ""
        let previewFileListError =
            job.metadata["aria2_file_list_error"] ?? ""
        let previewPeerCount =
            job.metadata["aria2_peer_count"] ?? ""
        let previewPeerError =
            job.metadata["aria2_runtime_peer_error"] ?? ""

        var metadata = baseMetadata
        metadata["selected_files"] = runtimeSelectedFiles
        metadata["runtime_selected_files"] = runtimeSelectedFiles
        metadata["runtime_max_download_limit"] =
            runtimeDownloadLimit
        metadata["runtime_max_upload_limit"] = runtimeUploadLimit
        metadata["seed_time_minutes"] = runtimeSeedTime
        metadata["seed_ratio"] = runtimeSeedRatio
        metadata["runtime_seed_time_minutes"] = runtimeSeedTime
        metadata["runtime_seed_ratio"] = runtimeSeedRatio
        if !runtimeSeedError.isEmpty {
            metadata["aria2_runtime_seed_error"] = runtimeSeedError
        }
        if !previewFileCount.isEmpty {
            metadata["aria2_file_count"] = previewFileCount
        }
        if !previewFileListError.isEmpty {
            metadata["aria2_file_list_error"] =
                previewFileListError
        }
        if !previewPeerCount.isEmpty {
            metadata["aria2_peer_count"] = previewPeerCount
        }
        if !previewPeerError.isEmpty {
            metadata["aria2_runtime_peer_error"] =
                previewPeerError
        }

        var updated = job
        updated.title = output.lastPathComponent
        updated.outputPath = output.path
        updated.metadata =
            ResolvedDownloadJobPreparationService
            .resolvedMetadataPreservingRuntimeState(
                DownloadMetadata.clean(metadata),
                previous: job.metadata
            )
        updated.completed = 1
        updated.progress = 1
        updated.status = .finished
        updated.message = "Done"
        return updated
    }
}
