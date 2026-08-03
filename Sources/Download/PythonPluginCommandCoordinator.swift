import Foundation

@MainActor
final class PythonPluginCommandCoordinator {
    private var tasks: [UUID: Task<Void, Never>] = [:]

    var activeCommandCount: Int {
        tasks.count
    }

    @discardableResult
    func begin(
        operation:
            @escaping @MainActor () async -> Void
    ) -> UUID {
        let commandID = UUID()
        tasks[commandID] =
            Task { @MainActor [weak self] in
                await operation()
                self?.finish(commandID)
            }
        return commandID
    }

    @discardableResult
    func cancelAll() -> Int {
        let activeTasks = Array(tasks.values)
        tasks.removeAll()
        activeTasks.forEach { $0.cancel() }
        return activeTasks.count
    }

    private func finish(_ commandID: UUID) {
        tasks.removeValue(forKey: commandID)
    }

    deinit {
        tasks.values.forEach { $0.cancel() }
    }
}
