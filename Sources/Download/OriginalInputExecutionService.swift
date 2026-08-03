import Foundation

struct OriginalInputExecutionOptions: Equatable {
    var rangeExpression: String
    var hitomi: HitomiResolverExecutionOptions
    var preferOriginalEHentaiImages: Bool
    var preferJapaneseEHentaiTitle: Bool
    var pixiv: PixivArtworkResolverExecutionOptions
}

@MainActor
final class OriginalInputExecutionService {
    let registry: SourceResolverRegistry
    let executor: SourceResolverExecutor

    init(
        registry: SourceResolverRegistry,
        executor: SourceResolverExecutor
    ) {
        precondition(
            executor.registry === registry,
            "SourceResolverExecutor must use the original-input registry."
        )
        self.registry = registry
        self.executor = executor
    }

    func execute(
        _ type: OriginalInputType,
        url: URL,
        headers: HTTPRequestOptions,
        options: OriginalInputExecutionOptions,
        context: SourceResolverExecutionContext,
        reportStatus: (String) -> Void,
        downloadResolved: (ResolvedDownload, URL) async throws -> Void
    ) async throws {
        reportStatus(Self.statusMessage(for: type))
        let plan = try executionPlan(
            for: type,
            url: url,
            headers: headers,
            options: options,
            context: context
        )
        try await execute(
            plan,
            sourceURL: url,
            downloadResolved: downloadResolved
        )
    }

    func executionPlan(
        for type: OriginalInputType,
        url: URL,
        headers: HTTPRequestOptions,
        options: OriginalInputExecutionOptions,
        context: SourceResolverExecutionContext
    ) throws -> SourceResolverExecutionPlan {
        switch type {
        case .hitomi:
            guard let plan = executor.executionPlan(
                for: .hitomi,
                url: url,
                headers: headers,
                options: SourceResolverExecutionOptions(
                    hitomi: options.hitomi
                ),
                context: context
            ) else {
                throw NativeDownloadError.unsupported(
                    "Hitomi execution settings are unavailable."
                )
            }
            return plan
        case .ehen:
            return SourceResolverExecutionPlan(
                route: .eHentai,
                statusMessage: Self.statusMessage(for: type),
                options: SourceResolverExecutionOptions(),
                operation: { [registry] in
                    try await registry.eHentaiResolver.resolve(
                        url,
                        headers: headers,
                        preferOriginal:
                            options.preferOriginalEHentaiImages,
                        preferJapaneseTitle:
                            options.preferJapaneseEHentaiTitle
                    )
                }
            )
        case .pixiv:
            guard let plan = executor.executionPlan(
                for: .pixivArtwork,
                url: url,
                headers: headers,
                options: SourceResolverExecutionOptions(
                    rangeExpression: options.rangeExpression,
                    pixiv: options.pixiv
                ),
                context: context
            ) else {
                throw NativeDownloadError.unsupported(
                    "Pixiv execution settings are unavailable."
                )
            }
            return plan
        case .hiyobi:
            return SourceResolverExecutionPlan(
                route: .hiyobi,
                statusMessage: Self.statusMessage(for: type),
                options: SourceResolverExecutionOptions(),
                operation: { [registry] in
                    try await registry.hiyobiResolver.resolve(
                        url,
                        headers: headers
                    )
                }
            )
        }
    }

    func execute(
        _ plan: SourceResolverExecutionPlan,
        sourceURL: URL,
        downloadResolved: (ResolvedDownload, URL) async throws -> Void
    ) async throws {
        let resolved = try await plan.resolve()
        try await downloadResolved(resolved, sourceURL)
    }

    nonisolated static func statusMessage(
        for type: OriginalInputType
    ) -> String {
        switch type {
        case .hitomi:
            return "Reading Hitomi gallery"
        case .ehen:
            return "Reading E-Hentai gallery"
        case .pixiv:
            return "Reading Pixiv artwork"
        case .hiyobi:
            return "Reading Hiyobi gallery"
        }
    }
}
