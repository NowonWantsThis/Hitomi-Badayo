import Foundation

struct YTDLPResult {
    let outputDirectory: URL
    let downloadedItems: [URL]
    let infoMetadata: [String: String]
    let wasInterrupted: Bool
}

struct YTDLPPlannedFormat: Equatable, Sendable {
    var formatID: String
    var expectedBytes: Int64?
}

struct YTDLPRuntimeUpdate: Equatable, Sendable {
    var downloadedBytes: Int64?
    var totalBytes: Int64?
    var speedBytesPerSecond: Int64?
    var etaSeconds: Int?
    var fraction: Double?
    var isLive: Bool?
    var liveStatus: String?
    var title: String?
    var mediaID: String? = nil
    var formatID: String? = nil
    var transferStatus: String? = nil
    var playlistIndex: Int? = nil
    var playlistCount: Int? = nil
    var plannedFormats: [YTDLPPlannedFormat]? = nil
}

final class YTDLPBridge {
    private let knownHosts = [
        "afreecatv.com",
        "avgle.com",
        "b23.tv",
        "bilibili.com",
        "bilibili.tv",
        "chzzk.naver.com",
        "dai.ly",
        "dailymotion.com",
        "douyin.com",
        "fb.watch",
        "facebook.com",
        "fc2.com",
        "hanime.tv",
        "instagram.co",
        "instagram.com",
        "ixigua.com",
        "bitchute.com",
        "iwara.tv",
        "kick.com",
        "kissjav.com",
        "kissjav.li",
        "mrjav.net",
        "tv.naver.com",
        "tvcast.naver.com",
        "nico.ms",
        "niconico.com",
        "nicovideo.jp",
        "odysee.com",
        "ok.ru",
        "pornhub.com",
        "pornhubpremium.com",
        "redd.it",
        "reddit.com",
        "rumble.com",
        "rutube.ru",
        "sina.com.cn",
        "soundcloud.com",
        "sooplive.com",
        "sooplive.co.kr",
        "streamable.com",
        "thisvid.com",
        "tiktok.com",
        "tokyomotion.net",
        "tumblr.com",
        "twitcasting.tv",
        "twitch.tv",
        "tver.jp",
        "vlive.tv",
        "v.redd.it",
        "vimeo.com",
        "vk.com",
        "vkvideo.ru",
        "weibo.cn",
        "weibo.com",
        "xhamster.com",
        "xnxx.com",
        "xvideos.com",
        "yourporn.sexy",
        "youku.com",
        "youporn.com",
        "x.com",
        "youtube.co",
        "youtube.com",
        "youtu.be",
        "yewtu.be",
        "twitter.com"
    ]

    func canResolve(_ url: URL) -> Bool {
        canResolve(url, siteRules: [])
    }

    func canResolve(_ url: URL, siteRules: [SiteRule]) -> Bool {
        guard let host = url.host?.lowercased() else { return false }

        if ProcessInfo.processInfo.environment["HITOMI_NATIVE_YTDLP_ALL"] == "1" {
            return true
        }

        if siteRules.contains(where: { $0.handler == .ytdlp && $0.matches(url) }) {
            return true
        }

        let normalized = Self.normalizedSourceURL(for: url)
        if Self.usesOriginalManagedExtractor(for: url) ||
            Self.usesOriginalManagedExtractor(for: normalized) {
            return true
        }
        if Self.isNativeOnlyMediaURL(url) || Self.isNativeOnlyMediaURL(normalized) {
            return false
        }

        if knownHosts.contains(where: { known in
            host == known || host.hasSuffix("." + known)
        }) {
            return true
        }

        if normalized.absoluteString != url.absoluteString,
           let normalizedHost = normalized.host?.lowercased(),
           knownHosts.contains(where: { known in
               normalizedHost == known || normalizedHost.hasSuffix("." + known)
           }) {
            return true
        }

        return Self.isFacebookHostAlias(host) ||
            Self.isXHamsterHostAlias(host) ||
            Self.isXNXXHostAlias(host) ||
            Self.isXVideosHostAlias(host)
    }

    static func usesOriginalManagedExtractor(for url: URL) -> Bool {
        (EtcVideoPageResolver.site(for: url) == .youku &&
            EtcVideoPageResolver.contentID(from: url) != nil) ||
            NaverTVResolver.clipID(from: url) != nil
    }

    func download(
        url: URL,
        to root: URL,
        headers: HTTPRequestOptions = HTTPRequestOptions(),
        youtubePreferredLanguage: String = "",
        youtubePreferredResolution: String = "",
        youtubePreferredAudioLanguage: String = "",
        soopPreferredResolution: String = "",
        extractAudioFormat: String? = nil,
        writeYouTubeThumbnail: Bool = false,
        reverseYouTubePlaylist: Bool = false,
        numberPlaylistFiles: Bool = false,
        writeYouTubeAutoSubtitles: Bool = false,
        youtubeSubtitleLanguages: String = "",
        embedYouTubeChapters: Bool = false,
        youtubeVideoCodecSort: String = "",
        preferYouTubeEnhancedBitrate: Bool = false,
        useYouTubeUploadDateForFileModificationTime: Bool = true,
        processControl: ExternalProcessControl? = nil,
        progressHandler: (@Sendable (YTDLPRuntimeUpdate) -> Void)? = nil
    ) async throws -> YTDLPResult {
        guard let executable = executableURL() else {
            throw NativeDownloadError.unsupported("yt-dlp is not installed. Open Settings > External Tools to install it or choose an executable.")
        }

        try AppPaths.ensureDirectory(root)
        let sourceURL = Self.normalizedSourceURL(for: url)

        let host = (sourceURL.host ?? url.host ?? "media").replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression)
        let outputDirectory = AppPaths.uniqueDirectoryURL(in: root, name: "\(host) media")
        try AppPaths.ensureDirectory(outputDirectory)

        let logURL = outputDirectory.appendingPathComponent("yt-dlp.log")
        var temporaryCookieDirectory: URL?
        let outputTemplate = Self.outputTemplate(for: sourceURL, numberPlaylistFiles: numberPlaylistFiles)
        var arguments = OriginalRuntimeCompatibility.ytdlpIsolationArguments + [
            "--newline",
            "--no-color",
            "--progress",
            "--no-simulate",
            "--print",
            "before_dl:HITOMI_NATIVE_INFO\t%(is_live)s\t%(live_status)s\t%(title)s",
            "--print",
            "before_dl:HITOMI_NATIVE_PLAN\t%(id)s\t%(playlist_index)s\t%(playlist_count)s\t%(format_id)s\t%(filesize)s\t%(filesize_approx)s\t%(requested_formats.0.format_id)s\t%(requested_formats.0.filesize)s\t%(requested_formats.0.filesize_approx)s\t%(requested_formats.1.format_id)s\t%(requested_formats.1.filesize)s\t%(requested_formats.1.filesize_approx)s\t%(requested_formats.2.format_id)s\t%(requested_formats.2.filesize)s\t%(requested_formats.2.filesize_approx)s\t%(requested_formats.3.format_id)s\t%(requested_formats.3.filesize)s\t%(requested_formats.3.filesize_approx)s",
            "--progress-template",
            "download:HITOMI_NATIVE_PROGRESS\t%(info.id)s\t%(info.format_id)s\t%(info.playlist_index)s\t%(info.playlist_count)s\t%(progress.status)s\t%(progress.downloaded_bytes)s\t%(progress.total_bytes)s\t%(progress.total_bytes_estimate)s\t%(progress.speed)s\t%(progress.eta)s\t%(progress._percent_str)s",
            "--concurrent-fragments",
            "4",
            "--paths",
            outputDirectory.path,
            "--write-info-json",
            "-o",
            outputTemplate
        ]
        if let deno = denoExecutableURL() {
            arguments.append(contentsOf: ["--js-runtimes", "deno:\(deno.path)"])
        }
        if let ffmpeg = ffmpegExecutableURL() {
            arguments.append(contentsOf: ["--ffmpeg-location", ffmpeg.deletingLastPathComponent().path])
        }
        if !Self.allowsPlaylist(for: sourceURL) {
            arguments.insert("--no-playlist", at: 0)
        }
        if Self.isYouTubeSource(sourceURL) {
            arguments.append("--hls-use-mpegts")
        }

        if let languageArgument = Self.youtubeLanguageExtractorArgument(for: sourceURL, preferredLanguage: youtubePreferredLanguage) {
            arguments.append(contentsOf: ["--extractor-args", languageArgument])
        }

        if let formatSelector = Self.youtubeFormatSelector(
            for: sourceURL,
            preferredResolution: youtubePreferredResolution,
            preferredAudioLanguage: youtubePreferredAudioLanguage,
            extractAudioFormat: extractAudioFormat
        ) {
            arguments.append(contentsOf: ["--format", formatSelector])
        }

        if let formatSelector = Self.soopFormatSelector(for: sourceURL, preferredResolution: soopPreferredResolution) {
            arguments.append(contentsOf: ["--format", formatSelector])
        }

        if let formatSelector = Self.tverFormatSelector(for: sourceURL) {
            arguments.append(contentsOf: ["--format", formatSelector])
        }

        if let formatSelector = Self.naverTVFormatSelector(for: sourceURL) {
            arguments.append(contentsOf: ["--format", formatSelector])
        }

        if Self.shouldWriteYouTubeThumbnail(for: sourceURL, enabled: writeYouTubeThumbnail) {
            arguments.append("--write-thumbnail")
        }

        if Self.shouldReverseYouTubePlaylist(for: sourceURL, enabled: reverseYouTubePlaylist) {
            arguments.append("--playlist-reverse")
        }

        if let subtitleLanguages = Self.vliveSubtitleLanguages(for: sourceURL) {
            arguments.append(contentsOf: [
                "--write-subs",
                "--sub-langs",
                subtitleLanguages,
                "--sub-format",
                "srt/vtt/best"
            ])
        } else if let subtitleLanguages = Self.youtubeAutoSubtitleLanguages(
            for: sourceURL,
            enabled: writeYouTubeAutoSubtitles,
            languages: youtubeSubtitleLanguages
        ) {
            arguments.append(contentsOf: [
                "--write-auto-subs",
                "--sub-langs",
                subtitleLanguages,
                "--sub-format",
                "srt/vtt/best"
            ])
        }

        if Self.shouldRestrictFilenames(for: sourceURL) {
            arguments.append("--restrict-filenames")
        }

        if Self.shouldEmbedYouTubeChapters(for: sourceURL, enabled: embedYouTubeChapters) {
            arguments.append("--embed-chapters")
        }

