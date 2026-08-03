import Foundation

@MainActor
final class CompletedJobMetadataEnrichmentCoordinator {
    private var tasks: [UUID: Task<Void, Never>] = [:]

    var activeEnrichmentCount: Int {
        tasks.count
    }

    @discardableResult
    func begin(
        operation:
            @escaping @MainActor () async -> Void
    ) -> UUID {
        let enrichmentID = UUID()
        tasks[enrichmentID] =
            Task { @MainActor [weak self] in
                await operation()
                self?.finish(enrichmentID)
            }
        return enrichmentID
    }

    @discardableResult
    func cancelAll() -> Int {
        let activeTasks = Array(tasks.values)
        tasks.removeAll()
        activeTasks.forEach { $0.cancel() }
        return activeTasks.count
    }

    private func finish(_ enrichmentID: UUID) {
        tasks.removeValue(
            forKey: enrichmentID
        )
    }

    deinit {
        tasks.values.forEach { $0.cancel() }
    }
}
