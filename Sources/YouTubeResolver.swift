import Foundation

enum YouTubeMediaKind: String {
    case progressive
    case videoOnly = "video_only"
    case audioOnly = "audio_only"
    case hls
}

struct YouTubeMediaCandidate {
    var url: URL
    var height: Int
    var width: Int
    var mimeType: String
    var qualityLabel: String
    var itag: String
    var bitrate: Int
    var fps: Int
    var extensionHint: String
    var sourcePath: String
    var score: Int
    var kind: YouTubeMediaKind = .progressive
    var audioQuality: String = ""
    var audioChannels: Int = 0
    var contentLength: Int64 = 0
    var isDRC: Bool = false
}

struct YouTubePlayerAPIConfiguration: Equatable {
    let apiKey: String
    let visitorData: String?
    let endpoint: URL
}

final class YouTubeResolver {
    static let androidClientName = "ANDROID"
    static let androidClientNumber = "3"
    static let androidClientVersion = "20.10.38"
    static let androidUserAgent = "com.google.android.youtube/20.10.38 (Linux; U; Android 14) gzip"

    func canResolve(_ url: URL) -> Bool {
        Self.canonicalURL(for: url) != nil
    }

    func resolve(
        _ url: URL,
        headers: HTTPRequestOptions = HTTPRequestOptions(),
        preferredResolution: String = "",
        codecPriority: [YouTubeVideoCodec] = YouTubeVideoCodec.originalDefaultPriority
    ) async throws -> ResolvedDownload {
        guard let pageURL = Self.canonicalURL(for: url) else {
            throw NativeDownloadError.invalidURL(url.absoluteString)
        }
        let html = try await HTTPClient.shared.string(from: pageURL, referer: headers.referer, userAgent: headers.userAgent)
        let pageCandidates = Self.formatCandidates(fromHTML: html, pageURL: pageURL)
        let pageHasAdaptivePair = Self.bestMuxPair(
            pageCandidates,
            preferredResolution: preferredResolution,
            codecPriority: codecPriority
        ) != nil

        if !pageHasAdaptivePair,
           let id = Self.videoID(from: pageURL) ?? Self.firstVideoID(fromHTML: html),
           let configuration = Self.playerAPIConfiguration(fromHTML: html, pageURL: pageURL) {
            do {
                let playerResponse = try await Self.fetchAndroidPlayerResponse(
                    videoID: id,
                    configuration: configuration,
                    pageURL: pageURL
                )
                var resolved = try await Self.resolvedDownload(
                    fromHTML: html,
                    supplementalObjects: [playerResponse],
                    pageURL: pageURL,
                    preferredResolution: preferredResolution,
                    codecPriority: codecPriority,
                    userAgent: Self.androidUserAgent
                )
                resolved.metadata["player_client"] = Self.androidClientName
                resolved.metadata["player_client_version"] = Self.androidClientVersion
                resolved.metadata["player_api"] = "innertube"
                return resolved
            } catch {
                guard !pageCandidates.isEmpty else { throw error }
            }
        }

        return try await Self.resolvedDownload(
            fromHTML: html,
            pageURL: pageURL,
            preferredResolution: preferredResolution,
            codecPriority: codecPriority,
            userAgent: headers.userAgent
        )
    }

    static func canonicalURL(for url: URL) -> URL? {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host?.lowercased(),
              isSupportedHost(host),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        let lower = parts.map { $0.lowercased() }
        let queryItems = components.queryItems ?? []

        if isShortHost(host),
           let id = parts.first,
           isVideoSlug(id) {
            return watchURL(videoID: id, originalHost: host, preservedItems: queryItems)
        }

        if isYewtuHost(host),
           parts.count == 1,
           let id = parts.first,
           isVideoSlug(id),
           !isYewtuReservedPath(id) {
            return watchURL(videoID: id, originalHost: host, preservedItems: queryItems)
        }

        if let first = lower.first,
           ["embed", "v", "e", "live"].contains(first),
           parts.count >= 2,
           isVideoSlug(parts[1]) {
            return watchURL(videoID: parts[1], originalHost: host, preservedItems: queryItems)
        }

        if lower.first == "shorts",
           parts.count >= 2,
           isVideoSlug(parts[1]) {
            return watchURL(videoID: parts[1], originalHost: host, preservedItems: queryItems)
        }

        if lower.first == "clip",
           parts.count >= 2,
           isVideoSlug(parts[1]) {
            return clipURL(clipID: parts[1], originalHost: host)
        }

        if ["", "watch", "watch_popup", "get_video_info", "verify_age"].contains(lower.first ?? ""),
           let id = videoID(from: queryItems) ?? (lower.first == "watch" && parts.count >= 2 ? parts[1] : nil),
           isVideoSlug(id) {
            return watchURL(videoID: id, originalHost: host, preservedItems: queryItems)
        }

        if isYouTubeWatchHost(host),
           let id = videoID(from: queryItems),
           isVideoSlug(id) {
            components.scheme = "https"
            components.host = normalizedWatchHost(for: host)
            components.path = "/watch"
            components.fragment = nil
            components.queryItems = watchQueryItems(videoID: id, existingItems: queryItems)
            return components.url
        }

        return nil
    }

    static func videoID(from url: URL) -> String? {
        canonicalURL(for: url).flatMap { canonical in
            URLComponents(url: canonical, resolvingAgainstBaseURL: false)?.queryItems
                .flatMap(videoID)
        }
    }

    static func resolvedDownload(
        fromHTML html: String,
        supplementalObjects: [Any] = [],
        pageURL: URL,
        preferredResolution: String = "",
        codecPriority: [YouTubeVideoCodec] = YouTubeVideoCodec.originalDefaultPriority,
        userAgent: String? = nil
    ) async throws -> ResolvedDownload {
        guard let id = videoID(from: pageURL) ?? clipID(from: pageURL) ?? firstVideoID(fromHTML: html) else {
            throw NativeDownloadError.invalidURL(pageURL.absoluteString)
        }
        let candidates = formatCandidates(
            fromHTML: html,
            supplementalObjects: supplementalObjects,
            pageURL: pageURL
        )
        let liveContent = isLiveContent(fromHTML: html, supplementalObjects: supplementalObjects)
        let liveCandidate = liveContent ? bestCandidate(
            candidates.filter { $0.kind == .hls },
            preferredResolution: preferredResolution,
            codecPriority: codecPriority
        ) : nil
        let candidate = liveCandidate ?? bestCandidate(
            candidates,
            preferredResolution: preferredResolution,
            codecPriority: codecPriority
        )
        let muxPair = liveContent ? nil : bestMuxPair(
            candidates,
            preferredResolution: preferredResolution,
            codecPriority: codecPriority
        )
        if liveContent, liveCandidate == nil {
            throw NativeDownloadError.unsupported("YouTube live HLS was not available; use the managed yt-dlp fallback.")
        }
        guard candidate != nil || muxPair != nil else {
            throw NativeDownloadError.noFiles
        }
        let info = videoInfo(
            fromHTML: html,
            supplementalObjects: supplementalObjects,
            pageURL: pageURL,
            fallbackID: id
        )

        if let pair = muxPair,
           candidate == nil || shouldPreferMux(pair.video, over: candidate!) {
            return muxedDownload(
                video: pair.video,
                audio: pair.audio,
                info: info,
                pageURL: pageURL,
                userAgent: userAgent
            )
        }

        guard let candidate else {
            throw NativeDownloadError.noFiles
        }

        if isM3U8(candidate.url) {
            let hls = try await M3U8Resolver().resolve(
                candidate.url,
                headers: HTTPRequestOptions(referer: pageURL.absoluteString, userAgent: userAgent)
            )
            var downloadMetadata = hls.metadata.merging(metadata(info: info, candidate: candidate, pageURL: pageURL)) { _, new in new }
            if liveContent {
                downloadMetadata["live"] = "true"
                downloadMetadata["is_live"] = "true"
                downloadMetadata["was_live"] = "true"
                downloadMetadata["live_status"] = "is_live"
                downloadMetadata["hls_remux_required"] = "true"
            }
            return ResolvedDownload(
                title: info.displayTitle,
                folderName: "YouTube \(info.displayTitle)".sanitizedFilename(maxLength: 120),
                assets: hlsAssetsWithPageMetadata(hls.assets, info: info, pageURL: pageURL),
                packageMode: .concatenate(outputFilename: "\(info.title)-\(info.id).ts".sanitizedFilename(maxLength: 180)),
                metadata: DownloadMetadata.clean(downloadMetadata)
            )
        }

        let ext = mediaFormat(for: candidate)
        let filename = "\(info.title)-\(info.id).\(ext)".sanitizedFilename(maxLength: 180)
        return ResolvedDownload(
            title: info.displayTitle,
            folderName: "YouTube \(info.displayTitle)".sanitizedFilename(maxLength: 120),
            assets: [
                ResolvedAsset(
                    remoteURL: candidate.url,
                    filename: filename,
                    metadata: mediaMetadata(for: candidate, info: info, pageURL: pageURL),
                    referer: pageURL.absoluteString,
                    userAgent: userAgent
                )
            ],
            packageMode: .concatenate(outputFilename: filename),
            metadata: metadata(info: info, candidate: candidate, pageURL: pageURL)
        )
    }

