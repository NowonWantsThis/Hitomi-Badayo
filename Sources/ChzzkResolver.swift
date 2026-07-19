import Foundation

enum ChzzkResolverError: LocalizedError {
    case authenticationRequired

    var errorDescription: String? {
        "Chzzk login or age verification is required."
    }
}

struct ChzzkPlaybackKey: Hashable {
    var videoID: String
    var inKey: String
}

private struct ChzzkVideoCandidate {
    var url: URL
    var info: [String: Any]
}

final class ChzzkResolver {
    enum ContentKind: Equatable {
        case clip(String)
        case video(String)
    }

    func canResolve(_ url: URL) -> Bool {
        Self.contentKind(from: url) != nil || Self.liveID(from: url) != nil
    }

    func resolve(
        _ url: URL,
        headers: HTTPRequestOptions = HTTPRequestOptions(),
        preferredResolution: String = ""
    ) async throws -> ResolvedDownload {
        guard let kind = Self.contentKind(from: url) else {
            guard let liveID = Self.liveID(from: url) else {
                throw NativeDownloadError.invalidURL(url.absoluteString)
            }
            let pageURL = Self.canonicalLiveURL(for: url) ?? url
            let channelData = try? await HTTPClient.shared.data(
                from: Self.channelAPIURL(for: liveID, sourceURL: pageURL),
                referer: headers.referer ?? pageURL.absoluteString,
                userAgent: headers.userAgent,
                additionalHeaders: Self.apiHeaders()
            )
            let statusData = try? await HTTPClient.shared.data(
                from: Self.liveStatusAPIURL(for: liveID, sourceURL: pageURL),
                referer: headers.referer ?? pageURL.absoluteString,
                userAgent: headers.userAgent,
                additionalHeaders: Self.apiHeaders()
            )
            let detailData = try await HTTPClient.shared.data(
                from: Self.liveDetailAPIURL(for: liveID, sourceURL: pageURL),
                referer: headers.referer ?? pageURL.absoluteString,
                userAgent: headers.userAgent,
                additionalHeaders: Self.apiHeaders()
            )
            let channelObject = channelData.flatMap { try? Self.jsonObject(from: $0) }
            let statusObject = statusData.flatMap { try? Self.jsonObject(from: $0) }
            let detailObject = try Self.jsonObject(from: detailData)
            if let status = Self.liveStatus(in: statusObject ?? detailObject),
               status.caseInsensitiveCompare("OPEN") != .orderedSame {
                throw NativeDownloadError.unsupported("Chzzk live is not open (\(status)).")
            }
            return try await Self.resolvedLiveDownload(
                fromChannelJSONObject: channelObject,
                statusJSONObject: statusObject,
                detailJSONObject: detailObject,
                pageURL: pageURL,
                liveID: liveID
            )
        }

        let pageURL = Self.canonicalURL(for: url) ?? url
        let apiURL: URL
        switch kind {
        case .clip(let clipID):
            apiURL = Self.clipAPIURL(for: clipID, sourceURL: pageURL)
        case .video(let videoID):
            apiURL = Self.videoAPIURL(for: videoID, sourceURL: pageURL)
        }
        let clipData = try await HTTPClient.shared.data(
            from: apiURL,
            referer: headers.referer ?? pageURL.absoluteString,
            userAgent: headers.userAgent,
            additionalHeaders: Self.apiHeaders()
        )
        let contentObject = try Self.jsonObject(from: clipData)
        if Self.requiresAuthentication(in: contentObject) {
            throw ChzzkResolverError.authenticationRequired
        }

        if let direct = try? await Self.resolvedDownload(
            fromContentData: clipData,
            playbackData: nil,
            pageURL: pageURL,
            kind: kind,
            preferredResolution: preferredResolution
        ) {
            return direct
        }

        switch kind {
        case .clip(let clipID):
            guard let videoID = Self.recursiveStringValue(in: contentObject, keys: ["videoId", "videoID", "vid"]) else {
                throw NativeDownloadError.noFiles
            }
            do {
                let playbackAPIURL = Self.clipPlaybackAPIURL(videoID: videoID, clipID: clipID, sourceURL: pageURL)
                let playbackData = try await HTTPClient.shared.data(
                    from: playbackAPIURL,
                    referer: pageURL.absoluteString,
                    userAgent: headers.userAgent,
                    additionalHeaders: Self.apiHeaders()
                )
                let playbackObject = try Self.jsonObject(from: playbackData)
                if Self.requiresAuthentication(in: playbackObject) {
                    throw ChzzkResolverError.authenticationRequired
                }
                return try await Self.resolvedDownload(
                    fromContentData: clipData,
                    playbackData: playbackData,
                    pageURL: pageURL,
                    kind: kind,
                    preferredResolution: preferredResolution
                )
            } catch ChzzkResolverError.authenticationRequired {
                throw ChzzkResolverError.authenticationRequired
            } catch {
                // Older Naver deployments still expose the same metadata in the Shorts page.
            }
            let playbackPageURL = Self.clipPlaybackPageURL(videoID: videoID, clipID: clipID, sourceURL: pageURL)
            let playbackHTML = try await HTTPClient.shared.data(
                from: playbackPageURL,
                referer: pageURL.absoluteString,
                userAgent: headers.userAgent,
                additionalHeaders: [:]
            )
            guard let playbackData = Self.clipPlaybackMetadataData(fromHTMLData: playbackHTML) else {
                throw NativeDownloadError.noFiles
            }
            return try await Self.resolvedDownload(
                fromContentData: clipData,
                playbackData: playbackData,
                pageURL: pageURL,
                kind: kind,
                preferredResolution: preferredResolution
            )
        case .video:
            if let key = try Self.playbackKey(fromContentData: clipData) {
                let playbackURL = Self.playbackAPIURL(for: key, sourceURL: pageURL)
                let playbackData = try await HTTPClient.shared.data(
                    from: playbackURL,
                    referer: pageURL.absoluteString,
                    userAgent: headers.userAgent,
                    additionalHeaders: Self.apiHeaders()
                )
                return try await Self.resolvedDownload(
                    fromContentData: clipData,
                    playbackData: playbackData,
                    pageURL: pageURL,
                    kind: kind,
                    preferredResolution: preferredResolution
                )
            }
            guard let playbackData = try Self.rewindPlaybackData(fromVideoData: clipData) else {
                throw NativeDownloadError.noFiles
            }
            return try await Self.resolvedDownload(
                fromContentData: clipData,
                playbackData: playbackData,
                pageURL: pageURL,
                kind: kind,
                preferredResolution: preferredResolution
            )
        }
    }

