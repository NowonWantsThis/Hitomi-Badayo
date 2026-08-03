import Foundation

@MainActor
protocol SourceJobExecutionCommandHandling: AnyObject {
    func executeDiscordEmoji(
        _ request: DiscordEmojiRequest,
        source: String,
        jobIndex: Int
    ) async throws

    func executeTestingResolvedDownload(
        source: String,
        sourceURL: URL,
        jobIndex: Int
    ) async throws

    func downloadWithAria2(
        _ url: URL,
        jobIndex: Int
    ) async throws

    func downloadLocalFile(
        _ url: URL,
        jobIndex: Int
    ) async throws

    func executeDirectFile(
        _ url: URL,
        jobIndex: Int
    ) async throws

    func executeOriginalInput(
        _ type: OriginalInputType,
        url: URL,
        jobIndex: Int
    ) async throws

    func canResolveSourceJobWithYTDLP(_ url: URL) -> Bool

    func downloadWithYTDLP(
        _ url: URL,
        jobIndex: Int
    ) async throws

    func executeSourceResolverPlan(
        _ plan: SourceResolverExecutionPlan,
        originalURL: URL,
        jobIndex: Int
    ) async throws

    func executePythonSource(
        _ script: PythonSourceExecutionMatch,
        sourceURL: URL,
        headers: HTTPRequestOptions,
        jobIndex: Int
    ) async throws

    func downloadWithCustomCommand(
        _ url: URL,
        rule: SiteRule,
        jobIndex: Int
    ) async throws

    func executeGenericPage(
        _ url: URL,
        headers: HTTPRequestOptions,
        jobIndex: Int
    ) async throws

    func downloadDirect(
        _ url: URL,
        jobIndex: Int,
        resolveHTMLMedia: Bool
    ) async throws
}

@MainActor
final class SourceJobExecutionActionFactory {
    func makeActions(
        source: String,
        jobIndex: Int,
        handler: any SourceJobExecutionCommandHandling
    ) -> SourceJobExecutionActions {
        SourceJobExecutionActions(
            input: SourceInputExecutionActions(
                downloadDiscordEmoji: { request in
                    try await handler.executeDiscordEmoji(
                        request,
                        source: source,
                        jobIndex: jobIndex
                    )
                },
                downloadTestingResolved: { testingURL in
                    try await handler.executeTestingResolvedDownload(
                        source: source,
                        sourceURL: testingURL,
                        jobIndex: jobIndex
                    )
                },
                downloadWithAria2: { url in
                    try await handler.downloadWithAria2(
                        url,
                        jobIndex: jobIndex
                    )
                },
                downloadLocalFile: { url in
                    try await handler.downloadLocalFile(
                        url,
                        jobIndex: jobIndex
                    )
                },
                downloadDirectFile: { url in
                    try await handler.executeDirectFile(
                        url,
                        jobIndex: jobIndex
                    )
                },
                downloadOriginalInput: { type, url in
                    try await handler.executeOriginalInput(
                        type,
                        url: url,
                        jobIndex: jobIndex
                    )
                }
            ),
            source: { headers in
                SourceExecutionActions(
                    ytDLPCanResolve: { url in
                        handler.canResolveSourceJobWithYTDLP(
                            url
                        )
                    },
                    downloadWithYTDLP: { url in
                        try await handler.downloadWithYTDLP(
                            url,
                            jobIndex: jobIndex
                        )
                    },
                    downloadWithAria2: { url in
                        try await handler.downloadWithAria2(
                            url,
                            jobIndex: jobIndex
                        )
                    },
                    executeResolverPlan: { plan, url in
                        try await handler.executeSourceResolverPlan(
                            plan,
                            originalURL: url,
                            jobIndex: jobIndex
                        )
                    },
                    executePythonPlugin: { script, url in
                        try await handler.executePythonSource(
                            script,
                            sourceURL: url,
                            headers: headers,
                            jobIndex: jobIndex
                        )
                    },
                    downloadWithCustomCommand: { url, rule in
                        try await handler.downloadWithCustomCommand(
                            url,
                            rule: rule,
                            jobIndex: jobIndex
                        )
                    },
                    executeGenericPage: { url in
                        try await handler.executeGenericPage(
                            url,
                            headers: headers,
                            jobIndex: jobIndex
                        )
                    },
                    downloadDirect: { url in
                        try await handler.downloadDirect(
                            url,
                            jobIndex: jobIndex,
                            resolveHTMLMedia: true
                        )
                    }
                )
            }
        )
    }
}