    private static func muxedDownload(
        video: YouTubeMediaCandidate,
        audio: YouTubeMediaCandidate,
        info: (
            id: String,
            title: String,
            displayTitle: String,
            uploader: String,
            channelID: String,
            uploaderID: String,
            thumbnail: URL?,
            date: String,
            duration: String
        ),
        pageURL: URL,
        userAgent: String?
    ) -> ResolvedDownload {
        let outputFilename = "\(info.title)-\(info.id).mp4".sanitizedFilename(maxLength: 180)
        let videoExtension = mediaFormat(for: video)
        let videoFilename = "youtube-video-\(video.itag.isEmpty ? "track" : video.itag).\(videoExtension)"
        let audioFilename = "youtube-audio-\(audio.itag.isEmpty ? "track" : audio.itag).m4a"

        var videoMetadata = mediaMetadata(for: video, info: info, pageURL: pageURL)
        videoMetadata["media_role"] = "video"
        videoMetadata["package_mode"] = "mux"
        var audioMetadata = mediaMetadata(for: audio, info: info, pageURL: pageURL)
        audioMetadata["category"] = "audio"
        audioMetadata["type"] = "audio"
        audioMetadata["media_type"] = "audio"
        audioMetadata["media_role"] = "audio"
        audioMetadata["package_mode"] = "mux"
        audioMetadata["audio_url"] = audio.url.absoluteString

        let videoAsset = ResolvedAsset(
            remoteURL: video.url,
            filename: videoFilename,
            metadata: DownloadMetadata.clean(videoMetadata),
            referer: pageURL.absoluteString,
            userAgent: userAgent
        )
        let audioAsset = ResolvedAsset(
            remoteURL: audio.url,
            filename: audioFilename,
            metadata: DownloadMetadata.clean(audioMetadata),
            referer: pageURL.absoluteString,
            userAgent: userAgent
        )

        var downloadMetadata = metadata(info: info, candidate: video, pageURL: pageURL)
        downloadMetadata["format"] = "mp4"
        downloadMetadata["media_format"] = "mp4"
        downloadMetadata["package_mode"] = "mux"
        downloadMetadata["media_count"] = "2"
        downloadMetadata["video_count"] = "1"
        downloadMetadata["audio_count"] = "1"
        downloadMetadata["video_itag"] = video.itag
        downloadMetadata["audio_itag"] = audio.itag
        downloadMetadata["video_url"] = video.url.absoluteString
        downloadMetadata["audio_url"] = audio.url.absoluteString
        downloadMetadata["audio_mime_type"] = audio.mimeType
        downloadMetadata["audio_bitrate"] = audio.bitrate > 0 ? String(audio.bitrate) : ""
        downloadMetadata["audio_channels"] = audio.audioChannels > 0 ? String(audio.audioChannels) : ""
        let totalContentLength = video.contentLength + audio.contentLength
        downloadMetadata["content_length"] = totalContentLength > 0 ? String(totalContentLength) : ""
        downloadMetadata["byte_count"] = totalContentLength > 0 ? String(totalContentLength) : ""
        downloadMetadata["filesize"] = totalContentLength > 0 ? String(totalContentLength) : ""

        return ResolvedDownload(
            title: info.displayTitle,
            folderName: "YouTube \(info.displayTitle)".sanitizedFilename(maxLength: 120),
            assets: [videoAsset, audioAsset],
            packageMode: .mux(
                videoAssets: [videoAsset],
                audioAssets: [audioAsset],
                outputFilename: outputFilename
            ),
            metadata: DownloadMetadata.clean(downloadMetadata)
        )
    }

    static func formatCandidates(
        fromHTML html: String,
        supplementalObjects: [Any] = [],
        pageURL: URL
    ) -> [YouTubeMediaCandidate] {
        var candidates: [YouTubeMediaCandidate] = []
        for object in jsonObjects(fromHTML: html) + supplementalObjects {
            collectFormatCandidates(in: object, pageURL: pageURL, keyPath: [], candidates: &candidates)
        }
        candidates.append(contentsOf: legacyFormatCandidates(fromHTML: html, pageURL: pageURL))

        var seen = Set<String>()
        return candidates.compactMap { candidate in
            let normalized = URLIdentity.normalize(candidate.url.absoluteString)
            guard !seen.contains(normalized) else { return nil }
            seen.insert(normalized)
            return candidate
        }
    }

    static func bestCandidate(
        _ candidates: [YouTubeMediaCandidate],
        preferredResolution: String = "",
        codecPriority: [YouTubeVideoCodec] = YouTubeVideoCodec.originalDefaultPriority
    ) -> YouTubeMediaCandidate? {
        let progressive = candidates.filter { $0.kind == .progressive || $0.kind == .hls }
        var pool = progressive
        if let height = preferredHeight(preferredResolution) {
            let bounded = progressive.filter { candidate in
                candidate.height > 0 && candidate.height <= height
            }
            if !bounded.isEmpty {
                pool = bounded
            }
        }
        let priority = YouTubeVideoCodec.normalizedPriority(codecPriority)
        return pool.max { lhs, rhs in
            if lhs.height != rhs.height { return lhs.height < rhs.height }
            let lhsCodec = lhs.codecPriorityIndex(in: priority)
            let rhsCodec = rhs.codecPriorityIndex(in: priority)
            if lhsCodec != rhsCodec { return lhsCodec > rhsCodec }
            if lhs.fps != rhs.fps { return lhs.fps < rhs.fps }
            if lhs.bitrate != rhs.bitrate { return lhs.bitrate < rhs.bitrate }
            if lhs.isDirectMP4 != rhs.isDirectMP4 { return !lhs.isDirectMP4 && rhs.isDirectMP4 }
            return lhs.score < rhs.score
        }
    }

    static func bestMuxPair(
        _ candidates: [YouTubeMediaCandidate],
        preferredResolution: String = "",
        codecPriority: [YouTubeVideoCodec] = YouTubeVideoCodec.originalDefaultPriority
    ) -> (video: YouTubeMediaCandidate, audio: YouTubeMediaCandidate)? {
        var videos = candidates.filter { $0.kind == .videoOnly }
        guard !videos.isEmpty else { return nil }

        if let height = preferredHeight(preferredResolution) {
            let bounded = videos.filter { $0.height > 0 && $0.height <= height }
            guard !bounded.isEmpty else { return nil }
            videos = bounded
        }

        let priority = YouTubeVideoCodec.normalizedPriority(codecPriority)
        guard let video = videos.max(by: { lhs, rhs in
            if lhs.height != rhs.height { return lhs.height < rhs.height }
            let lhsCodec = lhs.codecPriorityIndex(in: priority)
            let rhsCodec = rhs.codecPriorityIndex(in: priority)
            if lhsCodec != rhsCodec { return lhsCodec > rhsCodec }
            if lhs.fps != rhs.fps { return lhs.fps < rhs.fps }
            if lhs.bitrate != rhs.bitrate { return lhs.bitrate < rhs.bitrate }
            return lhs.score < rhs.score
        }) else {
            return nil
        }

        let audioPool = candidates.filter { $0.kind == .audioOnly && $0.isM4AAudio }
        guard let audio = audioPool.max(by: { lhs, rhs in
            if lhs.isDRC != rhs.isDRC { return lhs.isDRC && !rhs.isDRC }
            if lhs.bitrate != rhs.bitrate { return lhs.bitrate < rhs.bitrate }
            if lhs.audioChannels != rhs.audioChannels { return lhs.audioChannels < rhs.audioChannels }
            return lhs.score < rhs.score
        }) else {
            return nil
        }
        return (video, audio)
    }

    static func playerAPIConfiguration(fromHTML html: String, pageURL: URL) -> YouTubePlayerAPIConfiguration? {
        let apiKey = legacyJSONStringValues(named: "INNERTUBE_API_KEY", from: html).first ??
            legacyJSONStringValues(named: "innertubeApiKey", from: html).first
        guard let apiKey = apiKey?.trimmed, !apiKey.isEmpty else { return nil }

        var components = URLComponents()
        components.scheme = pageURL.scheme ?? "https"
        components.host = pageURL.host
        components.path = "/youtubei/v1/player"
        components.queryItems = [
            URLQueryItem(name: "key", value: apiKey),
            URLQueryItem(name: "prettyPrint", value: "false")
        ]
        guard let endpoint = components.url else { return nil }

        let visitorData = legacyJSONStringValues(named: "VISITOR_DATA", from: html).first ??
            legacyJSONStringValues(named: "visitorData", from: html).first
        let cleanedVisitorData = visitorData?.trimmed
        return YouTubePlayerAPIConfiguration(
            apiKey: apiKey,
            visitorData: cleanedVisitorData?.isEmpty == false ? cleanedVisitorData : nil,
            endpoint: endpoint
        )
    }

