import Foundation

struct MediaConcatenationRequest {
    var assets: [ResolvedAsset]
    var temporaryFolder: URL
    var output: URL
}

enum MediaConcatenationEvent {
    case joiningSegments
}

struct MediaConcatenationOperations {
    var downloadAssets:
        (_ assets: [ResolvedAsset], _ folder: URL) async throws -> [URL]
    var onEvent: (MediaConcatenationEvent) -> Void
}

@MainActor
final class MediaConcatenationCoordinator {
    let concatenationService: MediaConcatenationService
    private let fileManager: FileManager

    init(
        concatenationService: MediaConcatenationService =
            MediaConcatenationService(),
        fileManager: FileManager = .default
    ) {
        self.concatenationService = concatenationService
        self.fileManager = fileManager
    }

    func execute(
        _ request: MediaConcatenationRequest,
        operations: MediaConcatenationOperations
    ) async throws {
        _ = try await operations.downloadAssets(
            request.assets,
            request.temporaryFolder
        )
        operations.onEvent(.joiningSegments)
        try concatenationService.concatenateContents(
            of: request.temporaryFolder,
            to: request.output
        )
        try? fileManager.removeItem(at: request.temporaryFolder)
    }
}
