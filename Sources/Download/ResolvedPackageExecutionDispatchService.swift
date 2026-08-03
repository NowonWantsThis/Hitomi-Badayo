import Foundation

struct ResolvedPackageExecutionActions {
    var downloadFiles: () async throws -> Void
    var concatenate: (String) async throws -> Void
    var mux:
        ([ResolvedAsset], [ResolvedAsset], String) async throws -> Void
    var grouped:
        (
            [Int],
            [ResolvedConcatenationGroup],
            [ResolvedMuxGroup]
        ) async throws -> Void
}

@MainActor
final class ResolvedPackageExecutionDispatchService {
    func execute(
        _ mode: DownloadPackageMode,
        actions: ResolvedPackageExecutionActions
    ) async throws {
        switch mode {
        case .files:
            try await actions.downloadFiles()
        case .concatenate(let outputFilename):
            try await actions.concatenate(outputFilename)
        case .mux(
            let videoAssets,
            let audioAssets,
            let outputFilename
        ):
            try await actions.mux(
                videoAssets,
                audioAssets,
                outputFilename
            )
        case .grouped(
            let fileAssetIndexes,
            let concatenations
        ):
            try await actions.grouped(
                fileAssetIndexes,
                concatenations,
                []
            )
        case .groupedMedia(
            let fileAssetIndexes,
            let concatenations,
            let muxes
        ):
            try await actions.grouped(
                fileAssetIndexes,
                concatenations,
                muxes
            )
        }
    }
}
