import Foundation

struct MediaRemuxRequest {
    var output: URL
    var metadata: [String: String]
    var defaultEnabled: Bool
    var options: FFmpegTranscodeOptions
}

enum MediaRemuxEvent {
    case preparing(transcoding: Bool)
    case completed(
        output: URL,
        options: FFmpegTranscodeOptions
    )
}

struct MediaRemuxOperations {
    var uniqueOutput: (_ directory: URL, _ filename: String) -> URL
    var remux:
        (
            _ input: URL,
            _ output: URL,
            _ options: FFmpegTranscodeOptions
        ) async throws -> Void
    var onEvent: (MediaRemuxEvent) -> Void
}

@MainActor
final class MediaRemuxCoordinator {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func execute(
        _ request: MediaRemuxRequest,
        operations: MediaRemuxOperations
    ) async throws -> URL {
        guard MediaRemuxPolicy.shouldRemux(
            defaultEnabled: request.defaultEnabled,
            metadata: request.metadata
        ), MediaRemuxPolicy.isHLS(metadata: request.metadata) else {
            return request.output
        }

        operations.onEvent(
            .preparing(transcoding: request.options.enabled)
        )
        let output = operations.uniqueOutput(
            request.output.deletingLastPathComponent(),
            "\(request.output.deletingPathExtension().lastPathComponent).mp4"
        )
        try await operations.remux(
            request.output,
            output,
            request.options
        )
        try? fileManager.removeItem(at: request.output)
        operations.onEvent(
            .completed(output: output, options: request.options)
        )
        return output
    }
}

enum MediaRemuxPolicy {
    static func isHLS(metadata: [String: String]) -> Bool {
        metadata["type"] == "hls" || metadata["format"] == "m3u8"
    }

    static func shouldRemux(
        defaultEnabled: Bool,
        metadata: [String: String]
    ) -> Bool {
        if let required = metadata["hls_remux_required"],
           directiveValue(required) == true {
            return true
        }
        if let explicit = metadata[
            "python_stream_post_processing"
        ]?.trimmed.lowercased() {
            if ["true", "1", "yes", "on"].contains(explicit) {
                return true
            }
            if ["false", "0", "no", "off"].contains(explicit) {
                return false
            }
        }
        return defaultEnabled
    }

    private static func directiveValue(_ raw: String) -> Bool? {
        switch raw.trimmed.lowercased() {
        case "1", "true", "yes", "y", "on", "enable", "enabled":
            return true
        case "0", "false", "no", "n", "off", "disable", "disabled":
            return false
        default:
            return nil
        }
    }
}
