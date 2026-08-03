import Foundation

@MainActor
final class AutoRecordCheckCommandCoordinator {
    private var tasks: [UUID: Task<Void, Never>] = [:]

    var activeCommandCount: Int {
        tasks.count
    }

    @discardableResult
    func begin(
        check:
            @escaping @MainActor () -> Void
    ) -> UUID {
        let commandID = UUID()
        tasks[commandID] =
            Task { @MainActor [weak self] in
                guard !Task.isCancelled else {
                    self?.finish(commandID)
                    return
                }
                check()
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