        if let formatSort = Self.youtubeFormatSortArgument(
            for: sourceURL,
            sort: youtubeVideoCodecSort,
            preferEnhancedBitrate: preferYouTubeEnhancedBitrate
        ) {
            arguments.append(contentsOf: ["--format-sort", formatSort])
        }

        if let extractAudioFormat = extractAudioFormat?.trimmed.lowercased(),
           !extractAudioFormat.isEmpty {
            arguments.append(contentsOf: [
                "--extract-audio",
                "--audio-format",
                extractAudioFormat
            ])
        }

        if let proxy = NetworkSettings.load().proxyArgument(for: sourceURL) {
            arguments.append(contentsOf: ["--proxy", proxy])
        }

        if let referer = headers.referer?.trimmed, !referer.isEmpty {
            arguments.append(contentsOf: ["--referer", referer])
        }

        if let userAgent = headers.userAgent?.trimmed, !userAgent.isEmpty {
            arguments.append(contentsOf: ["--user-agent", userAgent])
        }

        if let cookieText = await CookieStore.shared.netscapeCookieFile(for: sourceURL) {
            let cookieDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("HitomiBadayo-ytdlp-\(UUID().uuidString)", isDirectory: true)
            try AppPaths.ensureDirectory(cookieDirectory)
            let cookieURL = cookieDirectory.appendingPathComponent("cookies.txt")
            try cookieText.write(to: cookieURL, atomically: true, encoding: .utf8)
            temporaryCookieDirectory = cookieDirectory
            arguments.append(contentsOf: ["--cookies", cookieURL.path])
        }

        arguments.append(sourceURL.absoluteString)

        defer {
            if let temporaryCookieDirectory {
                try? FileManager.default.removeItem(at: temporaryCookieDirectory)
            }
        }

        let runtimeControl = processControl ?? ExternalProcessControl()
        let progressTask = progressHandler.map { handler in
            Task.detached(priority: .utility) {
                await Self.monitorProgressLog(
                    at: logURL,
                    outputDirectory: outputDirectory,
                    handler: handler
                )
            }
        }
        defer { progressTask?.cancel() }

        try await run(
            executable: executable,
            arguments: arguments,
            logURL: logURL,
            processControl: runtimeControl
        )
        progressTask?.cancel()
        if let progressTask {
            await progressTask.value
        }

        if runtimeControl.wasInterrupted {
            try await finalizeInterruptedPartials(in: outputDirectory)
        }

        let infoMetadata = Self.infoMetadata(in: outputDirectory)
        let items = try outputItems(in: outputDirectory)
        guard !items.isEmpty else {
            throw NativeDownloadError.unsupported("yt-dlp finished, but no media file was created.")
        }
        Self.applyYouTubeUploadModificationDates(
            in: outputDirectory,
            downloadedItems: items,
            sourceURL: sourceURL,
            enabled: useYouTubeUploadDateForFileModificationTime
        )
        try? Self.removeInfoJSONFiles(in: outputDirectory)

