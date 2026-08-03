import Foundation

enum SearchExecutionOutcome {
    case success(
        rawCount: Int,
        results: [SearchResultLink]
    )
    case cancelled
    case failed
}

@MainActor
final class SearchExecutionFacade {
    typealias ResultProcessor = (
        [SearchResultLink]
    ) -> [SearchResultLink]
    typealias Completion = (
        SearchExecutionOutcome
    ) -> Void

    private let requestCoordinator: SearchRequestCoordinator
    private let fetchService: SearchResultFetchService

    var hasActiveRequest: Bool {
        requestCoordinator.hasActiveRequest
    }

    init(
        requestCoordinator: SearchRequestCoordinator,
        fetchService: SearchResultFetchService
    ) {
        self.requestCoordinator = requestCoordinator
        self.fetchService = fetchService
    }

    func begin(
        url: URL,
        options: HTTPRequestOptions,
        processResults: @escaping ResultProcessor,
        completion: @escaping Completion
    ) {
        requestCoordinator.begin { [weak self] requestID in
            guard let self else { return }
            do {
                let links = try await fetchService.fetchLinks(
                    from: url,
                    options: options
                )
                guard requestCoordinator.isCurrent(requestID) else {
                    return
                }
                let processed = processResults(links)
                guard requestCoordinator.finish(requestID) else {
                    return
                }
                completion(
                    .success(
                        rawCount: links.count,
                        results: processed
                    )
                )
            } catch {
                guard requestCoordinator.isCurrent(requestID),
                      requestCoordinator.finish(requestID) else {
                    return
                }
                completion(
                    Task.isCancelled || Self.isCancellation(error)
                        ? .cancelled
                        : .failed
                )
            }
        }
    }

    @discardableResult
    func cancel() -> Bool {
        requestCoordinator.cancelAndClear()
    }

    private nonisolated static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        return (error as? URLError)?.code == .cancelled
    }
}
