import Foundation

struct ResolvedMuxPackageOperations {
    var mergedMetadata:
        (
            [String: String],
            [String: String]
        ) -> [String: String]
    var templatedFileName:
        (
            String,
            String,
            URL,
            Int,
            [String: String]
        ) -> String
    var downloadAndMux:
        (
            [ResolvedAsset],
            [ResolvedAsset],
            String,
            String,
            URL,
            Int
        ) async throws -> Void
}

final class ResolvedMuxPackageCoordinator {
    func execute(
        _ resolved: ResolvedDownload,
        videoAssets: [ResolvedAsset],
        audioAssets: [ResolvedAsset],
        outputFilename: String,
        root: URL,
        folderName: String,
        sourceURL: URL,
        jobIndex: Int,
        operations: ResolvedMuxPackageOperations
    ) async throws {
        let assetMetadata =
            videoAssets.first?.metadata ??
            audioAssets.first?.metadata ??
            [:]
        let metadata = operations.mergedMetadata(
            resolved.metadata,
            assetMetadata
        )
        let outputName = operations.templatedFileName(
            outputFilename,
            resolved.title,
            sourceURL,
            resolved.assets.count,
            metadata
        )
        try await operations.downloadAndMux(
            videoAssets,
            audioAssets,
            folderName,
            outputName,
            root,
            jobIndex
        )
    }
}
