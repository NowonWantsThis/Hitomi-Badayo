import Foundation

@MainActor
final class OutputPreviewLoadCoordinator {
    typealias Scanner =
        @Sendable (String) -> [OutputPreviewFile]

    private let scanner: Scanner
    private var task: Task<Void, Never>?
    private var activeRequestID: UUID?

    init(
        scanner:
            @escaping Scanner = {
                OutputPreviewFileScanner.files(at: $0)
            }
    ) {
        self.scanner = scanner
    }

    var hasActiveRequest: Bool {
        task != nil || activeRequestID != nil
    }

    @discardableResult
    func begin(
        resolveOutputPath:
            @escaping @MainActor () async -> String,
        shouldContinue:
            @escaping @MainActor () -> Bool = { true },
        completion:
            @escaping @MainActor ([OutputPreviewFile]) -> Void
    ) -> UUID {
        cancelAndClear()

        let requestID = UUID()
        let scanner = scanner
        activeRequestID = requestID
        task = Task { @MainActor [weak self] in
            let outputPath = await resolveOutputPath()
            guard !Task.isCancelled,
                  shouldContinue() else {
                self?.finish(requestID)
                return
            }

            let scanTask = Task.detached(
                priority: .userInitiated
            ) {
                scanner(outputPath)
            }
            let files = await withTaskCancellationHandler {
                await scanTask.value
            } onCancel: {
                scanTask.cancel()
            }

            guard !Task.isCancelled,
                  shouldContinue(),
                  self?.finish(requestID) == true else {
                return
            }
            completion(files)
        }
        return requestID
    }

    @discardableResult
    func cancelAndClear() -> Bool {
        let hadActiveRequest = hasActiveRequest
        task?.cancel()
        task = nil
        activeRequestID = nil
        return hadActiveRequest
    }

    @discardableResult
    private func finish(_ requestID: UUID) -> Bool {
        guard activeRequestID == requestID else {
            return false
        }
        task = nil
        activeRequestID = nil
        return true
    }

    deinit {
        task?.cancel()
    }
}