    static func contentKind(from url: URL) -> ContentKind? {
        if let clipID = clipID(from: url) {
            return .clip(clipID)
        }
        if let videoID = vodID(from: url) {
            return .video(videoID)
        }
        return nil
    }

    static func clipID(from url: URL) -> String? {
        guard let host = url.host?.lowercased(),
              isChzzkHost(host),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }

        let parts = url.path.split(separator: "/").map(String.init)
        for marker in ["clips", "clip"] {
            guard let index = parts.firstIndex(where: { $0.lowercased() == marker }),
                  index + 1 < parts.count else {
                continue
            }
            let candidate = parts[index + 1]
            if isClipID(candidate) {
                return candidate
            }
        }

        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        for name in ["clipUID", "clipUid", "clipId", "clipNo"] {
            if let value = queryItems.first(where: { $0.name.lowercased() == name.lowercased() })?.value,
               isClipID(value) {
                return value
            }
        }
        return nil
    }

    static func vodID(from url: URL) -> String? {
        guard let host = url.host?.lowercased(),
              isChzzkHost(host),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }

        let parts = url.path.split(separator: "/").map(String.init)
        for marker in ["video", "videos", "vod"] {
            guard let index = parts.firstIndex(where: { $0.lowercased() == marker }),
                  index + 1 < parts.count else {
                continue
            }
            let candidate = parts[index + 1]
            if isVideoID(candidate) {
                return candidate
            }
        }

        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        for name in ["videoNo", "videoId", "vodId", "vodNo"] {
            if let value = queryItems.first(where: { $0.name.lowercased() == name.lowercased() })?.value,
               isVideoID(value) {
                return value
            }
        }
        return nil
    }

    static func liveID(from url: URL) -> String? {
        guard let host = url.host?.lowercased(),
              isChzzkHost(host),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }

        let parts = url.path.split(separator: "/").map(String.init)
        let lower = parts.map { $0.lowercased() }
        if lower.first == "live",
           parts.count >= 2,
           isLiveChannelID(parts[1]) {
            return parts[1]
        }
        if parts.count == 1,
           let first = parts.first,
           isLiveChannelID(first) {
            return first
        }
        return nil
    }

    static func canonicalURL(for url: URL) -> URL? {
        guard let kind = contentKind(from: url),
              let host = url.host?.lowercased() else {
            return nil
        }

        var components = URLComponents()
        components.scheme = url.scheme ?? "https"
        components.host = host.hasSuffix(".test") ? "chzzk.naver.test" : "chzzk.naver.com"
        switch kind {
        case .clip(let clipID):
            components.path = "/clips/\(clipID)"
        case .video(let videoID):
            components.path = "/video/\(videoID)"
        }
        return components.url
    }

    static func canonicalLiveURL(for url: URL) -> URL? {
        guard let liveID = liveID(from: url),
              let host = url.host?.lowercased() else {
            return nil
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = host.hasSuffix(".test") ? "chzzk.naver.test" : "chzzk.naver.com"
        components.path = "/live/\(liveID)"
        return components.url
    }

    static func clipAPIURL(for clipID: String, sourceURL: URL) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = sourceURL.host?.lowercased().hasSuffix(".test") == true ? "api.chzzk.naver.test" : "api.chzzk.naver.com"
        components.path = "/service/v1/clips/\(clipID)/detail"
        components.queryItems = ["COMMENT", "PRIVATE_USER_BLOCK", "PENALTY", "MAKER_CHANNEL", "OWNER_CHANNEL"].map {
            URLQueryItem(name: "optionalProperties", value: $0)
        }
        return components.url!
    }

    static func videoAPIURL(for videoID: String, sourceURL: URL) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = sourceURL.host?.lowercased().hasSuffix(".test") == true ? "api.chzzk.naver.test" : "api.chzzk.naver.com"
        components.path = "/service/v3/videos/\(videoID)"
        return components.url!
    }

    static func channelAPIURL(for liveID: String, sourceURL: URL) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = sourceURL.host?.lowercased().hasSuffix(".test") == true ? "api.chzzk.naver.test" : "api.chzzk.naver.com"
        components.path = "/service/v1/channels/\(liveID)"
        return components.url!
    }

    static func liveStatusAPIURL(for liveID: String, sourceURL: URL) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = sourceURL.host?.lowercased().hasSuffix(".test") == true ? "api.chzzk.naver.test" : "api.chzzk.naver.com"
        components.path = "/polling/v3/channels/\(liveID)/live-status"
        return components.url!
    }

    static func liveDetailAPIURL(for liveID: String, sourceURL: URL) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = sourceURL.host?.lowercased().hasSuffix(".test") == true ? "api.chzzk.naver.test" : "api.chzzk.naver.com"
        components.path = "/service/v3/channels/\(liveID)/live-detail"
        return components.url!
    }

    static func playbackAPIURL(for key: ChzzkPlaybackKey, sourceURL: URL) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = sourceURL.host?.lowercased().hasSuffix(".test") == true ? "apis.naver.test" : "apis.naver.com"
        components.path = "/neonplayer/vodplay/v2/playback/\(key.videoID)"
        components.queryItems = [
            URLQueryItem(name: "key", value: key.inKey),
            URLQueryItem(name: "sid", value: "2099"),
            URLQueryItem(name: "env", value: "real"),
            URLQueryItem(name: "lc", value: "ko"),
            URLQueryItem(name: "cpl", value: "ko")
        ]
        return components.url!
    }

    static func clipPlaybackAPIURL(videoID: String, clipID: String, sourceURL: URL) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = sourceURL.host?.lowercased().hasSuffix(".test") == true ? "api-videohub.naver.test" : "api-videohub.naver.com"
        components.path = "/shortformhub/feeds/v5/card"
        let recommendation = "{\"seedClipUID\":\"\(clipID)\",\"fromType\":\"GLOBAL\",\"listType\":\"RECOMMEND\"}"
        components.queryItems = [
            URLQueryItem(name: "seedType", value: "SPECIFIC"),
            URLQueryItem(name: "serviceType", value: "CHZZK"),
            URLQueryItem(name: "seedMediaId", value: videoID),
            URLQueryItem(name: "mediaType", value: "VOD"),
            URLQueryItem(name: "panelType", value: "sdk_chzzk"),
            URLQueryItem(name: "recType", value: "CHZZK"),
            URLQueryItem(name: "recId", value: recommendation),
            URLQueryItem(name: "blogId", value: ""),
            URLQueryItem(name: "docNo", value: ""),
            URLQueryItem(name: "sessionId", value: ""),
            URLQueryItem(name: "airsSessionId", value: ""),
            URLQueryItem(name: "mainSessionId", value: ""),
            URLQueryItem(name: "airsArea", value: ""),
            URLQueryItem(name: "enableReverse", value: "false"),
            URLQueryItem(name: "adAllowed", value: "Y"),
            URLQueryItem(name: "clickNsc", value: "chzzk_url_clip"),
            URLQueryItem(name: "clickArea", value: "clip_item")
        ]
        return components.url!
    }

    static func clipPlaybackPageURL(videoID: String, clipID: String, sourceURL: URL) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = sourceURL.host?.lowercased().hasSuffix(".test") == true ? "m.naver.test" : "m.naver.com"
        components.path = "/shorts/"
        let recommendation = "{\"seedClipUID\":\"\(clipID)\",\"fromType\":\"GLOBAL\",\"listType\":\"RECOMMEND\"}"
        components.queryItems = [
            URLQueryItem(name: "mediaId", value: videoID),
            URLQueryItem(name: "serviceType", value: "CHZZK"),
            URLQueryItem(name: "mediaType", value: ""),
            URLQueryItem(name: "recType", value: "CHZZK"),
            URLQueryItem(name: "recId", value: recommendation),
            URLQueryItem(name: "blogId", value: ""),
            URLQueryItem(name: "docNo", value: ""),
            URLQueryItem(name: "adAllowed", value: "Y"),
            URLQueryItem(name: "feedBlock", value: ""),
            URLQueryItem(name: "enableReverse", value: "false"),
            URLQueryItem(name: "notInterestedMediaIds", value: ""),
            URLQueryItem(name: "notInterestedChannelIds", value: ""),
            URLQueryItem(name: "panelType", value: "sdk_chzzk"),
            URLQueryItem(name: "entryPoint", value: ""),
            URLQueryItem(name: "stmsId", value: ""),
            URLQueryItem(name: "clickNsc", value: "chzzk_url_clip"),
            URLQueryItem(name: "clickArea", value: "clip_item"),
            URLQueryItem(name: "adUnitId", value: "chzzk_shortformviewer_web"),
            URLQueryItem(name: "viewerInfo", value: "chzzk_shortformviewer_web"),
            URLQueryItem(name: "adCtrl", value: ""),
            URLQueryItem(name: "theme", value: "light"),
            URLQueryItem(name: "viewMode", value: "mobile"),
            URLQueryItem(name: "sdkTargetId", value: "PLAYER-SDK-0-49"),
            URLQueryItem(name: "env", value: ""),
            URLQueryItem(name: "embed", value: "true")
        ]
        return components.url!
    }

    static func playbackKey(fromClipData data: Data) throws -> ChzzkPlaybackKey? {
        try playbackKey(fromContentData: data)
    }

    static func playbackKey(fromVideoData data: Data) throws -> ChzzkPlaybackKey? {
        try playbackKey(fromContentData: data)
    }

    static func rewindPlaybackData(fromVideoData data: Data) throws -> Data? {
        let object = try jsonObject(from: data)
        guard let raw = recursiveStringValue(in: object, keys: ["liveRewindPlaybackJson"]),
              let payload = raw.data(using: .utf8),
              (try? JSONSerialization.jsonObject(with: payload)) != nil else {
            return nil
        }
        return payload
    }

    private static func playbackKey(fromContentData data: Data) throws -> ChzzkPlaybackKey? {
        let object = try jsonObject(from: data)
        guard let videoID = recursiveStringValue(in: object, keys: ["videoId", "videoID", "vid"]),
              let inKey = recursiveStringValue(in: object, keys: ["inKey", "inkey", "key"]) else {
            return nil
        }
        return ChzzkPlaybackKey(videoID: videoID, inKey: inKey)
    }

    static func resolvedDownload(
        fromClipData clipData: Data,
        playbackData: Data?,
        pageURL: URL,
        preferredResolution: String = ""
    ) async throws -> ResolvedDownload {
        let fallbackID = clipID(from: pageURL) ?? "clip"
        return try await resolvedDownload(
            fromContentData: clipData,
            playbackData: playbackData,
            pageURL: pageURL,
            kind: .clip(fallbackID),
            preferredResolution: preferredResolution
        )
    }

    static func resolvedDownload(
        fromVideoData videoData: Data,
        playbackData: Data?,
        pageURL: URL,
        preferredResolution: String = ""
    ) async throws -> ResolvedDownload {
        let fallbackID = vodID(from: pageURL) ?? "video"
        return try await resolvedDownload(
            fromContentData: videoData,
            playbackData: playbackData,
            pageURL: pageURL,
            kind: .video(fallbackID),
            preferredResolution: preferredResolution
        )
    }

    static func clipPlaybackMetadataData(fromHTMLData data: Data) -> Data? {
        guard let html = String(data: data, encoding: .utf8),
              let value = balancedScriptValue(afterPattern: #"window\.\$__videoMeta\s*="#, in: html) else {
            return nil
        }
        let payload = Data(value.utf8)
        guard (try? JSONSerialization.jsonObject(with: payload)) != nil else { return nil }
        return payload
    }

    static func resolvedLiveDownload(fromChannelJSONObject channelObject: Any?, statusJSONObject: Any?, detailJSONObject detailObject: Any, pageURL: URL, liveID: String) async throws -> ResolvedDownload {
        if requiresAuthentication(in: detailObject) {
            throw ChzzkResolverError.authenticationRequired
        }
        guard let candidate = bestLiveVideoCandidate(in: detailObject, sourceURL: pageURL) else {
            throw NativeDownloadError.noFiles
        }

        let info = liveInfo(channelObject: channelObject, statusObject: statusJSONObject, detailObject: detailObject, liveID: liveID, pageURL: pageURL)
        if isM3U8(candidate.url) {
            let hls = try await M3U8Resolver().resolve(
                candidate.url,
                headers: HTTPRequestOptions(referer: pageURL.absoluteString)
            )
            return resolvedLiveDownload(fromHLS: hls, info: info, playlistURL: candidate.url, pageURL: pageURL)
        }

        let filename = "\(info.title)-\(info.id).\(mediaFormat(for: candidate.url, fallback: "mp4"))".sanitizedFilename(maxLength: 180)
        return ResolvedDownload(
            title: info.displayTitle,
            folderName: "Chzzk \(info.displayTitle)".sanitizedFilename(maxLength: 120),
            assets: [
                ResolvedAsset(
                    remoteURL: candidate.url,
                    filename: filename,
                    metadata: liveMediaMetadata(info: info, mediaURL: candidate.url, pageURL: pageURL),
                    referer: pageURL.absoluteString
                )
            ],
            packageMode: .concatenate(outputFilename: filename),
            metadata: liveMetadata(info: info, mediaURL: candidate.url, pageURL: pageURL)
        )
    }

    static func livePlaylistURL(in detailObject: Any, sourceURL: URL) -> URL? {
        bestLiveVideoCandidate(in: detailObject, sourceURL: sourceURL)?.url
    }

    static func liveInfo(channelObject: Any?, statusObject: Any?, detailObject: Any, liveID: String, pageURL: URL) -> (id: String, title: String, displayTitle: String, channel: String, date: String, thumbnail: URL?, status: String) {
        let title = cleanTitle(
            recursiveStringValue(in: detailObject, keys: ["liveTitle", "title"]) ?? "Chzzk \(liveID)",
            fallback: "Chzzk \(liveID)"
        )
        let channel = cleanTitle(
            channelObject.flatMap { recursiveStringValue(in: $0, keys: ["channelName", "name", "nickname"]) } ??
                recursiveStringValue(in: detailObject, keys: ["channelName", "ownerChannelName", "nickname"]) ??
                "",
            fallback: ""
        )
        let date = normalizedDate(
            recursiveStringValue(in: detailObject, keys: ["openDate", "createdDate", "publishDate", "publishedDate", "startDate", "startTime"]) ??
                statusObject.flatMap { recursiveStringValue(in: $0, keys: ["openDate", "createdDate", "publishDate", "publishedDate", "startDate", "startTime"]) }
        ) ?? ""
        let thumbnailRaw = recursiveStringValue(
            in: detailObject,
            keys: ["snapshotThumbnailTemplate", "thumbnailImageUrl", "thumbnailUrl", "imageUrl", "thumbnail"]
        )
        let thumbnail = thumbnailRaw.flatMap { liveThumbnailURL($0, baseURL: pageURL) }
        let status = statusObject.flatMap { recursiveStringValue(in: $0, keys: ["status", "liveStatus"]) } ??
            recursiveStringValue(in: detailObject, keys: ["status", "liveStatus"]) ??
            ""
        let displayTitle = channel.isEmpty || channel.caseInsensitiveCompare(title) == .orderedSame ? title : "\(channel) - \(title)"
        return (liveID, title, displayTitle.sanitizedFilename(maxLength: 120), channel, date, thumbnail, status)
    }

    static func resolvedLiveDownload(fromHLS hls: ResolvedDownload, info: (id: String, title: String, displayTitle: String, channel: String, date: String, thumbnail: URL?, status: String), playlistURL: URL, pageURL: URL) -> ResolvedDownload {
        var metadata = hls.metadata.merging(
            liveMetadata(info: info, mediaURL: playlistURL, pageURL: pageURL)
        ) { _, new in new }
        for key in ["duration", "duration_seconds", "duration_string", "duration_ms"] {
            metadata.removeValue(forKey: key)
        }
        metadata["live_recorded_duration"] = "0"

        return ResolvedDownload(
            title: info.displayTitle,
            folderName: "Chzzk \(info.displayTitle)".sanitizedFilename(maxLength: 120),
            assets: hls.assets.enumerated().map { offset, asset in
                var enriched = asset
                enriched.metadata = asset.metadata.merging(liveSegmentMetadata(info: info, asset: asset, playlistURL: playlistURL, pageURL: pageURL, index: offset + 1)) { current, _ in current }
                return enriched
            },
            packageMode: .concatenate(outputFilename: "\(info.title)-\(info.id).ts".sanitizedFilename(maxLength: 180)),
            metadata: metadata
        )
    }

    private static func resolvedDownload(
        fromContentData contentData: Data,
        playbackData: Data?,
        pageURL: URL,
        kind: ContentKind,
        preferredResolution: String
    ) async throws -> ResolvedDownload {
        let contentObject = try jsonObject(from: contentData)
        if requiresAuthentication(in: contentObject) {
            throw ChzzkResolverError.authenticationRequired
        }
        let playbackObject = try playbackData.map { try playbackObject(from: $0, sourceURL: pageURL) }
        let sourceObject = playbackObject ?? contentObject
        guard let candidate = bestVideoCandidate(
            in: sourceObject,
            sourceURL: pageURL,
            preferredResolution: preferredResolution
        ) else {
            throw NativeDownloadError.noFiles
        }
        let remote = candidate.url

        let contentID: String
        let isClip: Bool
        switch kind {
        case .clip(let clipID):
            contentID = Self.clipID(from: pageURL) ??
                recursiveStringValue(in: contentObject, keys: ["clipUID", "clipUid", "clipId", "clipNo"]) ??
                clipID
            isClip = true
        case .video(let videoID):
            contentID = Self.vodID(from: pageURL) ??
                recursiveStringValue(in: contentObject, keys: ["videoNo", "videoNO", "vodId", "vodNo"]) ??
                videoID
            isClip = false
        }
        let title = cleanTitle(
            recursiveStringValue(in: contentObject, keys: ["clipTitle", "videoTitle", "title"]) ?? "Chzzk \(contentID)",
            fallback: "Chzzk \(contentID)"
        )
        let channel = cleanTitle(
            recursiveStringValue(in: contentObject, keys: ["channelName", "ownerChannelName", "nickname"]) ??
                playbackObject.flatMap { recursiveStringValue(in: $0, keys: ["channelName", "ownerChannelName", "nickname", "name"]) } ??
                "",
            fallback: ""
        )
        let playbackVideoID = recursiveStringValue(in: contentObject, keys: ["videoId", "videoID", "vid"]) ?? ""
        let date = normalizedDate(recursiveStringValue(in: contentObject, keys: ["createdDate", "createdAt", "publishDate", "publishedDate", "openDate"]))
        let thumbnail = recursiveStringValue(
            in: contentObject,
            keys: ["thumbnailImageUrl", "thumbnailImageURL", "thumbnailUrl", "thumbnailURL", "thumbnail"]
        ).flatMap { absoluteURL($0, baseURL: pageURL) }
        var jobMetadata = metadata(
            title: title,
            channel: channel,
            contentID: contentID,
            playbackVideoID: playbackVideoID,
            candidate: candidate,
            pageURL: pageURL,
            isClip: isClip,
            date: date
        )
        if let thumbnail {
            jobMetadata["thumbnail"] = thumbnail.absoluteString
            jobMetadata["thumbnail_referer"] = pageURL.absoluteString
        }
        if let date, !date.isEmpty {
            jobMetadata["published_date"] = date
        }
        if let duration = recursiveStringValue(
            in: contentObject,
            keys: ["duration", "durationSeconds", "videoDuration", "playTime", "runningTime"]
        )?.trimmed,
           !duration.isEmpty {
            jobMetadata["duration"] = duration
            if Double(duration) != nil {
                jobMetadata["duration_seconds"] = duration
            }
        }

        if isM3U8(remote) {
            let hls = try await M3U8Resolver().resolve(
                remote,
                headers: HTTPRequestOptions(referer: pageURL.absoluteString)
            )
            return ResolvedDownload(
                title: title,
                folderName: "Chzzk \(title)".sanitizedFilename(maxLength: 120),
                assets: hls.assets.enumerated().map { offset, asset in
                    var enriched = asset
                    enriched.metadata = asset.metadata.merging(segmentMetadata(
                        title: title,
                        channel: channel,
                        contentID: contentID,
                        playbackVideoID: playbackVideoID,
                        asset: asset,
                        pageURL: pageURL,
                        isClip: isClip,
                        date: date,
                        index: offset + 1
                    )) { current, _ in current }
                    return enriched
                },
                packageMode: .concatenate(outputFilename: "\(title)-\(contentID).ts".sanitizedFilename(maxLength: 180)),
                metadata: hls.metadata.merging(jobMetadata) { _, new in new }
            )
        }

        return ResolvedDownload(
            title: title,
            folderName: "Chzzk \(title)".sanitizedFilename(maxLength: 120),
            assets: [
                ResolvedAsset(
                    remoteURL: remote,
                    filename: filename(for: remote, title: title),
                    metadata: mediaMetadata(
                        for: candidate,
                        title: title,
                        channel: channel,
                        contentID: contentID,
                        playbackVideoID: playbackVideoID,
                        pageURL: pageURL,
                        isClip: isClip,
                        date: date
                    ),
                    referer: pageURL.absoluteString
                )
            ],
            metadata: jobMetadata
        )
    }

    static func bestVideoURL(in object: Any, sourceURL: URL) -> URL? {
        bestVideoCandidate(in: object, sourceURL: sourceURL)?.url
    }

    private static func bestVideoCandidate(
        in object: Any,
        sourceURL: URL,
        preferredResolution: String = ""
    ) -> ChzzkVideoCandidate? {
        let candidates = videoDictionaries(in: object)
        let resolved = candidates.compactMap { item -> ChzzkVideoCandidate? in
            guard let url = candidateURL(from: item, sourceURL: sourceURL) else {
                return nil
            }
            return ChzzkVideoCandidate(url: url, info: item)
        }
        let pool: [ChzzkVideoCandidate]
        if let ceiling = preferredHeight(from: preferredResolution) {
            let bounded = resolved.filter { candidate in
                guard let height = candidateHeight(for: candidate) else { return false }
                return height <= ceiling
            }
            pool = bounded.isEmpty ? resolved : bounded
        } else {
            pool = resolved
        }
        return pool.max { lhs, rhs in
            videoScore(lhs.info) < videoScore(rhs.info)
        }
    }

    private static func bestLiveVideoCandidate(in detailObject: Any, sourceURL: URL) -> ChzzkVideoCandidate? {
        var candidates: [ChzzkVideoCandidate] = []
        if let playbackObject = livePlaybackObject(in: detailObject),
           let candidate = bestVideoCandidate(in: playbackObject, sourceURL: sourceURL) {
            candidates.append(candidate)
        }
        if let candidate = bestVideoCandidate(in: detailObject, sourceURL: sourceURL) {
            candidates.append(candidate)
        }
        return candidates.max { lhs, rhs in
            videoScore(lhs.info) < videoScore(rhs.info)
        }
    }

    private static func livePlaybackObject(in detailObject: Any) -> Any? {
        guard let raw = recursiveStringValue(in: detailObject, keys: ["livePlaybackJson", "playbackJson", "playback"]) else {
            return nil
        }
        guard let data = raw.data(using: .utf8) else {
            return nil
        }
        return try? JSONSerialization.jsonObject(with: data)
    }

    private static func apiHeaders() -> [String: String] {
        ["Accept": "application/json, text/plain, */*"]
    }

    private static func jsonObject(from data: Data) throws -> Any {
        try JSONSerialization.jsonObject(with: data)
    }

    private static func playbackObject(from data: Data, sourceURL: URL) throws -> Any {
        if let object = try? JSONSerialization.jsonObject(with: data) {
            return object
        }

        let document = try XMLDocument(data: data, options: [.nodePreserveAll])
        let nodes = try document.nodes(forXPath: "//*[local-name()='Representation']")
        let representations: [[String: Any]] = nodes.compactMap { node in
            guard let element = node as? XMLElement,
                  let baseNode = (try? element.nodes(forXPath: "./*[local-name()='BaseURL']"))?.first,
                  let rawURL = baseNode.stringValue?.trimmed,
                  let url = absoluteURL(rawURL, baseURL: sourceURL) else {
                return nil
            }
            var representation: [String: Any] = ["baseurl": url.absoluteString]
            for name in ["width", "height", "bandwidth", "bitrate", "id"] {
                if let value = element.attribute(forName: name)?.stringValue, !value.trimmed.isEmpty {
                    representation[name] = value
                }
            }
            return representation
        }
        guard !representations.isEmpty else { throw NativeDownloadError.noFiles }
        return ["representation": representations]
    }

    private static func balancedScriptValue(afterPattern pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
              let matchRange = Range(match.range, in: text) else {
            return nil
        }
        var index = matchRange.upperBound
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
            let character = text[cursor]
            if let quote = inString {
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == quote {
                    inString = nil
                }
            } else if character == "\"" || character == "'" {
                inString = character
            } else if character == opener {
                depth += 1
            } else if character == closer {
                depth -= 1
                if depth == 0 {
                    return String(text[index...cursor])
                }
            }
            cursor = text.index(after: cursor)
        }
        return nil
    }

    private static func videoDictionaries(in object: Any) -> [[String: Any]] {
        if let dict = object as? [String: Any] {
            var found: [[String: Any]] = []
            if candidateURL(from: dict, sourceURL: nil) != nil {
                found.append(dict)
            }
            for value in dict.values {
                found.append(contentsOf: videoDictionaries(in: value))
            }
            return found
        }
        if let array = object as? [Any] {
            return array.flatMap(videoDictionaries(in:))
        }
        return []
    }

    private static func candidateURL(from dictionary: [String: Any], sourceURL: URL?) -> URL? {
        for key in ["source", "url", "videoUrl", "videoURL", "playUrl", "playURL", "contentUrl", "contentURL", "path", "baseurl", "baseUrl", "baseURL"] {
            guard let raw = nestedVideoURLString(in: dictionary[key]) else {
                continue
            }
            if let base = sourceURL {
                return absoluteURL(raw, baseURL: base)
            }
            return URL(string: raw)
        }

        if let attributes = dictionary["otherAttributes"] as? [String: Any] {
            for key in ["m3u", "m3u8", "url", "videoUrl", "playUrl"] {
                guard let raw = nestedVideoURLString(in: attributes[key]) else { continue }
                if let base = sourceURL {
                    return absoluteURL(raw, baseURL: base)
                }
                return URL(string: raw)
            }
        }

        if let raw = stringValue(dictionary["value"]), looksLikeVideoURL(raw) {
            if let base = sourceURL {
                return absoluteURL(raw, baseURL: base)
            }
            return URL(string: raw)
        }
        return nil
    }

    private static func nestedVideoURLString(in value: Any?) -> String? {
        if let raw = stringValue(value), looksLikeVideoURL(raw) {
            return raw
        }
        if let dictionary = value as? [String: Any] {
            for key in ["value", "m3u", "m3u8", "url", "source", "path"] {
                if let raw = nestedVideoURLString(in: dictionary[key]) {
                    return raw
                }
            }
            return nil
        }
        if let array = value as? [Any] {
            return array.lazy.compactMap(nestedVideoURLString(in:)).first
        }
        return nil
    }

    private static func videoScore(_ item: [String: Any]) -> Int {
        let urlBonus = candidateURL(from: item, sourceURL: nil).map { url -> Int in
            let ext = url.pathExtension.lowercased()
            if ext == "mp4" { return 1_000_000_000 }
            if ext == "m3u8" { return 500_000_000 }
            return 0
        } ?? 0
        if let size = intValue(item["size"]) ?? intValue(item["fileSize"]) {
            return urlBonus + size
        }
        if let bitrate = intValue(item["bitrate"]) ?? intValue(item["bitRate"]) {
            return urlBonus + bitrate
        }
        let width = intValue(item["width"]) ?? intValue(item["w"]) ?? 0
        let height = intValue(item["height"]) ?? intValue(item["h"]) ?? 0
        return urlBonus + width * height
    }

    private static func metadata(title: String, channel: String, contentID: String, playbackVideoID: String, candidate: ChzzkVideoCandidate, pageURL: URL, isClip: Bool, date: String?) -> [String: String] {
        let isHLS = isM3U8(candidate.url)
        return DownloadMetadata.clean([
            "title": title,
            "series": title,
            "artist": channel,
            "author": channel,
            "creator": channel,
            "uploader": channel,
            "channel": channel,
            "category": "video",
            "type": isHLS ? "hls" : "video",
            "media_type": isHLS ? "hls" : "video",
            "format": mediaFormat(for: candidate.url),
            "media_format": mediaFormat(for: candidate.url),
            "site": "Chzzk",
            "host": pageURL.host ?? "",
            "id": contentID,
            "clip_id": isClip ? contentID : "",
            "vod_id": isClip ? "" : contentID,
            "video_no": isClip ? "" : contentID,
            "gallery_id": contentID,
            "video_id": playbackVideoID,
            "media_id": playbackVideoID.isEmpty ? contentID : playbackVideoID,
            "media_count": isHLS ? "" : "1",
            "video_count": "1",
            "width": candidateWidth(for: candidate).map(String.init) ?? "",
            "height": candidateHeight(for: candidate).map(String.init) ?? "",
            "resolution": resolution(for: candidate),
            "quality": qualityLabel(for: candidate),
            "video_url": candidate.url.absoluteString,
            "media_url": candidate.url.absoluteString,
            "playlist_url": isHLS ? candidate.url.absoluteString : "",
            "source_url": pageURL.absoluteString,
            "page_url": pageURL.absoluteString,
            "date": date ?? ""
        ])
    }

    private static func liveMetadata(info: (id: String, title: String, displayTitle: String, channel: String, date: String, thumbnail: URL?, status: String), mediaURL: URL, pageURL: URL) -> [String: String] {
        let format = mediaFormat(for: mediaURL, fallback: "m3u8")
        return DownloadMetadata.clean([
            "title": info.title,
            "series": info.channel,
            "artist": info.channel,
            "author": info.channel,
            "creator": info.channel,
            "uploader": info.channel,
            "channel": info.channel,
            "category": "live",
            "type": "live",
            "media_type": "live",
            "format": format,
            "media_format": format,
            "site": "Chzzk",
            "host": pageURL.host ?? "",
            "id": info.id,
            "live_id": info.id,
            "channel_id": info.id,
            "video_id": info.id,
            "media_id": info.id,
            "live": "true",
            "live_status": info.status,
            "date": info.date,
            "published_date": info.date,
            "thumbnail": info.thumbnail?.absoluteString ?? "",
            "media_count": "1",
            "video_count": "1",
            "video_url": mediaURL.absoluteString,
            "media_url": mediaURL.absoluteString,
            "playlist_url": isM3U8(mediaURL) ? mediaURL.absoluteString : "",
            "hls_remux_required": isM3U8(mediaURL) ? "true" : "",
            "source_url": pageURL.absoluteString,
            "page_url": pageURL.absoluteString
        ])
    }

    private static func mediaMetadata(for candidate: ChzzkVideoCandidate, title: String, channel: String, contentID: String, playbackVideoID: String, pageURL: URL, isClip: Bool, date: String?) -> [String: String] {
        DownloadMetadata.clean([
            "site": "Chzzk",
            "title": title,
            "series": title,
            "artist": channel,
            "author": channel,
            "creator": channel,
            "uploader": channel,
            "channel": channel,
            "category": "video",
            "type": isM3U8(candidate.url) ? "hls" : "video",
            "media_type": isM3U8(candidate.url) ? "hls" : "video",
            "format": mediaFormat(for: candidate.url),
            "media_format": mediaFormat(for: candidate.url),
            "id": contentID,
            "clip_id": isClip ? contentID : "",
            "vod_id": isClip ? "" : contentID,
            "video_no": isClip ? "" : contentID,
            "gallery_id": contentID,
            "video_id": playbackVideoID,
            "media_id": playbackVideoID.isEmpty ? contentID : playbackVideoID,
            "date": date ?? "",
            "page": "1",
            "position": "1",
            "width": candidateWidth(for: candidate).map(String.init) ?? "",
            "height": candidateHeight(for: candidate).map(String.init) ?? "",
            "resolution": resolution(for: candidate),
            "quality": qualityLabel(for: candidate),
            "video_url": candidate.url.absoluteString,
            "media_url": candidate.url.absoluteString,
            "playlist_url": isM3U8(candidate.url) ? candidate.url.absoluteString : "",
            "source_url": pageURL.absoluteString,
            "page_url": pageURL.absoluteString
        ])
    }

    private static func liveMediaMetadata(info: (id: String, title: String, displayTitle: String, channel: String, date: String, thumbnail: URL?, status: String), mediaURL: URL, pageURL: URL) -> [String: String] {
        let format = mediaFormat(for: mediaURL, fallback: "mp4")
        return DownloadMetadata.clean([
            "site": "Chzzk",
            "title": info.title,
            "series": info.channel,
            "artist": info.channel,
            "author": info.channel,
            "creator": info.channel,
            "uploader": info.channel,
            "channel": info.channel,
            "category": "live",
            "type": "live",
            "media_type": isM3U8(mediaURL) ? "hls" : "video",
            "format": format,
            "media_format": format,
            "id": info.id,
            "live_id": info.id,
            "channel_id": info.id,
            "video_id": info.id,
            "media_id": info.id,
            "live": "true",
            "live_status": info.status,
            "date": info.date,
            "published_date": info.date,
            "thumbnail": info.thumbnail?.absoluteString ?? "",
            "page": "1",
            "position": "1",
            "video_url": mediaURL.absoluteString,
            "media_url": mediaURL.absoluteString,
            "playlist_url": isM3U8(mediaURL) ? mediaURL.absoluteString : "",
            "source_url": pageURL.absoluteString,
            "page_url": pageURL.absoluteString
        ])
    }

    private static func segmentMetadata(title: String, channel: String, contentID: String, playbackVideoID: String, asset: ResolvedAsset, pageURL: URL, isClip: Bool, date: String?, index: Int) -> [String: String] {
        let format = mediaFormat(for: asset.remoteURL, fallback: mediaFormat(forFilename: asset.filename, fallback: "ts"))
        return DownloadMetadata.clean([
            "site": "Chzzk",
            "title": title,
            "series": title,
            "artist": channel,
            "author": channel,
            "creator": channel,
            "uploader": channel,
            "channel": channel,
            "category": "video",
            "type": "hls_segment",
            "media_type": "segment",
            "format": format,
            "media_format": format,
            "id": contentID,
            "clip_id": isClip ? contentID : "",
            "vod_id": isClip ? "" : contentID,
            "video_no": isClip ? "" : contentID,
            "gallery_id": contentID,
            "video_id": playbackVideoID,
            "media_id": "\(playbackVideoID.isEmpty ? contentID : playbackVideoID)-segment-\(index)",
            "date": date ?? "",
            "page": String(index),
            "position": String(index),
            "video_url": asset.remoteURL.absoluteString,
            "media_url": asset.remoteURL.absoluteString,
            "source_url": pageURL.absoluteString,
            "page_url": pageURL.absoluteString
        ])
    }

    private static func liveSegmentMetadata(info: (id: String, title: String, displayTitle: String, channel: String, date: String, thumbnail: URL?, status: String), asset: ResolvedAsset, playlistURL: URL, pageURL: URL, index: Int) -> [String: String] {
        let format = mediaFormat(for: asset.remoteURL, fallback: mediaFormat(forFilename: asset.filename, fallback: "ts"))
        return DownloadMetadata.clean([
            "site": "Chzzk",
            "title": info.title,
            "series": info.channel,
            "artist": info.channel,
            "author": info.channel,
            "creator": info.channel,
            "uploader": info.channel,
            "channel": info.channel,
            "category": "live",
            "type": "hls_segment",
            "media_type": "segment",
            "format": format,
            "media_format": format,
            "id": info.id,
            "live_id": info.id,
            "channel_id": info.id,
            "video_id": info.id,
            "media_id": "\(info.id)-segment-\(index)",
            "live": "true",
            "live_status": info.status,
            "date": info.date,
            "published_date": info.date,
            "thumbnail": info.thumbnail?.absoluteString ?? "",
            "page": String(index),
            "position": String(index),
            "video_url": asset.remoteURL.absoluteString,
            "media_url": asset.remoteURL.absoluteString,
            "playlist_url": playlistURL.absoluteString,
            "source_url": pageURL.absoluteString,
            "page_url": pageURL.absoluteString
        ])
    }

    private static func mediaFormat(for url: URL) -> String {
        if isM3U8(url) { return "m3u8" }
        let ext = url.pathExtension.lowercased()
        return ext.isEmpty ? "mp4" : ext
    }

    private static func mediaFormat(for url: URL, fallback: String) -> String {
        let ext = url.pathExtension.trimmed
        return (ext.isEmpty ? fallback : ext).lowercased()
    }

    private static func mediaFormat(forFilename filename: String, fallback: String) -> String {
        let ext = (filename as NSString).pathExtension.trimmed
        return (ext.isEmpty ? fallback : ext).lowercased()
    }

    private static func candidateWidth(for candidate: ChzzkVideoCandidate) -> Int? {
        let width = intValue(candidate.info["width"]) ?? intValue(candidate.info["w"]) ?? intValue(candidate.info["videoWidth"])
        return width.flatMap { $0 > 0 ? $0 : nil }
    }

    private static func candidateHeight(for candidate: ChzzkVideoCandidate) -> Int? {
        let height = intValue(candidate.info["height"]) ??
            intValue(candidate.info["h"]) ??
            intValue(candidate.info["videoHeight"]) ??
            intValue(candidate.info["resolution"]) ??
            stringValue(candidate.info["quality"]).flatMap(heightFromText) ??
            stringValue(candidate.info["label"]).flatMap(heightFromText) ??
            heightFromText(candidate.url.absoluteString)
        return height.flatMap { $0 > 0 ? $0 : nil }
    }

    private static func resolution(for candidate: ChzzkVideoCandidate) -> String {
        candidateHeight(for: candidate).map { "\($0)p" } ?? ""
    }

    private static func qualityLabel(for candidate: ChzzkVideoCandidate) -> String {
        let explicit = stringValue(candidate.info["quality"]) ??
            stringValue(candidate.info["label"]) ??
            stringValue(candidate.info["encodingOption"]) ??
            stringValue(candidate.info["profile"]) ??
            ""
        if !explicit.trimmed.isEmpty {
            return explicit
        }
        return resolution(for: candidate)
    }

    private static func preferredHeight(from rawValue: String) -> Int? {
        var value = rawValue.trimmed.lowercased()
        guard !value.isEmpty, value != "best", value != "source", value != "original" else {
            return nil
        }
        value = value.replacingOccurrences(of: "p", with: "")
        return Int(value.components(separatedBy: CharacterSet.decimalDigits.inverted).joined())
    }

    private static func heightFromText(_ text: String) -> Int? {
        firstCapture(pattern: #"([0-9]{3,4})\s*p"#, in: text).flatMap(Int.init) ??
            firstCapture(pattern: #"[/-]([0-9]{3,4})(?:[./_-])"#, in: text).flatMap(Int.init)
    }

    private static func firstCapture(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[range])
    }

    private static func looksLikeVideoURL(_ raw: String) -> Bool {
        let value = raw.lowercased()
        return value.hasPrefix("http://") || value.hasPrefix("https://") || value.hasPrefix("//")
            ? value.contains(".mp4") || value.contains(".m3u8") || value.contains("/vod/") || value.contains("/video/")
            : false
    }

    private static func isM3U8(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "m3u8" || url.absoluteString.lowercased().contains(".m3u8")
    }

    private static func recursiveStringValue(in object: Any, keys: Set<String>) -> String? {
        if let dict = object as? [String: Any] {
            for (key, value) in dict where keys.contains(key) {
                if let string = stringValue(value), !string.trimmed.isEmpty {
                    return string
                }
            }
            for value in dict.values {
                if let found = recursiveStringValue(in: value, keys: keys) {
                    return found
                }
            }
        } else if let array = object as? [Any] {
            for value in array {
                if let found = recursiveStringValue(in: value, keys: keys) {
                    return found
                }
            }
        }
        return nil
    }

    private static func recursiveValue(in object: Any, keys: Set<String>) -> Any? {
        if let dictionary = object as? [String: Any] {
            for (key, value) in dictionary where keys.contains(key) {
                return value
            }
            for value in dictionary.values {
                if let found = recursiveValue(in: value, keys: keys) {
                    return found
                }
            }
        } else if let array = object as? [Any] {
            for value in array {
                if let found = recursiveValue(in: value, keys: keys) {
                    return found
                }
            }
        }
        return nil
    }

    private static func requiresAuthentication(in object: Any) -> Bool {
        let errorCode = recursiveStringValue(in: object, keys: ["errorCode"])?.uppercased() ?? ""
        if ["ADULT_AUTH_REQUIRED", "LOGIN_REQUIRED", "AUTHENTICATION_REQUIRED"].contains(errorCode) {
            return true
        }

        let adult = boolValue(recursiveValue(in: object, keys: ["adult", "isAdult", "ageRestricted"])) ?? false
        let adultStatus = recursiveStringValue(
            in: object,
            keys: ["userAdultStatus", "adultStatus", "authenticationStatus"]
        )?.uppercased() ?? ""
        if adult && ["NOT_LOGIN_USER", "NOT_REAL_NAME_AUTH", "LOGIN_REQUIRED", "AGE_VERIFICATION_REQUIRED"].contains(adultStatus) {
            return true
        }

        let code = intValue(recursiveValue(in: object, keys: ["statusCode", "httpStatus"]))
        if code == 401 || code == 403 { return true }
        let message = recursiveStringValue(in: object, keys: ["message", "errorMessage", "reason"])?.lowercased() ?? ""
        return message.contains("login required") || message.contains("로그인") || message.contains("본인인증")
    }

    private static func liveStatus(in object: Any) -> String? {
        recursiveStringValue(in: object, keys: ["status", "liveStatus"])
    }

    private static func normalizedDate(_ raw: String?) -> String? {
        guard let raw = raw?.trimmed, !raw.isEmpty else { return nil }
        if let match = raw.range(of: #"[0-9]{4}-[0-9]{2}-[0-9]{2}"#, options: .regularExpression) {
            return String(raw[match])
        }
        if raw.range(of: #"^[0-9]{8}$"#, options: .regularExpression) != nil {
            let year = raw.prefix(4)
            let monthStart = raw.index(raw.startIndex, offsetBy: 4)
            let dayStart = raw.index(raw.startIndex, offsetBy: 6)
            return "\(year)-\(raw[monthStart..<dayStart])-\(raw[dayStart..<raw.endIndex])"
        }
        return nil
    }

    private static func filename(for url: URL, title: String) -> String {
        let ext = url.pathExtension.trimmed.isEmpty ? "mp4" : url.pathExtension
        return "\(title).\(ext)".sanitizedFilename(maxLength: 180)
    }

    private static func cleanTitle(_ raw: String, fallback: String) -> String {
        let title = decodeHTML(stripTags(raw))
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmed
        return title.isEmpty ? fallback : title
    }

    private static func stripTags(_ raw: String) -> String {
        raw.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
    }

    private static func decodeHTML(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
    }

    private static func absoluteURL(_ raw: String, baseURL: URL) -> URL? {
        let value = raw.trimmed
        if value.hasPrefix("//") {
            return URL(string: "\(baseURL.scheme ?? "https"):\(value)")
        }
        return URL(string: value, relativeTo: baseURL)?.absoluteURL
    }

    private static func liveThumbnailURL(_ raw: String, baseURL: URL) -> URL? {
        let value = raw
            .replacingOccurrences(of: "{type}", with: "720")
            .replacingOccurrences(of: "{format}", with: "jpg")
        return absoluteURL(value, baseURL: baseURL)
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

    private static func boolValue(_ value: Any?) -> Bool? {
        switch value {
        case let bool as Bool:
            return bool
        case let number as NSNumber:
            return number.boolValue
        case let string as String:
            switch string.trimmed.lowercased() {
            case "1", "true", "yes", "on": return true
            case "0", "false", "no", "off": return false
            default: return nil
            }
        default:
            return nil
        }
    }

    private static func isClipID(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z0-9_-]{4,}$"#, options: .regularExpression) != nil
    }

    private static func isVideoID(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z0-9_-]{2,}$"#, options: .regularExpression) != nil
    }

    private static func isLiveChannelID(_ value: String) -> Bool {
        guard isVideoID(value) else { return false }
        let reserved = [
            "clip", "clips", "video", "videos", "vod", "live", "search",
            "category", "following", "lounge", "settings", "notice"
        ]
        return !reserved.contains(value.lowercased())
    }

    private static func isChzzkHost(_ host: String) -> Bool {
        host == "chzzk.naver.com" ||
            host == "m.chzzk.naver.com" ||
            host == "chzzk.naver.test" ||
            host == "m.chzzk.naver.test"
    }
}