    static func androidPlayerRequestBody(videoID: String, visitorData: String?) throws -> Data {
        var client: [String: Any] = [
            "clientName": androidClientName,
            "clientVersion": androidClientVersion,
            "hl": "en",
            "gl": "US"
        ]
        if let visitorData = visitorData?.trimmed, !visitorData.isEmpty {
            client["visitorData"] = visitorData
        }
        let body: [String: Any] = [
            "context": ["client": client],
            "videoId": videoID,
            "contentCheckOk": true,
            "racyCheckOk": true
        ]
        return try JSONSerialization.data(withJSONObject: body)
    }

    static func fetchAndroidPlayerResponse(
        videoID: String,
        configuration: YouTubePlayerAPIConfiguration,
        pageURL: URL
    ) async throws -> Any {
        let body = try androidPlayerRequestBody(videoID: videoID, visitorData: configuration.visitorData)
        var requestHeaders = [
            "X-YouTube-Client-Name": androidClientNumber,
            "X-YouTube-Client-Version": androidClientVersion,
            "Origin": origin(for: pageURL)
        ]
        if let visitorData = configuration.visitorData {
            requestHeaders["X-Goog-Visitor-Id"] = visitorData
        }
        let data = try await HTTPClient.shared.postJSON(
            to: configuration.endpoint,
            body: body,
            referer: pageURL.absoluteString,
            userAgent: androidUserAgent,
            additionalHeaders: requestHeaders
        )
        let object = try JSONSerialization.jsonObject(with: data)
        guard let response = object as? [String: Any] else {
            throw NativeDownloadError.unsupported("YouTube player API returned invalid JSON.")
        }
        let playability = response["playabilityStatus"] as? [String: Any]
        let status = stringValue(playability?["status"]) ?? ""
        if !status.isEmpty, status != "OK" {
            let reason = stringValue(playability?["reason"]) ??
                textValue(playability?["errorScreen"]) ??
                status
            throw NativeDownloadError.unsupported("YouTube player API: \(reason)")
        }
        return response
    }

    private static func shouldPreferMux(_ video: YouTubeMediaCandidate, over progressive: YouTubeMediaCandidate) -> Bool {
        if video.height != progressive.height {
            return video.height > progressive.height
        }
        return progressive.kind != .progressive && video.bitrate > progressive.bitrate
    }

