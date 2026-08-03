import Foundation

enum DuplicateImageScanOutcome {
    case completed([DuplicateImageGroup])
    case failed(Error)
}

@MainActor
final class DuplicateImageScanCoordinator {
    typealias Scanner =
        @Sendable (
            _ roots: [URL],
            _ similarityPercent: Int,
            _ excludeSameSource: Bool
        ) async throws -> [DuplicateImageGroup]

    let service: DuplicateImageScanService
    private let scanner: Scanner
    private var task: Task<Void, Never>?

    init(
        service:
            DuplicateImageScanService =
                DuplicateImageScanService(),
        scanner: Scanner? = nil
    ) {
        self.service = service
        if let scanner {
            self.scanner = scanner
        } else {
            self.scanner = {
                roots,
                similarityPercent,
                excludeSameSource in
                let scanTask =
                    Task.detached(
                        priority: .userInitiated
                    ) {
                        try service.groups(
                            in: roots,
                            similarityPercent:
                                similarityPercent,
                            excludeSameSource:
                                excludeSameSource
                        )
                    }
                return try await
                    withTaskCancellationHandler {
                        try await scanTask.value
                    } onCancel: {
                        scanTask.cancel()
                    }
            }
        }
    }

    var hasActiveScan: Bool {
        task != nil
    }

    @discardableResult
    func begin(
        roots: [URL],
        similarityPercent: Int,
        excludeSameSource: Bool,
        completion:
            @escaping @MainActor (
                DuplicateImageScanOutcome
            ) -> Void
    ) -> Bool {
        guard task == nil else {
            return false
        }
        let scanner = scanner
        task = Task { @MainActor [weak self] in
            do {
                let groups = try await scanner(
                    roots,
                    similarityPercent,
                    excludeSameSource
                )
                guard !Task.isCancelled,
                      let self,
                      self.task != nil else {
                    return
                }
                self.task = nil
                completion(.completed(groups))
            } catch {
                guard !Task.isCancelled,
                      let self,
                      self.task != nil else {
                    return
                }
                self.task = nil
                completion(.failed(error))
            }
        }
        return true
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