        try? FileManager.default.removeItem(at: logURL)
        return YTDLPResult(
            outputDirectory: outputDirectory,
            downloadedItems: items,
            infoMetadata: infoMetadata,
            wasInterrupted: runtimeControl.wasInterrupted
        )
    }

    private func executableURL() -> URL? {
        ExternalToolSettings.executableURL(
            kind: .ytdlp,
            environmentKey: "HITOMI_NATIVE_YTDLP",
            executableName: "yt-dlp",
            knownPaths: [
                "/opt/homebrew/bin/yt-dlp",
                "/usr/local/bin/yt-dlp",
                "/usr/bin/yt-dlp"
            ]
        )
    }

    private func ffmpegExecutableURL() -> URL? {
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

    private func denoExecutableURL() -> URL? {
        ExternalToolSettings.executableURL(
            kind: .deno,
            environmentKey: "HITOMI_NATIVE_DENO",
            executableName: "deno",
            knownPaths: [
                "/opt/homebrew/bin/deno",
                "/usr/local/bin/deno",
                "/usr/bin/deno"
            ]
        )
    }

    private func run(
        executable: URL,
        arguments: [String],
        logURL: URL,
        processControl: ExternalProcessControl
    ) async throws {
        try await ExternalProcessRunner.run(
            executable: executable,
            arguments: arguments,
            logURL: logURL,
            control: processControl,
            acceptInterruptedTermination: true,
            failureDescription: "yt-dlp"
        )
    }

    static func runtimeUpdate(from rawLine: String) -> YTDLPRuntimeUpdate? {
        let line = rawLine.trimmed
        if line.hasPrefix("HITOMI_NATIVE_INFO\t") {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 3 else { return nil }
            let liveFlag = normalizedRuntimeBool(fields[1])
            let liveStatus = normalizedRuntimeValue(fields[2])
            let title = fields.count > 3
                ? normalizedRuntimeValue(fields.dropFirst(3).joined(separator: "\t"))
                : nil
            return YTDLPRuntimeUpdate(
                downloadedBytes: nil,
                totalBytes: nil,
                speedBytesPerSecond: nil,
                etaSeconds: nil,
                fraction: nil,
                isLive: liveFlag,
                liveStatus: liveStatus,
                title: title
            )
        }

        if line.hasPrefix("HITOMI_NATIVE_PLAN\t") {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 7 else { return nil }
            let mediaID = normalizedRuntimeValue(fields[1])
            let playlistIndex = runtimeInt64(fields[2]).flatMap { Int(exactly: $0) }
            let playlistCount = runtimeInt64(fields[3]).flatMap { Int(exactly: $0) }
            let combinedFormatID = normalizedRuntimeValue(fields[4])
            let combinedBytes = runtimeInt64(fields[5]) ?? runtimeInt64(fields[6])
            var planned: [YTDLPPlannedFormat] = []
            var seen = Set<String>()
            var offset = 7
            while offset + 2 < fields.count {
                if let formatID = normalizedRuntimeValue(fields[offset]),
                   seen.insert(formatID).inserted {
                    planned.append(YTDLPPlannedFormat(
                        formatID: formatID,
                        expectedBytes: runtimeInt64(fields[offset + 1]) ?? runtimeInt64(fields[offset + 2])
                    ))
                }
                offset += 3
            }
            if planned.isEmpty, let combinedFormatID {
                planned = [YTDLPPlannedFormat(formatID: combinedFormatID, expectedBytes: combinedBytes)]
            }
            return YTDLPRuntimeUpdate(
                downloadedBytes: nil,
                totalBytes: combinedBytes,
                speedBytesPerSecond: nil,
                etaSeconds: nil,
                fraction: nil,
                isLive: nil,
                liveStatus: nil,
                title: nil,
                mediaID: mediaID,
                playlistIndex: playlistIndex,
                playlistCount: playlistCount,
                plannedFormats: planned
            )
        }

        if line.hasPrefix("HITOMI_NATIVE_PROGRESS\t") {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 7 else { return nil }
            let isDetailed = fields.count >= 12
            let mediaID = isDetailed ? normalizedRuntimeValue(fields[1]) : nil
            let formatID = isDetailed ? normalizedRuntimeValue(fields[2]) : nil
            let playlistIndex = isDetailed ? runtimeInt64(fields[3]).flatMap { Int(exactly: $0) } : nil
            let playlistCount = isDetailed ? runtimeInt64(fields[4]).flatMap { Int(exactly: $0) } : nil
            let status = isDetailed ? normalizedRuntimeValue(fields[5]) : nil
            let base = isDetailed ? 6 : 1
            let downloaded = runtimeInt64(fields[base])
            let total = runtimeInt64(fields[base + 1]) ?? runtimeInt64(fields[base + 2])
            let speed = runtimeInt64(fields[base + 3])
            let eta = runtimeInt64(fields[base + 4]).flatMap { Int(exactly: $0) }
            let explicitPercent = runtimeDouble(fields[base + 5]).map { min(1, max(0, $0 / 100)) }
            let fraction = explicitPercent ?? {
                guard let downloaded, let total, total > 0 else { return nil }
                return min(1, max(0, Double(downloaded) / Double(total)))
            }()
            return YTDLPRuntimeUpdate(
                downloadedBytes: downloaded,
                totalBytes: total,
                speedBytesPerSecond: speed,
                etaSeconds: eta,
                fraction: fraction,
                isLive: nil,
                liveStatus: nil,
                title: nil,
                mediaID: mediaID,
                formatID: formatID,
                transferStatus: status,
                playlistIndex: playlistIndex,
                playlistCount: playlistCount
            )
        }
        return nil
    }

    private static func monitorProgressLog(
        at logURL: URL,
        outputDirectory: URL,
        handler: @escaping @Sendable (YTDLPRuntimeUpdate) -> Void
    ) async {
        var reader: FileHandle?
        var remainder = ""
        var previousOutputBytes: Int64 = 0
        var previousOutputSampleDate = Date()
        defer { try? reader?.close() }

        while !Task.isCancelled {
            if reader == nil {
                reader = try? FileHandle(forReadingFrom: logURL)
            }
            if let reader,
               let data = try? reader.readToEnd(),
               !data.isEmpty {
                let text = remainder + String(decoding: data, as: UTF8.self)
                let endsWithNewline = text.hasSuffix("\n") || text.hasSuffix("\r")
                var lines = text.components(separatedBy: .newlines)
                remainder = endsWithNewline ? "" : (lines.popLast() ?? "")
                for line in lines {
                    if let update = runtimeUpdate(from: line) {
                        handler(update)
                    }
                }
            }
            let sampleDate = Date()
            let outputBytes = runtimeOutputBytes(in: outputDirectory)
            if outputBytes > previousOutputBytes {
                let elapsed = max(0.001, sampleDate.timeIntervalSince(previousOutputSampleDate))
                let speed = Int64(Double(outputBytes - previousOutputBytes) / elapsed)
                handler(YTDLPRuntimeUpdate(
                    downloadedBytes: outputBytes,
                    totalBytes: nil,
                    speedBytesPerSecond: speed,
                    etaSeconds: nil,
                    fraction: nil,
                    isLive: nil,
                    liveStatus: nil,
                    title: nil
                ))
                previousOutputBytes = outputBytes
                previousOutputSampleDate = sampleDate
            }
            try? await Task.sleep(nanoseconds: 150_000_000)
        }

        if let reader,
           let data = try? reader.readToEnd(),
           !data.isEmpty {
            remainder += String(decoding: data, as: UTF8.self)
        }
        for line in remainder.components(separatedBy: .newlines) {
            if let update = runtimeUpdate(from: line) {
                handler(update)
            }
        }
    }

    private static func runtimeOutputBytes(in directory: URL) -> Int64 {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]
        ) else { return 0 }
        return files.reduce(0) { total, file in
            let name = file.lastPathComponent
            guard name != "yt-dlp.log",
                  !name.hasSuffix(".info.json"),
                  !name.hasSuffix(".ytdl"),
                  !name.hasPrefix(".") else { return total }
            guard let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true else { return total }
            return total + Int64(values.fileSize ?? 0)
        }
    }

    private static func normalizedRuntimeBool(_ raw: String) -> Bool? {
        switch raw.trimmed.lowercased() {
        case "1", "true", "yes", "is_live", "live": return true
        case "0", "false", "no", "not_live", "was_live", "post_live": return false
        default: return nil
        }
    }

    private static func normalizedRuntimeValue(_ raw: String) -> String? {
        let value = raw.trimmed
        guard !value.isEmpty,
              !["na", "n/a", "none", "null", "unknown"].contains(value.lowercased()) else {
            return nil
        }
        return value
    }

    private static func runtimeInt64(_ raw: String) -> Int64? {
        guard let value = normalizedRuntimeValue(raw) else { return nil }
        if let integer = Int64(value) { return integer }
        return Double(value).flatMap { number in
            guard number.isFinite, number >= 0, number <= Double(Int64.max) else { return nil }
            return Int64(number)
        }
    }

    private static func runtimeDouble(_ raw: String) -> Double? {
        guard let value = normalizedRuntimeValue(raw) else { return nil }
        let numeric = value.replacingOccurrences(of: "%", with: "").trimmed
        return Double(numeric)
    }

    private func finalizeInterruptedPartials(in directory: URL) async throws {
        let fileManager = FileManager.default
        let initialFiles = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]
        )
        let partials = initialFiles.filter { file in
            guard file.lastPathComponent.hasSuffix(".part"),
                  !file.lastPathComponent.hasSuffix(".ytdl.part") else { return false }
            let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            return values?.isRegularFile == true && (values?.fileSize ?? 0) > 0
        }

        for partial in partials {
            let finalName = String(partial.lastPathComponent.dropLast(".part".count))
            guard !finalName.isEmpty else { continue }
            let final = directory.appendingPathComponent(finalName)
            if fileManager.fileExists(atPath: final.path) {
                continue
            }
            try await remuxInterruptedOutput(from: partial, to: final)
        }

        // yt-dlp may catch SIGINT itself and rename an MPEG-TS .part file to its
        // final .mp4 name before it exits. Inspect final names too so a valid TS
        // stream is never presented to QuickTime as though it were an MP4 file.
        let finalizedFiles = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]
        )
        for file in finalizedFiles where Self.requiresISOBaseMediaContainer(file) {
            let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values?.isRegularFile == true,
                  (values?.fileSize ?? 0) > 0,
                  Self.isMPEGTransportStream(at: file) else { continue }
            try await remuxInterruptedOutput(from: file, to: file)
        }
    }

    private func remuxInterruptedOutput(from input: URL, to final: URL) async throws {
        guard let ffmpeg = ffmpegExecutableURL() else {
            throw NativeDownloadError.unsupported(
                "FFmpeg is required to finalize the stopped live recording. The received stream was preserved."
            )
        }

        let fileManager = FileManager.default
        let outputExtension = final.pathExtension.isEmpty ? "mp4" : final.pathExtension
        let staging = final.deletingLastPathComponent().appendingPathComponent(
            ".ytdlp-finalize-\(UUID().uuidString).\(outputExtension)"
        )
        let finalizeLog = final.deletingLastPathComponent().appendingPathComponent(
            ".ytdlp-finalize-\(UUID().uuidString).log"
        )
        defer {
            try? fileManager.removeItem(at: staging)
            try? fileManager.removeItem(at: finalizeLog)
        }

        var arguments = [
            "-hide_banner", "-loglevel", "error", "-y",
            "-fflags", "+genpts",
            "-i", input.path,
            "-map", "0?",
            "-c", "copy",
            "-avoid_negative_ts", "make_zero"
        ]
        if Self.requiresISOBaseMediaContainer(final) {
            arguments.append(contentsOf: ["-movflags", "+faststart"])
        }
        arguments.append(staging.path)

        try await ExternalProcessRunner.run(
            executable: ffmpeg,
            arguments: arguments,
            logURL: finalizeLog,
            failureDescription: "FFmpeg live recording finalization"
        )

        let size = (try? staging.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size > 0,
              !Self.requiresISOBaseMediaContainer(final) || Self.hasISOBaseMediaHeader(at: staging) else {
            throw NativeDownloadError.unsupported(
                "FFmpeg did not create a playable live recording. The received stream was preserved."
            )
        }

        if input.standardizedFileURL == final.standardizedFileURL {
            let backup = final.deletingLastPathComponent().appendingPathComponent(
                ".ytdlp-original-\(UUID().uuidString)"
            )
            try fileManager.moveItem(at: final, to: backup)
            do {
                try fileManager.moveItem(at: staging, to: final)
                try? fileManager.removeItem(at: backup)
            } catch {
                if !fileManager.fileExists(atPath: final.path) {
                    try? fileManager.moveItem(at: backup, to: final)
                }
                throw error
            }
        } else {
            try fileManager.moveItem(at: staging, to: final)
            try fileManager.removeItem(at: input)
        }
    }

    private static func requiresISOBaseMediaContainer(_ file: URL) -> Bool {
        ["mp4", "m4a", "m4v", "mov"].contains(file.pathExtension.lowercased())
    }

    private static func isMPEGTransportStream(at file: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return false }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 188 * 4),
              data.count >= 188 * 3 else { return false }

        let maximumOffset = min(187, data.count - (188 * 2) - 1)
        guard maximumOffset >= 0 else { return false }
        return (0...maximumOffset).contains { offset in
            data[offset] == 0x47 &&
                data[offset + 188] == 0x47 &&
                data[offset + 376] == 0x47
        }
    }

    private static func hasISOBaseMediaHeader(at file: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return false }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 16),
              data.count >= 8 else { return false }
        return String(decoding: data[4..<8], as: UTF8.self) == "ftyp"
    }

    private func outputItems(in directory: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey])
            .filter { url in
                let name = url.lastPathComponent
                return name != "yt-dlp.log" &&
                    !name.hasSuffix(".info.json") &&
                    !name.hasPrefix(".") &&
                    !name.hasSuffix(".part") &&
                    !name.hasSuffix(".ytdl")
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private static func infoMetadata(in directory: URL) -> [String: String] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return [:]
        }

        let infoFiles = files
            .filter { $0.lastPathComponent.hasSuffix(".info.json") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        for file in infoFiles {
            guard let data = try? Data(contentsOf: file),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            return infoMetadata(from: object)
        }

        return [:]
    }

    private struct YouTubeModificationRecord {
        var exactNames: Set<String>
        var stems: Set<String>
        var date: Date
    }

    @discardableResult
    static func applyYouTubeUploadModificationDates(
        in directory: URL,
        downloadedItems: [URL],
        sourceURL: URL,
        enabled: Bool,
        fileManager: FileManager = .default
    ) -> Int {
        guard enabled,
              isYouTubeSource(sourceURL),
              let infoFiles = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
              ) else {
            return 0
        }

        let records = infoFiles
            .filter { $0.lastPathComponent.hasSuffix(".info.json") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { infoURL -> YouTubeModificationRecord? in
                guard let data = try? Data(contentsOf: infoURL),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let date = youtubeUploadModificationDate(from: infoMetadata(from: object)) else {
                    return nil
                }

                var exactNames = Set<String>()
                var stems = Set<String>()
                func addPath(_ raw: Any?) {
                    guard let value = stringValue(raw), !value.isEmpty else { return }
                    let name = URL(fileURLWithPath: value).lastPathComponent
                    guard !name.isEmpty else { return }
                    exactNames.insert(name)
                    stems.insert((name as NSString).deletingPathExtension)
                }

                addPath(object["filepath"])
                addPath(object["filename"])
                addPath(object["_filename"])
                if let requested = object["requested_downloads"] as? [[String: Any]] {
                    for item in requested {
                        addPath(item["filepath"])
                        addPath(item["filename"])
                        addPath(item["_filename"])
                    }
                }

                let infoName = infoURL.lastPathComponent
                let infoStem = String(infoName.dropLast(".info.json".count))
                if !infoStem.isEmpty {
                    stems.insert(infoStem)
                }
                return YouTubeModificationRecord(exactNames: exactNames, stems: stems, date: date)
            }

        guard !records.isEmpty else { return 0 }
        var appliedCount = 0
        for item in downloadedItems where youtubeMediaFileExtensions.contains(item.pathExtension.lowercased()) {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: item.path, isDirectory: &isDirectory),
                  !isDirectory.boolValue else {
                continue
            }
            let name = item.lastPathComponent
            let stem = (name as NSString).deletingPathExtension
            let record = records.first {
                $0.exactNames.contains(name) || $0.stems.contains(stem)
            } ?? (records.count == 1 ? records[0] : nil)
            guard let record else { continue }
            do {
                try fileManager.setAttributes([.modificationDate: record.date], ofItemAtPath: item.path)
                appliedCount += 1
            } catch {
                continue
            }
        }
        return appliedCount
    }

    static func youtubeUploadModificationDate(from metadata: [String: String]) -> Date? {
        guard let raw = metadata["upload_date"]?.trimmed,
              raw.range(of: #"^[0-9]{8}$"#, options: .regularExpression) != nil else {
            return nil
        }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd"
        formatter.isLenient = false
        guard let date = formatter.date(from: raw), formatter.string(from: date) == raw else {
            return nil
        }
        return date
    }

    static func isYouTubeSource(_ url: URL, metadata: [String: String] = [:]) -> Bool {
        if let host = url.host?.lowercased(), isYouTubeHost(host) {
            return true
        }
        let site = (metadata["site"] ?? "")
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: ".", with: "")
        if site == "youtube" {
            return true
        }
        return ["extractor", "extractor_key", "handler"].contains { key in
            metadata[key]?.lowercased().contains("youtube") == true
        }
    }

    private static let youtubeMediaFileExtensions: Set<String> = [
        "3gp", "aac", "aiff", "alac", "avi", "flac", "m4a", "m4v", "mka",
        "mkv", "mov", "mp3", "mp4", "mpeg", "mpg", "ogg", "opus", "ts",
        "wav", "webm"
    ]

    static func infoMetadata(from object: [String: Any]) -> [String: String] {
        let uploader = stringValue(object["uploader"])
        let channel = stringValue(object["channel"])
        let creator = stringValue(object["creator"])
        let primaryCreator = uploader ?? channel ?? creator
        let displayID = stringValue(object["display_id"])
        let id = stringValue(object["id"])
        let uploadDate = stringValue(object["upload_date"])
        let releaseDate = stringValue(object["release_date"])
        let webpageURL = stringValue(object["webpage_url"])
        let thumbnail = firstThumbnailURL(from: object) ?? stringValue(object["thumbnail"])
        var metadata: [String: String] = [:]
        metadata["media_title"] = stringValue(object["title"])
        metadata["id"] = id
        metadata["display_id"] = displayID
        metadata["media_id"] = displayID ?? id
        metadata["artist"] = primaryCreator
        metadata["author"] = primaryCreator
        metadata["creator"] = creator ?? primaryCreator
        metadata["uploader"] = uploader
        metadata["uploader_id"] = stringValue(object["uploader_id"])
        metadata["channel"] = channel
        metadata["channel_id"] = stringValue(object["channel_id"])
        metadata["webpage_url"] = webpageURL
        metadata["thumbnail"] = thumbnail
        metadata["thumbnail_referer"] = webpageURL
        metadata["extractor"] = stringValue(object["extractor"])
        metadata["extractor_key"] = stringValue(object["extractor_key"])
        metadata["format"] = stringValue(object["ext"])
        metadata["format_id"] = stringValue(object["format_id"])
        metadata["format_note"] = stringValue(object["format_note"])
        metadata["resolution"] = stringValue(object["resolution"])
        metadata["width"] = stringValue(object["width"])
        metadata["height"] = stringValue(object["height"])
        metadata["fps"] = stringValue(object["fps"])
        metadata["vcodec"] = stringValue(object["vcodec"])
        metadata["acodec"] = stringValue(object["acodec"])
        metadata["filesize"] = stringValue(object["filesize"]) ?? stringValue(object["filesize_approx"])
        metadata["duration"] = stringValue(object["duration"])
        metadata["duration_string"] = stringValue(object["duration_string"])
        metadata["upload_date"] = uploadDate
        metadata["release_date"] = releaseDate
        metadata["timestamp"] = stringValue(object["timestamp"])
        metadata["playlist"] = stringValue(object["playlist"])
        metadata["playlist_id"] = stringValue(object["playlist_id"])
        metadata["playlist_title"] = stringValue(object["playlist_title"])
        metadata["playlist_index"] = stringValue(object["playlist_index"])
        metadata["album"] = stringValue(object["album"])
        metadata["album_artist"] = stringValue(object["album_artist"])
        metadata["track"] = stringValue(object["track"])
        metadata["track_number"] = stringValue(object["track_number"])
        metadata["live_status"] = stringValue(object["live_status"])
        metadata["was_live"] = stringValue(object["was_live"])
        metadata["date"] = normalizedYTDLPDate(uploadDate) ??
            normalizedYTDLPDate(releaseDate) ??
            normalizedUnixTimestamp(object["timestamp"])
        return DownloadMetadata.clean(metadata)
    }

    private static func firstThumbnailURL(from object: [String: Any]) -> String? {
        guard let thumbnails = object["thumbnails"] as? [Any] else { return nil }
        for value in thumbnails {
            guard let thumbnail = value as? [String: Any],
                  let url = stringValue(thumbnail["url"]) else {
                continue
            }
            return url
        }
        return nil
    }

    static func sourceMetadata(for url: URL) -> [String: String] {
        let sourceURL = normalizedSourceURL(for: url)
        var metadata: [String: String] = [:]
        if let spaceID = twitterSpaceID(from: sourceURL) {
            metadata["category"] = "space"
            metadata["id"] = spaceID
            metadata["media_id"] = spaceID
            metadata["space_id"] = spaceID
            metadata["slug"] = spaceID
        } else if let broadcastID = twitterBroadcastID(from: sourceURL) {
            metadata["category"] = "broadcast"
            metadata["id"] = broadcastID
            metadata["media_id"] = broadcastID
            metadata["broadcast_id"] = broadcastID
            metadata["slug"] = broadcastID
        } else if let userID = twitterUserID(from: sourceURL) {
            metadata["category"] = "profile"
            metadata["id"] = userID
            metadata["media_id"] = userID
            metadata["user_id"] = userID
            metadata["uid"] = userID
            metadata["uids"] = userID
            metadata["slug"] = userID
        } else if let tver = tverSourceMetadata(from: sourceURL) {
            metadata.merge(tver) { _, new in new }
        }
        return DownloadMetadata.clean(metadata)
    }

    static func shouldRestrictFilenames(for url: URL) -> Bool {
        let sourceURL = normalizedSourceURL(for: url)
        let decodedPieces = [
            sourceURL.path.removingPercentEncoding ?? sourceURL.path,
            sourceURL.query?.removingPercentEncoding ?? sourceURL.query ?? "",
            sourceURL.fragment?.removingPercentEncoding ?? sourceURL.fragment ?? ""
        ]
        if decodedPieces.contains(where: containsNonASCII) {
            return true
        }

        let userMetadataKeys = ["artist", "author", "creator", "uploader", "channel", "username", "user", "user_id", "uid", "slug"]
        let metadata = sourceMetadata(for: sourceURL)
        return userMetadataKeys.contains { key in
            metadata[key].map(containsNonASCII) ?? false
        }
    }

    private static func containsNonASCII(_ text: String) -> Bool {
        text.unicodeScalars.contains { $0.value > 0x7F }
    }

    private static func removeInfoJSONFiles(in directory: URL) throws {
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        for file in files where file.lastPathComponent.hasSuffix(".info.json") {
            try FileManager.default.removeItem(at: file)
        }
    }

    private static func stringValue(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            let trimmed = string.trimmed
            return trimmed.isEmpty ? nil : trimmed
        case let number as NSNumber:
            return number.stringValue
        default:
            return nil
        }
    }

    private static func normalizedYTDLPDate(_ value: String?) -> String? {
        guard let value = value?.trimmed, !value.isEmpty else { return nil }
        if value.range(of: #"^[0-9]{8}$"#, options: .regularExpression) != nil {
            let year = value.prefix(4)
            let monthStart = value.index(value.startIndex, offsetBy: 4)
            let dayStart = value.index(value.startIndex, offsetBy: 6)
            let month = value[monthStart..<dayStart]
            let day = value[dayStart..<value.endIndex]
            return "\(year)-\(month)-\(day)"
        }
        if let match = value.range(of: #"[0-9]{4}-[0-9]{2}-[0-9]{2}"#, options: .regularExpression) {
            return String(value[match])
        }
        return nil
    }

    private static func normalizedUnixTimestamp(_ value: Any?) -> String? {
        let seconds: TimeInterval?
        if let number = value as? NSNumber {
            seconds = number.doubleValue
        } else if let string = value as? String {
            seconds = TimeInterval(string.trimmed)
        } else {
            seconds = nil
        }
        guard let seconds, seconds > 0 else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date(timeIntervalSince1970: seconds))
    }

    static func allowsPlaylist(for url: URL) -> Bool {
        if ProcessInfo.processInfo.environment["HITOMI_NATIVE_YTDLP_PLAYLIST"] == "1" {
            return true
        }

        guard let host = url.host?.lowercased() else { return false }
        let path = url.path.lowercased()
        let parts = path.split(separator: "/").map(String.init)
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []

        if InstagramResolver.profileUsername(from: url) != nil ||
            InstagramResolver.storyCollectionUsername(from: url) != nil {
            return true
        }

        if isYouTubeHost(host) {
            if parts.first == "playlist", queryItems.contains(where: { $0.name == "list" }) {
                return true
            }
            if let first = parts.first,
               ["channel", "user", "c"].contains(first),
               !path.hasSuffix("/live") {
                return true
            }
            if let first = parts.first, first.hasPrefix("@"), !path.hasSuffix("/live") {
                return true
            }
            return false
        }

        if isBilibiliHost(host) {
            return host.hasPrefix("space.") ||
                path.contains("/channel/collectiondetail") ||
                path.contains("/medialist/") ||
                path.contains("/medialist/detail") ||
                path.contains("/channel/") && queryItems.contains(where: { $0.name == "sid" || $0.name == "season_id" })
        }

        if isTwitchHost(host), isTwitchChannelListingPath(parts) {
            return true
        }

        if isXVideosHostAlias(host), isXVideosPlaylistPath(parts) {
            return true
        }

        if isXHamsterHostAlias(host), isXHamsterPlaylistPath(parts) {
            return true
        }

        if isIwaraHost(host), isIwaraPlaylistPath(parts) {
            return true
        }

        return false
    }

    static func normalizedSourceURL(for url: URL) -> URL {
        guard let host = url.host?.lowercased(),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }

        if isYouTubeHost(host) {
            return normalizedYouTubeURL(url, components: components, host: host)
        }

        if isGoogleRedirectHost(host),
           let nested = nestedYouTubeURL(from: components.queryItems ?? [], baseURL: url),
           let nestedHost = nested.host?.lowercased(),
           let nestedComponents = URLComponents(url: nested, resolvingAgainstBaseURL: false) {
            return normalizedYouTubeURL(nested, components: nestedComponents, host: nestedHost)
        }

        if host == "nico.ms" || host == "www.nico.ms" {
            let parts = url.path.split(separator: "/").map(String.init)
            if let videoID = parts.first, !videoID.isEmpty {
                components.scheme = "https"
                components.host = "www.nicovideo.jp"
                components.path = "/watch/\(videoID)"
                return components.url ?? url
            }
        }

        if host == "niconico.com" || host == "www.niconico.com" {
            let parts = url.path.split(separator: "/").map(String.init)
            if parts.count >= 2, parts.first?.lowercased() == "watch" {
                components.scheme = "https"
                components.host = "www.nicovideo.jp"
                components.path = "/watch/\(parts[1])"
                return components.url ?? url
            }
        }

        if host == "m.bilibili.com" {
            components.scheme = "https"
            components.host = "www.bilibili.com"
            return components.url ?? url
        }

        if host == "m.bilibili.tv" {
            components.scheme = "https"
            components.host = "www.bilibili.tv"
            return components.url ?? url
        }

        if host == "m.twitch.tv" {
            components.scheme = "https"
            components.host = "www.twitch.tv"
            return components.url ?? url
        }

        if isTwitterHost(host) {
            return normalizedTwitterURL(url, components: components, host: host)
        }

        if isTVerHost(host) {
            return normalizedTVerURL(url, components: components)
        }

        if isSOOPLiveAliasHost(host) {
            let parts = url.path.split(separator: "/").map(String.init)
            if parts.count == 1, let liveID = parts.first, !liveID.isEmpty {
                components.scheme = "https"
                components.host = "play.sooplive.com"
                components.path = "/\(liveID)"
                return components.url ?? url
            }
        }

        if isXVideosHostAlias(host) {
            let parts = url.path.split(separator: "/").map(String.init)
            if isXVideosPlaylistPath(parts) {
                components.scheme = "https"
                components.host = "www.xvideos.com"
                components.fragment = nil
                return components.url ?? url
            }
        }

        if isXHamsterHostAlias(host),
           let creatorURL = EtcVideoPageResolver.canonicalXHamsterCreatorURL(for: url) {
            return creatorURL
        }

        if isKakaoTVHost(host) {
            let path = components.path
            if path == "/m" {
                components.path = "/"
                return components.url ?? url
            }
            if path.hasPrefix("/m/") {
                components.path = String(path.dropFirst(2))
                return components.url ?? url
            }
        }

        return url
    }

    private static func normalizedYouTubeURL(_ url: URL, components input: URLComponents, host: String) -> URL {
        var components = input
        let queryItems = components.queryItems ?? []
        let fragmentItems = youtubeFragmentQueryItems(components.fragment)
        let lookupItems = queryItems + fragmentItems
        components.scheme = "https"
        components.host = "www.youtube.com"
        components.fragment = nil

        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        let lower = parts.map { $0.lowercased() }

        if let nested = nestedYouTubeURL(from: lookupItems, baseURL: url),
           let nestedHost = nested.host?.lowercased(),
           let nestedComponents = URLComponents(url: nested, resolvingAgainstBaseURL: false) {
            let normalized = normalizedYouTubeURL(nested, components: nestedComponents, host: nestedHost)
            if normalized.absoluteString != url.absoluteString {
                return normalized
            }
        }

        if isYouTubeShortHost(host),
           let id = parts.first,
           isYouTubeVideoSlug(id) {
            components.path = "/watch"
            components.queryItems = youtubeWatchQueryItems(videoID: id, existingItems: lookupItems)
            return components.url ?? url
        }

        if let first = lower.first,
           ["embed", "v", "e", "live"].contains(first),
           parts.count >= 2,
           isYouTubeVideoSlug(parts[1]) {
            components.path = "/watch"
            components.queryItems = youtubeWatchQueryItems(videoID: parts[1], existingItems: lookupItems)
            return components.url ?? url
        }

        if isYewtuHost(host),
           parts.count == 1,
           let id = parts.first,
           isYouTubeVideoSlug(id),
           !isYewtuReservedPath(id) {
            components.path = "/watch"
            components.queryItems = youtubeWatchQueryItems(videoID: id, existingItems: lookupItems)
            return components.url ?? url
        }

        if ["", "watch", "watch_popup", "get_video_info", "verify_age"].contains(lower.first ?? ""),
           let id = youtubeVideoID(from: lookupItems) ?? (lower.first == "watch" && parts.count >= 2 ? parts[1] : nil),
           isYouTubeVideoSlug(id) {
            components.path = "/watch"
            components.queryItems = youtubeWatchQueryItems(videoID: id, existingItems: lookupItems)
            return components.url ?? url
        }

        if lower.first == "shorts",
           parts.count >= 2,
           isYouTubeVideoSlug(parts[1]) {
            components.path = "/shorts/\(parts[1])"
            components.queryItems = nil
            return components.url ?? url
        }

        if lower.first == "clip",
           parts.count >= 2,
           isYouTubeVideoSlug(parts[1]) {
            components.path = "/clip/\(parts[1])"
            components.queryItems = nil
            return components.url ?? url
        }

        if let collectionURL = normalizedYouTubeCollectionURL(
            parts: parts,
            lower: lower,
            components: components
        ) {
            return collectionURL
        }

        if isYewtuHost(host) {
            return components.url ?? url
        }

        return url
    }

    static func youtubeLanguageExtractorArgument(for url: URL, preferredLanguage: String) -> String? {
        guard let host = url.host?.lowercased(),
              isYouTubeHost(host) else {
            return nil
        }
        let language = preferredLanguage.trimmed
        guard !language.isEmpty else { return nil }
        return "youtube:lang=\(language)"
    }

    private static func youtubeVideoID(from items: [URLQueryItem]) -> String? {
        for name in ["v", "video_id", "videoid", "video"] {
            if let value = items.first(where: { $0.name.lowercased() == name })?.value,
               isYouTubeVideoSlug(value) {
                return value
            }
        }
        return nil
    }

    private static func youtubeWatchQueryItems(videoID: String, existingItems: [URLQueryItem]?) -> [URLQueryItem] {
        var items = [URLQueryItem(name: "v", value: videoID)]
        let preserved = Set(["t", "start", "end", "time_continue"])
        for item in existingItems ?? [] where preserved.contains(item.name.lowercased()) {
            items.append(item)
        }
        return items
    }

    private static func normalizedYouTubeCollectionURL(
        parts: [String],
        lower: [String],
        components input: URLComponents
    ) -> URL? {
        guard let first = lower.first else { return nil }
        var components = input
        components.queryItems = nil
        components.fragment = nil

        if ["channel", "user", "c"].contains(first),
           parts.count >= 2,
           shouldNormalizeYouTubeCollectionTab(lower.dropFirst(2).first) {
            components.path = "/\(parts[0])/\(parts[1])/videos"
            return components.url
        }

        if first.hasPrefix("@"),
           parts.count >= 1,
           shouldNormalizeYouTubeCollectionTab(lower.dropFirst().first) {
            components.path = "/\(parts[0])/videos"
            return components.url
        }

        return nil
    }

    private static func shouldNormalizeYouTubeCollectionTab(_ tab: String?) -> Bool {
        guard let tab, !tab.isEmpty else { return true }
        return tab == "featured"
    }

    private static func youtubeFragmentQueryItems(_ fragment: String?) -> [URLQueryItem] {
        guard var value = fragment?.trimmed, !value.isEmpty else { return [] }
        while value.hasPrefix("!") || value.hasPrefix("#") {
            value.removeFirst()
        }
        if value.hasPrefix("/") {
            return URLComponents(string: "https://www.youtube.com\(value)")?.queryItems ?? []
        }
        if value.hasPrefix("?") {
            value.removeFirst()
        }
        return URLComponents(string: "https://www.youtube.com/?\(value)")?.queryItems ?? []
    }

    private static func nestedYouTubeURL(from items: [URLQueryItem], baseURL: URL) -> URL? {
        let names = Set(["u", "url", "q", "next", "next_url", "continue", "redirect", "redir_url", "target"])
        for item in items where names.contains(item.name.lowercased()) {
            guard let value = item.value else { continue }
            let candidates = [
                value,
                value.removingPercentEncoding ?? value
            ]
            for candidate in candidates {
                let cleaned = candidate
                    .replacingOccurrences(of: "\\u0026", with: "&", options: .caseInsensitive)
                    .replacingOccurrences(of: "\\/", with: "/")
                    .replacingOccurrences(of: "&amp;", with: "&")
                    .trimmed
                guard !cleaned.isEmpty else { continue }

                let rawURL: URL?
                if cleaned.hasPrefix("//") {
                    rawURL = URL(string: "\(baseURL.scheme ?? "https"):\(cleaned)")
                } else if cleaned.contains("://") {
                    rawURL = URL(string: cleaned)
                } else if cleaned.lowercased().hasPrefix("www.youtube.") || cleaned.lowercased().hasPrefix("youtube.") || cleaned.lowercased().hasPrefix("youtu.be/") {
                    rawURL = URL(string: "https://\(cleaned)")
                } else {
                    rawURL = URL(string: cleaned, relativeTo: baseURL)?.absoluteURL
                }

                guard let rawURL,
                      let host = rawURL.host?.lowercased(),
                      isYouTubeHost(host),
                      rawURL.absoluteString != baseURL.absoluteString else {
                    continue
                }
                return rawURL
            }
        }
        return nil
    }

    private static func isYouTubeVideoSlug(_ value: String) -> Bool {
        !value.isEmpty &&
            value.range(of: #"^[A-Za-z0-9][A-Za-z0-9._-]*$"#, options: .regularExpression) != nil
    }

    private static func isYewtuReservedPath(_ value: String) -> Bool {
        [
            "channel", "c", "clip", "embed", "feed", "hashtag", "live", "playlist",
            "playlists", "redirect", "results", "shorts", "user", "watch"
        ].contains(value.lowercased()) || value.hasPrefix("@")
    }

    static func soopFormatSelector(for url: URL, preferredResolution: String) -> String? {
        guard let host = url.host?.lowercased(),
              isSOOPAfreecaHost(host) else {
            return nil
        }

        var value = preferredResolution.trimmed.lowercased()
        guard !value.isEmpty else { return nil }
        if value.hasSuffix("p") {
            value.removeLast()
        }
        guard value.range(of: #"^[0-9]{3,5}$"#, options: .regularExpression) != nil,
              let height = Int(value),
              (144...8640).contains(height) else {
            return nil
        }

        return "bestvideo[height<=\(height)]+bestaudio/best[height<=\(height)]/best"
    }

    static func tverFormatSelector(for url: URL) -> String? {
        guard let host = url.host?.lowercased(),
              isTVerHost(host) else {
            return nil
        }

        return "best[protocol^=m3u8]/best[ext=mp4][protocol!*=dash]/best[protocol!*=dash]/best"
    }

    static func naverTVFormatSelector(for url: URL) -> String? {
        guard NaverTVResolver.clipID(from: url) != nil else { return nil }
        return "best[protocol^=http]"
    }

    static func youtubeFormatSelector(
        for url: URL,
        preferredResolution: String,
        preferredAudioLanguage: String = "",
        extractAudioFormat: String? = nil
    ) -> String? {
        guard let host = url.host?.lowercased(),
              isYouTubeHost(host),
              extractAudioFormat?.trimmed.isEmpty != false else {
            return nil
        }

        let height = preferredYouTubeHeight(preferredResolution)
        let audioLanguage = normalizedYouTubeAudioLanguage(preferredAudioLanguage)
        guard height != nil || audioLanguage != nil else {
            return nil
        }

        if let height {
            if let audioLanguage {
                return "bestvideo[height<=\(height)]+bestaudio[language=\(audioLanguage)]/bestvideo[height<=\(height)]+bestaudio/best[height<=\(height)][ext=mp4]/best[height<=\(height)]/best[ext=mp4]/best"
            }
            return "bestvideo[height<=\(height)]+bestaudio/best[height<=\(height)][ext=mp4]/best[height<=\(height)]/best[ext=mp4]/best"
        }

        if let audioLanguage {
            return "bestvideo+bestaudio[language=\(audioLanguage)]/bestvideo+bestaudio/best"
        }

        return nil
    }

    private static func preferredYouTubeHeight(_ preferredResolution: String) -> Int? {
        var value = preferredResolution.trimmed.lowercased()
        guard !value.isEmpty else { return nil }
        if value.hasSuffix("p") {
            value.removeLast()
        }
        guard value.range(of: #"^[0-9]{3,5}$"#, options: .regularExpression) != nil,
              let height = Int(value),
              (144...8640).contains(height) else {
            return nil
        }
        return height
    }

    static func normalizedYouTubeAudioLanguage(_ language: String) -> String? {
        let value = language.trimmed
        guard !value.isEmpty,
              value.range(of: #"^[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil else {
            return nil
        }
        return value
    }

    private static func isYouTubeHost(_ host: String) -> Bool {
        host == "youtube.com" ||
            host == "youtube.co" ||
            host == "www.youtube.com" ||
            host == "www.youtube.co" ||
            host == "m.youtube.com" ||
            host == "music.youtube.com" ||
            host == "youtube-nocookie.com" ||
            host == "www.youtube-nocookie.com" ||
            host == "youtu.be" ||
            host == "www.youtu.be" ||
            host == "yewtu.be" ||
            host.hasSuffix(".yewtu.be")
    }

    private static func isVLiveHost(_ host: String) -> Bool {
        host == "vlive.tv" || host.hasSuffix(".vlive.tv")
    }

    private static func isGoogleRedirectHost(_ host: String) -> Bool {
        host == "google.com" ||
            host.hasSuffix(".google.com") ||
            host.hasPrefix("google.") ||
            host.hasPrefix("www.google.")
    }

    private static func shouldWriteYouTubeThumbnail(for url: URL, enabled: Bool) -> Bool {
        guard enabled,
              let host = url.host?.lowercased() else {
            return false
        }
        return isYouTubeHost(host)
    }

    private static func shouldReverseYouTubePlaylist(for url: URL, enabled: Bool) -> Bool {
        guard enabled,
              let host = url.host?.lowercased(),
              isYouTubeHost(host) else {
            return false
        }

        let path = url.path.lowercased()
        let parts = path.split(separator: "/").map(String.init)
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []

        if parts.first == "playlist",
           queryItems.contains(where: { $0.name == "list" }) {
            return true
        }
        if let first = parts.first,
           ["channel", "user", "c"].contains(first),
           !path.hasSuffix("/live") {
            return true
        }
        if let first = parts.first,
           first.hasPrefix("@"),
           !path.hasSuffix("/live") {
            return true
        }
        return false
    }

    static func shouldNumberPlaylistFiles(for url: URL, enabled: Bool) -> Bool {
        guard enabled else { return false }
        return allowsPlaylist(for: normalizedSourceURL(for: url))
    }

    static func outputTemplate(for url: URL, numberPlaylistFiles: Bool) -> String {
        let sourceURL = normalizedSourceURL(for: url)
        if usesOriginalManagedExtractor(for: sourceURL) {
            return "%(title).200B (%(id)s).%(ext)s"
        }
        return shouldNumberPlaylistFiles(for: sourceURL, enabled: numberPlaylistFiles)
            ? "%(playlist_index)03d - %(title).200B [%(id)s].%(ext)s"
            : "%(title).200B [%(id)s].%(ext)s"
    }

    private static func youtubeAutoSubtitleLanguages(for url: URL, enabled: Bool, languages: String) -> String? {
        guard enabled,
              let host = url.host?.lowercased(),
              isYouTubeHost(host) else {
            return nil
        }
        let normalized = languages
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ",")
        return normalized.isEmpty ? "all" : normalized
    }

    private static func vliveSubtitleLanguages(for url: URL) -> String? {
        guard let host = url.host?.lowercased(),
              isVLiveHost(host) else {
            return nil
        }
        return "all"
    }

    private static func shouldEmbedYouTubeChapters(for url: URL, enabled: Bool) -> Bool {
        guard enabled,
              let host = url.host?.lowercased() else {
            return false
        }
        return isYouTubeHost(host)
    }

    static func youtubeFormatSortArgument(
        for url: URL,
        sort: String,
        preferEnhancedBitrate: Bool = false
    ) -> String? {
        guard let host = url.host?.lowercased(),
              isYouTubeHost(host) else {
            return nil
        }
        var parts = sort
            .split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if preferEnhancedBitrate {
            var fields = parts.map(formatSortFieldName)
            if let bitrateIndex = fields.firstIndex(of: "br") {
                parts.remove(at: bitrateIndex)
                fields.remove(at: bitrateIndex)
            }
            if let resolutionIndex = fields.firstIndex(of: "res") {
                parts.insert("br", at: resolutionIndex + 1)
            } else {
                parts.insert(contentsOf: ["res", "br"], at: 0)
            }
        }

        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: ",")
    }

    private static func formatSortFieldName(_ sortPart: String) -> String {
        var value = sortPart.trimmed.lowercased()
        while value.first == "+" || value.first == "-" {
            value.removeFirst()
        }
        if let delimiter = value.firstIndex(where: { $0 == ":" || $0 == "~" }) {
            value = String(value[..<delimiter])
        }
        return value
    }

    private static func isYouTubeShortHost(_ host: String) -> Bool {
        host == "youtu.be" ||
            host == "www.youtu.be"
    }

    private static func isYewtuHost(_ host: String) -> Bool {
        host == "yewtu.be" ||
            host == "www.yewtu.be" ||
            host.hasSuffix(".yewtu.be")
    }

    private static func isSOOPAfreecaHost(_ host: String) -> Bool {
        host == "afreecatv.com" ||
            host.hasSuffix(".afreecatv.com") ||
            host == "sooplive.com" ||
            host.hasSuffix(".sooplive.com") ||
            host == "sooplive.co.kr" ||
            host.hasSuffix(".sooplive.co.kr")
    }

    private static func isSOOPVODNativeMediaURL(_ url: URL) -> Bool {
        SOOPVODResolver.videoID(from: url) != nil ||
            SOOPVODResolver.liveID(from: url) != nil
    }

    private static func isTwitterHost(_ host: String) -> Bool {
        host == "twitter.com" ||
            host == "www.twitter.com" ||
            host == "mobile.twitter.com" ||
            host.hasSuffix(".twitter.com") ||
            host == "x.com" ||
            host == "www.x.com" ||
            host == "mobile.x.com" ||
            host.hasSuffix(".x.com") ||
            host == "twitter.test" ||
            host == "www.twitter.test" ||
            host == "mobile.twitter.test" ||
            host.hasSuffix(".twitter.test") ||
            host == "x.test" ||
            host == "www.x.test" ||
            host == "mobile.x.test" ||
            host.hasSuffix(".x.test")
    }

    private static func isTwitchHost(_ host: String) -> Bool {
        host == "twitch.tv" ||
            host == "www.twitch.tv" ||
            host == "m.twitch.tv"
    }

    private static func isTwitchNativeMediaURL(_ url: URL) -> Bool {
        TwitchClipCollectionResolver.request(from: url) != nil ||
            TwitchVODResolver.canonicalURL(for: url) != nil
    }

    private static func isTVerHost(_ host: String) -> Bool {
        host == "tver.jp" ||
            host == "www.tver.jp"
    }

    private static func isTVerEpisodeNativeMediaURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(),
              isTVerHost(host),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let metadata = tverSourceMetadata(from: url),
              metadata["category"] == "episode",
              EtcVideoPageResolver.contentID(from: url) != nil else {
            return false
        }
        return true
    }

    private static func isTwitchChannelListingPath(_ parts: [String]) -> Bool {
        guard parts.count >= 2 else { return false }
        let login = parts[0]
        let tab = parts[1].lowercased()
        return (tab == "videos" || tab == "clips") &&
            login.range(of: #"^[A-Za-z0-9_]{3,25}$"#, options: .regularExpression) != nil &&
            !["about", "directory", "search", "videos", "clips"].contains(login.lowercased())
    }

    static func twitterSpaceID(from url: URL) -> String? {
        guard let host = url.host?.lowercased(),
              isTwitterHost(host) else {
            return nil
        }
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        guard parts.count >= 3,
              parts[0].lowercased() == "i",
              parts[1].lowercased() == "spaces" else {
            return nil
        }
        let id = parts[2].trimmed
        return id.isEmpty ? nil : id
    }

    static func twitterBroadcastID(from url: URL) -> String? {
        guard let host = url.host?.lowercased(),
              isTwitterHost(host) else {
            return nil
        }
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        guard parts.count >= 3,
              parts[0].lowercased() == "i",
              parts[1].lowercased() == "broadcasts" else {
            return nil
        }
        let id = parts[2].trimmed
        return id.isEmpty ? nil : id
    }

    static func twitterUserID(from url: URL) -> String? {
        guard let host = url.host?.lowercased(),
              isTwitterHost(host) else {
            return nil
        }
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        guard parts.count >= 3,
              parts[0].lowercased() == "i",
              parts[1].lowercased() == "user" else {
            return nil
        }
        let id = parts[2].trimmed
        guard id.range(of: #"^[0-9]+$"#, options: .regularExpression) != nil else {
            return nil
        }
        return id
    }

    private static func normalizedTwitterURL(_ url: URL, components input: URLComponents, host: String) -> URL {
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        if parts.first?.lowercased() == "search" {
            return url
        }

        var components = input
        components.scheme = "https"
        components.host = host.hasSuffix(".test") ? "twitter.test" : "twitter.com"
        components.queryItems = nil
        components.fragment = nil

        if parts.count >= 3,
           parts[0].lowercased() == "i",
           parts[1].lowercased() == "spaces" {
            components.path = "/i/spaces/\(parts[2])"
        } else if parts.count >= 3,
                  parts[0].lowercased() == "i",
                  parts[1].lowercased() == "broadcasts" {
            components.path = "/i/broadcasts/\(parts[2])"
        } else if parts.count >= 3,
                  parts[0].lowercased() == "i",
                  parts[1].lowercased() == "user",
                  let userID = twitterUserID(from: url) {
            components.path = "/i/user/\(userID)"
        } else if parts.count >= 2, parts[1].lowercased() == "media" {
            let username = parts[0].trimmingCharacters(in: CharacterSet(charactersIn: "@/ "))
            if !username.isEmpty {
                components.path = "/\(username)"
            }
        } else if let first = parts.first, first.hasPrefix("@") {
            let username = first.trimmingCharacters(in: CharacterSet(charactersIn: "@/ "))
            if !username.isEmpty {
                components.path = "/\(username)"
            }
        }

        return components.url ?? url
    }

    private static func normalizedTVerURL(_ url: URL, components input: URLComponents) -> URL {
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        let lower = parts.map { $0.lowercased() }

        var components = input
        components.scheme = "https"
        components.host = "tver.jp"
        components.fragment = nil
        components.queryItems = normalizedTVerQueryItems(components.queryItems)

        if lower.count >= 3, lower[0] == "lp" {
            if lower[1] == "episodes", isTVerEpisodeID(parts[2]) {
                components.path = "/episodes/\(parts[2])"
                return components.url ?? url
            }
            if lower[1] == "series", isTVerSeriesID(parts[2]) {
                components.path = "/series/\(parts[2])"
                return components.url ?? url
            }
        }

        if lower.count >= 2 {
            if lower[0] == "episodes", isTVerEpisodeID(parts[1]) {
                components.path = "/episodes/\(parts[1])"
                return components.url ?? url
            }
            if lower[0] == "series", isTVerSeriesID(parts[1]) {
                components.path = "/series/\(parts[1])"
                return components.url ?? url
            }
            if ["corner", "specials", "live", "feature"].contains(lower[0]) {
                components.path = "/\(parts[0])/\(parts[1])"
                return components.url ?? url
            }
        }

        return components.url ?? url
    }

    private static func normalizedTVerQueryItems(_ items: [URLQueryItem]?) -> [URLQueryItem]? {
        let preserved = Set(["utm_content", "utm_term"])
        let filtered = (items ?? []).filter { item in
            let name = item.name.lowercased()
            guard !name.hasPrefix("utm_") || preserved.contains(name) else { return false }
            return !["fbclid", "gclid", "yclid", "ref", "from", "cid"].contains(name)
        }
        return filtered.isEmpty ? nil : filtered
    }

    private static func tverSourceMetadata(from url: URL) -> [String: String]? {
        guard let host = url.host?.lowercased(),
              isTVerHost(host) else {
            return nil
        }
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        let lower = parts.map { $0.lowercased() }
        var metadata: [String: String] = [
            "site": "TVer",
            "service": "TVer",
            "platform": "TVer"
        ]

        if lower.count >= 2, lower[0] == "episodes", isTVerEpisodeID(parts[1]) {
            metadata["category"] = "episode"
            metadata["id"] = parts[1]
            metadata["episode_id"] = parts[1]
            metadata["media_id"] = parts[1]
            metadata["slug"] = parts[1]
            return metadata
        }

        if lower.count >= 2, lower[0] == "series", isTVerSeriesID(parts[1]) {
            metadata["category"] = "series"
            metadata["id"] = parts[1]
            metadata["series_id"] = parts[1]
            metadata["playlist_id"] = parts[1]
            metadata["media_id"] = parts[1]
            metadata["slug"] = parts[1]
            return metadata
        }

        if lower.count >= 2, ["corner", "specials", "live", "feature"].contains(lower[0]) {
            metadata["category"] = lower[0]
            metadata["id"] = parts[1]
            metadata["media_id"] = parts[1]
            metadata["slug"] = parts[1]
            return metadata
        }

        return nil
    }

    private static func isTVerEpisodeID(_ value: String) -> Bool {
        value.range(of: #"^ep[0-9A-Za-z_-]{4,}$"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func isTVerSeriesID(_ value: String) -> Bool {
        value.range(of: #"^sr[0-9A-Za-z_-]{4,}$"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func isSOOPLiveAliasHost(_ host: String) -> Bool {
        host == "play.afreecatv.com" ||
            host == "bj.afreecatv.com" ||
            host == "ch.afreecatv.com" ||
            host == "play.sooplive.co.kr" ||
            host == "bj.sooplive.co.kr" ||
            host == "ch.sooplive.co.kr" ||
            host == "play.sooplive.com" ||
            host == "bj.sooplive.com" ||
            host == "ch.sooplive.com"
    }

    private static func isFacebookHostAlias(_ host: String) -> Bool {
        let parts = host.split(separator: ".").map(String.init)
        guard parts.count >= 2,
              parts[parts.count - 2] == "facebook" else {
            return false
        }
        let topLevelDomain = parts[parts.count - 1]
        return topLevelDomain.range(of: #"^[a-z]{2,12}$"#, options: .regularExpression) != nil
    }

    private static func isXHamsterHostAlias(_ host: String) -> Bool {
        guard let labels = hostLabels(host), labels.count >= 2 else { return false }
        let base = labels[labels.count - 2]
        let topLevelDomain = labels[labels.count - 1]
        guard topLevelDomain.range(of: #"^[a-z0-9]{2,24}$"#, options: .regularExpression) != nil else {
            return false
        }
        return base.range(
            of: #"^(xhamster|xhwebsite|xhofficial|xhlocal|xhopen|xhtotal|megaxh|xhwide|xhtab|xhtime|xhamsterlive)[0-9]*$"#,
            options: .regularExpression
        ) != nil
    }

    private static func isXNXXHostAlias(_ host: String) -> Bool {
        guard let labels = hostLabels(host), labels.count >= 2 else { return false }
        let base = labels[labels.count - 2]
        let topLevelDomain = labels[labels.count - 1]
        guard topLevelDomain == "com" || topLevelDomain == "es" else { return false }
        return base.range(of: #"^xnxx[0-9]*$"#, options: .regularExpression) != nil
    }

    private static func isXVideosHostAlias(_ host: String) -> Bool {
        guard let labels = hostLabels(host), labels.count >= 2 else { return false }
        let base = labels[labels.count - 2]
        let topLevelDomain = labels[labels.count - 1]
        guard ["com", "in", "es"].contains(topLevelDomain) else { return false }
        return base.range(of: #"^xvideos[0-9]*$"#, options: .regularExpression) != nil
    }

    private static func isXVideosPlaylistPath(_ parts: [String]) -> Bool {
        guard parts.count >= 2 else { return false }
        let first = parts[0].lowercased()
        guard first == "profiles" || first.hasSuffix("channels") else { return false }
        return parts[1].range(of: #"^[0-9A-Za-z_-]+$"#, options: .regularExpression) != nil
    }

    private static func isXHamsterPlaylistPath(_ parts: [String]) -> Bool {
        guard let creatorsIndex = parts.map({ $0.lowercased() }).firstIndex(of: "creators"),
              creatorsIndex + 1 < parts.count else {
            return false
        }
        return parts[creatorsIndex + 1].range(of: #"^[A-Za-z0-9][A-Za-z0-9_-]*$"#, options: .regularExpression) != nil
    }

    private static func isIwaraHost(_ host: String) -> Bool {
        host == "iwara.tv" ||
            host == "www.iwara.tv" ||
            host == "ecchi.iwara.tv"
    }

    private static func isIwaraPlaylistPath(_ parts: [String]) -> Bool {
        guard parts.count >= 2 else { return false }
        let first = parts[0].lowercased()
        guard first == "profile" || first == "users" || first == "playlist" else { return false }
        return parts[1].range(of: #"^[0-9A-Za-z._-]+$"#, options: .regularExpression) != nil
    }

    private static func hostLabels(_ host: String) -> [String]? {
        let labels = host
            .lowercased()
            .split(separator: ".")
            .map(String.init)
            .filter { !$0.isEmpty }
        return labels.count >= 2 ? labels : nil
    }

    private static func isBilibiliHost(_ host: String) -> Bool {
        host == "bilibili.com" ||
            host == "www.bilibili.com" ||
            host.hasSuffix(".bilibili.com") ||
            host == "bilibili.tv" ||
            host == "www.bilibili.tv" ||
            host.hasSuffix(".bilibili.tv")
    }

    private static func isKakaoTVHost(_ host: String) -> Bool {
        host == "tv.kakao.com" ||
            host.hasSuffix(".tv.kakao.com") ||
            host == "kakao.tv" ||
            host.hasSuffix(".kakao.tv") ||
            host == "kakaotv.daum.net" ||
            host.hasSuffix(".kakaotv.daum.net")
    }

    private static func isNativeOnlyMediaURL(_ url: URL) -> Bool {
        isYouTubeNativeCollectionURL(url) ||
            isVimeoSingleVideoURL(url) ||
            isSoundCloudNativeMediaURL(url) ||
            isTumblrNativeMediaURL(url) ||
            isFC2NativeMediaURL(url) ||
            isSOOPVODNativeMediaURL(url) ||
            isFacebookPhotoNativeMediaURL(url) ||
            isFacebookVideoNativeMediaURL(url) ||
            isPornhubNativeMediaURL(url) ||
            isIwaraNativeMediaURL(url) ||
            isXHamsterCollectionNativeMediaURL(url) ||
            isXHamsterGalleryNativeMediaURL(url) ||
            isTVerEpisodeNativeMediaURL(url) ||
            isEtcVideoNativeMediaURL(url) ||
            isTikTokNativeMediaURL(url) ||
            isInstagramNativeMediaURL(url) ||
            isHanimeNativeMediaURL(url) ||
            isVLiveNativeMediaURL(url) ||
            isNiconicoNativeMediaURL(url) ||
            isNiconicoLiveWatchNativeMediaURL(url) ||
            isTwitterNativeMediaURL(url) ||
            isBilibiliNativeMediaURL(url) ||
            isChzzkNativeMediaURL(url) ||
            isTwitchNativeMediaURL(url) ||
            isXVideoNativeMediaURL(url) ||
            isWeiboNativeMediaURL(url)
    }

    private static func isYouTubeNativeCollectionURL(_ url: URL) -> Bool {
        YouTubeCollectionResolver.request(from: url) != nil
    }

    private static func isVimeoSingleVideoURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(),
              isVimeoHost(host),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return false
        }

        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        let lower = parts.map { $0.lowercased() }
        if let videoIndex = lower.firstIndex(of: "video"),
           videoIndex + 1 < parts.count,
           isVimeoNumericID(parts[videoIndex + 1]) {
            return true
        }

        return parts.reversed().contains { isVimeoNumericID($0) }
    }

    private static func isVimeoHost(_ host: String) -> Bool {
        host == "vimeo.com" ||
            host == "www.vimeo.com" ||
            host == "player.vimeo.com" ||
            host == "vimeo.test" ||
            host == "www.vimeo.test" ||
            host == "player.vimeo.test"
    }

    private static func isVimeoNumericID(_ value: String) -> Bool {
        value.range(of: #"^[0-9]{4,}$"#, options: .regularExpression) != nil
    }

    private static func isSoundCloudNativeMediaURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(),
              isSoundCloudHost(host),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return false
        }

        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        guard !parts.isEmpty,
              isSoundCloudSlug(parts[0]),
              !isSoundCloudReservedPath(parts[0]) else {
            return false
        }

        if parts.count == 1 {
            return true
        }

        let second = parts[1].lowercased()
        if second == "sets" {
            return parts.count >= 3 && isSoundCloudSlug(parts[2])
        }

        return isSoundCloudSlug(parts[1]) &&
            !isSoundCloudReservedPath(parts[1])
    }

    private static func isSoundCloudHost(_ host: String) -> Bool {
        host == "soundcloud.com" ||
            host == "www.soundcloud.com" ||
            host == "soundcloud.test" ||
            host == "www.soundcloud.test"
    }

    private static func isSoundCloudSlug(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z0-9][A-Za-z0-9_-]*$"#, options: .regularExpression) != nil
    }

    private static func isSoundCloudReservedPath(_ value: String) -> Bool {
        [
            "charts",
            "comments",
            "discover",
            "feed",
            "followers",
            "following",
            "for-you",
            "likes",
            "messages",
            "notifications",
            "pages",
            "popular",
            "popular-tracks",
            "premium",
            "pro",
            "reposts",
            "search",
            "settings",
            "sets",
            "stream",
            "tags",
            "upload",
            "you"
        ].contains(value.lowercased())
    }

    private static func isTumblrNativeMediaURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return false
        }
        return TumblrResolver.canonicalBlogURL(for: url) != nil
    }

    private static func isFC2NativeMediaURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(),
              isFC2Host(host),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return false
        }

        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        guard let contentIndex = parts.firstIndex(where: { $0.lowercased() == "content" }),
              contentIndex + 1 < parts.count else {
            return false
        }
        return isFC2ContentID(parts[contentIndex + 1])
    }

    private static func isFC2Host(_ host: String) -> Bool {
        host == "fc2.com" ||
            host == "www.fc2.com" ||
            host == "video.fc2.com" ||
            host == "fc2.com.test" ||
            host == "www.fc2.com.test" ||
            host == "video.fc2.com.test"
    }

    private static func isFC2ContentID(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil
    }

    private static func isIwaraNativeMediaURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return false
        }
        return IwaraCollectionResolver.request(from: url) != nil ||
            IwaraImageResolver.imageID(from: url) != nil ||
            IwaraVideoResolver.videoID(from: url) != nil
    }

    private static func isFacebookPhotoNativeMediaURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return false
        }
        return FacebookPhotoCollectionResolver.request(from: url) != nil ||
            FacebookPhotoResolver.photoID(from: url) != nil
    }

    private static func isFacebookVideoNativeMediaURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return false
        }
        return FacebookVideoResolver.videoID(from: url) != nil
    }

    private static func isPornhubNativeMediaURL(_ url: URL) -> Bool {
        if PornhubCollectionResolver.request(from: url) != nil {
            return true
        }
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              PornhubMediaResolver.request(from: url) != nil else {
            return false
        }
        return true
    }

    private static func isXHamsterGalleryNativeMediaURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return false
        }
        return XHamsterGalleryResolver.galleryID(from: url) != nil
    }

    private static func isXHamsterCollectionNativeMediaURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return false
        }
        return XHamsterCollectionResolver.request(from: url) != nil
    }

    private static func isEtcVideoNativeMediaURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let site = EtcVideoPageResolver.site(for: url),
              EtcVideoPageResolver.contentID(from: url) != nil else {
            return false
        }

        switch site {
        case .avgle, .bitchute, .dailymotion, .kick, .kissjav, .odysee,
             .okru, .reddit, .rumble, .rutube, .streamable, .tokyomotion,
             .twitcasting, .vk, .xhamster, .thisvid, .ixigua, .yourporn,
             .youporn, .youku:
            return true
        default:
            return false
        }
    }

    private static func isTikTokNativeMediaURL(_ url: URL) -> Bool {
        TikTokResolver.videoID(from: url) != nil ||
            TikTokResolver.profileUsername(from: url) != nil ||
            TikTokResolver.shortLinkCode(from: url) != nil
    }

    private static func isInstagramNativeMediaURL(_ url: URL) -> Bool {
        InstagramResolver.shortcode(from: url) != nil ||
            InstagramResolver.highlightID(from: url) != nil ||
            InstagramResolver.storyID(from: url) != nil ||
            InstagramResolver.storyCollectionUsername(from: url) != nil ||
            InstagramResolver.profileUsername(from: url) != nil
    }

    private static func isHanimeNativeMediaURL(_ url: URL) -> Bool {
        HanimeResolver.slug(from: url) != nil
    }

    private static func isVLiveNativeMediaURL(_ url: URL) -> Bool {
        VLiveResolver.contentID(from: url) != nil
    }

    private static func isNiconicoNativeMediaURL(_ url: URL) -> Bool {
        NiconicoResolver.videoID(from: url) != nil
    }

    private static func isNiconicoLiveWatchNativeMediaURL(_ url: URL) -> Bool {
        NiconicoLiveResolver.liveID(from: url) != nil
    }

    private static func isTwitterNativeMediaURL(_ url: URL) -> Bool {
        TwitterCollectionResolver.request(from: url) != nil ||
            TwitterResolver.tweetID(from: url) != nil ||
            TwitterResolver.twitpicID(from: url) != nil ||
            TwitterResolver.twitterSpaceID(from: url) != nil ||
            TwitterResolver.twitterBroadcastID(from: url) != nil
    }

    private static func isBilibiliNativeMediaURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(),
              isBilibiliNativeHost(host),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return false
        }

        if BilibiliCollectionResolver.request(from: url) != nil {
            return true
        }

        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        let lower = parts.map { $0.lowercased() }
        if isB23NativeHost(host),
           parts.count == 1,
           isBilibiliDirectShortVideoID(parts[0]) {
            return true
        }

        if BilibiliResolver.shortLinkCode(from: url) != nil {
            return true
        }

        if BilibiliResolver.tvVideoID(from: url) != nil {
            return true
        }

        if let videoIndex = lower.firstIndex(of: "video"),
           videoIndex + 1 < parts.count,
           isBilibiliVideoID(parts[videoIndex + 1]) {
            return true
        }

        if let animeIndex = lower.firstIndex(of: "anime"),
           animeIndex + 2 < parts.count,
           lower[animeIndex + 2] == "play",
           let fragment = url.fragment,
           isBilibiliNumericID(fragment) {
            return true
        }

        return false
    }

    private static func isBilibiliNativeHost(_ host: String) -> Bool {
        host == "bilibili.com" ||
            host == "www.bilibili.com" ||
            host == "m.bilibili.com" ||
            host == "bangumi.bilibili.com" ||
            host.hasSuffix(".bilibili.com") ||
            host == "bilibili.tv" ||
            host == "www.bilibili.tv" ||
            host == "m.bilibili.tv" ||
            host.hasSuffix(".bilibili.tv") ||
            isB23NativeHost(host) ||
            host == "bilibili.test" ||
            host == "www.bilibili.test" ||
            host.hasSuffix(".bilibili.test")
    }

    private static func isB23NativeHost(_ host: String) -> Bool {
        host == "b23.tv" ||
            host == "www.b23.tv" ||
            host == "b23.test" ||
            host == "www.b23.test"
    }

    private static func isBilibiliVideoID(_ value: String) -> Bool {
        value.range(of: #"^BV[0-9A-Za-z]+$"#, options: [.caseInsensitive, .regularExpression]) != nil ||
            value.range(of: #"^av[0-9]+$"#, options: [.caseInsensitive, .regularExpression]) != nil ||
            value.range(of: #"^[0-9A-Za-z_-]{6,}$"#, options: .regularExpression) != nil
    }

    private static func isBilibiliDirectShortVideoID(_ value: String) -> Bool {
        value.range(of: #"^BV[0-9A-Za-z]+$"#, options: [.caseInsensitive, .regularExpression]) != nil ||
            value.range(of: #"^av[0-9]+$"#, options: [.caseInsensitive, .regularExpression]) != nil
    }

    private static func isBilibiliNumericID(_ value: String) -> Bool {
        value.range(of: #"^[0-9]+$"#, options: .regularExpression) != nil
    }

    private static func isChzzkNativeMediaURL(_ url: URL) -> Bool {
        if ChzzkCollectionResolver.request(from: url) != nil {
            return true
        }
        guard let host = url.host?.lowercased(),
              isChzzkHost(host),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return false
        }

        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        let lower = parts.map { $0.lowercased() }
        for marker in ["clips", "clip"] {
            if let index = lower.firstIndex(of: marker),
               index + 1 < parts.count,
               isChzzkClipID(parts[index + 1]) {
                return true
            }
        }
        for marker in ["video", "videos", "vod"] {
            if let index = lower.firstIndex(of: marker),
               index + 1 < parts.count,
               isChzzkVideoID(parts[index + 1]) {
                return true
            }
        }
        if lower.first == "live",
           parts.count >= 2,
           isChzzkLiveID(parts[1]) {
            return true
        }
        if parts.count == 1,
           let first = parts.first,
           isChzzkLiveID(first) {
            return true
        }

        guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else {
            return false
        }
        for name in ["clipUID", "clipUid", "clipId", "clipNo"] {
            if let value = items.first(where: { $0.name.lowercased() == name.lowercased() })?.value,
               isChzzkClipID(value) {
                return true
            }
        }
        for name in ["videoNo", "videoId", "vodId", "vodNo"] {
            if let value = items.first(where: { $0.name.lowercased() == name.lowercased() })?.value,
               isChzzkVideoID(value) {
                return true
            }
        }
        return false
    }

    private static func isXVideoNativeMediaURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return false
        }
        return XVideoCollectionResolver.request(from: url) != nil ||
            XVideoPageResolver.videoID(from: url) != nil
    }

    private static func isWeiboNativeMediaURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return false
        }
        return WeiboStatusResolver.canonicalInputURL(for: url) != nil
    }

    private static func isChzzkHost(_ host: String) -> Bool {
        host == "chzzk.naver.com" ||
            host == "m.chzzk.naver.com" ||
            host == "chzzk.naver.test" ||
            host == "m.chzzk.naver.test"
    }

    private static func isChzzkClipID(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z0-9_-]{4,}$"#, options: .regularExpression) != nil
    }

    private static func isChzzkVideoID(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z0-9_-]{2,}$"#, options: .regularExpression) != nil
    }

    private static func isChzzkLiveID(_ value: String) -> Bool {
        guard isChzzkVideoID(value) else { return false }
        return ![
            "clip", "clips", "video", "videos", "vod", "live", "search",
            "category", "following", "lounge", "settings", "notice"
        ].contains(value.lowercased())
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
