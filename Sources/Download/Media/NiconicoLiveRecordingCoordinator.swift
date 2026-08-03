import Foundation

struct NiconicoLiveRecordingRequest {
    var resolved: ResolvedDownload
    var sessionToken: String
    var root: URL
    var sourceURL: URL
    var jobID: UUID
    var options: FFmpegTranscodeOptions
}

enum NiconicoLiveRecordingEvent {
    case starting(
        output: URL,
        transcoding: Bool,
        startedAt: String
    )
    case failure(cancelled: Bool, hasPartialOutput: Bool)
    case completed(
        output: URL,
        hadSeparateAudio: Bool,
        options: FFmpegTranscodeOptions,
        byteCount: Int?
    )
}

struct NiconicoLiveRecordingOperations {
    var outputName:
        (_ resolved: ResolvedDownload, _ sourceURL: URL) -> String
    var uniqueOutput: (_ root: URL, _ filename: String) -> URL
    var record:
        (
            _ jobID: UUID,
            _ videoPlaylist: URL,
            _ audioPlaylist: URL?,
            _ output: URL,
            _ headers: [String: String],
            _ options: FFmpegTranscodeOptions,
            _ onStart: @escaping @MainActor () async -> Void
        ) async throws -> Void
    var stopSession: (_ token: String) async -> Void
    var onEvent: @MainActor (NiconicoLiveRecordingEvent) async -> Void
    var now: () -> Date = Date.init
}

@MainActor
final class NiconicoLiveRecordingCoordinator {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func execute(
        _ request: NiconicoLiveRecordingRequest,
        operations: NiconicoLiveRecordingOperations
    ) async throws {
        let resolved = request.resolved
        guard let rawVideoURL = resolved.metadata[
            "video_playlist_url"
        ], let videoPlaylist = URL(string: rawVideoURL),
              let filename = resolved.metadata[
                "live_output_filename"
              ]?.trimmed,
              !filename.isEmpty else {
            await operations.stopSession(request.sessionToken)
            throw NativeDownloadError.unsupported(
                "Niconico Live recording information is incomplete."
            )
        }
        let audioPlaylist = resolved.metadata[
            "audio_playlist_url"
        ].flatMap { raw -> URL? in
            let value = raw.trimmed
            return value.isEmpty ? nil : URL(string: value)
        }
        let output = operations.uniqueOutput(
            request.root,
            operations.outputName(resolved, request.sourceURL)
        )
        let prototype = resolved.assets.first
        var headers = prototype?.additionalHeaderFields ?? [:]
        if let referer = prototype?.referer?.trimmed,
           !referer.isEmpty {
            headers["Referer"] = referer
        }
        if let userAgent = prototype?.userAgent?.trimmed,
           !userAgent.isEmpty {
            headers["User-Agent"] = userAgent
        }

        do {
            try await operations.record(
                request.jobID,
                videoPlaylist,
                audioPlaylist,
                output,
                headers,
                request.options
            ) {
                await operations.onEvent(
                    .starting(
                        output: output,
                        transcoding: request.options.enabled,
                        startedAt: ISO8601DateFormatter().string(
                            from: operations.now()
                        )
                    )
                )
            }
        } catch {
            await operations.stopSession(request.sessionToken)
            let hasPartialOutput = MediaFileInspection.hasContent(output)
            await operations.onEvent(
                .failure(
                    cancelled: error is CancellationError,
                    hasPartialOutput: hasPartialOutput
                )
            )
            if !hasPartialOutput {
                try? fileManager.removeItem(at: output)
            }
            throw error
        }

        await operations.stopSession(request.sessionToken)
        await operations.onEvent(
            .completed(
                output: output,
                hadSeparateAudio: audioPlaylist != nil,
                options: request.options,
                byteCount: try? output.resourceValues(
                    forKeys: [.fileSizeKey]
                ).fileSize
            )
        )
    }
}
