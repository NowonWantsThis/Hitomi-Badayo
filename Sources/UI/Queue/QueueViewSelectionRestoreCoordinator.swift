import Foundation

@MainActor
final class QueueViewSelectionRestoreCoordinator {
    typealias Delay =
        @Sendable () async -> Void

    private let delay: Delay
    private var task: Task<Void, Never>?

    init(
        delay: @escaping Delay = {
            await Task.yield()
            await Task.yield()
        }
    ) {
        self.delay = delay
    }

    var hasPendingRestore: Bool {
        task != nil
    }

    func begin(
        completion:
            @escaping @MainActor () -> Void
    ) {
        cancelAndClear()
        let delay = delay
        task = Task { @MainActor [weak self] in
            await delay()
            guard !Task.isCancelled,
                  let self,
                  self.task != nil else {
                return
            }
            self.task = nil
            completion()
        }
    }

    @discardableResult
    func cancelAndClear() -> Bool {
        guard let task else {
            return false
        }
        self.task = nil
        task.cancel()
        return true
    }

    deinit {
        task?.cancel()
    }
}
