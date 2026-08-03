import Foundation

final class OutputPathRepairService: @unchecked Sendable {
    typealias ExistingOutputLocator =
        @Sendable (
            _ outputPath: String,
            _ destinationPath: String
        ) -> URL?

    private let existingOutputLocator:
        ExistingOutputLocator

    init(
        existingOutputLocator:
            @escaping ExistingOutputLocator = {
                outputPath,
                destinationPath in
                QueueThumbnailProvider
                    .existingOutputURL(
                        forOutputPath: outputPath,
                        destinationPath:
                            destinationPath
                    )
            }
    ) {
        self.existingOutputLocator =
            existingOutputLocator
    }

    func existingOutputPath(
        for outputPath: String,
        destinationPath: String
    ) async -> String? {
        let existingOutputLocator =
            existingOutputLocator
        let searchTask =
            Task.detached(
                priority: .userInitiated
            ) {
                existingOutputLocator(
                    outputPath,
                    destinationPath
                )?.path
            }
        return await withTaskCancellationHandler {
            await searchTask.value
        } onCancel: {
            searchTask.cancel()
        }
    }
}
