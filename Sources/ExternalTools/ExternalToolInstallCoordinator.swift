import Foundation

@MainActor
final class ExternalToolInstallCoordinator {
    private var task: Task<Void, Never>?
    private var activeToken: UUID?

    var isRunning: Bool {
        task != nil
    }

    @discardableResult
    func begin(
        operation: @escaping @MainActor () async -> Void
    ) -> Bool {
        guard task == nil else { return false }

        let token = UUID()
        activeToken = token
        task = Task { @MainActor [weak self] in
            await operation()
            self?.finish(token: token)
        }
        return true
    }

    func cancel() {
        task?.cancel()
    }

    func cancelAndClear() {
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
