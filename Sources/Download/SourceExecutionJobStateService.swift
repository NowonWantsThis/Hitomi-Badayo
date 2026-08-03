import Foundation

final class SourceExecutionJobStateService {
    func resolving(
        _ job: DownloadJob,
        message: String
    ) -> DownloadJob {
        var updated = job
        updated.status = .resolving
        updated.message = message
        return updated
    }

    func delegatingPythonToNative(
        _ job: DownloadJob,
        match: PythonSourceExecutionMatch,
        feature: String
    ) -> DownloadJob {
        var updated = job
        updated.metadata[
            "python_native_fallback"
        ] = "true"
        updated.metadata[
            "python_native_fallback_type"
        ] = match.downloader.type
        updated.metadata[
            "python_native_fallback_plugin"
        ] = match.plugin.title
        updated.metadata[
            "python_native_fallback_feature"
        ] = String(feature.prefix(500))
        updated.message =
            "Switching to native resolver"
        return updated
    }
}
