import Foundation

struct FFmpegTranscodeOptions: Equatable {
    var enabled: Bool
    var videoCodec: String
    var audioCodec: String
    var videoBitrate: String
    var audioBitrate: String
    var crf: String
    var preset: String

    static let defaults = FFmpegTranscodeOptions(
        enabled: false,
        videoCodec: "libx264",
        audioCodec: "aac",
        videoBitrate: "",
        audioBitrate: "",
        crf: "23",
        preset: "medium"
    )

    var normalized: FFmpegTranscodeOptions {
        FFmpegTranscodeOptions(
            enabled: enabled,
            videoCodec: Self.requiredToken(videoCodec, fallback: Self.defaults.videoCodec),
            audioCodec: Self.requiredToken(audioCodec, fallback: Self.defaults.audioCodec),
            videoBitrate: Self.optionalBitrate(videoBitrate),
            audioBitrate: Self.optionalBitrate(audioBitrate),
            crf: Self.optionalCRF(crf),
            preset: Self.optionalToken(preset)
        )
    }

    var ffmpegArguments: [String] {
        let options = normalized
        guard options.enabled else { return ["-c", "copy"] }

        var arguments = [
            "-c:v", options.videoCodec,
            "-c:a", options.audioCodec
        ]
        if !options.videoBitrate.isEmpty {
            arguments += ["-b:v", options.videoBitrate]
        }
        if !options.audioBitrate.isEmpty {
            arguments += ["-b:a", options.audioBitrate]
        }
        if !options.preset.isEmpty {
            arguments += ["-preset", options.preset]
        }
        if !options.crf.isEmpty {
            arguments += ["-crf", options.crf]
        }
        return arguments
    }

    var metadata: [String: String] {
        let options = normalized
        guard options.enabled else { return [:] }

        var metadata = [
            "ffmpeg_mode": "transcode",
            "ffmpeg_video_codec": options.videoCodec,
            "ffmpeg_audio_codec": options.audioCodec
        ]
        if !options.videoBitrate.isEmpty {
            metadata["ffmpeg_video_bitrate"] = options.videoBitrate
        }
        if !options.audioBitrate.isEmpty {
            metadata["ffmpeg_audio_bitrate"] = options.audioBitrate
        }
        if !options.crf.isEmpty {
            metadata["ffmpeg_crf"] = options.crf
        }
        if !options.preset.isEmpty {
            metadata["ffmpeg_preset"] = options.preset
        }
        return metadata
    }

    private static func requiredToken(_ raw: String, fallback: String) -> String {
        let token = optionalToken(raw)
        return token.isEmpty ? fallback : token
    }

    private static func optionalToken(_ raw: String) -> String {
        let value = raw.trimmed
        guard !value.isEmpty else { return "" }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._+-")
        guard value.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return "" }
        return value
    }

    private static func optionalBitrate(_ raw: String) -> String {
        let value = raw.trimmed
        guard !value.isEmpty else { return "" }
        let allowed = CharacterSet(charactersIn: "0123456789kKmMgG")
        guard value.unicodeScalars.allSatisfy({ allowed.contains($0) }),
              value.unicodeScalars.contains(where: { CharacterSet.decimalDigits.contains($0) }) else {
            return ""
        }
        return value
    }

    private static func optionalCRF(_ raw: String) -> String {
        let value = raw.trimmed
        guard !value.isEmpty else { return "" }
        let allowed = CharacterSet(charactersIn: "0123456789.")
        guard value.unicodeScalars.allSatisfy({ allowed.contains($0) }),
              value.filter({ $0 == "." }).count <= 1,
              let numeric = Double(value),
              numeric >= 0,
              numeric <= 63 else {
            return ""
        }
        return value
    }
}

final class FFmpegBridge {
    private static let executionGate = FFmpegExecutionGate()

    func mux(video: URL, audio: URL, output: URL, options: FFmpegTranscodeOptions = .defaults) async throws {
        guard let executable = executableURL() else {
            throw NativeDownloadError.unsupported("FFmpeg is not installed. Open Settings > External Tools to install it or choose an executable.")
        }

        let command = FFmpegCommandBuilder.mux(
            video: video,
            audio: audio,
            output: output,
            options: options
        )
        try await run(
            executable: executable,
            arguments: command.arguments,
            logURL: command.logURL
        )
        try? FileManager.default.removeItem(at: command.logURL)
    }

    func remux(input: URL, output: URL, options: FFmpegTranscodeOptions = .defaults) async throws {
        guard let executable = executableURL() else {
            throw NativeDownloadError.unsupported("FFmpeg is not installed. Open Settings > External Tools to install it or choose an executable.")
        }

        let command = FFmpegCommandBuilder.remux(
            input: input,
            output: output,
            options: options
        )
        try await run(
            executable: executable,
            arguments: command.arguments,
            logURL: command.logURL
        )
        try? FileManager.default.removeItem(at: command.logURL)
    }

