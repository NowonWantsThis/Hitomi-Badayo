import Foundation

@MainActor
final class CompletedOutputMetadataBackfillCoordinator {
    private var task: Task<Void, Never>?
    private var activeToken: UUID?

    var isRunning: Bool {
        task != nil
    }

    @discardableResult
    func start(
        operation: @escaping @MainActor () async -> Void
    ) -> Task<Void, Never> {
        task?.cancel()

        let token = UUID()
        activeToken = token
        let launchedTask = Task { @MainActor [weak self] in
            await operation()
            self?.finish(token: token)
        }
        task = launchedTask
        return launchedTask
    }

    func cancel() {
        task?.cancel()
        task = nil
        activeToken = nil
    }

    private func finish(token: UUID) {
        guard activeToken == token else { return }
        task = nil
        activeToken = nil
    }

    deinit {
        task?.cancel()
    }
}
