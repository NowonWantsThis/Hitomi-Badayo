import Foundation

@MainActor
final class SearchRequestCoordinator {
    private var task: Task<Void, Never>?
    private var activeRequestID: UUID?

    var hasActiveRequest: Bool {
        task != nil || activeRequestID != nil
    }

    @discardableResult
    func begin(
        operation:
            @escaping @MainActor (UUID) async -> Void
    ) -> UUID {
        task?.cancel()

        let requestID = UUID()
        activeRequestID = requestID
        task = Task { @MainActor in
            await operation(requestID)
        }
        return requestID
    }

    func isCurrent(_ requestID: UUID) -> Bool {
        activeRequestID == requestID
    }

    @discardableResult
    func finish(_ requestID: UUID) -> Bool {
        guard activeRequestID == requestID else {
            return false
        }
        task = nil
        activeRequestID = nil
        return true
    }

    @discardableResult
    func cancelAndClear() -> Bool {
        let hadActiveRequest = hasActiveRequest
        task?.cancel()
        task = nil
        activeRequestID = nil
        return hadActiveRequest
    }

    deinit {
        task?.cancel()
    }
}