    func convertPixivUgoira(
        originalZip: Data,
        package: PixivUgoiraPackage,
        output: URL
    ) async throws {
        guard package.outputFormat.requiresFFmpeg else {
            throw NativeDownloadError.unsupported("Pixiv ugoira conversion format is invalid.")
        }
        guard let executable = executableURL() else {
            throw NativeDownloadError.unsupported("FFmpeg is not installed. Open Settings > External Tools to install it or choose .ugoira/.zip in Settings > Pixiv.")
        }
        guard !package.frames.isEmpty else {
            throw NativeDownloadError.unsupported("Pixiv ugoira has no frame timing metadata.")
        }

        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("HitomiBadayo-PixivUgoira-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }

        let archiveURL = work.appendingPathComponent("source.zip")
        try originalZip.write(to: archiveURL, options: .atomic)
        let entries = try ZipArchiveReader.entries(in: archiveURL)
        var entriesByName: [String: ZipArchiveReader.Entry] = [:]
        for entry in entries where entriesByName[entry.name] == nil {
            entriesByName[entry.name] = entry
        }

        var manifestLines = ["ffconcat version 1.0"]
        var finalFrameName = ""
        for (index, frame) in package.frames.enumerated() {
            guard let entry = entriesByName[frame.file] ?? entries.first(where: { $0.name.hasSuffix("/\(frame.file)") }) else {
                throw NativeDownloadError.unsupported("Pixiv ugoira frame is missing from the source ZIP: \(frame.file)")
            }
            let sourceExtension = (frame.file as NSString).pathExtension.lowercased()
            let safeExtension = ["avif", "bmp", "jpeg", "jpg", "png", "webp"].contains(sourceExtension)
                ? sourceExtension
                : "jpg"
            let frameName = String(format: "frame-%06d.%@", index, safeExtension)
            let frameURL = work.appendingPathComponent(frameName)
            try ZipArchiveReader.data(for: entry, in: archiveURL).write(to: frameURL, options: .atomic)
            manifestLines.append("file \(frameName)")
            manifestLines.append(String(format: "duration %.6f", Double(max(1, frame.delay)) / 1_000))
            finalFrameName = frameName
        }
        manifestLines.append("file \(finalFrameName)")

        let manifestURL = work.appendingPathComponent("frames.ffconcat")
        try (manifestLines.joined(separator: "\n") + "\n").write(to: manifestURL, atomically: true, encoding: .utf8)
        if FileManager.default.fileExists(atPath: output.path) {
            try FileManager.default.removeItem(at: output)
        }

        let quality = min(max(1, package.quality), 100)
        var arguments = [
            "-hide_banner", "-nostdin", "-loglevel", "warning", "-y",
            "-f", "concat", "-safe", "0", "-i", manifestURL.path,
            "-fps_mode", "vfr"
        ]
        switch package.outputFormat {
        case .gif:
            let colors = min(256, max(16, 16 + Int((Double(quality) / 100) * 240)))
            let dither = package.dither ? "sierra2_4a" : "none"
            arguments += [
                "-filter_complex",
                "[0:v]split[p0][p1];[p0]palettegen=max_colors=\(colors):stats_mode=diff[p];[p1][p]paletteuse=dither=\(dither)",
                "-loop", "0"
            ]
        case .webp:
            arguments += [
                "-an", "-c:v", "libwebp_anim", "-lossless", "0",
                "-q:v", String(quality), "-loop", "0"
            ]
        case .png:
            arguments += ["-an", "-c:v", "apng", "-plays", "0", "-f", "apng"]
        case .ugoira, .zip:
            throw NativeDownloadError.unsupported("Pixiv ugoira conversion format is invalid.")
        }
        arguments.append(output.path)

        let logURL = work.appendingPathComponent("ffmpeg.log")
        try await run(executable: executable, arguments: arguments, logURL: logURL)
        guard FileManager.default.fileExists(atPath: output.path) else {
            throw NativeDownloadError.unsupported("FFmpeg did not create the Pixiv ugoira output.")
        }
    }

    func recordLiveHLS(
        videoPlaylist: URL,
        audioPlaylist: URL?,
        output: URL,
        headers: [String: String],
        options: FFmpegTranscodeOptions = .defaults,
        processControl: ExternalProcessControl? = nil
    ) async throws {
        guard let executable = executableURL() else {
            throw NativeDownloadError.unsupported("FFmpeg is not installed. Open Settings > External Tools to install it or choose an executable.")
        }

        if FileManager.default.fileExists(atPath: output.path) {
            try FileManager.default.removeItem(at: output)
        }

        let command = FFmpegCommandBuilder.liveRecording(
            videoPlaylist: videoPlaylist,
            audioPlaylist: audioPlaylist,
            output: output,
            headers: headers,
            options: options
        )
        try await run(
            executable: executable,
            arguments: command.arguments,
            logURL: command.logURL,
            processControl: processControl
        )
        try? FileManager.default.removeItem(at: command.logURL)
    }

    private func executableURL() -> URL? {
        ExternalToolSettings.executableURL(
            kind: .ffmpeg,
            environmentKey: "HITOMI_NATIVE_FFMPEG",
            executableName: "ffmpeg",
            knownPaths: [
                "/opt/homebrew/bin/ffmpeg",
                "/usr/local/bin/ffmpeg",
                "/usr/bin/ffmpeg"
            ]
        )
    }

    private func run(
        executable: URL,
        arguments: [String],
        logURL: URL,
        processControl: ExternalProcessControl? = nil
    ) async throws {
        await Self.executionGate.wait()
        do {
            try await ExternalProcessRunner.run(
                executable: executable,
                arguments: arguments,
                logURL: logURL,
                control: processControl,
                failureDescription: "ffmpeg"
            )
            await Self.executionGate.signal()
        } catch {
            await Self.executionGate.signal()
            throw error
        }
    }

    private static func tail(_ text: String) -> String {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmed }
            .filter { !$0.isEmpty }
        let tail = lines.suffix(6).joined(separator: " ")
        return tail.isEmpty ? "no diagnostic output" : tail
    }
}

private actor FFmpegExecutionGate {
    private var isRunning = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if !isRunning {
            isRunning = true
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func signal() {
        if waiters.isEmpty {
            isRunning = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}
