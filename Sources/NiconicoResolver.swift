import Foundation

struct NiconicoFormatCandidate {
    var url: URL
    var height: Int
    var audioBitrate: Int
    var label: String
    var extensionHint: String
    var score: Int
}

struct NiconicoDomandVideo: Equatable {
    let id: String
    let label: String
    let width: Int
    let height: Int
    let bitRate: Int
    let qualityLevel: Int
    let recommendedHighestAudioQualityLevel: Int?
}

struct NiconicoDomandAudio: Equatable {
    let id: String
    let bitRate: Int
    let samplingRate: Int
    let qualityLevel: Int
}

struct NiconicoDomandContext {
    let video: NiconicoDomandVideo
    let audio: NiconicoDomandAudio
    let accessRightKey: String
    let watchTrackID: String
    let info: NiconicoAPIInfo
}

struct NiconicoAPIInfo {
    let id: String
    let title: String
    let displayTitle: String
    let uploader: String
    let uploaderID: String
    let thumbnail: URL?
    let date: String
    let duration: Int
    let viewCount: Int
    let commentCount: Int
    let likeCount: Int
}

struct NiconicoDomandAccess {
    let contentURL: URL
    let createTime: String
    let expireTime: String
}

final class NiconicoResolver {
    static let frontendID = "6"
    static let frontendVersion = "0"

    func canResolve(_ url: URL) -> Bool {
        Self.videoID(from: url) != nil
    }

    func resolve(
        _ url: URL,
        headers: HTTPRequestOptions = HTTPRequestOptions(),
        preferredResolution: String = ""
    ) async throws -> ResolvedDownload {
        guard let videoID = Self.videoID(from: url) else {
            throw NativeDownloadError.invalidURL(url.absoluteString)
        }
        let pageURL = Self.canonicalURL(for: url)
        var officialError: Error?
        do {
            return try await resolveOfficialAPI(
                videoID: videoID,
                pageURL: pageURL,
                headers: headers,
                preferredResolution: preferredResolution
            )
        } catch {
            officialError = error
        }

        do {
            let html = try await HTTPClient.shared.string(
                from: pageURL,
                referer: headers.referer,
                userAgent: headers.userAgent
            )
            return try await Self.resolvedDownload(
                fromHTML: html,
                pageURL: pageURL,
                userAgent: headers.userAgent,
                preferredResolution: preferredResolution
            )
        } catch {
            throw officialError ?? error
        }
    }

    static func videoID(from url: URL) -> String? {
        guard let host = url.host?.lowercased(),
              isSupportedHost(host),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }

        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        let lower = parts.map { $0.lowercased() }

        if host == "nico.ms" || host == "www.nico.ms" || host == "nico.ms.test" || host == "www.nico.ms.test" {
            guard let id = parts.first, isVideoID(id) else { return nil }
            return id
        }