    static func isLiveContent(fromHTML html: String, supplementalObjects: [Any] = []) -> Bool {
        let objects = supplementalObjects + jsonObjects(fromHTML: html)
        if objects.contains(where: { recursiveBool(in: $0, keys: ["isLiveContent", "isLive", "isLiveNow"]) == true }) {
            return true
        }
        return html.range(
            of: #"\"(?:isLiveContent|isLive|isLiveNow)\"\s*:\s*true"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    private static func videoInfo(
        fromHTML html: String,
        supplementalObjects: [Any] = [],
        pageURL: URL,
        fallbackID: String
    ) -> (
        id: String,
        title: String,
        displayTitle: String,
        uploader: String,
        channelID: String,
        uploaderID: String,
        thumbnail: URL?,
        date: String,
        duration: String
    ) {
        let objects = supplementalObjects + jsonObjects(fromHTML: html)
        let details = firstRecursiveDictionary(in: objects, keys: ["videoDetails"]) ?? [:]
        let micro = firstRecursiveDictionary(in: objects, keys: ["playerMicroformatRenderer"]) ?? [:]
        let titleDict = micro["title"] as? [String: Any]

        let id = stringValue(details["videoId"]) ??
            stringValue(details["video_id"]) ??
            firstRecursiveString(in: objects, keys: ["videoId", "video_id"]) ??
            fallbackID
        let title = cleanTitle(
            stringValue(details["title"]) ??
                textValue(titleDict) ??
                metaContent(from: html, names: ["og:title", "twitter:title"]) ??
                titleTag(fromHTML: html) ??
                "YouTube \(fallbackID)",
            fallback: "YouTube \(fallbackID)"
        )
        let uploader = cleanTitle(
            stringValue(details["author"]) ??
                stringValue(micro["ownerChannelName"]) ??
                stringValue(micro["ownerProfileUrl"]) ??
                firstRecursiveString(in: objects, keys: ["ownerChannelName", "channelName", "author", "uploader"]) ??
                "",
            fallback: ""
        )
        let channelID = stringValue(details["channelId"]) ??
            stringValue(details["channel_id"]) ??
            stringValue(micro["externalChannelId"]) ??
            firstRecursiveString(in: objects, keys: ["channelId", "channel_id", "externalChannelId"]) ??
            ""
        let uploaderID = firstRecursiveString(in: objects, keys: ["uploader_id", "uploaderId"]) ?? channelID
        let duration = stringValue(details["lengthSeconds"]) ??
            stringValue(micro["lengthSeconds"]) ??
            firstRecursiveString(in: objects, keys: ["duration", "lengthSeconds"]) ??
            ""
        let thumbnailRaw = thumbnailURLString(from: details["thumbnail"]) ??
            thumbnailURLString(from: micro["thumbnail"]) ??
            thumbnailURLString(from: objects) ??
            metaContent(from: html, names: ["og:image", "twitter:image"])
        let date = normalizedDate(
            stringValue(micro["publishDate"]) ??
                stringValue(micro["uploadDate"]) ??
                stringValue(micro["datePublished"]) ??
                firstRecursiveString(
                    in: objects,
                    keys: ["publishDate", "publish_date", "uploadDate", "upload_date", "datePublished", "date_published"]
                ) ??
                metaContent(from: html, names: ["datePublished", "uploadDate", "article:published_time", "date"])
        ) ?? ""
        let displayTitle = uploader.isEmpty ? title : "\(uploader) - \(title)"
        return (
            id,
            title,
            displayTitle.sanitizedFilename(maxLength: 120),
            uploader,
            channelID,
            uploaderID,
            thumbnailRaw.flatMap { absoluteURL($0, baseURL: pageURL) },
            date,
            duration
        )
    }

    private static func metadata(
        info: (
            id: String,
            title: String,
            displayTitle: String,
            uploader: String,
            channelID: String,
            uploaderID: String,
            thumbnail: URL?,
            date: String,
            duration: String
        ),
        candidate: YouTubeMediaCandidate,
        pageURL: URL
    ) -> [String: String] {
        DownloadMetadata.clean([
            "site": "YouTube",
            "title": info.title,
            "artist": info.uploader,
            "author": info.uploader,
            "creator": info.uploader,
            "uploader": info.uploader,
            "channel": info.uploader,
            "channel_id": info.channelID,
            "uploader_id": info.uploaderID,
            "category": "video",
            "type": isM3U8(candidate.url) ? "hls" : "video",
            "media_type": isM3U8(candidate.url) ? "hls" : "video",
            "format": mediaFormat(for: candidate),
            "media_format": mediaFormat(for: candidate),
            "host": pageURL.host ?? "",
            "extractor": "youtube_native",
            "handler": "native",
            "id": info.id,
            "video_id": info.id,
            "media_id": info.id,
            "clip_id": clipID(from: pageURL) ?? "",
            "gallery_id": info.id,
            "itag": candidate.itag,
            "mime_type": candidate.mimeType,
            "media_count": isM3U8(candidate.url) ? "" : "1",
            "video_count": "1",
            "date": info.date,
            "upload_date": uploadDate(from: info.date),
            "published_date": info.date,
            "duration": info.duration,
            "height": candidate.height > 0 ? String(candidate.height) : "",
            "width": candidate.width > 0 ? String(candidate.width) : "",
            "fps": candidate.fps > 0 ? String(candidate.fps) : "",
            "bitrate": candidate.bitrate > 0 ? String(candidate.bitrate) : "",
            "content_length": candidate.contentLength > 0 ? String(candidate.contentLength) : "",
            "byte_count": candidate.contentLength > 0 ? String(candidate.contentLength) : "",
            "filesize": candidate.contentLength > 0 ? String(candidate.contentLength) : "",
            "resolution": resolution(for: candidate),
            "quality": qualityLabel(for: candidate),
            "thumbnail": info.thumbnail?.absoluteString ?? "",
            "video_url": candidate.url.absoluteString,
            "media_url": candidate.url.absoluteString,
            "playlist_url": isM3U8(candidate.url) ? candidate.url.absoluteString : "",
            "url": pageURL.absoluteString,
            "source_url": pageURL.absoluteString,
            "page_url": pageURL.absoluteString
        ])
    }

    private static func mediaMetadata(
        for candidate: YouTubeMediaCandidate,
        info: (
            id: String,
            title: String,
            displayTitle: String,
            uploader: String,
            channelID: String,
            uploaderID: String,
            thumbnail: URL?,
            date: String,
            duration: String
        ),
        pageURL: URL
    ) -> [String: String] {
        DownloadMetadata.clean([
            "site": "YouTube",
            "title": info.title,
            "artist": info.uploader,
            "author": info.uploader,
            "creator": info.uploader,
            "uploader": info.uploader,
            "channel": info.uploader,
            "channel_id": info.channelID,
            "uploader_id": info.uploaderID,
            "category": "video",
            "type": isM3U8(candidate.url) ? "hls" : "video",
            "media_type": isM3U8(candidate.url) ? "hls" : "video",
            "format": mediaFormat(for: candidate),
            "media_format": mediaFormat(for: candidate),
            "extractor": "youtube_native",
            "handler": "native",
            "id": info.id,
            "video_id": info.id,
            "media_id": info.id,
            "clip_id": clipID(from: pageURL) ?? "",
            "gallery_id": info.id,
            "itag": candidate.itag,
            "mime_type": candidate.mimeType,
            "date": info.date,
            "upload_date": uploadDate(from: info.date),
            "published_date": info.date,
            "duration": info.duration,
            "page": "1",
            "position": "1",
            "height": candidate.height > 0 ? String(candidate.height) : "",
            "width": candidate.width > 0 ? String(candidate.width) : "",
            "fps": candidate.fps > 0 ? String(candidate.fps) : "",
            "bitrate": candidate.bitrate > 0 ? String(candidate.bitrate) : "",
            "content_length": candidate.contentLength > 0 ? String(candidate.contentLength) : "",
            "byte_count": candidate.contentLength > 0 ? String(candidate.contentLength) : "",
            "filesize": candidate.contentLength > 0 ? String(candidate.contentLength) : "",
            "resolution": resolution(for: candidate),
            "quality": qualityLabel(for: candidate),
            "thumbnail": info.thumbnail?.absoluteString ?? "",
            "video_url": candidate.url.absoluteString,
            "media_url": candidate.url.absoluteString,
            "playlist_url": isM3U8(candidate.url) ? candidate.url.absoluteString : "",
            "source_url": pageURL.absoluteString,
            "page_url": pageURL.absoluteString
        ])
    }

    static func hlsAssetsWithPageMetadata(
        _ assets: [ResolvedAsset],
        info: (
            id: String,
            title: String,
            displayTitle: String,
            uploader: String,
            channelID: String,
            uploaderID: String,
            thumbnail: URL?,
            date: String,
            duration: String
        ),
        pageURL: URL
    ) -> [ResolvedAsset] {
        assets.enumerated().map { offset, asset in
            var enriched = asset
            let pageMetadata = segmentMetadata(info: info, asset: asset, pageURL: pageURL, index: offset + 1)
            enriched.metadata = segmentTimingPreservingMerge(base: asset.metadata, pageMetadata: pageMetadata)
            return enriched
        }
    }

    private static func segmentTimingPreservingMerge(base: [String: String], pageMetadata: [String: String]) -> [String: String] {
        let segmentKeys = Set([
            "duration",
            "duration_seconds",
            "segment_index",
            "segment_number",
            "segment_total",
            "total_segments",
            "media_sequence",
            "discontinuity_sequence",
            "segment_title",
            "hls_title",
            "encrypted",
            "key_url",
            "playlist_url"
        ])
        var merged = base
        for (key, value) in pageMetadata {
            if segmentKeys.contains(key), merged[key] != nil {
                continue
            }
            merged[key] = value
        }
        return DownloadMetadata.clean(merged)
    }

    private static func segmentMetadata(
        info: (
            id: String,
            title: String,
            displayTitle: String,
            uploader: String,
            channelID: String,
            uploaderID: String,
            thumbnail: URL?,
            date: String,
            duration: String
        ),
        asset: ResolvedAsset,
        pageURL: URL,
        index: Int
    ) -> [String: String] {
        let format = mediaFormat(for: asset.remoteURL, fallback: mediaFormat(forFilename: asset.filename, fallback: "ts"))
        return DownloadMetadata.clean([
            "site": "YouTube",
            "title": info.title,
            "artist": info.uploader,
            "author": info.uploader,
            "creator": info.uploader,
            "uploader": info.uploader,
            "channel": info.uploader,
            "channel_id": info.channelID,
            "uploader_id": info.uploaderID,
            "category": "video",
            "type": "hls_segment",
            "media_type": "segment",
            "format": format,
            "media_format": format,
            "extractor": "youtube_native",
            "handler": "native",
            "id": info.id,
            "video_id": info.id,
            "media_id": "\(info.id)-segment-\(index)",
            "clip_id": clipID(from: pageURL) ?? "",
            "gallery_id": info.id,
            "date": info.date,
            "upload_date": uploadDate(from: info.date),
            "published_date": info.date,
            "duration": info.duration,
            "page": String(index),
            "position": String(index),
            "thumbnail": info.thumbnail?.absoluteString ?? "",
            "video_url": asset.remoteURL.absoluteString,
            "media_url": asset.remoteURL.absoluteString,
            "source_url": pageURL.absoluteString,
            "page_url": pageURL.absoluteString
        ])
    }

    private static func collectFormatCandidates(
        in value: Any,
        pageURL: URL,
        keyPath: [String],
        candidates: inout [YouTubeMediaCandidate]
    ) {
        if let dict = value as? [String: Any] {
            if let candidate = candidate(from: dict, pageURL: pageURL, keyPath: keyPath) {
                candidates.append(candidate)
            }
            for (key, child) in dict {
                collectFormatCandidates(in: child, pageURL: pageURL, keyPath: keyPath + [key], candidates: &candidates)
            }
            return
        }

        if let array = value as? [Any] {
            for child in array {
                collectFormatCandidates(in: child, pageURL: pageURL, keyPath: keyPath, candidates: &candidates)
            }
        }
    }

    private static func candidate(from dict: [String: Any], pageURL: URL, keyPath: [String]) -> YouTubeMediaCandidate? {
        let mimeType = stringValue(dict["mimeType"]) ?? stringValue(dict["mime"]) ?? ""
        let keys = ["url", "hlsManifestUrl", "manifestUrl", "videoUrl", "video_url", "streamUrl", "stream_url", "file", "src"]
        var sources = keys.compactMap { key -> (key: String, raw: String, url: URL)? in
            guard let raw = stringValue(dict[key]), let url = absoluteURL(raw, baseURL: pageURL) else {
                return nil
            }
            return (key, raw, url)
        }
        if sources.isEmpty,
           let cipher = stringValue(dict["signatureCipher"]) ?? stringValue(dict["cipher"]),
           let url = cipherMediaURL(from: cipher, baseURL: pageURL) {
            sources.append(("signatureCipher", url.absoluteString, url))
        }

        for source in sources {
            let key = source.key
            let raw = source.raw
            let url = source.url
            guard isLikelyPlayableURL(url: url, raw: raw, mimeType: mimeType, keyPath: keyPath + [key]) else {
                continue
            }
            let isAdaptive = containsAdaptiveFormats(keyPath)
            let isAudio = mimeType.lowercased().hasPrefix("audio/")
            let isDirectHLS = isM3U8(url) || key.lowercased().contains("hls")
            let kind: YouTubeMediaKind
            if isDirectHLS {
                kind = .hls
            } else if isAudio {
                kind = .audioOnly
            } else if isAdaptive {
                kind = .videoOnly
            } else {
                kind = .progressive
            }
            guard kind == .hls || isAudio || mimeType.lowercased().hasPrefix("video/") ||
                    keyPath.map({ $0.lowercased() }).contains("formats") else {
                continue
            }

            let height = intValue(dict["height"]) ??
                stringValue(dict["qualityLabel"]).flatMap(heightFromText) ??
                stringValue(dict["quality"]).flatMap(heightFromText) ??
                heightFromText(raw) ??
                0
            let width = intValue(dict["width"]) ?? 0
            let quality = cleanText(
                stringValue(dict["qualityLabel"]) ??
                    stringValue(dict["quality"]) ??
                    stringValue(dict["format"]) ??
                    "",
                fallback: ""
            )
            let ext = extensionHint(
                url: url,
                mimeType: mimeType,
                fallback: isDirectHLS ? "m3u8" : (isAudio ? "m4a" : "mp4")
            )
            let itag = stringValue(dict["itag"]) ?? stringValue(dict["format_id"]) ?? ""
            let bitrate = intValue(dict["bitrate"]) ?? intValue(dict["averageBitrate"]) ?? 0
            let fps = intValue(dict["fps"]) ?? 0
            let path = (keyPath + [key]).joined(separator: ".")
            let audioQuality = stringValue(dict["audioQuality"]) ?? stringValue(dict["audioQualityClass"]) ?? ""
            let audioChannels = intValue(dict["audioChannels"]) ?? 0
            let contentLength = int64Value(dict["contentLength"]) ?? int64Value(dict["clen"]) ?? 0
            let drcText = "\(raw) \(quality) \(audioQuality)".lowercased()
            let isDRC = boolValue(dict["isDrc"]) ||
                boolValue(dict["drc"]) ||
                drcText.contains("drc=1") ||
                drcText.contains("drc%3d1") ||
                drcText.contains("dynamic range compression")
            return YouTubeMediaCandidate(
                url: url,
                height: height,
                width: width,
                mimeType: mimeType,
                qualityLabel: quality,
                itag: itag,
                bitrate: bitrate,
                fps: fps,
                extensionHint: ext,
                sourcePath: path,
                score: score(raw: raw, mimeType: mimeType, keyPath: keyPath + [key], height: height, bitrate: bitrate, fps: fps),
                kind: kind,
                audioQuality: audioQuality,
                audioChannels: audioChannels,
                contentLength: contentLength,
                isDRC: isDRC
            )
        }

        return nil
    }

    private static func cipherMediaURL(from cipher: String, baseURL: URL) -> URL? {
        let fields = legacyFormFields(from: cipher)
        guard let rawURL = fields["url"], let base = absoluteURL(rawURL, baseURL: baseURL) else {
            return nil
        }
        let signature = fields["sig"] ?? fields["signature"]
        if fields["s"]?.trimmed.isEmpty == false, signature == nil {
            return nil
        }
        guard let signature = signature?.trimmed, !signature.isEmpty,
              var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            return base
        }
        let parameter = fields["sp"]?.trimmed.isEmpty == false ? fields["sp"]! : "signature"
        if !(components.queryItems ?? []).contains(where: { $0.name == parameter }) {
            var items = components.queryItems ?? []
            items.append(URLQueryItem(name: parameter, value: signature))
            components.queryItems = items
        }
        return components.url ?? base
    }

