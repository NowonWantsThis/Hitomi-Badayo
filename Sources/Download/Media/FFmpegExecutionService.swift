import Foundation

enum FFmpegExecutionRequest {
    case mux(
        video: URL,
        audio: URL,
        output: URL,
        options: FFmpegTranscodeOptions
    )
    case remux(
        input: URL,
        output: URL,
        options: FFmpegTranscodeOptions
    )
    case liveRecording(
        videoPlaylist: URL,
        audioPlaylist: URL?,
        output: URL,
        headers: [String: String],
        options: FFmpegTranscodeOptions,
        processControl: ExternalProcessControl?
    )
    case pixivUgoira(
        originalZip: Data,
        package: PixivUgoiraPackage,
        output: URL
    )
}

struct FFmpegExecutionOperations {
    var mux: (
        _ video: URL,
        _ audio: URL,
        _ output: URL,
        _ options: FFmpegTranscodeOptions
    ) async throws -> Void
    var remux: (
        _ input: URL,
        _ output: URL,
        _ options: FFmpegTranscodeOptions
    ) async throws -> Void
    var liveRecording: (
        _ videoPlaylist: URL,
        _ audioPlaylist: URL?,
        _ output: URL,
        _ headers: [String: String],
        _ options: FFmpegTranscodeOptions,
        _ processControl: ExternalProcessControl?
    ) async throws -> Void
    var pixivUgoira: (
        _ originalZip: Data,
        _ package: PixivUgoiraPackage,
        _ output: URL
    ) async throws -> Void

    static func live(bridge: FFmpegBridge) -> FFmpegExecutionOperations {
        FFmpegExecutionOperations(
            mux: { video, audio, output, options in
                try await bridge.mux(
                    video: video,
                    audio: audio,
                    output: output,
                    options: options
                )
            },
            remux: { input, output, options in
                try await bridge.remux(
                    input: input,
                    output: output,
                    options: options
                )
            },
            liveRecording: {
                videoPlaylist,
                audioPlaylist,
                output,
                headers,
                options,
                processControl in
                try await bridge.recordLiveHLS(
                    videoPlaylist: videoPlaylist,
                    audioPlaylist: audioPlaylist,
                    output: output,
                    headers: headers,
                    options: options,
                    processControl: processControl
                )
            },
            pixivUgoira: { originalZip, package, output in
                try await bridge.convertPixivUgoira(
                    originalZip: originalZip,
                    package: package,
                    output: output
                )
            }
        )
    }
}

final class FFmpegExecutionService {
    private let operations: FFmpegExecutionOperations

    init(bridge: FFmpegBridge = FFmpegBridge()) {
        operations = .live(bridge: bridge)
    }

    init(operations: FFmpegExecutionOperations) {
        self.operations = operations
    }

    func execute(_ request: FFmpegExecutionRequest) async throws {
        switch request {
        case .mux(let video, let audio, let output, let options):
            try await operations.mux(video, audio, output, options)
        case .remux(let input, let output, let options):
            try await operations.remux(input, output, options)
        case .liveRecording(
            let videoPlaylist,
            let audioPlaylist,
            let output,
            let headers,
            let options,
            let processControl
        ):
            try await operations.liveRecording(
                videoPlaylist,
                audioPlaylist,
                output,
                headers,
                options,
                processControl
            )
        case .pixivUgoira(let originalZip, let package, let output):
            try await operations.pixivUgoira(originalZip, package, output)
        }
    }
}
