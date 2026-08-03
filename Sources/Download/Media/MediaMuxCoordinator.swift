import Foundation

struct MediaMuxRequest {
    var videoAssets: [ResolvedAsset]
    var audioAssets: [ResolvedAsset]
    var workFolder: URL
    var output: URL
    var options: FFmpegTranscodeOptions
}

enum MediaMuxEvent {
    case preparingVideo
    case preparingAudio
    case preparingFinalization(transcoding: Bool)
    case completed(
        output: URL,
        options: FFmpegTranscodeOptions
    )
}

struct MediaMuxOperations {
    var downloadAndConcatenate:
        (
            _ assets: [ResolvedAsset],
            _ temporaryFolder: URL,
            _ output: URL
        ) async throws -> Void
    var mux:
        (
            _ video: URL,
            _ audio: URL,
            _ output: URL,
            _ options: FFmpegTranscodeOptions
        ) async throws -> Void
    var onEvent: @MainActor (MediaMuxEvent) async -> Bool
}

@MainActor
final class MediaMuxCoordinator {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func execute(
        _ request: MediaMuxRequest,
        operations: MediaMuxOperations
    ) async throws {
        let videoFolder = request.workFolder.appendingPathComponent(
            "video",
            isDirectory: true
        )
        let audioFolder = request.workFolder.appendingPathComponent(
            "audio",
            isDirectory: true
        )
        let videoTrack = request.workFolder.appendingPathComponent(
            "video-track.mp4"
        )
        let audioTrack = request.workFolder.appendingPathComponent(
            "audio-track.m4a"
        )
        try AppPaths.ensureDirectory(videoFolder)
        try AppPaths.ensureDirectory(audioFolder)
        defer { try? fileManager.removeItem(at: request.workFolder) }

        guard await operations.onEvent(.preparingVideo) else { return }
        try await operations.downloadAndConcatenate(
            request.videoAssets,
            videoFolder,
            videoTrack
        )
        guard await operations.onEvent(.preparingAudio) else { return }
        try await operations.downloadAndConcatenate(
            request.audioAssets,
            audioFolder,
            audioTrack
        )
        guard await operations.onEvent(
            .preparingFinalization(
                transcoding: request.options.enabled
            )
        ) else {
            return
        }
        try await operations.mux(
            videoTrack,
            audioTrack,
            request.output,
            request.options
        )
        _ = await operations.onEvent(
            .completed(
                output: request.output,
                options: request.options
            )
        )
    }
}
