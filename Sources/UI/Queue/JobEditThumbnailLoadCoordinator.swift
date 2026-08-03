import AppKit
import Foundation

@MainActor
final class JobEditThumbnailLoadCoordinator {
    typealias Loader =
        @MainActor (
            DownloadJob,
            String,
            Bool
        ) async -> NSImage?

    private let loadImage: Loader
    private var task: Task<Void, Never>?
    private var activeRequestID: UUID?

    init(
        loadImage:
            @escaping Loader = {
                await QueueThumbnailProvider.image(
                    for: $0,
                    destinationPath: $1,
                    includeCustomOverride: $2
                )
            }
    ) {
        self.loadImage = loadImage
    }

    var hasActiveRequest: Bool {
        task != nil || activeRequestID != nil
    }

    @discardableResult
    func begin(
        job: DownloadJob,
        destinationPath: String,
        includeCustomOverride: Bool,
        completion:
            @escaping @MainActor (NSImage?) -> Void
    ) -> UUID {
        cancelAndClear()

        let requestID = UUID()
        let loadImage = loadImage
        activeRequestID = requestID
        task = Task { @MainActor [weak self] in
            let image = await loadImage(
                job,
                destinationPath,
                includeCustomOverride
            )
            guard !Task.isCancelled,
                  self?.finish(requestID) == true else {
                return
            }
            completion(image)
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
