import Foundation

@MainActor
final class DiscordEmojiJobCoordinator {
    let queueStore: QueueStore
    let jobStateService: SourceExecutionJobStateService
    let resolver: any DiscordEmojiResolving

    init(
        queueStore: QueueStore,
        jobStateService: SourceExecutionJobStateService,
        resolver: any DiscordEmojiResolving
    ) {
        self.queueStore = queueStore
        self.jobStateService = jobStateService
        self.resolver = resolver
    }

    func execute(
        _ request: DiscordEmojiRequest,
        source: String,
        jobIndex: Int,
        persist: @MainActor () -> Void,
        downloadResolved:
            (ResolvedDownload, URL) async throws -> Void
    ) async throws {
        var jobs = queueStore.jobs
        jobs[jobIndex] =
            jobStateService.resolving(
                jobs[jobIndex],
                message: "Reading Discord emoji"
            )
        queueStore.replaceJobs(with: jobs)
        persist()

        let resolved = try await resolver.resolve(source)
        try await downloadResolved(
            resolved,
            DiscordEmojiResolver.sourceURL(
                for: request
            )
        )
    }
}
