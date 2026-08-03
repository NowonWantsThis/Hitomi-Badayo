import Foundation

@MainActor
final class SyntheticPythonDownloadHookService {
    typealias HasHooks = (
        PythonHookEvent,
        Set<String>?
    ) -> Bool
    typealias RunHooks = (
        PythonHookEvent,
        PythonHookContext,
        Set<String>?
    ) async throws -> PythonHookContext

    func prepare(
        job: DownloadJob,
        sourceURL: URL,
        title: String,
        filename: String?,
        metadata: [String: String],
        requestOptions: (URL) -> HTTPRequestOptions,
        hasHooks: HasHooks,
        runHooks: RunHooks
    ) async throws -> PythonHookContext? {
        guard job.metadata["python_hook_download_ran"] != "true",
              hasHooks(.taskAboutToDownload, nil) else {
            return nil
        }

        var context = PythonScriptBridge.hookContext(
            job: job,
            sourceURL: sourceURL
        )
        context.title = title
        context.metadata = DownloadMetadata.clean(
            job.metadata.merging(metadata) { _, new in new }
        )
        context.type = context.metadata["type"]

        if ["http", "https", "file"].contains(
            sourceURL.scheme?.lowercased() ?? ""
        ) {
            let headers = requestOptions(sourceURL)
            let preferredFilename = filename?.trimmed ?? ""
            let fallbackFilename =
                sourceURL.lastPathComponent.trimmed.isEmpty
                    ? "download"
                    : sourceURL.lastPathComponent
            context.assets = [
                PythonHookAssetContext(
                    url: sourceURL.absoluteString,
                    filename: preferredFilename.isEmpty
                        ? fallbackFilename
                        : preferredFilename,
                    referer: headers.referer,
                    userAgent: headers.userAgent,
                    metadata: metadata
                )
            ]
            context.total = 1
        }

        context = try await runHooks(
            .taskAboutToDownload,
            context,
            nil
        )
        let formatType = context.type?.trimmed ?? ""
        let formatNames: Set<String> =
            formatType.isEmpty ? [] : [formatType]
        if !context.assets.isEmpty,
           !formatNames.isEmpty,
           hasHooks(.format, formatNames) {
            context = try await runHooks(
                .format,
                context,
                formatNames
            )
        }
        return context
    }

    func markingDownloadHooksRan(
        _ original: DownloadJob
    ) -> DownloadJob {
        var job = original
        job.metadata["python_hook_download_ran"] = "true"
        let existingKeys = job.metadata[
            "python_hook_preserved_keys",
            default: ""
        ]
            .split(separator: ",")
            .map { String($0).trimmed }
            .filter { !$0.isEmpty }
        job.metadata["python_hook_preserved_keys"] =
            Set(existingKeys + ["python_hook_download_ran"])
                .sorted()
                .joined(separator: ",")
        return job
    }
}
