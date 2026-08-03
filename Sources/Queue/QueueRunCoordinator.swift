import Foundation

@MainActor
final class QueueRunCoordinator {
    private var task: Task<Void, Never>?
    private var activeRunID: UUID?

    var hasActiveRun: Bool {
        task != nil || activeRunID != nil
    }

    @discardableResult
    func start(
        operation:
            @escaping @MainActor () async -> Void,
        completion:
            @escaping @MainActor () -> Void
    ) -> Bool {
        guard !hasActiveRun else { return false }

        let runID = UUID()
        activeRunID = runID
        task = Task { @MainActor [weak self] in
            await operation()
            self?.finish(runID)
            completion()
        }
        return true
    }

    @discardableResult
    func cancel() -> Bool {
        guard let task else { return false }
        task.cancel()
        return true
    }

    @discardableResult
    func cancelAndClear() -> Bool {
        let hadActiveRun = hasActiveRun
        task?.cancel()
        task = nil
        activeRunID = nil
        return hadActiveRun
    }

    private func finish(_ runID: UUID) {
        guard activeRunID == runID else { return }
        task = nil
        activeRunID = nil
    }

    deinit {
        task?.cancel()
    }
}
