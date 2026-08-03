import Foundation

@MainActor
final class OutputJobCommandCoordinator {
    typealias RevealURLResolver =
        @MainActor () async -> [URL]
    typealias OpenRequestResolver =
        @MainActor () async ->
            FirstOutputOpenRequest?
    typealias OpenRequestsResolver =
        @MainActor () async ->
            [FirstOutputOpenRequest]

    let outputCommandService: OutputCommandService
    private var tasks: [UUID: Task<Void, Never>] = [:]

    init(
        outputCommandService: OutputCommandService
    ) {
        self.outputCommandService =
            outputCommandService
    }

    var activeCommandCount: Int {
        tasks.count
    }

    @discardableResult
    func reveal(
        resolveURLs:
            @escaping RevealURLResolver,
        completion:
            @escaping @MainActor (
                OutputCommandResult
            ) -> Void
    ) -> UUID {
        begin(
            operation: {
                let urls = await resolveURLs()
                guard !Task.isCancelled else {
                    return .cancelled
                }
                return self.outputCommandService
                    .reveal(urls)
            },
            completion: completion
        )
    }

    @discardableResult
    func openFirst(
        resolveRequest:
            @escaping OpenRequestResolver,
        completion:
            @escaping @MainActor (
                OutputCommandResult
            ) -> Void
    ) -> UUID {
        begin(
            operation: {
                guard let request =
                    await resolveRequest() else {
                    return .unavailable
                }
                guard !Task.isCancelled else {
                    return .cancelled
                }
                return await self.outputCommandService
                    .openFirstOutput(for: request)
            },
            completion: completion
        )
    }

    @discardableResult
    func openFirstBatch(
        resolveRequests:
            @escaping OpenRequestsResolver,
        confirmLargeBatch:
            @escaping @MainActor (Int) -> Bool,
        completion:
            @escaping @MainActor (
                OutputCommandResult
            ) -> Void
    ) -> UUID {
        begin(
            operation: {
                let requests =
                    await resolveRequests()
                guard !Task.isCancelled else {
                    return .cancelled
                }
                return await self.outputCommandService
                    .openFirstOutputs(
                        for: requests,
                        confirmLargeBatch:
                            confirmLargeBatch
                    )
            },
            completion: completion
        )
    }

    @discardableResult
    func cancelAll() -> Int {
        let activeTasks = Array(tasks.values)
        tasks.removeAll()
        activeTasks.forEach { $0.cancel() }
        return activeTasks.count
    }

    @discardableResult
    private func begin(
        operation:
            @escaping @MainActor () async ->
                OutputCommandResult,
        completion:
            @escaping @MainActor (
                OutputCommandResult
            ) -> Void
    ) -> UUID {
        let commandID = UUID()
        tasks[commandID] =
            Task { @MainActor [weak self] in
                let result = await operation()
                guard !Task.isCancelled,
                      self?.finish(commandID) == true
                else {
                    return
                }
                completion(result)
            }
        return commandID
    }

    @discardableResult
    private func finish(_ commandID: UUID) -> Bool {
        tasks.removeValue(forKey: commandID) != nil
    }

    deinit {
        tasks.values.forEach { $0.cancel() }
    }
}
