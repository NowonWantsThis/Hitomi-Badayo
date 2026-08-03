import Foundation

struct FFmpegCommand: Equatable {
    var arguments: [String]
    var logURL: URL
}

enum FFmpegCommandBuilder {
    static func mux(
        video: URL,
        audio: URL,
        output: URL,
        options: FFmpegTranscodeOptions
    ) -> FFmpegCommand {
        FFmpegCommand(
            arguments: [
                "-y",
                "-i", video.path,
                "-i", audio.path
            ] + options.ffmpegArguments + [
                "-movflags", "+faststart",
                output.path
            ],
            logURL: output.deletingLastPathComponent()
                .appendingPathComponent(
                    ".\(output.deletingPathExtension().lastPathComponent)-ffmpeg.log"
                )
        )
    }

    static func remux(
        input: URL,
        output: URL,
        options: FFmpegTranscodeOptions
    ) -> FFmpegCommand {
        FFmpegCommand(
            arguments: [
                "-y",
                "-i", input.path
            ] + options.ffmpegArguments + [
                "-movflags", "+faststart",
                output.path
            ],
            logURL: output.deletingLastPathComponent()
                .appendingPathComponent(
                    ".\(output.deletingPathExtension().lastPathComponent)-ffmpeg-remux.log"
                )
        )
    }

    static func liveRecording(
        videoPlaylist: URL,
        audioPlaylist: URL?,
        output: URL,
        headers: [String: String],
        options: FFmpegTranscodeOptions
    ) -> FFmpegCommand {
        var arguments = [
            "-hide_banner",
            "-nostdin",
            "-loglevel", "warning",
            "-y"
        ]
        arguments += liveInputArguments(
            headers: headers,
            inputURL: videoPlaylist
        ) + ["-i", videoPlaylist.absoluteString]
        if let audioPlaylist {
            arguments += liveInputArguments(
                headers: headers,
                inputURL: audioPlaylist
            ) + ["-i", audioPlaylist.absoluteString]
            arguments += ["-map", "0:v:0", "-map", "1:a:0"]
        } else {
            arguments += ["-map", "0:v:0", "-map", "0:a:0?"]
        }
        arguments += options.ffmpegArguments + [
            "-avoid_negative_ts", "make_zero",
            "-movflags", "+faststart",
            output.path
        ]

        return FFmpegCommand(
            arguments: arguments,
            logURL: output.deletingLastPathComponent()
                .appendingPathComponent(
                    ".\(output.deletingPathExtension().lastPathComponent)-ffmpeg-live.log"
                )
        )
    }

    private static func liveInputArguments(
        headers: [String: String],
        inputURL: URL
    ) -> [String] {
        var arguments = ["-thread_queue_size", "4096"]
        let scheme = inputURL.scheme?.lowercased()
        guard scheme == "http" || scheme == "https" else {
            return arguments
        }
        arguments += [
            "-reconnect", "1",
            "-reconnect_streamed", "1",
            "-reconnect_delay_max", "5"
        ]
        let headerBlock = headers
            .compactMap { name, value -> (String, String)? in
                let cleanName = name.trimmed
                let cleanValue = value.trimmed
                guard !cleanName.isEmpty,
                      cleanName.range(
                        of: #"^[!#$%&'*+.^_`|~0-9A-Za-z-]+$"#,
                        options: .regularExpression
                      ) != nil,
                      !cleanValue.isEmpty,
                      !cleanValue.contains("\r"),
                      !cleanValue.contains("\n") else {
                    return nil
                }
                return (cleanName, cleanValue)
            }
            .sorted {
                $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending
            }
            .map { "\($0.0): \($0.1)\r\n" }
            .joined()
        if !headerBlock.isEmpty {
            arguments += ["-headers", headerBlock]
        }
        return arguments
    }
}
