import Foundation

@MainActor
final class SourceResolverPlanExecutionService {
    let executor: SourceResolverExecutor
    let fallbackPolicy: SourceResolverFallbackPolicy

    init(
        executor: SourceResolverExecutor,
        fallbackPolicy: SourceResolverFallbackPolicy
    ) {
        self.executor = executor
        self.fallbackPolicy = fallbackPolicy
    }

    func execute(
        _ plan: SourceResolverExecutionPlan,
        originalURL: URL,
        ytDLPCanResolve: () -> Bool,
        updateSourceURL: (URL) throws -> Void,
        downloadResolved: (ResolvedDownload, URL) async throws -> Void,
        downloadWithYTDLP: (URL) async throws -> Void
    ) async throws {
        do {
            let result = try await plan.resolveResult()
            let resolved = result.download
            let resolvedSourceURL = result.sourceURLOverride ?? originalURL

            if let sourceURLOverride = result.sourceURLOverride,
               sourceURLOverride != originalURL {
                try updateSourceURL(sourceURLOverride)
            }

            do {
                try await downloadResolved(resolved, resolvedSourceURL)
            } catch {
                await executor.cleanUpAfterDownloadFailure(
                    for: plan,
                    resolved: resolved
                )
                throw error
            }
        } catch {
            guard plan.fallback == .ytDLP,
                  fallbackPolicy.allowsYTDLPFallback(
                      for: plan.route,
                      url: originalURL,
                      ytdlpCanResolve: ytDLPCanResolve()
                  ) else {
                throw error
            }
            try await downloadWithYTDLP(originalURL)
        }
    }
}
