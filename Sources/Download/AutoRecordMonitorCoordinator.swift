import Foundation

@MainActor
final class AutoRecordMonitorCoordinator {
    typealias Sleeper =
        @MainActor (UInt64) async throws -> Void

    private let sleep: Sleeper
    private var task: Task<Void, Never>?
    private var activeRunID: UUID?

    init(
        sleep:
            @escaping Sleeper = {
                try await Task.sleep(nanoseconds: $0)
            }
    ) {
        self.sleep = sleep
    }

    var isRunning: Bool {
        task != nil || activeRunID != nil
    }

    @discardableResult
    func start(
        check: @escaping @MainActor () -> Void,
        intervalNanoseconds:
            @escaping @MainActor () -> UInt64
    ) -> UUID {
        cancelAndClear()

        let runID = UUID()
        let sleep = sleep
        activeRunID = runID
        task = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                check()
                let delay = intervalNanoseconds()
                do {
                    try await sleep(delay)
                } catch {
                    break
                }
            }
            self?.finish(runID)
        }
        return runID
    }

    @discardableResult
    func cancelAndClear() -> Bool {
        let wasRunning = isRunning
        task?.cancel()
        task = nil
        activeRunID = nil
        return wasRunning
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
