import Foundation

struct ResolvedDownloadHookPreparation {
    var resolved: ResolvedDownload
    var sourceURL: URL
    var previousMetadata: [String: String]
}

@MainActor
final class ResolvedDownloadHookPreparationService {
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
        resolved initialResolved: ResolvedDownload,
        sourceURL initialSourceURL: URL,
        previousMetadata initialPreviousMetadata: [String: String],
        hasHooks: HasHooks,
        runHooks: RunHooks,
        applySourceURL: (URL) -> Void
    ) async throws -> ResolvedDownloadHookPreparation {
        var previousMetadata = initialPreviousMetadata
        var resolved = initialResolved
        var sourceURL = initialSourceURL
        var hookContext = PythonScriptBridge.hookContext(
            job: job,
            sourceURL: sourceURL,
            resolved: resolved
        )
        let downloadHooksAlreadyRan =
            previousMetadata["python_hook_download_ran"] == "true"
        var didRunPythonDownloadHooks = false

        if !downloadHooksAlreadyRan,
           hasHooks(.taskAboutToDownload, nil) {
            hookContext = try await runHooks(
                .taskAboutToDownload,
                hookContext,
                nil
            )
            resolved = try PythonScriptBridge.resolvedDownload(
                resolved,
                applying: hookContext
            )
            didRunPythonDownloadHooks = true
            let sourceValue = hookContext.sourceURL.trimmed
            if !sourceValue.isEmpty,
               let hookedSourceURL = URL(string: sourceValue) {
                sourceURL = hookedSourceURL
                applySourceURL(hookedSourceURL)
            }
        }

        let formatType = hookContext.type?.trimmed.isEmpty == false
            ? hookContext.type!.trimmed
            : resolved.metadata["type"]?.trimmed ?? ""
        let formatNames: Set<String> =
            formatType.isEmpty ? [] : [formatType]
        if !downloadHooksAlreadyRan,
           !formatNames.isEmpty,
           hasHooks(.format, formatNames) {
            hookContext = PythonScriptBridge.hookContext(
                job: job,
                sourceURL: sourceURL,
                resolved: resolved
            )
            hookContext = try await runHooks(
                .format,
                hookContext,
                formatNames
            )
            resolved = try PythonScriptBridge.resolvedDownload(
                resolved,
                applying: hookContext
            )
            didRunPythonDownloadHooks = true
        }

        if didRunPythonDownloadHooks {
            previousMetadata["python_hook_download_ran"] = "true"
            let hookKeys = previousMetadata[
                "python_hook_preserved_keys",
                default: ""
            ]
                .split(separator: ",")
                .map { String($0).trimmed }
                .filter { !$0.isEmpty }
            previousMetadata["python_hook_preserved_keys"] =
                Set(hookKeys + ["python_hook_download_ran"])
                    .sorted()
                    .joined(separator: ",")
        }

        return ResolvedDownloadHookPreparation(
            resolved: resolved,
            sourceURL: sourceURL,
            previousMetadata: previousMetadata
        )
    }
}