    private static func legacyFormatCandidates(fromHTML html: String, pageURL: URL) -> [YouTubeMediaCandidate] {
        let maps = legacyJSONStringValues(named: "url_encoded_fmt_stream_map", from: html) +
            legacyFormStringValues(named: "url_encoded_fmt_stream_map", from: html)
        let streamMapCandidates = maps.flatMap { map in
            map.split(separator: ",", omittingEmptySubsequences: true).compactMap { entry in
                legacyCandidate(from: String(entry), pageURL: pageURL, sourceName: "url_encoded_fmt_stream_map")
            }
        }

        let dimensions = legacyFormatDimensions(from: legacyJSONStringValues(named: "fmt_list", from: html) + legacyFormStringValues(named: "fmt_list", from: html))
        let pipeMapCandidates = legacyPipeMapCandidates(
            named: "fmt_stream_map",
            fromHTML: html,
            pageURL: pageURL,
            dimensions: dimensions
        ) + legacyPipeMapCandidates(
            named: "fmt_url_map",
            fromHTML: html,
            pageURL: pageURL,
            dimensions: dimensions
        )

        let hlsCandidates = (legacyJSONStringValues(named: "hlsvp", from: html) + legacyFormStringValues(named: "hlsvp", from: html))
            .compactMap { raw -> YouTubeMediaCandidate? in
                guard let url = absoluteURL(formDecode(raw), baseURL: pageURL),
                      isM3U8(url) else {
                    return nil
                }
                return YouTubeMediaCandidate(
                    url: url,
                    height: heightFromText(raw) ?? 0,
                    width: 0,
                    mimeType: "application/vnd.apple.mpegurl",
                    qualityLabel: "",
                    itag: "",
                    bitrate: 0,
                    fps: 0,
                    extensionHint: "m3u8",
                    sourcePath: "legacy.hlsvp",
                    score: score(raw: raw, mimeType: "application/vnd.apple.mpegurl", keyPath: ["legacy", "hlsvp"], height: heightFromText(raw) ?? 0, bitrate: 0, fps: 0)
                )
            }

        return streamMapCandidates + pipeMapCandidates + hlsCandidates
    }

    private static func legacyCandidate(from entry: String, pageURL: URL, sourceName: String) -> YouTubeMediaCandidate? {
        let fields = legacyFormFields(from: entry)
        guard stringValue(fields["cipher"]) == nil,
              stringValue(fields["signaturecipher"]) == nil,
              !(fields["s"]?.trimmed.isEmpty == false && fields["sig"] == nil && fields["signature"] == nil),
              let rawURL = fields["url"],
              let url = legacyMediaURL(from: rawURL, signature: fields["sig"] ?? fields["signature"], baseURL: pageURL) else {
            return nil
        }

        let mimeType = fields["type"] ?? fields["mime"] ?? ""
        guard !mimeType.lowercased().hasPrefix("audio/"),
              isLikelyPlayableURL(url: url, raw: rawURL, mimeType: mimeType, keyPath: ["legacy", sourceName, "url"]) else {
            return nil
        }

        let quality = cleanText(fields["quality_label"] ?? fields["quality"] ?? "", fallback: "")
        let height = fields["height"].flatMap(Int.init) ??
            fields["quality_label"].flatMap(heightFromText) ??
            fields["quality"].flatMap(legacyQualityHeight) ??
            heightFromText(rawURL) ??
            0
        let width = fields["width"].flatMap(Int.init) ?? 0
        let bitrate = fields["bitrate"].flatMap(Int.init) ?? 0
        let fps = fields["fps"].flatMap(Int.init) ?? 0
        let ext = extensionHint(url: url, mimeType: mimeType, fallback: isM3U8(url) ? "m3u8" : "mp4")
        return YouTubeMediaCandidate(
            url: url,
            height: height,
            width: width,
            mimeType: mimeType,
            qualityLabel: quality,
            itag: fields["itag"] ?? "",
            bitrate: bitrate,
            fps: fps,
            extensionHint: ext,
            sourcePath: "legacy.\(sourceName)",
            score: score(raw: rawURL, mimeType: mimeType, keyPath: ["legacy", sourceName, "url"], height: height, bitrate: bitrate, fps: fps)
        )
    }

    private static func legacyMediaURL(from rawURL: String, signature: String?, baseURL: URL) -> URL? {
        guard let url = absoluteURL(rawURL, baseURL: baseURL) else {
            return nil
        }
        guard let signature = signature?.trimmed, !signature.isEmpty,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        let existingNames = Set((components.queryItems ?? []).map { $0.name.lowercased() })
        guard !existingNames.contains("sig"), !existingNames.contains("signature") else {
            return url
        }
        var items = components.queryItems ?? []
        items.append(URLQueryItem(name: "signature", value: signature))
        components.queryItems = items
        return components.url ?? url
    }

    private static func legacyPipeMapCandidates(
        named name: String,
        fromHTML html: String,
        pageURL: URL,
        dimensions: [String: (width: Int, height: Int)]
    ) -> [YouTubeMediaCandidate] {
        let maps = legacyJSONStringValues(named: name, from: html) + legacyFormStringValues(named: name, from: html)
        return maps.flatMap { map in
            legacyPipeEntries(from: map).compactMap { entry in
                legacyPipeCandidate(from: entry, pageURL: pageURL, sourceName: name, dimensions: dimensions)
            }
        }
    }

    private static func legacyPipeEntries(from map: String) -> [String] {
        let value = map.contains("|") ? map : formDecode(map)
        return value.split(separator: ",", omittingEmptySubsequences: true).map(String.init)
    }