        if let marker = lower.firstIndex(where: { $0 == "watch" || $0 == "shorts" }),
           marker + 1 < parts.count,
           isVideoID(parts[marker + 1]) {
            return parts[marker + 1]
        }
        return nil
    }

    static func canonicalURL(for url: URL) -> URL {
        guard let id = videoID(from: url) else {
            return url
        }
        var components = URLComponents()
        components.scheme = url.scheme ?? "https"
        components.host = url.host?.lowercased().hasSuffix(".test") == true ? "www.nicovideo.test" : "www.nicovideo.jp"
        components.path = canonicalPath(for: id)
        return components.url ?? url
    }

    static func canonicalInputURL(for url: URL) -> URL? {
        if videoID(from: url) != nil {
            return canonicalURL(for: url)
        }

        guard let host = url.host?.lowercased(),
              host == "niconico.com" || host == "www.niconico.com",
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }

        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        guard parts.count >= 2,
              ["watch", "shorts"].contains(parts[0].lowercased()),
              isVideoID(parts[1]) else {
            return nil
        }

        var components = URLComponents()
        components.scheme = url.scheme ?? "https"
        components.host = "www.nicovideo.jp"
        components.path = canonicalPath(for: parts[1])
        return components.url
    }

    static func canonicalInputURL(forBareVideoID value: String) -> URL? {
        let id = value.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard isBareVideoID(id) else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.nicovideo.jp"
        components.path = canonicalPath(for: id)
        return components.url
    }

    static func canonicalInputURL(forShortcut value: String) -> URL? {
        let trimmed = value.trimmed
        let lowercased = trimmed.lowercased()
        for prefix in ["niconico:", "nicovideo:", "nico:"] {
            guard lowercased.hasPrefix(prefix) else { continue }
            let start = trimmed.index(trimmed.startIndex, offsetBy: prefix.count)
            let id = String(trimmed[start...]).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return canonicalInputURL(forBareVideoID: id)
        }
        return nil
    }

    private func resolveOfficialAPI(
        videoID: String,
        pageURL: URL,
        headers: HTTPRequestOptions,
        preferredResolution: String
    ) async throws -> ResolvedDownload {
        let hasSession = await CookieStore.shared.cookieValue(named: "user_session", for: pageURL) != nil
        let trackID = Self.actionTrackID()
        var endpointKinds = hasSession ? ["v3", "v3_guest"] : ["v3_guest"]
        var lastError: Error?

        while !endpointKinds.isEmpty {
            let kind = endpointKinds.removeFirst()
            let apiURL = Self.watchAPIURL(
                for: pageURL,
                videoID: videoID,
                endpointKind: kind,
                actionTrackID: trackID
            )
            do {
                let (apiData, _) = try await HTTPClient.shared.dataResponse(
                    from: apiURL,
                    referer: pageURL.absoluteString,
                    userAgent: headers.userAgent,
                    additionalHeaders: Self.officialAPIHeaders,
                    acceptedStatusCodes: [400, 404]
                )
                let context = try Self.domandContext(
                    fromAPIResponse: apiData,
                    pageURL: pageURL,
                    fallbackID: videoID,
                    preferredResolution: preferredResolution
                )
                let accessURL = Self.accessRightsURL(
                    for: pageURL,
                    videoID: context.info.id,
                    actionTrackID: context.watchTrackID
                )
                let accessData = try await HTTPClient.shared.postJSON(
                    to: accessURL,
                    body: try Self.domandRequestBody(video: context.video, audio: context.audio),
                    referer: pageURL.absoluteString,
                    userAgent: headers.userAgent,
                    additionalHeaders: [
                        "Accept": "application/json;charset=utf-8",
                        "X-Access-Right-Key": context.accessRightKey,
                        "X-Request-With": Self.officialBaseURL(for: pageURL).absoluteString,
                        "X-Frontend-ID": Self.frontendID,
                        "X-Frontend-Version": Self.frontendVersion
                    ]
                )
                let access = try Self.domandAccess(from: accessData)
                let outputFilename = "\(context.info.title)-\(context.info.id).mp4"
                    .sanitizedFilename(maxLength: 180)
                guard let hls = try await M3U8Resolver().resolveAlternateAudioMux(
                    access.contentURL,
                    titleHint: context.info.displayTitle,
                    outputFilename: outputFilename,
                    headers: HTTPRequestOptions(
                        referer: pageURL.absoluteString,
                        userAgent: headers.userAgent
                    ),
                    preferredResolution: preferredResolution,
                    segmentReferer: pageURL.absoluteString
                ) else {
                    throw NativeDownloadError.unsupported("Niconico returned an HLS manifest without its required audio track.")
                }
                return try Self.domandResolvedDownload(
                    hls: hls,
                    context: context,
                    access: access,
                    pageURL: pageURL
                )
            } catch {
                lastError = error
            }
        }

        throw lastError ?? NativeDownloadError.noFiles
    }

    static func actionTrackID(now: Date = Date()) -> String {
        "AAAAAAAAAA_\(Int64((now.timeIntervalSince1970 * 1_000).rounded()))"
    }

    static func watchAPIURL(
        for pageURL: URL,
        videoID: String,
        endpointKind: String,
        actionTrackID: String
    ) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = pageURL.host?.lowercased().hasSuffix(".test") == true
            ? "www.nicovideo.test"
            : "www.nicovideo.jp"
        components.path = "/api/watch/\(endpointKind)/\(videoID)"
        components.queryItems = [URLQueryItem(name: "actionTrackId", value: actionTrackID)]
        return components.url!
    }

    static func accessRightsURL(
        for pageURL: URL,
        videoID: String,
        actionTrackID: String
    ) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = pageURL.host?.lowercased().hasSuffix(".test") == true
            ? "nvapi.nicovideo.test"
            : "nvapi.nicovideo.jp"
        components.path = "/v1/watch/\(videoID)/access-rights/hls"
        components.queryItems = [URLQueryItem(name: "actionTrackId", value: actionTrackID)]
        return components.url!
    }

    static func domandRequestBody(video: NiconicoDomandVideo, audio: NiconicoDomandAudio) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "outputs": [[video.id, audio.id]]
        ])
    }

    static func domandContext(
        fromAPIResponse data: Data,
        pageURL: URL,
        fallbackID: String,
        preferredResolution: String
    ) throws -> NiconicoDomandContext {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NativeDownloadError.unsupported("Niconico returned invalid API metadata.")
        }
        let meta = root["meta"] as? [String: Any]
        let status = intValue(meta?["status"]) ?? 0
        guard status == 200, let api = root["data"] as? [String: Any] else {
            throw NativeDownloadError.unsupported(apiErrorMessage(root: root, status: status))
        }
        guard let media = api["media"] as? [String: Any],
              let domand = media["domand"] as? [String: Any],
              let accessRightKey = stringValue(domand["accessRightKey"]),
              let client = api["client"] as? [String: Any],
              let watchTrackID = stringValue(client["watchTrackId"]) else {
            throw NativeDownloadError.unsupported("Niconico did not expose a current native playback session for this video.")
        }

        let videos = (domand["videos"] as? [[String: Any]] ?? []).compactMap(domandVideo)
        let audios = (domand["audios"] as? [[String: Any]] ?? []).compactMap(domandAudio)
        guard let video = selectedDomandVideo(videos, preferredResolution: preferredResolution),
              let audio = selectedDomandAudio(audios, for: video) else {
            throw NativeDownloadError.unsupported("Niconico did not provide an available video and audio pair.")
        }

        return NiconicoDomandContext(
            video: video,
            audio: audio,
            accessRightKey: accessRightKey,
            watchTrackID: watchTrackID,
            info: apiInfo(from: api, pageURL: pageURL, fallbackID: fallbackID)
        )
    }

    static func domandAccess(from data: Data) throws -> NiconicoDomandAccess {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = root["data"] as? [String: Any],
              let rawURL = stringValue(payload["contentUrl"]),
              let contentURL = URL(string: rawURL) else {
            throw NativeDownloadError.unsupported("Niconico did not return a playable HLS URL.")
        }
        let status = intValue((root["meta"] as? [String: Any])?["status"]) ?? 0
        guard status == 200 || status == 201 else {
            throw NativeDownloadError.unsupported(apiErrorMessage(root: root, status: status))
        }
        return NiconicoDomandAccess(
            contentURL: contentURL,
            createTime: stringValue(payload["createTime"]) ?? "",
            expireTime: stringValue(payload["expireTime"]) ?? ""
        )
    }

    static func selectedDomandVideo(
        _ videos: [NiconicoDomandVideo],
        preferredResolution: String
    ) -> NiconicoDomandVideo? {
        guard !videos.isEmpty else { return nil }
        var pool = videos
        if let ceiling = preferredHeight(from: preferredResolution) {
            let bounded = videos.filter {
                let qualityHeight = domandQualityHeight($0)
                return qualityHeight > 0 && qualityHeight <= ceiling
            }
            if !bounded.isEmpty {
                pool = bounded
            } else if let lowest = videos.min(by: domandVideoIsLowerQuality) {
                pool = [lowest]
            }
        }
        return pool.max { lhs, rhs in
            if lhs.qualityLevel != rhs.qualityLevel {
                return lhs.qualityLevel < rhs.qualityLevel
            }
            if lhs.bitRate != rhs.bitRate {
                return lhs.bitRate < rhs.bitRate
            }
            return lhs.height < rhs.height
        }
    }

    static func selectedDomandAudio(
        _ audios: [NiconicoDomandAudio],
        for video: NiconicoDomandVideo
    ) -> NiconicoDomandAudio? {
        guard !audios.isEmpty else { return nil }
        var pool = audios
        if let maximum = video.recommendedHighestAudioQualityLevel {
            let bounded = audios.filter { $0.qualityLevel <= maximum }
            if !bounded.isEmpty {
                pool = bounded
            }
        }
        return pool.max { lhs, rhs in
            if lhs.qualityLevel != rhs.qualityLevel {
                return lhs.qualityLevel < rhs.qualityLevel
            }
            return lhs.bitRate < rhs.bitRate
        }
    }

    private static func domandVideo(from object: [String: Any]) -> NiconicoDomandVideo? {
        guard boolValue(object["isAvailable"]) == true,
              let id = stringValue(object["id"]) else {
            return nil
        }
        return NiconicoDomandVideo(
            id: id,
            label: stringValue(object["label"]) ?? "",
            width: intValue(object["width"]) ?? 0,
            height: intValue(object["height"]) ?? 0,
            bitRate: intValue(object["bitRate"]) ?? 0,
            qualityLevel: intValue(object["qualityLevel"]) ?? 0,
            recommendedHighestAudioQualityLevel: intValue(object["recommendedHighestAudioQualityLevel"])
        )
    }

    private static func domandAudio(from object: [String: Any]) -> NiconicoDomandAudio? {
        guard boolValue(object["isAvailable"]) == true,
              let id = stringValue(object["id"]) else {
            return nil
        }
        return NiconicoDomandAudio(
            id: id,
            bitRate: intValue(object["bitRate"]) ?? 0,
            samplingRate: intValue(object["samplingRate"]) ?? 0,
            qualityLevel: intValue(object["qualityLevel"]) ?? 0
        )
    }

    private static func apiInfo(from api: [String: Any], pageURL: URL, fallbackID: String) -> NiconicoAPIInfo {
        let video = api["video"] as? [String: Any] ?? [:]
        let owner = api["owner"] as? [String: Any]
        let channel = api["channel"] as? [String: Any]
        let uploaderRaw = stringValue(owner?["nickname"]) ??
            stringValue(owner?["name"]) ??
            stringValue(channel?["name"])
        let uploader = uploaderRaw.map { cleanTitle($0, fallback: $0) } ?? ""
        let uploaderID = stringValue(owner?["id"]) ??
            stringValue(channel?["id"]) ??
            stringValue(channel?["globalId"]) ?? ""
        let id = stringValue(video["id"]) ?? fallbackID
        let title = cleanTitle(stringValue(video["title"]) ?? "Niconico \(id)", fallback: "Niconico \(id)")
        let displayTitle = uploader.isEmpty ? title : "\(uploader) - \(title)"
        let thumbnailObject = video["thumbnail"] as? [String: Any] ?? [:]
        let thumbnailRaw = ["player", "ogp", "largeUrl", "middleUrl", "url", "short", "shortUrl"]
            .compactMap { stringValue(thumbnailObject[$0]) }
            .first
        let counts = video["count"] as? [String: Any] ?? [:]
        return NiconicoAPIInfo(
            id: id,
            title: title,
            displayTitle: displayTitle.sanitizedFilename(maxLength: 120),
            uploader: uploader,
            uploaderID: uploaderID,
            thumbnail: thumbnailRaw.flatMap { absoluteURL($0, baseURL: pageURL) },
            date: normalizedDate(stringValue(video["registeredAt"])) ?? "",
            duration: intValue(video["duration"]) ?? 0,
            viewCount: intValue(counts["view"]) ?? 0,
            commentCount: intValue(counts["comment"]) ?? 0,
            likeCount: intValue(counts["like"]) ?? 0
        )
    }

    private static func domandResolvedDownload(
        hls: ResolvedDownload,
        context: NiconicoDomandContext,
        access: NiconicoDomandAccess,
        pageURL: URL
    ) throws -> ResolvedDownload {
        guard case .mux(let rawVideoAssets, let rawAudioAssets, let outputFilename) = hls.packageMode else {
            throw NativeDownloadError.unsupported("Niconico native HLS did not produce separate video and audio tracks.")
        }
        let videoAssets = domandAssets(
            rawVideoAssets,
            kind: "video",
            trackID: context.video.id,
            info: context.info,
            pageURL: pageURL
        )
        let audioAssets = domandAssets(
            rawAudioAssets,
            kind: "audio",
            trackID: context.audio.id,
            info: context.info,
            pageURL: pageURL
        )
        let assets = videoAssets + audioAssets
        let encryptedCount = assets.filter { $0.decryption != nil }.count
        let metadata = DownloadMetadata.clean(hls.metadata.merging([
            "handler": "native",
            "site": "Niconico",
            "title": context.info.title,
            "series": context.info.uploader,
            "artist": context.info.uploader,
            "author": context.info.uploader,
            "creator": context.info.uploader,
            "uploader": context.info.uploader,
            "artist_id": context.info.uploaderID,
            "author_id": context.info.uploaderID,
            "creator_id": context.info.uploaderID,
            "uploader_id": context.info.uploaderID,
            "channel_id": context.info.uploaderID,
            "category": "video",
            "type": "hls",
            "media_type": "hls",
            "format": "mp4",
            "media_format": "mp4",
            "package_mode": "mux",
            "delivery_api": "domand",
            "id": context.info.id,
            "video_id": context.info.id,
            "media_id": context.info.id,
            "gallery_id": context.info.id,
            "video_format_id": context.video.id,
            "audio_format_id": context.audio.id,
            "width": context.video.width > 0 ? String(context.video.width) : "",
            "height": context.video.height > 0 ? String(context.video.height) : "",
            "resolution": domandQualityHeight(context.video) > 0 ? "\(domandQualityHeight(context.video))p" : "",
            "quality": context.video.label,
            "video_bitrate": context.video.bitRate > 0 ? String(context.video.bitRate) : "",
            "audio_bitrate": context.audio.bitRate > 0 ? String(context.audio.bitRate) : "",
            "audio_sample_rate": context.audio.samplingRate > 0 ? String(context.audio.samplingRate) : "",
            "duration": context.info.duration > 0 ? String(context.info.duration) : "",
            "duration_seconds": context.info.duration > 0 ? String(context.info.duration) : "",
            "view_count": context.info.viewCount > 0 ? String(context.info.viewCount) : "",
            "comment_count": context.info.commentCount > 0 ? String(context.info.commentCount) : "",
            "like_count": context.info.likeCount > 0 ? String(context.info.likeCount) : "",
            "date": context.info.date,
            "published_date": context.info.date,
            "thumbnail": context.info.thumbnail?.absoluteString ?? "",
            "media_count": String(assets.count),
            "video_count": "1",
            "audio_count": "1",
            "encrypted": encryptedCount > 0 ? "true" : "false",
            "encrypted_count": String(encryptedCount),
            "content_url": access.contentURL.absoluteString,
            "playback_created_at": access.createTime,
            "playback_expires_at": access.expireTime,
            "url": pageURL.absoluteString,
            "source_url": pageURL.absoluteString,
            "page_url": pageURL.absoluteString
        ]) { _, new in new })

        return ResolvedDownload(
            title: context.info.displayTitle,
            folderName: "Niconico \(context.info.displayTitle)".sanitizedFilename(maxLength: 120),
            assets: assets,
            packageMode: .mux(
                videoAssets: videoAssets,
                audioAssets: audioAssets,
                outputFilename: outputFilename
            ),
            metadata: metadata
        )
    }

    private static func domandAssets(
        _ assets: [ResolvedAsset],
        kind: String,
        trackID: String,
        info: NiconicoAPIInfo,
        pageURL: URL
    ) -> [ResolvedAsset] {
        assets.enumerated().map { offset, asset in
            var enriched = asset
            let baseType = asset.metadata["type"] ?? "hls_segment"
            let segmentNumber = asset.metadata["segment_number"] ?? String(offset + 1)
            enriched.metadata = DownloadMetadata.clean(asset.metadata.merging([
                "site": "Niconico",
                "title": info.title,
                "series": info.uploader,
                "artist": info.uploader,
                "author": info.uploader,
                "creator": info.uploader,
                "uploader": info.uploader,
                "uploader_id": info.uploaderID,
                "category": "video",
                "type": baseType == "hls_map" ? "hls_\(kind)_map" : "hls_\(kind)_segment",
                "media_type": kind,
                "id": info.id,
                "video_id": info.id,
                "media_id": "\(info.id)-\(kind)-\(offset + 1)",
                "gallery_id": info.id,
                "track_id": trackID,
                "\(kind)_format_id": trackID,
                "date": info.date,
                "published_date": info.date,
                "page": String(offset + 1),
                "position": String(offset + 1),
                "segment_number": segmentNumber,
                "media_url": asset.remoteURL.absoluteString,
                kind == "video" ? "video_url" : "audio_url": asset.remoteURL.absoluteString,
                "source_url": pageURL.absoluteString,
                "page_url": pageURL.absoluteString
            ]) { _, new in new })
            return enriched
        }
    }

    private static var officialAPIHeaders: [String: String] {
        [
            "X-Frontend-ID": frontendID,
            "X-Frontend-Version": frontendVersion
        ]
    }

    private static func officialBaseURL(for pageURL: URL) -> URL {
        URL(string: pageURL.host?.lowercased().hasSuffix(".test") == true
            ? "https://www.nicovideo.test"
            : "https://www.nicovideo.jp")!
    }

    private static func apiErrorMessage(root: [String: Any], status: Int) -> String {
        let meta = root["meta"] as? [String: Any]
        let data = root["data"] as? [String: Any]
        let code = stringValue(meta?["errorCode"]) ?? ""
        let reason = stringValue(data?["reasonCode"]) ?? ""
        switch reason {
        case "CHANNEL_MEMBER_ONLY": return "This Niconico video is available to channel members only. Save a signed-in Niconico session in the app and retry."
        case "PREMIUM_ONLY": return "This Niconico video requires a Premium account. Save a signed-in Niconico session in the app and retry."
        case "PPV_VIDEO": return "This Niconico video requires purchase access and a signed-in session."
        case "HARMFUL_VIDEO": return "Niconico requires a signed-in account with sensitive-content viewing enabled for this video."
        case "HIDDEN_VIDEO": return "This Niconico video is private, scheduled, or otherwise unavailable."
        case "RIGHT_HOLDER_DELETE_VIDEO", "ADMINISTRATOR_DELETE_VIDEO", "DELETED_CHANNEL_VIDEO":
            return "This Niconico video has been removed."
        default:
            let suffix = [code, reason].filter { !$0.isEmpty }.joined(separator: "/")
            return suffix.isEmpty
                ? "Niconico API returned status \(status)."
                : "Niconico API returned \(suffix) (status \(status))."
        }
    }

    private static func preferredHeight(from preferredResolution: String) -> Int? {
        var value = preferredResolution.trimmed.lowercased()
        if value.hasSuffix("p") { value.removeLast() }
        guard let height = Int(value), (144...8640).contains(height) else { return nil }
        return height
    }

    private static func domandVideoIsLowerQuality(_ lhs: NiconicoDomandVideo, _ rhs: NiconicoDomandVideo) -> Bool {
        if lhs.qualityLevel != rhs.qualityLevel { return lhs.qualityLevel < rhs.qualityLevel }
        if lhs.bitRate != rhs.bitRate { return lhs.bitRate < rhs.bitRate }
        return lhs.height < rhs.height
    }

    private static func domandQualityHeight(_ video: NiconicoDomandVideo) -> Int {
        if let labelHeight = firstCapture(pattern: #"([0-9]{3,4})\s*p"#, in: video.label),
           let value = Int(labelHeight),
           (144...8640).contains(value) {
            return value
        }
        if video.width > 0, video.height > 0 {
            return min(video.width, video.height)
        }
        return video.height
    }

    private static func formatCandidateIsLowerQuality(_ lhs: NiconicoFormatCandidate, _ rhs: NiconicoFormatCandidate) -> Bool {
        if lhs.height != rhs.height { return lhs.height < rhs.height }
        if lhs.isDirectMP4 != rhs.isDirectMP4 { return !lhs.isDirectMP4 && rhs.isDirectMP4 }
        if lhs.audioBitrate != rhs.audioBitrate { return lhs.audioBitrate < rhs.audioBitrate }
        return lhs.score < rhs.score
    }

    private static func boolValue(_ value: Any?) -> Bool? {
        switch value {
        case let bool as Bool: return bool
        case let number as NSNumber: return number.boolValue
        case let string as String:
            if ["true", "1", "yes"].contains(string.lowercased()) { return true }
            if ["false", "0", "no"].contains(string.lowercased()) { return false }
            return nil
        default: return nil
        }
    }

    private static func canonicalPath(for id: String) -> String {
        id.lowercased().hasPrefix("ss") ? "/shorts/\(id)" : "/watch/\(id)"
    }

    static func resolvedDownload(
        fromHTML html: String,
        pageURL: URL,
        userAgent: String? = nil,
        preferredResolution: String = ""
    ) async throws -> ResolvedDownload {
        guard let id = videoID(from: pageURL) else {
            throw NativeDownloadError.invalidURL(pageURL.absoluteString)
        }
        guard let candidate = bestCandidate(
            formatCandidates(fromHTML: html, pageURL: pageURL),
            preferredResolution: preferredResolution
        ) else {
            throw NativeDownloadError.noFiles
        }
        let info = videoInfo(fromHTML: html, pageURL: pageURL, fallbackID: id)

        if isM3U8(candidate.url) {
            let hls = try await M3U8Resolver().resolve(
                candidate.url,
                headers: HTTPRequestOptions(referer: pageURL.absoluteString, userAgent: userAgent)
            )
            return ResolvedDownload(
                title: info.displayTitle,
                folderName: "Niconico \(info.displayTitle)".sanitizedFilename(maxLength: 120),
                assets: hlsAssetsWithPageMetadata(hls.assets, info: info, pageURL: pageURL),
                packageMode: .concatenate(outputFilename: "\(info.title)-\(info.id).ts".sanitizedFilename(maxLength: 180)),
                metadata: hls.metadata.merging(metadata(info: info, candidate: candidate, pageURL: pageURL)) { _, new in new }
            )
        }

        let ext = candidate.url.pathExtension.trimmed.isEmpty ? (candidate.extensionHint.isEmpty ? "mp4" : candidate.extensionHint) : candidate.url.pathExtension
        let filename = "\(info.title)-\(info.id).\(ext)".sanitizedFilename(maxLength: 180)
        return ResolvedDownload(
            title: info.displayTitle,
            folderName: "Niconico \(info.displayTitle)".sanitizedFilename(maxLength: 120),
            assets: [
                ResolvedAsset(
                    remoteURL: candidate.url,
                    filename: filename,
                    metadata: mediaMetadata(for: candidate, info: info, pageURL: pageURL),
                    referer: pageURL.absoluteString
                )
            ],
            packageMode: .concatenate(outputFilename: filename),
            metadata: metadata(info: info, candidate: candidate, pageURL: pageURL)
        )
    }

    static func formatCandidates(fromHTML html: String, pageURL: URL) -> [NiconicoFormatCandidate] {
        var candidates: [NiconicoFormatCandidate] = []
        for object in jsonObjects(fromHTML: html) {
            collectFormatCandidates(in: object, pageURL: pageURL, keyPath: [], candidates: &candidates)
        }
        candidates.append(contentsOf: directVideoCandidates(fromHTML: html, pageURL: pageURL))

        var seen = Set<String>()
        return candidates.compactMap { candidate in
            let normalized = URLIdentity.normalize(candidate.url.absoluteString)
            guard !seen.contains(normalized) else { return nil }
            seen.insert(normalized)
            return candidate
        }
    }

    static func bestCandidate(
        _ candidates: [NiconicoFormatCandidate],
        preferredResolution: String = ""
    ) -> NiconicoFormatCandidate? {
        var pool = candidates
        if let ceiling = preferredHeight(from: preferredResolution) {
            let bounded = candidates.filter { $0.height > 0 && $0.height <= ceiling }
            if !bounded.isEmpty {
                pool = bounded
            } else if let lowest = candidates.min(by: formatCandidateIsLowerQuality) {
                pool = [lowest]
            }
        }
        return pool.max { lhs, rhs in
            if lhs.height != rhs.height { return lhs.height < rhs.height }
            if lhs.isDirectMP4 != rhs.isDirectMP4 { return !lhs.isDirectMP4 && rhs.isDirectMP4 }
            if lhs.audioBitrate != rhs.audioBitrate { return lhs.audioBitrate < rhs.audioBitrate }
            return lhs.score < rhs.score
        }
    }

    static func videoInfo(fromHTML html: String, pageURL: URL, fallbackID: String) -> (id: String, title: String, displayTitle: String, uploader: String, thumbnail: URL?, date: String) {
        let objects = jsonObjects(fromHTML: html)
        let id = firstRecursiveString(in: objects, keys: ["video_id", "videoId", "id"]) ?? fallbackID
        let title = cleanTitle(
            firstRecursiveString(in: objects, keys: ["fulltitle", "fullTitle", "title"]) ??
                metaContent(from: html, names: ["og:title", "twitter:title"]) ??
                titleTag(fromHTML: html) ??
                "Niconico \(fallbackID)",
            fallback: "Niconico \(fallbackID)"
        )
        let uploaderRaw = firstRecursiveString(
            in: objects,
            keys: ["uploader", "owner", "username", "userName", "nickname"]
        )
        let uploader = uploaderRaw.map { cleanTitle($0, fallback: $0) } ?? ""
        let thumbnailRaw = firstRecursiveString(in: objects, keys: ["thumbnail", "thumbnail_url", "thumbnailUrl", "url_thumb", "thumb"]) ??
            metaContent(from: html, names: ["og:image", "twitter:image"])
        let date = publishedDate(fromHTML: html, objects: objects) ?? ""
        let displayTitle = uploader.isEmpty ? title : "\(uploader) - \(title)"
        return (id, title, displayTitle.sanitizedFilename(maxLength: 120), uploader, thumbnailRaw.flatMap { absoluteURL($0, baseURL: pageURL) }, date)
    }

    private static func metadata(info: (id: String, title: String, displayTitle: String, uploader: String, thumbnail: URL?, date: String), candidate: NiconicoFormatCandidate, pageURL: URL) -> [String: String] {
        DownloadMetadata.clean([
            "handler": "native",
            "site": "Niconico",
            "title": info.title,
            "series": info.uploader,
            "artist": info.uploader,
            "author": info.uploader,
            "creator": info.uploader,
            "uploader": info.uploader,
            "channel": info.uploader,
            "category": "video",
            "type": isM3U8(candidate.url) ? "hls" : "video",
            "media_type": isM3U8(candidate.url) ? "hls" : "video",
            "format": mediaFormat(for: candidate),
            "media_format": mediaFormat(for: candidate),
            "host": pageURL.host ?? "",
            "id": info.id,
            "video_id": info.id,
            "media_id": info.id,
            "gallery_id": info.id,
            "media_count": isM3U8(candidate.url) ? "" : "1",
            "video_count": "1",
            "date": info.date,
            "published_date": info.date,
            "height": candidate.height > 0 ? String(candidate.height) : "",
            "audio_bitrate": candidate.audioBitrate > 0 ? String(candidate.audioBitrate) : "",
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

    private static func mediaMetadata(for candidate: NiconicoFormatCandidate, info: (id: String, title: String, displayTitle: String, uploader: String, thumbnail: URL?, date: String), pageURL: URL) -> [String: String] {
        DownloadMetadata.clean([
            "handler": "native",
            "site": "Niconico",
            "title": info.title,
            "series": info.uploader,
            "artist": info.uploader,
            "author": info.uploader,
            "creator": info.uploader,
            "uploader": info.uploader,
            "channel": info.uploader,
            "category": "video",
            "type": isM3U8(candidate.url) ? "hls" : "video",
            "media_type": isM3U8(candidate.url) ? "hls" : "video",
            "format": mediaFormat(for: candidate),
            "media_format": mediaFormat(for: candidate),
            "id": info.id,
            "video_id": info.id,
            "media_id": info.id,
            "gallery_id": info.id,
            "date": info.date,
            "published_date": info.date,
            "page": "1",
            "position": "1",
            "height": candidate.height > 0 ? String(candidate.height) : "",
            "audio_bitrate": candidate.audioBitrate > 0 ? String(candidate.audioBitrate) : "",
            "resolution": resolution(for: candidate),
            "quality": qualityLabel(for: candidate),
            "video_url": candidate.url.absoluteString,
            "media_url": candidate.url.absoluteString,
            "playlist_url": isM3U8(candidate.url) ? candidate.url.absoluteString : "",
            "source_url": pageURL.absoluteString,
            "page_url": pageURL.absoluteString
        ])
    }

    static func hlsAssetsWithPageMetadata(_ assets: [ResolvedAsset], info: (id: String, title: String, displayTitle: String, uploader: String, thumbnail: URL?, date: String), pageURL: URL) -> [ResolvedAsset] {
        assets.enumerated().map { offset, asset in
            var enriched = asset
            enriched.metadata = asset.metadata.merging(segmentMetadata(info: info, asset: asset, pageURL: pageURL, index: offset + 1)) { _, new in new }
            return enriched
        }
    }

    private static func segmentMetadata(info: (id: String, title: String, displayTitle: String, uploader: String, thumbnail: URL?, date: String), asset: ResolvedAsset, pageURL: URL, index: Int) -> [String: String] {
        let format = mediaFormat(for: asset.remoteURL, fallback: mediaFormat(forFilename: asset.filename, fallback: "ts"))
        return DownloadMetadata.clean([
            "site": "Niconico",
            "title": info.title,
            "series": info.uploader,
            "artist": info.uploader,
            "author": info.uploader,
            "creator": info.uploader,
            "uploader": info.uploader,
            "channel": info.uploader,
            "category": "video",
            "type": "hls_segment",
            "media_type": "segment",
            "format": format,
            "media_format": format,
            "id": info.id,
            "video_id": info.id,
            "media_id": "\(info.id)-segment-\(index)",
            "gallery_id": info.id,
            "date": info.date,
            "published_date": info.date,
            "page": String(index),
            "position": String(index),
            "video_url": asset.remoteURL.absoluteString,
            "media_url": asset.remoteURL.absoluteString,
            "source_url": pageURL.absoluteString,
            "page_url": pageURL.absoluteString
        ])
    }

    private static func mediaFormat(for candidate: NiconicoFormatCandidate) -> String {
        if isM3U8(candidate.url) { return "m3u8" }
        let ext = candidate.url.pathExtension.lowercased()
        if !ext.isEmpty { return ext }
        let hint = candidate.extensionHint.lowercased()
        return hint.isEmpty ? "mp4" : hint
    }

    private static func mediaFormat(for url: URL, fallback: String) -> String {
        let ext = url.pathExtension.trimmed
        return (ext.isEmpty ? fallback : ext).lowercased()
    }

    private static func mediaFormat(forFilename filename: String, fallback: String) -> String {
        let ext = (filename as NSString).pathExtension.trimmed
        return (ext.isEmpty ? fallback : ext).lowercased()
    }

    private static func resolution(for candidate: NiconicoFormatCandidate) -> String {
        if candidate.height > 0 { return "\(candidate.height)p" }
        if let height = heightFromText(candidate.label) { return "\(height)p" }
        return ""
    }

    private static func qualityLabel(for candidate: NiconicoFormatCandidate) -> String {
        let resolution = resolution(for: candidate)
        return resolution.isEmpty ? candidate.label : resolution
    }

    private static func publishedDate(fromHTML html: String, objects: [Any]) -> String? {
        let raw = firstRecursiveString(
            in: objects,
            keys: [
                "registeredAt", "registered_at", "firstRetrieve", "first_retrieve",
                "publishedAt", "published_at", "publishDate", "publish_date",
                "datePublished", "date_published", "uploadDate", "upload_date", "createdAt", "created_at"
            ]
        ) ?? metaContent(
            from: html,
            names: ["datePublished", "datepublished", "article:published_time", "uploadDate", "pubdate", "date"]
        )
        return normalizedDate(raw)
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

    private static func collectFormatCandidates(in value: Any, pageURL: URL, keyPath: [String], candidates: inout [NiconicoFormatCandidate]) {
        if let raw = stringValue(value),
           let url = absoluteURL(raw, baseURL: pageURL),
           isLikelyVideoURL(url),
           !isDMCOnlyPath(keyPath: keyPath, raw: raw) {
            candidates.append(NiconicoFormatCandidate(
                url: url,
                height: heightFromText((keyPath + [raw]).joined(separator: " ")) ?? 0,
                audioBitrate: audioBitrateFromText((keyPath + [raw]).joined(separator: " ")) ?? 0,
                label: keyPath.last ?? "",
                extensionHint: url.pathExtension.lowercased(),
                score: score(raw: raw, keyPath: keyPath)
            ))
            return
        }

        if let dict = value as? [String: Any] {
            if isNativeUnsupportedVideoOnlyHLS(dict, pageURL: pageURL) {
                return
            }
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

    private static func candidate(from dict: [String: Any], pageURL: URL, keyPath: [String]) -> NiconicoFormatCandidate? {
        guard !isDMCOnlyDictionary(dict) else {
            return nil
        }
        for key in ["url", "file", "src", "video_url", "videoUrl", "stream_url", "streamUrl"] {
            guard let raw = stringValue(dict[key]),
                  let url = absoluteURL(raw, baseURL: pageURL),
                  isLikelyVideoURL(url),
                  !isDMCOnlyPath(keyPath: keyPath + [key], raw: raw) else {
                continue
            }
            let height = intValue(dict["height"]) ??
                intValue(dict["resolution"]) ??
                stringValue(dict["format_note"]).flatMap(heightFromText) ??
                stringValue(dict["quality"]).flatMap(heightFromText) ??
                heightFromText(raw) ??
                0
            let abr = intValue(dict["abr"]) ??
                intValue(dict["audio_bitrate"]) ??
                stringValue(dict["format"]).flatMap(audioBitrateFromText) ??
                0
            let label = cleanTitle(
                stringValue(dict["format"]) ??
                    stringValue(dict["format_id"]) ??
                    stringValue(dict["format_note"]) ??
                    stringValue(dict["quality"]) ??
                    "",
                fallback: ""
            )
            let ext = stringValue(dict["ext"]) ?? stringValue(dict["extension"]) ?? url.pathExtension.lowercased()
            return NiconicoFormatCandidate(url: url, height: height, audioBitrate: abr, label: label, extensionHint: ext, score: score(raw: raw, keyPath: keyPath + [label]))
        }
        return nil
    }

    private static func directVideoCandidates(fromHTML html: String, pageURL: URL) -> [NiconicoFormatCandidate] {
        let patterns = [
            #"\b(?:src|href)\s*=\s*["']([^"']+\.(?:mp4|m3u8)(?:\?[^"']*)?)["']"#,
            #""(?:url|file|videoUrl|streamUrl)"\s*:\s*"([^"]+\.(?:mp4|m3u8)(?:\?[^"]*)?)""#
        ]
        return patterns.flatMap { pattern in
            captures(pattern: pattern, in: html).compactMap { raw in
                guard let url = absoluteURL(raw, baseURL: pageURL), isLikelyVideoURL(url) else { return nil }
                return NiconicoFormatCandidate(url: url, height: heightFromText(raw) ?? 0, audioBitrate: 0, label: "", extensionHint: url.pathExtension.lowercased(), score: score(raw: raw, keyPath: []))
            }
        }
    }

    static func jsonObjects(fromHTML html: String) -> [Any] {
        let payloads = scriptJSONPayloads(fromHTML: html) + assignmentPayloads(fromHTML: html)
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
            if raw.hasPrefix("{") || raw.hasPrefix("[") {
                return raw
            }
            if let dataAttribute = firstCapture(pattern: #"data-api-data\s*=\s*["']([^"']+)["']"#, in: raw) {
                return decodeHTML(dataAttribute)
            }
            return nil
        }
    }

    private static func assignmentPayloads(fromHTML html: String) -> [String] {
        var payloads: [String] = []
        if let data = firstCapture(pattern: #"<div\b[^>]*\bid\s*=\s*["']js-initial-watch-data["'][^>]*\bdata-api-data\s*=\s*["']([^"']+)["'][^>]*>"#, in: html) {
            payloads.append(decodeHTML(data))
        }
        let assignmentPatterns = [
            #"window\.__(?:INITIAL|NICO|DATA)[\w$]*\s*="#,
            #"(?:var|let|const)\s+[\w$]*(?:Data|Info|Video|Player)[\w$]*\s*="#
        ]
        for pattern in assignmentPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(html.startIndex..<html.endIndex, in: html)
            payloads.append(contentsOf: regex.matches(in: html, range: range).compactMap { match in
                guard let matchRange = Range(match.range, in: html) else { return nil }
                return balancedValue(startingAtOrAfter: matchRange.upperBound, in: html)
            })
        }
        return payloads
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

    private static func score(raw: String, keyPath: [String]) -> Int {
        let text = (keyPath.joined(separator: ".") + " " + raw).lowercased()
        var score = 0
        if text.contains("formats") { score += 1_000_000 }
        if text.contains("source") || text.contains("original") { score += 500_000 }
        if text.contains(".mp4") { score += 100_000 }
        if text.contains(".m3u8") { score += 80_000 }
        if text.contains("dmc") { score -= 1_000_000 }
        score += heightFromText(text) ?? 0
        return score
    }

    private static func heightFromText(_ text: String) -> Int? {
        let patterns = [
            #"([0-9]{3,4})\s*p"#,
            #"[xX]([0-9]{3,4})"#,
            #"[^0-9]([0-9]{3,4})[^0-9]"#
        ]
        for pattern in patterns {
            if let value = firstCapture(pattern: pattern, in: text), let height = Int(value), (144...8640).contains(height) {
                return height
            }
        }
        return nil
    }

    private static func audioBitrateFromText(_ text: String) -> Int? {
        firstCapture(pattern: #"([0-9]{2,4})\s*(?:k|kbps|abr)"#, in: text).flatMap(Int.init)
    }

    private static func isDMCOnlyDictionary(_ dict: [String: Any]) -> Bool {
        if let protocolValue = stringValue(dict["protocol"])?.lowercased(), protocolValue.contains("niconico_dmc") {
            return true
        }
        if let formatID = stringValue(dict["format_id"])?.lowercased(), formatID.contains("niconico_dmc") {
            return true
        }
        return false
    }

    private static func isNativeUnsupportedVideoOnlyHLS(_ dict: [String: Any], pageURL: URL) -> Bool {
        let protocolValue = stringValue(dict["protocol"])?.lowercased() ?? ""
        let explicitVideoOnly = stringValue(dict["acodec"])?.lowercased() == "none"
        guard explicitVideoOnly else { return false }

        for key in ["url", "file", "src", "video_url", "videoUrl", "stream_url", "streamUrl"] {
            guard let raw = stringValue(dict[key]),
                  let url = absoluteURL(raw, baseURL: pageURL) else {
                continue
            }
            if isM3U8(url) || protocolValue.hasPrefix("m3u8") {
                return true
            }
        }

        return protocolValue.hasPrefix("m3u8")
    }

    private static func isDMCOnlyPath(keyPath: [String], raw: String) -> Bool {
        let text = (keyPath.joined(separator: ".") + " " + raw).lowercased()
        return text.contains("niconico_dmc") || text.contains("heartbeat")
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

    private static func isSupportedHost(_ host: String) -> Bool {
        host == "nicovideo.jp" ||
            host == "www.nicovideo.jp" ||
            host == "sp.nicovideo.jp" ||
            host == "nico.ms" ||
            host == "www.nico.ms" ||
            host == "nicovideo.test" ||
            host == "www.nicovideo.test" ||
            host == "sp.nicovideo.test" ||
            host == "nico.ms.test" ||
            host == "www.nico.ms.test"
    }

    private static func isLikelyVideoURL(_ url: URL) -> Bool {
        let text = url.absoluteString.lowercased()
        return ["mp4", "m3u8", "webm", "m4v", "mov"].contains(url.pathExtension.lowercased()) ||
            text.contains(".mp4") ||
            text.contains(".m3u8")
    }

    private static func isM3U8(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "m3u8" || url.absoluteString.lowercased().contains(".m3u8")
    }

    private static func isVideoID(_ value: String) -> Bool {
        value.range(of: #"^(?:sm|so|nm|ss)?[0-9]+$"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func isBareVideoID(_ value: String) -> Bool {
        value.range(of: #"^(?:sm|so|nm|ss)[0-9]+$"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func cleanTitle(_ raw: String, fallback: String) -> String {
        var value = decodeHTML(stripTags(raw))
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmed
        value = value.replacingOccurrences(of: #"(?i)\s*[-|]\s*(?:ニコニコ動画|Niconico|Nicovideo)\s*$"#, with: "", options: .regularExpression)
        return value.isEmpty ? fallback.sanitizedFilename(maxLength: 120) : value.sanitizedFilename(maxLength: 120)
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
}

private extension NiconicoFormatCandidate {
    var isDirectMP4: Bool {
        url.pathExtension.lowercased() == "mp4" || extensionHint.lowercased() == "mp4"
    }
}
