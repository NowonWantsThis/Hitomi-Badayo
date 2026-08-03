import Foundation

final class PythonHookJobApplicationService {
    func preparingForStartHook(
        _ original: DownloadJob
    ) -> DownloadJob {
        var job = original
        job.metadata.removeValue(
            forKey: "python_hook_download_ran"
        )
        guard let rawKeys =
                job.metadata["python_hook_preserved_keys"]
        else {
            return job
        }

        let keys = rawKeys
            .split(separator: ",")
            .map { String($0).trimmed }
            .filter {
                !$0.isEmpty &&
                    $0 != "python_hook_download_ran"
            }
        if keys.isEmpty {
            job.metadata.removeValue(
                forKey: "python_hook_preserved_keys"
            )
        } else {
            job.metadata["python_hook_preserved_keys"] =
                keys.joined(separator: ",")
        }
        return job
    }

    func applying(
        _ context: PythonHookContext,
        to original: DownloadJob
    ) -> DownloadJob {
        var job = original
        let previousMetadata = job.metadata

        if !context.sourceURL.trimmed.isEmpty {
            job.source = context.sourceURL.trimmed
        }
        if !context.title.trimmed.isEmpty {
            job.title = context.title.trimmed
        }

        var metadata =
            ResolvedDownloadJobPreparationService
                .resolvedMetadataPreservingRuntimeState(
                    context.metadata,
                    previous: previousMetadata
                )
        let changedKeys = Set(previousMetadata.keys)
            .union(metadata.keys)
            .filter { key in
                key != "python_hook_preserved_keys" &&
                    previousMetadata[key] != metadata[key]
            }
        let previouslyPreserved = Set(
            previousMetadata[
                "python_hook_preserved_keys",
                default: ""
            ]
                .split(separator: ",")
                .map { String($0).trimmed }
                .filter { !$0.isEmpty }
        )
        let preserved =
            previouslyPreserved.union(changedKeys).sorted()
        if !preserved.isEmpty {
            metadata["python_hook_preserved_keys"] =
                preserved.joined(separator: ",")
        }
        job.metadata = metadata

        if !context.outputPath.trimmed.isEmpty {
            job.outputPath = context.outputPath.trimmed
        }
        job.total = max(job.total, context.total)
        job.completed = max(job.completed, context.completed)
        return job
    }
}