    private static func legacyPipeCandidate(
        from entry: String,
        pageURL: URL,
        sourceName: String,
        dimensions: [String: (width: Int, height: Int)]
    ) -> YouTubeMediaCandidate? {
        let value = entry.contains("|") ? entry : formDecode(entry)
        let pieces = value.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        guard pieces.count == 2 else { return nil }
        let itag = formDecode(String(pieces[0])).trimmed
        let rawURL = formDecode(String(pieces[1])).trimmed
        guard !itag.isEmpty,
              let url = legacyMediaURL(from: rawURL, signature: nil, baseURL: pageURL) else {
            return nil
        }

        let mimeType = mimeType(from: url) ?? legacyMimeType(forItag: itag)
        guard !mimeType.lowercased().hasPrefix("audio/"),
              isLikelyPlayableURL(url: url, raw: rawURL, mimeType: mimeType, keyPath: ["legacy", sourceName, "url"]) else {
            return nil
        }

        let dimension = dimensions[itag]
        let height = dimension?.height ?? legacyItagHeight(itag) ?? heightFromText(rawURL) ?? 0
        let width = dimension?.width ?? 0
        let ext = extensionHint(url: url, mimeType: mimeType, fallback: legacyExtension(forItag: itag))
        return YouTubeMediaCandidate(
            url: url,
            height: height,
            width: width,
            mimeType: mimeType,
            qualityLabel: height > 0 ? "\(height)p" : "",
            itag: itag,
            bitrate: 0,
            fps: 0,
            extensionHint: ext,
            sourcePath: "legacy.\(sourceName)",
            score: score(raw: rawURL, mimeType: mimeType, keyPath: ["legacy", sourceName, "url"], height: height, bitrate: 0, fps: 0)
        )
    }

    private static func legacyFormatDimensions(from values: [String]) -> [String: (width: Int, height: Int)] {
        var dimensions: [String: (width: Int, height: Int)] = [:]
        for raw in values {
            let value = raw.contains("/") ? raw : formDecode(raw)
            for entry in value.split(separator: ",", omittingEmptySubsequences: true) {
                let pieces = entry.split(separator: "/", maxSplits: 2, omittingEmptySubsequences: false)
                guard pieces.count >= 2 else { continue }
                let itag = formDecode(String(pieces[0])).trimmed
                let size = formDecode(String(pieces[1]))
                guard let match = size.range(of: #"([0-9]{2,5})x([0-9]{2,5})"#, options: .regularExpression) else {
                    continue
                }
                let parts = size[match].split(separator: "x", maxSplits: 1).compactMap { Int($0) }
                guard parts.count == 2, (144...8640).contains(parts[1]) else { continue }
                dimensions[itag] = (width: parts[0], height: parts[1])
            }
        }
        return dimensions
    }

    private static func legacyFormFields(from entry: String) -> [String: String] {
        var fields: [String: String] = [:]
        for pair in entry.split(separator: "&", omittingEmptySubsequences: true) {
            let pieces = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard let key = pieces.first else { continue }
            let name = formDecode(String(key)).lowercased()
            guard !name.isEmpty else { continue }
            fields[name] = pieces.count > 1 ? formDecode(String(pieces[1])) : ""
        }
        return fields
    }

    private static func legacyJSONStringValues(named name: String, from html: String) -> [String] {
        let key = NSRegularExpression.escapedPattern(for: name)
        let patterns = [
            "\"\(key)\"\\s*:\\s*\"((?:\\\\.|[^\"\\\\])*)\"",
            "'\(key)'\\s*:\\s*'((?:\\\\.|[^'\\\\])*)'"
        ]
        return patterns.flatMap { pattern in
            captures(pattern: pattern, in: html).map(jsonStringDecode)
        }
    }

    private static func legacyFormStringValues(named name: String, from html: String) -> [String] {
        let key = NSRegularExpression.escapedPattern(for: name)
        let patterns = [
            "(?:^|[?&#;\\s])\(key)=([^&<>\"'\\s]+)"
        ]
        return patterns.flatMap { pattern in
            captures(pattern: pattern, in: html).map(formDecode)
        }
    }

    private static func jsonStringDecode(_ raw: String) -> String {
        normalizeEscapes(decodeHTML(raw))
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\'", with: "'")
    }

    private static func formDecode(_ raw: String) -> String {
        let value = raw.replacingOccurrences(of: "+", with: " ")
        return value.removingPercentEncoding ?? value
    }

    private static func mimeType(from url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { item in
            item.name.lowercased() == "mime" || item.name.lowercased() == "type"
        }?.value
    }

    private static func legacyMimeType(forItag itag: String) -> String {
        switch itag {
        case "5", "6", "34", "35":
            return "video/x-flv"
        case "17", "36":
            return "video/3gpp"
        case "43", "44", "45", "46", "100", "101", "102":
            return "video/webm"
        default:
            return "video/mp4"
        }
    }

    private static func legacyExtension(forItag itag: String) -> String {
        switch legacyMimeType(forItag: itag) {
        case "video/x-flv":
            return "flv"
        case "video/3gpp":
            return "3gp"
        case "video/webm":
            return "webm"
        default:
            return "mp4"
        }
    }

    private static func legacyItagHeight(_ itag: String) -> Int? {
        switch itag {
        case "5", "17", "36":
            return 240
        case "18", "34", "43", "82", "100":
            return 360
        case "35", "44", "59", "78", "83", "101":
            return 480
        case "22", "45", "84", "102":
            return 720
        case "37", "46", "85":
            return 1080
        case "38":
            return 3072
        default:
            return nil
        }
    }

    private static func legacyQualityHeight(_ raw: String) -> Int? {
        let value = raw.lowercased()
        if let height = heightFromText(value) {
            return height
        }
        if let capture = firstCapture(pattern: #"(?:hd|sd)?([0-9]{3,4})"#, in: value),
           let height = Int(capture),
           (144...8640).contains(height) {
            return height
        }
        switch value {
        case "highres":
            return 2160
        case "hd1080":
            return 1080
        case "hd720":
            return 720
        case "large":
            return 480
        case "medium":
            return 360
        case "small":
            return 240
        case "tiny":
            return 144
        default:
            return nil
        }
    }

    static func jsonObjects(fromHTML html: String) -> [Any] {
        let payloads = scriptJSONPayloads(fromHTML: html) +
            assignmentPayloads(fromHTML: html) +
            attributePayloads(fromHTML: html) +
            playerResponsePayloads(fromHTML: html)
        return payloads.compactMap { raw in
            guard let data = jsonData(from: raw) else { return nil }
            return try? JSONSerialization.jsonObject(with: data)
        }
    }

    private static func scriptJSONPayloads(fromHTML html: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"<script\b[^>]*>(.*?)</script>"#, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        return regex.matches(in: html, range: range).compactMap { match in
            guard let capture = Range(match.range(at: 1), in: html) else { return nil }
            let raw = String(html[capture]).trimmed
            return raw.hasPrefix("{") || raw.hasPrefix("[") ? raw : nil
        }
    }

    private static func assignmentPayloads(fromHTML html: String) -> [String] {
        var payloads: [String] = []
        let patterns = [
            #"ytInitialPlayerResponse\s*="#,
            #"window\s*\[\s*["']ytInitialPlayerResponse["']\s*\]\s*="#,
            #"window\.ytInitialPlayerResponse\s*="#,
            #"(?:var|let|const)\s+ytInitialPlayerResponse\s*="#,
            #"ytInitialData\s*="#,
            #"window\s*\[\s*["']ytInitialData["']\s*\]\s*="#,
            #"ytcfg\.set\s*\(\s*"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(html.startIndex..<html.endIndex, in: html)
            payloads.append(contentsOf: regex.matches(in: html, range: range).compactMap { match in
                guard let matchRange = Range(match.range, in: html) else { return nil }
                return balancedValue(startingAtOrAfter: matchRange.upperBound, in: html)
            })
        }
        return payloads
    }

    private static func attributePayloads(fromHTML html: String) -> [String] {
        captures(pattern: #"\bdata-player-response\s*=\s*["']([^"']+)["']"#, in: html)
            .map(decodeHTML)
    }

    private static func playerResponsePayloads(fromHTML html: String) -> [String] {
        let values = legacyJSONStringValues(named: "player_response", from: html) +
            legacyJSONStringValues(named: "playerResponse", from: html) +
            legacyFormStringValues(named: "player_response", from: html)
        return values.compactMap(playerResponsePayload)
    }

    private static func playerResponsePayload(_ raw: String) -> String? {
        let decoded = decodeHTML(normalizeEscapes(raw)).trimmed
        if decoded.hasPrefix("{") || decoded.hasPrefix("[") {
            return decoded
        }
        let formDecoded = formDecode(decoded).trimmed
        if formDecoded.hasPrefix("{") || formDecoded.hasPrefix("[") {
            return formDecoded
        }
        return nil
    }

    private static func balancedValue(startingAtOrAfter start: String.Index, in text: String) -> String? {
        var index = start
        while index < text.endIndex, text[index].isWhitespace {
            index = text.index(after: index)
        }
        guard index < text.endIndex, text[index] == "{" || text[index] == "[" else {
            return nil
        }
        let opener = text[index]
        let closer: Character = opener == "{" ? "}" : "]"
        var depth = 0
        var inString: Character?
        var escaped = false
        var cursor = index
        while cursor < text.endIndex {
            let char = text[cursor]
            if let quote = inString {
                if escaped {
                    escaped = false
                } else if char == "\\" {
                    escaped = true
                } else if char == quote {
                    inString = nil
                }
                cursor = text.index(after: cursor)
                continue
            }
            if char == "\"" || char == "'" {
                inString = char
            } else if char == opener {
                depth += 1
            } else if char == closer {
                depth -= 1
                if depth == 0 {
                    return String(text[index...cursor])
                }
            }
            cursor = text.index(after: cursor)
        }
        return nil
    }

    private static func jsonData(from raw: String) -> Data? {
        let decoded = decodeHTML(normalizeEscapes(raw)).trimmed
        guard decoded.hasPrefix("{") || decoded.hasPrefix("[") else { return nil }
        return decoded.data(using: .utf8)
    }

    private static func firstRecursiveString(in values: [Any], keys: [String]) -> String? {
        for value in values {
            if let found = recursiveString(in: value, keys: keys) {
                return found
            }
        }
        return nil
    }

    private static func recursiveString(in value: Any, keys: [String]) -> String? {
        if let dict = value as? [String: Any] {
            for key in keys {
                if let direct = stringValue(dict[key]) {
                    return direct
                }
            }
            for child in dict.values {
                if let found = recursiveString(in: child, keys: keys) {
                    return found
                }
            }
        }
        if let array = value as? [Any] {
            for child in array {
                if let found = recursiveString(in: child, keys: keys) {
                    return found
                }
            }
        }
        return nil
    }

    private static func recursiveBool(in value: Any, keys: [String]) -> Bool? {
        if let dict = value as? [String: Any] {
            for key in keys where dict[key] != nil {
                return boolValue(dict[key])
            }
            for child in dict.values {
                if let found = recursiveBool(in: child, keys: keys) {
                    return found
                }
            }
        }
        if let array = value as? [Any] {
            for child in array {
                if let found = recursiveBool(in: child, keys: keys) {
                    return found
                }
            }
        }
        return nil
    }

    private static func firstRecursiveDictionary(in values: [Any], keys: [String]) -> [String: Any]? {
        for value in values {
            if let found = recursiveDictionary(in: value, keys: keys) {
                return found
            }
        }
        return nil
    }

    private static func recursiveDictionary(in value: Any, keys: [String]) -> [String: Any]? {
        if let dict = value as? [String: Any] {
            for key in keys {
                if let direct = dict[key] as? [String: Any] {
                    return direct
                }
            }
            for child in dict.values {
                if let found = recursiveDictionary(in: child, keys: keys) {
                    return found
                }
            }
        }
        if let array = value as? [Any] {
            for child in array {
                if let found = recursiveDictionary(in: child, keys: keys) {
                    return found
                }
            }
        }
        return nil
    }

    private static func textValue(_ value: Any?) -> String? {
        if let string = stringValue(value) {
            return string
        }
        if let dict = value as? [String: Any] {
            if let simple = stringValue(dict["simpleText"]) {
                return simple
            }
            if let runs = dict["runs"] as? [[String: Any]] {
                let text = runs.compactMap { stringValue($0["text"]) }.joined()
                return text.trimmed.isEmpty ? nil : text
            }
        }
        return nil
    }

    private static func thumbnailURLString(from value: Any?) -> String? {
        if let string = stringValue(value), isImageURLString(string) {
            return string
        }
        var best: (url: String, width: Int)?
        collectThumbnails(in: value as Any, best: &best)
        return best?.url
    }

    private static func collectThumbnails(in value: Any, best: inout (url: String, width: Int)?) {
        if let dict = value as? [String: Any] {
            if let raw = stringValue(dict["url"]), isImageURLString(raw) {
                let width = intValue(dict["width"]) ?? 0
                if best == nil || width > (best?.width ?? 0) {
                    best = (raw, width)
                }
            }
            for child in dict.values {
                collectThumbnails(in: child, best: &best)
            }
            return
        }
        if let array = value as? [Any] {
            for child in array {
                collectThumbnails(in: child, best: &best)
            }
        }
    }

    private static func mediaFormat(for candidate: YouTubeMediaCandidate) -> String {
        if isM3U8(candidate.url) { return "m3u8" }
        let ext = candidate.extensionHint.lowercased()
        if !ext.isEmpty { return ext }
        let pathExt = candidate.url.pathExtension.lowercased()
        return pathExt.isEmpty ? "mp4" : pathExt
    }

    private static func mediaFormat(for url: URL, fallback: String) -> String {
        let ext = url.pathExtension.trimmed
        return (ext.isEmpty ? fallback : ext).lowercased()
    }

    private static func mediaFormat(forFilename filename: String, fallback: String) -> String {
        let ext = (filename as NSString).pathExtension.trimmed
        return (ext.isEmpty ? fallback : ext).lowercased()
    }

    private static func resolution(for candidate: YouTubeMediaCandidate) -> String {
        if candidate.height > 0 { return "\(candidate.height)p" }
        if let height = heightFromText(candidate.qualityLabel) { return "\(height)p" }
        return ""
    }

    private static func qualityLabel(for candidate: YouTubeMediaCandidate) -> String {
        let resolution = resolution(for: candidate)
        return resolution.isEmpty ? candidate.qualityLabel : resolution
    }

    private static func preferredHeight(_ raw: String) -> Int? {
        var value = raw.trimmed.lowercased()
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

    private static func score(raw: String, mimeType: String, keyPath: [String], height: Int, bitrate: Int, fps: Int) -> Int {
        let text = (keyPath.joined(separator: ".") + " " + raw + " " + mimeType).lowercased()
        var score = height * 10_000 + bitrate / 1_000 + fps * 10
        if text.contains("streamingdata.formats") { score += 1_000_000 }
        if text.contains("video/mp4") || text.contains("mime=video%2fmp4") { score += 100_000 }
        if text.contains("video/webm") || text.contains("mime=video%2fwebm") { score += 60_000 }
        if text.contains(".m3u8") || text.contains("hlsmanifesturl") { score += 40_000 }
        if text.contains("adaptiveformats") { score -= 2_000_000 }
        return score
    }

    private static func isLikelyPlayableURL(url: URL, raw: String, mimeType: String, keyPath: [String]) -> Bool {
        let text = (url.absoluteString + " " + raw + " " + mimeType + " " + keyPath.joined(separator: ".")).lowercased()
        if isM3U8(url) || text.contains(".m3u8") || text.contains("hlsmanifesturl") {
            return true
        }
        if mimeType.lowercased().hasPrefix("video/") {
            return true
        }
        if mimeType.lowercased().hasPrefix("audio/") && containsAdaptiveFormats(keyPath) {
            return true
        }
        let ext = url.pathExtension.lowercased()
        if ["mp4", "m4a", "webm", "m4v", "mov"].contains(ext) {
            return true
        }
        return text.contains("videoplayback") && (text.contains("mime=video") || text.contains("mime=audio"))
    }

    private static func containsAdaptiveFormats(_ keyPath: [String]) -> Bool {
        keyPath.contains { $0.lowercased() == "adaptiveformats" }
    }

    private static func heightFromText(_ text: String) -> Int? {
        let patterns = [
            #"([0-9]{3,4})\s*p"#,
            #"[xX]([0-9]{3,4})"#,
            #"height[=:/_-]?([0-9]{3,4})"#
        ]
        for pattern in patterns {
            if let value = firstCapture(pattern: pattern, in: text), let height = Int(value), (144...8640).contains(height) {
                return height
            }
        }
        return nil
    }

    private static func extensionHint(url: URL, mimeType: String, fallback: String) -> String {
        let mime = mimeType.lowercased()
        if mime.contains("audio/mp4") { return "m4a" }
        if mime.contains("audio/webm") { return "webm" }
        if mime.contains("video/webm") { return "webm" }
        if mime.contains("video/mp4") { return "mp4" }
        if isM3U8(url) { return "m3u8" }
        let ext = url.pathExtension.lowercased()
        return ext.isEmpty ? fallback : ext
    }

    private static func normalizedDate(_ raw: String?) -> String? {
        guard let value = raw?.trimmed, !value.isEmpty else { return nil }
        if let match = value.range(of: #"[0-9]{4}-[0-9]{2}-[0-9]{2}"#, options: .regularExpression) {
            return String(value[match])
        }
        if value.range(of: #"^[0-9]{8}$"#, options: .regularExpression) != nil {
            let monthStart = value.index(value.startIndex, offsetBy: 4)
            let dayStart = value.index(value.startIndex, offsetBy: 6)
            return "\(value.prefix(4))-\(value[monthStart..<dayStart])-\(value[dayStart..<value.endIndex])"
        }
        return nil
    }

    private static func uploadDate(from date: String) -> String {
        date.replacingOccurrences(of: "-", with: "")
    }

    private static func metaContent(from html: String, names: [String]) -> String? {
        for name in names {
            let patterns = [
                #"<meta\b[^>]*(?:property|name)\s*=\s*["']\#(name)["'][^>]*content\s*=\s*["']([^"']+)["'][^>]*>"#,
                #"<meta\b[^>]*content\s*=\s*["']([^"']+)["'][^>]*(?:property|name)\s*=\s*["']\#(name)["'][^>]*>"#
            ]
            for pattern in patterns {
                if let value = firstCapture(pattern: pattern, in: html) {
                    return decodeHTML(value)
                }
            }
        }
        return nil
    }

    private static func titleTag(fromHTML html: String) -> String? {
        guard let raw = firstCapture(pattern: #"<title\b[^>]*>(.*?)</title>"#, in: html) else {
            return nil
        }
        return stripTags(raw)
    }

    private static func watchURL(videoID: String, originalHost: String, preservedItems: [URLQueryItem]) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = normalizedWatchHost(for: originalHost)
        components.path = "/watch"
        components.queryItems = watchQueryItems(videoID: videoID, existingItems: preservedItems)
        return components.url
    }

    private static func clipURL(clipID: String, originalHost: String) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = normalizedWatchHost(for: originalHost)
        components.path = "/clip/\(clipID)"
        return components.url
    }

    private static func watchQueryItems(videoID: String, existingItems: [URLQueryItem]) -> [URLQueryItem] {
        var items = [URLQueryItem(name: "v", value: videoID)]
        let preserved = Set(["t", "start", "end", "time_continue"])
        for item in existingItems where preserved.contains(item.name.lowercased()) {
            items.append(item)
        }
        return items
    }

    private static func videoID(from items: [URLQueryItem]) -> String? {
        for name in ["v", "video_id", "videoid", "video"] {
            if let value = items.first(where: { $0.name.lowercased() == name })?.value,
               isVideoSlug(value) {
                return value
            }
        }
        return nil
    }

    private static func clipID(from url: URL) -> String? {
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        guard parts.count >= 2,
              parts[0].lowercased() == "clip",
              isVideoSlug(parts[1]) else {
            return nil
        }
        return parts[1]
    }

    private static func firstVideoID(fromHTML html: String) -> String? {
        if let id = firstRecursiveString(in: jsonObjects(fromHTML: html), keys: ["videoId", "video_id"]),
           isVideoSlug(id) {
            return id
        }
        return nil
    }

    private static func normalizedWatchHost(for host: String) -> String {
        host.hasSuffix(".test") ? "www.youtube.test" : "www.youtube.com"
    }

    private static func isSupportedHost(_ host: String) -> Bool {
        isYouTubeWatchHost(host) ||
            isShortHost(host) ||
            isYewtuHost(host) ||
            host == "youtube-nocookie.com" ||
            host == "www.youtube-nocookie.com" ||
            host == "youtube-nocookie.test" ||
            host == "www.youtube-nocookie.test"
    }

    private static func isYouTubeWatchHost(_ host: String) -> Bool {
        host == "youtube.com" ||
            host == "youtube.co" ||
            host == "www.youtube.com" ||
            host == "www.youtube.co" ||
            host == "m.youtube.com" ||
            host == "music.youtube.com" ||
            host == "youtube.test" ||
            host == "www.youtube.test" ||
            host == "m.youtube.test" ||
            host == "music.youtube.test"
    }

    private static func isShortHost(_ host: String) -> Bool {
        host == "youtu.be" ||
            host == "www.youtu.be" ||
            host == "youtu.be.test" ||
            host == "www.youtu.be.test"
    }

    private static func isYewtuHost(_ host: String) -> Bool {
        host == "yewtu.be" ||
            host == "www.yewtu.be" ||
            host.hasSuffix(".yewtu.be") ||
            host == "yewtu.be.test" ||
            host == "www.yewtu.be.test"
    }

    private static func isYewtuReservedPath(_ value: String) -> Bool {
        [
            "channel", "clip", "feed", "hashtag", "playlist", "privacy", "search",
            "shorts", "subscriptions", "user", "watch"
        ].contains(value.lowercased())
    }

    private static func isVideoSlug(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z0-9_-]{6,64}$"#, options: .regularExpression) != nil
    }

    private static func isImageURLString(_ value: String) -> Bool {
        let lower = value.lowercased()
        return lower.contains(".jpg") ||
            lower.contains(".jpeg") ||
            lower.contains(".png") ||
            lower.contains(".webp") ||
            lower.contains("i.ytimg.")
    }

    private static func isM3U8(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "m3u8" || url.absoluteString.lowercased().contains(".m3u8")
    }

    private static func captures(pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > 1,
                  let capture = Range(match.range(at: 1), in: text) else {
                return nil
            }
            return String(text[capture])
        }
    }

    private static func firstCapture(pattern: String, in text: String) -> String? {
        captures(pattern: pattern, in: text).first
    }

    private static func absoluteURL(_ raw: String, baseURL: URL) -> URL? {
        var value = decodeHTML(normalizeEscapes(raw))
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'").union(.whitespacesAndNewlines))
        guard !value.isEmpty else { return nil }
        if value.hasPrefix("//") {
            value = "\(baseURL.scheme ?? "https"):\(value)"
        }
        return URL(string: value, relativeTo: baseURL)?.absoluteURL
    }

    private static func origin(for url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return "https://www.youtube.com"
        }
        components.path = ""
        components.query = nil
        components.fragment = nil
        return components.url?.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ??
            "https://www.youtube.com"
    }

    private static func cleanTitle(_ raw: String, fallback: String) -> String {
        var value = decodeHTML(stripTags(raw))
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmed
        value = value.replacingOccurrences(of: #"(?i)\s*[-|]\s*(?:YouTube)\s*$"#, with: "", options: .regularExpression)
        return value.isEmpty ? fallback.sanitizedFilename(maxLength: 120) : value.sanitizedFilename(maxLength: 120)
    }

    private static func cleanText(_ raw: String, fallback: String) -> String {
        let value = decodeHTML(stripTags(raw))
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmed
        return value.isEmpty ? fallback : value
    }

    private static func stripTags(_ raw: String) -> String {
        raw.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
    }

    private static func normalizeEscapes(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\/", with: "/")
            .replacingOccurrences(of: "\\u0026", with: "&", options: .caseInsensitive)
            .replacingOccurrences(of: "\\u003d", with: "=", options: .caseInsensitive)
            .replacingOccurrences(of: "\\u003f", with: "?", options: .caseInsensitive)
            .replacingOccurrences(of: "\\u002F", with: "/", options: .caseInsensitive)
            .replacingOccurrences(of: "\\u003A", with: ":", options: .caseInsensitive)
    }

    private static func decodeHTML(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#34;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
    }

    private static func stringValue(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            return string.trimmed.isEmpty ? nil : string
        case let number as NSNumber:
            return number.stringValue
        default:
            return nil
        }
    }

    private static func intValue(_ value: Any?) -> Int? {
        switch value {
        case let int as Int:
            return int
        case let number as NSNumber:
            return number.intValue
        case let string as String:
            return Int(string)
        default:
            return nil
        }
    }

    private static func int64Value(_ value: Any?) -> Int64? {
        switch value {
        case let int as Int:
            return Int64(int)
        case let number as NSNumber:
            return number.int64Value
        case let string as String:
            return Int64(string)
        default:
            return nil
        }
    }

    private static func boolValue(_ value: Any?) -> Bool {
        switch value {
        case let bool as Bool:
            return bool
        case let number as NSNumber:
            return number.boolValue
        case let string as String:
            return ["1", "true", "yes", "y"].contains(string.trimmed.lowercased())
        default:
            return false
        }
    }
}

private extension YouTubeMediaCandidate {
    var videoCodec: YouTubeVideoCodec? {
        let value = mimeType.lowercased()
        if value.contains("av01") || value.contains("av1") {
            return .av1
        }
        if value.contains("vp09") || value.contains("vp9") {
            return .vp9
        }
        if value.contains("avc1") || value.contains("h264") || value.contains("h.264") {
            return .avc1
        }
        return nil
    }

    func codecPriorityIndex(in priority: [YouTubeVideoCodec]) -> Int {
        guard let videoCodec,
              let index = priority.firstIndex(of: videoCodec) else {
            return priority.count
        }
        return index
    }

    var isDirectMP4: Bool {
        url.pathExtension.lowercased() == "mp4" ||
            extensionHint.lowercased() == "mp4" ||
            mimeType.lowercased().contains("video/mp4")
    }

    var isM4AAudio: Bool {
        kind == .audioOnly && (
            mimeType.lowercased().contains("audio/mp4") ||
                extensionHint.lowercased() == "m4a" ||
                url.pathExtension.lowercased() == "m4a"
        )
    }

}
