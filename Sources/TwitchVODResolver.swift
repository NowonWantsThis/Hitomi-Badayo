import Foundation

struct TwitchPlaybackAccessToken {
    var value: String
    var signature: String
}

struct TwitchClipCandidate: Equatable {
    var url: URL
    var quality: Int
    var label: String
}

final class TwitchVODResolver {
    private struct TwitchHLSAdjustment {
        var assets: [ResolvedAsset]
        var strippedAdSegments: Int
        var recoveredMutedSegments: Int
    }

    private static let clientID = "kimne78kx3ncx6brgo4mv6wki5h1ko"
    private static let reservedLiveLogins: Set<String> = [
        "about", "activate", "bits", "broadcast", "clip", "clips", "collections", "creatorcamp",
        "dashboard", "directory", "downloads", "drops", "embed", "event",
        "following", "friends", "inventory", "jobs", "login", "logout", "moderator", "p",
        "popout", "privacy", "search", "settings", "signup", "store", "subscriptions",
        "team", "terms", "turbo", "wallet", "watch", "videos"
    ]
    private static let playbackTokenQuery = """
    query PlaybackAccessToken_Template($login: String!, $isLive: Boolean!, $vodID: ID!, $isVod: Boolean!, $playerType: String!) {
      streamPlaybackAccessToken(channelName: $login, params: {platform: "web", playerBackend: "mediaplayer", playerType: $playerType}) @include(if: $isLive) {
        value
        signature
        authorization { isForbidden forbiddenReasonCode }
        __typename
      }
      videoPlaybackAccessToken(id: $vodID, params: {platform: "web", playerBackend: "mediaplayer", playerType: $playerType}) @include(if: $isVod) {
        value
        signature
        __typename
      }
    }
    """

    func canResolve(_ url: URL) -> Bool {
        Self.vodID(from: url) != nil ||
            Self.clipSlug(from: url) != nil ||
            Self.liveLogin(from: url) != nil
    }

    func resolve(_ url: URL, headers: HTTPRequestOptions = HTTPRequestOptions(), preferredResolution: String = "") async throws -> ResolvedDownload {
        if let vodID = Self.vodID(from: url) {
            let pageURL = Self.canonicalURL(vodID: vodID, sourceURL: url)
            let pageHTML = try? await HTTPClient.shared.string(from: pageURL, referer: headers.referer, userAgent: headers.userAgent)
            let body = try Self.graphQLRequestBody(vodID: vodID)
            let tokenData = try await HTTPClient.shared.postJSON(
                to: Self.graphQLURL(sourceURL: pageURL),
                body: body,
                referer: pageURL.absoluteString,
                userAgent: headers.userAgent,
                additionalHeaders: Self.graphQLHeaders()
            )
            let token = try Self.playbackAccessToken(fromGraphQLData: tokenData)
            let playlist = Self.playlistURL(vodID: vodID, token: token, sourceURL: pageURL)
            let hls = try await M3U8Resolver().resolve(
                playlist,
                headers: HTTPRequestOptions(referer: pageURL.absoluteString, userAgent: headers.userAgent),
                preferredResolution: preferredResolution
            )
            let info = Self.pageInfo(fromHTML: pageHTML ?? "", vodID: vodID, pageURL: pageURL)
            return Self.resolvedDownload(fromHLS: hls, info: info, playlistURL: playlist, pageURL: pageURL)
        }

        if let slug = Self.clipSlug(from: url) {
            let pageURL = Self.canonicalClipURL(slug: slug, sourceURL: url)
            let html = try await HTTPClient.shared.string(from: pageURL, referer: headers.referer, userAgent: headers.userAgent)
            return try await Self.resolvedClipDownload(fromHTML: html, clipSlug: slug, pageURL: pageURL, userAgent: headers.userAgent, preferredResolution: preferredResolution)
        }

        guard let login = Self.liveLogin(from: url) else {
            throw NativeDownloadError.invalidURL(url.absoluteString)
        }
        let pageURL = Self.canonicalLiveURL(login: login, sourceURL: url)
        let pageHTML = try? await HTTPClient.shared.string(from: pageURL, referer: headers.referer, userAgent: headers.userAgent)
        let body = try Self.graphQLRequestBody(liveLogin: login)
        let tokenData = try await HTTPClient.shared.postJSON(
            to: Self.graphQLURL(sourceURL: pageURL),
            body: body,
            referer: pageURL.absoluteString,
            userAgent: headers.userAgent,
            additionalHeaders: Self.graphQLHeaders()
        )
        let token = try Self.playbackAccessToken(fromGraphQLData: tokenData)
        let playlist = Self.livePlaylistURL(login: login, token: token, sourceURL: pageURL)
        let hls = try await M3U8Resolver().resolve(
            playlist,
            headers: HTTPRequestOptions(referer: pageURL.absoluteString, userAgent: headers.userAgent),
            preferredResolution: preferredResolution
        )
        let info = Self.livePageInfo(fromHTML: pageHTML ?? "", login: login, pageURL: pageURL)
        return Self.resolvedLiveDownload(fromHLS: hls, info: info, playlistURL: playlist, pageURL: pageURL)
    }

    static func vodID(from url: URL) -> String? {
        guard let host = url.host?.lowercased(),
              isSupportedHost(host),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }

        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        let lower = parts.map { $0.lowercased() }
        if lower.count >= 2, lower[0] == "videos", isNumericID(parts[1]) {
            return parts[1]
        }
        return nil
    }

    static func clipSlug(from url: URL) -> String? {
        guard let host = url.host?.lowercased(),
              isSupportedHost(host),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }

        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        let lower = parts.map { $0.lowercased() }

        if host == "clips.twitch.tv" || host == "clips.twitch.test" {
            guard let slug = parts.first, isValidClipSlug(slug) else { return nil }
            return slug
        }

        if let clipIndex = lower.firstIndex(of: "clip"),
           clipIndex + 1 < parts.count,
           isValidClipSlug(parts[clipIndex + 1]) {
            return parts[clipIndex + 1]
        }
        return nil
    }

    static func liveLogin(from url: URL) -> String? {
        guard let host = url.host?.lowercased(),
              isSupportedHost(host),
              !host.hasPrefix("clips."),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }

        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        let login: String
        if parts.count == 1 {
            login = parts[0]
        } else {
            return nil
        }
        guard isValidLiveLogin(login),
              !reservedLiveLogins.contains(login.lowercased()) else {
            return nil
        }
        return login
    }

    static func canonicalURL(vodID: String, sourceURL: URL) -> URL {
        var components = URLComponents()
        components.scheme = sourceURL.scheme ?? "https"
        components.host = sourceURL.host?.lowercased().hasSuffix(".test") == true ? "www.twitch.test" : "www.twitch.tv"
        components.path = "/videos/\(vodID)"
        return components.url!
    }

    static func canonicalClipURL(slug: String, sourceURL: URL) -> URL {
        var components = URLComponents()
        components.scheme = sourceURL.scheme ?? "https"
        components.host = sourceURL.host?.lowercased().hasSuffix(".test") == true ? "clips.twitch.test" : "clips.twitch.tv"
        components.path = "/\(slug)"
        return components.url!
    }

    static func canonicalLiveURL(login: String, sourceURL: URL) -> URL {
        var components = URLComponents()
        components.scheme = sourceURL.scheme ?? "https"
        components.host = sourceURL.host?.lowercased().hasSuffix(".test") == true ? "www.twitch.test" : "www.twitch.tv"
        components.path = "/\(login)"
        return components.url!
    }

    static func canonicalURL(for url: URL) -> URL? {
        if let vodID = vodID(from: url) {
            return canonicalURL(vodID: vodID, sourceURL: url)
        }
        if let slug = clipSlug(from: url) {
            return canonicalClipURL(slug: slug, sourceURL: url)
        }
        if let login = liveLogin(from: url) {
            return canonicalLiveURL(login: login, sourceURL: url)
        }
        return nil
    }

    static func graphQLURL(sourceURL: URL) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = sourceURL.host?.lowercased().hasSuffix(".test") == true ? "gql.twitch.test" : "gql.twitch.tv"
        components.path = "/gql"
        return components.url!
    }

    static func playlistURL(vodID: String, token: TwitchPlaybackAccessToken, sourceURL: URL) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = sourceURL.host?.lowercased().hasSuffix(".test") == true ? "usher.ttvnw.test" : "usher.ttvnw.net"
        components.path = "/vod/\(vodID).m3u8"
        components.queryItems = [
            URLQueryItem(name: "allow_source", value: "true"),
            URLQueryItem(name: "allow_audio_only", value: "true"),
            URLQueryItem(name: "allow_spectre", value: "true"),
            URLQueryItem(name: "player", value: "twitchweb"),
            URLQueryItem(name: "nauthsig", value: token.signature),
            URLQueryItem(name: "nauth", value: token.value)
        ]
        return components.url!
    }

    static func livePlaylistURL(login: String, token: TwitchPlaybackAccessToken, sourceURL: URL) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = sourceURL.host?.lowercased().hasSuffix(".test") == true ? "usher.ttvnw.test" : "usher.ttvnw.net"
        components.path = "/api/channel/hls/\(login).m3u8"
        components.queryItems = [
            URLQueryItem(name: "allow_source", value: "true"),
            URLQueryItem(name: "allow_audio_only", value: "true"),
            URLQueryItem(name: "allow_spectre", value: "true"),
            URLQueryItem(name: "player", value: "twitchweb"),
            URLQueryItem(name: "p", value: "987654"),
            URLQueryItem(name: "type", value: "any"),
            URLQueryItem(name: "sig", value: token.signature),
            URLQueryItem(name: "token", value: token.value)
        ]
        return components.url!
    }

    static func graphQLRequestBody(vodID: String) throws -> Data {
        let object: [String: Any] = [
            "operationName": "PlaybackAccessToken_Template",
            "query": playbackTokenQuery,
            "variables": [
                "isLive": false,
                "login": "",
                "isVod": true,
                "vodID": vodID,
                "playerType": "site"
            ]
        ]
        return try JSONSerialization.data(withJSONObject: object)
    }

    static func graphQLRequestBody(liveLogin: String) throws -> Data {
        let object: [String: Any] = [
            "operationName": "PlaybackAccessToken_Template",
            "query": playbackTokenQuery,
            "variables": [
                "isLive": true,
                "login": liveLogin,
                "isVod": false,
                "vodID": "",
                "playerType": "site"
            ]
        ]
        return try JSONSerialization.data(withJSONObject: object)
    }

    static func playbackAccessToken(fromGraphQLData data: Data) throws -> TwitchPlaybackAccessToken {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let token = playbackAccessToken(in: object) else {
            throw NativeDownloadError.noFiles
        }
        return token
    }

    static func pageInfo(fromHTML html: String, vodID: String, pageURL: URL) -> (id: String, title: String, displayTitle: String, uploader: String, username: String, thumbnail: URL?) {
        let rawTitle = metaContent(from: html, names: ["og:title", "twitter:title"]) ??
            titleTag(fromHTML: html) ??
            "Twitch VOD \(vodID)"
        let title = cleanTitle(rawTitle, fallback: "Twitch VOD \(vodID)")
        let uploader = cleanTitle(
            firstCapture(pattern: #""displayName"\s*:\s*"([^"]+)""#, in: html) ??
                firstCapture(pattern: #""display_name"\s*:\s*"([^"]+)""#, in: html) ??
                firstCapture(pattern: #""owner"\s*:\s*\{[^{}]*"name"\s*:\s*"([^"]+)""#, in: html) ??
                "",
            fallback: ""
        )
        let username = cleanTitle(
            firstCapture(pattern: #""login"\s*:\s*"([^"]+)""#, in: html) ??
                firstCapture(pattern: #""userLogin"\s*:\s*"([^"]+)""#, in: html) ??
                "",
            fallback: ""
        )
        let displayTitle = uploader.isEmpty ? title : "\(uploader) - \(title)"
        let thumbnailRaw = metaContent(from: html, names: ["og:image", "twitter:image"])
        return (vodID, title, displayTitle.sanitizedFilename(maxLength: 120), uploader, username, thumbnailRaw.flatMap { absoluteURL($0, baseURL: pageURL) })
    }

    static func livePageInfo(fromHTML html: String, login: String, pageURL: URL) -> (id: String, title: String, displayTitle: String, uploader: String, username: String, thumbnail: URL?) {
        let rawTitle = firstCapture(pattern: #""(?:broadcastTitle|streamTitle|status)"\s*:\s*"([^"]+)""#, in: html) ??
            metaContent(from: html, names: ["og:title", "twitter:title"]) ??
            titleTag(fromHTML: html) ??
            "Twitch Live \(login)"
        let title = cleanTitle(rawTitle, fallback: "Twitch Live \(login)")
        let uploader = cleanTitle(
            firstCapture(pattern: #""displayName"\s*:\s*"([^"]+)""#, in: html) ??
                firstCapture(pattern: #""display_name"\s*:\s*"([^"]+)""#, in: html) ??
                firstCapture(pattern: #""channel"\s*:\s*\{[^{}]*"displayName"\s*:\s*"([^"]+)""#, in: html) ??
                login,
            fallback: login
        )
        let username = cleanTitle(
            firstCapture(pattern: #""login"\s*:\s*"([^"]+)""#, in: html) ??
                firstCapture(pattern: #""userLogin"\s*:\s*"([^"]+)""#, in: html) ??
                login,
            fallback: login
        )
        let displayTitle = uploader.caseInsensitiveCompare(title) == .orderedSame ? title : "\(uploader) - \(title)"
        let thumbnailRaw = metaContent(from: html, names: ["og:image", "twitter:image"]) ??
            firstCapture(pattern: #""previewImageURL"\s*:\s*"([^"]+)""#, in: html) ??
            firstCapture(pattern: #""thumbnailURL"\s*:\s*"([^"]+)""#, in: html)
        return (login, title, displayTitle.sanitizedFilename(maxLength: 120), uploader, username, thumbnailRaw.flatMap { absoluteURL($0, baseURL: pageURL) })
    }

    static func resolvedDownload(fromHLS hls: ResolvedDownload, info: (id: String, title: String, displayTitle: String, uploader: String, username: String, thumbnail: URL?), playlistURL: URL, pageURL: URL) -> ResolvedDownload {
        let output = "\(info.title)-\(info.id).ts".sanitizedFilename(maxLength: 180)
        let twitchMetadata = metadata(info: info, playlistURL: playlistURL, pageURL: pageURL)
        let adjusted = adjustedTwitchHLSAssets(hls.assets)
        return ResolvedDownload(
            title: info.displayTitle,
            folderName: "Twitch \(info.displayTitle)".sanitizedFilename(maxLength: 120),
            assets: adjusted.assets.enumerated().map { offset, asset in
                var enriched = asset
                enriched.metadata = asset.metadata.merging(segmentMetadata(info: info, asset: asset, pageURL: pageURL, index: offset + 1, kind: "vod")) { current, _ in current }
                return enriched
            },
            packageMode: .concatenate(outputFilename: output),
            metadata: adjustedHLSMetadata(hls.metadata, adjustment: adjusted).merging(twitchMetadata) { _, new in new }
        )
    }

    static func resolvedLiveDownload(fromHLS hls: ResolvedDownload, info: (id: String, title: String, displayTitle: String, uploader: String, username: String, thumbnail: URL?), playlistURL: URL, pageURL: URL) -> ResolvedDownload {
        let output = "\(info.title)-\(info.id).ts".sanitizedFilename(maxLength: 180)
        let twitchMetadata = liveMetadata(info: info, playlistURL: playlistURL, pageURL: pageURL)
        let adjusted = adjustedTwitchHLSAssets(hls.assets)
        return ResolvedDownload(
            title: info.displayTitle,
            folderName: "Twitch \(info.displayTitle)".sanitizedFilename(maxLength: 120),
            assets: adjusted.assets.enumerated().map { offset, asset in
                var enriched = asset
                enriched.metadata = asset.metadata.merging(segmentMetadata(info: info, asset: asset, pageURL: pageURL, index: offset + 1, kind: "live")) { current, _ in current }
                return enriched
            },
            packageMode: .concatenate(outputFilename: output),
            metadata: adjustedHLSMetadata(hls.metadata, adjustment: adjusted).merging(twitchMetadata) { _, new in new }
        )
    }

    static func resolvedClipDownload(fromHTML html: String, clipSlug: String, pageURL: URL, userAgent: String? = nil, preferredResolution: String = "") async throws -> ResolvedDownload {
        guard let candidate = bestClipCandidate(clipCandidates(fromHTML: html, pageURL: pageURL), preferredResolution: preferredResolution) else {
            throw NativeDownloadError.noFiles
        }

        let info = clipPageInfo(fromHTML: html, clipSlug: clipSlug, pageURL: pageURL)
        if isM3U8(candidate.url) {
            let hls = try await M3U8Resolver().resolve(
                candidate.url,
                headers: HTTPRequestOptions(referer: pageURL.absoluteString, userAgent: userAgent),
                preferredResolution: preferredResolution
            )
            let output = "\(info.title)-\(clipSlug).ts".sanitizedFilename(maxLength: 180)
            return ResolvedDownload(
                title: info.displayTitle,
                folderName: "Twitch \(info.displayTitle)".sanitizedFilename(maxLength: 120),
                assets: hlsClipAssetsWithPageMetadata(
                    hls.assets,
                    candidate: candidate,
                    info: info,
                    pageURL: pageURL
                ),
                packageMode: .concatenate(outputFilename: output),
                metadata: hls.metadata.merging(clipMetadata(info: info, mediaURL: candidate.url, pageURL: pageURL, candidate: candidate)) { _, new in new }
            )
        }

        let ext = candidate.url.pathExtension.trimmed.isEmpty ? "mp4" : candidate.url.pathExtension
        let filename = "\(info.title)-\(clipSlug).\(ext)".sanitizedFilename(maxLength: 180)
        return ResolvedDownload(
            title: info.displayTitle,
            folderName: "Twitch \(info.displayTitle)".sanitizedFilename(maxLength: 120),
            assets: [
                ResolvedAsset(
                    remoteURL: candidate.url,
                    filename: filename,
                    metadata: clipMediaMetadata(for: candidate, info: info, pageURL: pageURL),
                    referer: pageURL.absoluteString
                )
            ],
            packageMode: .concatenate(outputFilename: filename),
            metadata: clipMetadata(info: info, mediaURL: candidate.url, pageURL: pageURL, candidate: candidate)
        )
    }

    static func clipCandidates(fromHTML html: String, pageURL: URL) -> [TwitchClipCandidate] {
        let normalized = normalizeEscapes(decodeHTML(html))
        var candidates: [TwitchClipCandidate] = []

        for tag in allCaptures(pattern: #"<(?:video|source)\b[^>]*>"#, in: normalized, group: 0) {
            let label = attributeValue("label", in: tag) ??
                attributeValue("data-quality", in: tag) ??
                attributeValue("title", in: tag) ??
                ""
            for attribute in ["src", "data-src", "data-url", "data-video", "data-file"] {
                if let raw = attributeValue(attribute, in: tag) {
                    appendClipCandidate(rawURL: raw, label: label, pageURL: pageURL, candidates: &candidates)
                }
            }
        }

        for meta in allCaptures(pattern: #"<meta\b[^>]*>"#, in: normalized, group: 0) {
            let name = (attributeValue("property", in: meta) ?? attributeValue("name", in: meta) ?? "").lowercased()
            guard ["og:video", "og:video:url", "og:video:secure_url", "twitter:player:stream"].contains(name),
                  let content = attributeValue("content", in: meta) else {
                continue
            }
            appendClipCandidate(rawURL: content, label: name, pageURL: pageURL, candidates: &candidates)
        }

        for pair in allCaptureGroups(
            pattern: #"\{[^{}]*"(?:quality|qualityText|height|label)"\s*:\s*"([^"]+)"[^{}]*"(?:sourceURL|sourceUrl|videoUrl|videoURL|video_url|playUrl|playURL|url|src)"\s*:\s*"([^"]+)""#,
            in: normalized,
            groups: [1, 2]
        ) {
            appendClipCandidate(rawURL: pair[1], label: pair[0], pageURL: pageURL, candidates: &candidates)
        }
        for pair in allCaptureGroups(
            pattern: #"\{[^{}]*"(?:sourceURL|sourceUrl|videoUrl|videoURL|video_url|playUrl|playURL|url|src)"\s*:\s*"([^"]+)"[^{}]*"(?:quality|qualityText|height|label)"\s*:\s*"([^"]+)""#,
            in: normalized,
            groups: [1, 2]
        ) {
            appendClipCandidate(rawURL: pair[0], label: pair[1], pageURL: pageURL, candidates: &candidates)
        }

        for pattern in [
            #""(?:sourceURL|sourceUrl|videoUrl|videoURL|video_url|playUrl|playURL|url|src)"\s*:\s*"([^"]+)""#,
            #"'(?:sourceURL|sourceUrl|videoUrl|videoURL|video_url|playUrl|playURL|url|src)'\s*:\s*'([^']+)'"#
        ] {
            for raw in allCaptures(pattern: pattern, in: normalized) {
                appendClipCandidate(rawURL: raw, label: "", pageURL: pageURL, candidates: &candidates)
            }
        }

        for raw in allCaptures(pattern: #"(?:https?:)?//[^"'\s<>]+?\.(?:mp4|m3u8)(?:\?[^"'\s<>]*)?"#, in: normalized, group: 0) {
            appendClipCandidate(rawURL: raw, label: "", pageURL: pageURL, candidates: &candidates)
        }

        return uniqueClipCandidates(candidates)
    }

    private static func graphQLHeaders() -> [String: String] {
        [
            "Client-ID": clientID,
            "Content-Type": "application/json",
            "Accept": "application/json"
        ]
    }

    private static func playbackAccessToken(in value: Any) -> TwitchPlaybackAccessToken? {
        if let array = value as? [Any] {
            for child in array {
                if let token = playbackAccessToken(in: child) {
                    return token
                }
            }
            return nil
        }

        guard let dict = value as? [String: Any] else {
            return nil
        }
        if let tokenDict = dict["videoPlaybackAccessToken"] as? [String: Any],
           let token = token(from: tokenDict) {
            return token
        }
        if let tokenDict = dict["streamPlaybackAccessToken"] as? [String: Any],
           let token = token(from: tokenDict) {
            return token
        }
        if let token = token(from: dict),
           dict["__typename"] as? String == "PlaybackAccessToken" || dict.keys.contains("authorization") {
            return token
        }
        for child in dict.values {
            if let token = playbackAccessToken(in: child) {
                return token
            }
        }
        return nil
    }

    private static func token(from dict: [String: Any]) -> TwitchPlaybackAccessToken? {
        guard let value = stringValue(dict["value"]),
              let signature = stringValue(dict["signature"]),
              !value.isEmpty,
              !signature.isEmpty else {
            return nil
        }
        return TwitchPlaybackAccessToken(value: value, signature: signature)
    }

    private static func metadata(info: (id: String, title: String, displayTitle: String, uploader: String, username: String, thumbnail: URL?), playlistURL: URL, pageURL: URL) -> [String: String] {
        DownloadMetadata.clean([
            "site": "Twitch",
            "title": info.title,
            "series": info.uploader,
            "artist": info.uploader,
            "author": info.uploader,
            "creator": info.uploader,
            "uploader": info.uploader,
            "channel": info.uploader,
            "user": info.username,
            "username": info.username,
            "category": "video",
            "type": "hls",
            "media_type": "hls",
            "format": "m3u8",
            "host": pageURL.host ?? "",
            "id": info.id,
            "vod_id": info.id,
            "video_id": info.id,
            "media_id": info.id,
            "gallery_id": info.id,
            "video_count": "1",
            "thumbnail": info.thumbnail?.absoluteString ?? "",
            "playlist_url": playlistURL.absoluteString,
            "url": pageURL.absoluteString,
            "source_url": pageURL.absoluteString,
            "page_url": pageURL.absoluteString
        ])
    }

    private static func liveMetadata(info: (id: String, title: String, displayTitle: String, uploader: String, username: String, thumbnail: URL?), playlistURL: URL, pageURL: URL) -> [String: String] {
        DownloadMetadata.clean([
            "site": "Twitch",
            "title": info.title,
            "series": info.uploader,
            "artist": info.uploader,
            "author": info.uploader,
            "creator": info.uploader,
            "uploader": info.uploader,
            "channel": info.uploader,
            "user": info.username,
            "username": info.username,
            "category": "video",
            "type": "live",
            "media_type": "live",
            "format": "m3u8",
            "live": "true",
            "host": pageURL.host ?? "",
            "id": info.id,
            "live_login": info.id,
            "channel_login": info.username,
            "video_id": info.id,
            "media_id": info.id,
            "gallery_id": info.id,
            "video_count": "1",
            "thumbnail": info.thumbnail?.absoluteString ?? "",
            "playlist_url": playlistURL.absoluteString,
            "url": pageURL.absoluteString,
            "source_url": pageURL.absoluteString,
            "page_url": pageURL.absoluteString
        ])
    }

    private static func segmentMetadata(
        info: (id: String, title: String, displayTitle: String, uploader: String, username: String, thumbnail: URL?),
        asset: ResolvedAsset,
        pageURL: URL,
        index: Int,
        kind: String
    ) -> [String: String] {
        let filenameExtension = (asset.filename as NSString).pathExtension
        let format = asset.remoteURL.pathExtension.isEmpty ? (filenameExtension.isEmpty ? "ts" : filenameExtension) : asset.remoteURL.pathExtension
        var metadata = [
            "site": "Twitch",
            "title": info.title,
            "series": info.uploader,
            "artist": info.uploader,
            "author": info.uploader,
            "creator": info.uploader,
            "uploader": info.uploader,
            "channel": info.uploader,
            "user": info.username,
            "username": info.username,
            "category": "video",
            "type": "hls_segment",
            "media_type": "segment",
            "format": format.lowercased(),
            "media_format": format.lowercased(),
            "id": info.id,
            "video_id": info.id,
            "media_id": "\(info.id)-segment-\(index)",
            "gallery_id": info.id,
            "page": String(index),
            "position": String(index),
            "source_url": pageURL.absoluteString,
            "page_url": pageURL.absoluteString
        ]
        metadata[kind == "live" ? "live_login" : "vod_id"] = info.id
        return DownloadMetadata.clean(metadata)
    }

    private static func adjustedTwitchHLSAssets(_ assets: [ResolvedAsset]) -> TwitchHLSAdjustment {
        var adjusted: [ResolvedAsset] = []
        var strippedAdSegments = 0
        var recoveredMutedSegments = 0

        for asset in assets {
            if isTwitchAdSegment(asset) {
                strippedAdSegments += 1
                continue
            }

            if let unmutedURL = unmutedRecoveryURL(for: asset.remoteURL) {
                var unmuted = copyAsset(asset, remoteURL: unmutedURL)
                unmuted.metadata["twitch_unmuted_recovery"] = "true"
                unmuted.metadata["original_muted_url"] = asset.remoteURL.absoluteString
                unmuted.metadata["media_url"] = unmutedURL.absoluteString
                unmuted.metadata["video_url"] = unmutedURL.absoluteString
                unmuted.metadata["source_url"] = unmutedURL.absoluteString
                adjusted.append(unmuted)

                var muted = asset
                muted.metadata["twitch_muted_segment"] = "true"
                adjusted.append(muted)
                recoveredMutedSegments += 1
            } else {
                adjusted.append(asset)
            }
        }

        return TwitchHLSAdjustment(
            assets: renumberedHLSAssets(adjusted),
            strippedAdSegments: strippedAdSegments,
            recoveredMutedSegments: recoveredMutedSegments
        )
    }

    static func adjustedLiveHLSAssetsForRefresh(_ assets: [ResolvedAsset]) -> [ResolvedAsset] {
        adjustedTwitchHLSAssets(assets).assets
    }

    private static func adjustedHLSMetadata(_ metadata: [String: String], adjustment: TwitchHLSAdjustment) -> [String: String] {
        let mapCount = adjustment.assets.filter { $0.metadata["type"] == "hls_map" || $0.filename.contains("-map.") }.count
        let segmentCount = adjustment.assets.filter { $0.metadata["type"] == "hls_segment" }.count
        var updated = metadata
        updated["media_count"] = String(adjustment.assets.count)
        updated["segment_count"] = String(segmentCount)
        updated["total_segments"] = String(segmentCount)
        updated["map_count"] = String(mapCount)
        if adjustment.strippedAdSegments > 0 {
            updated["strip_ads"] = "true"
            updated["twitch_ad_segments_stripped"] = String(adjustment.strippedAdSegments)
        }
        if adjustment.recoveredMutedSegments > 0 {
            updated["twitch_muted_segments_recovered"] = String(adjustment.recoveredMutedSegments)
        }
        return DownloadMetadata.clean(updated)
    }

    private static func isTwitchAdSegment(_ asset: ResolvedAsset) -> Bool {
        guard asset.metadata["type"] == "hls_segment" else { return false }
        let title = [
            asset.metadata["segment_title"],
            asset.metadata["hls_title"]
        ]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
        return title.contains("amazon")
    }

    private static func unmutedRecoveryURL(for url: URL) -> URL? {
        let value = url.absoluteString
        guard value.contains("-muted") else { return nil }
        return URL(string: value.replacingOccurrences(of: "-muted", with: ""))
    }

    private static func copyAsset(_ asset: ResolvedAsset, remoteURL: URL) -> ResolvedAsset {
        ResolvedAsset(
            remoteURL: remoteURL,
            filename: asset.filename,
            metadata: asset.metadata,
            referer: asset.referer,
            userAgent: asset.userAgent,
            additionalHeaders: asset.additionalHeaders,
            decryption: asset.decryption,
            xorKey: asset.xorKey,
            pixivGridShuffle: asset.pixivGridShuffle,
            pixivUgoiraPackage: asset.pixivUgoiraPackage,
            lezhinImageShuffle: asset.lezhinImageShuffle,
            pythonSegmentDecorator: asset.pythonSegmentDecorator
        )
    }

    private static func renumberedHLSAssets(_ assets: [ResolvedAsset]) -> [ResolvedAsset] {
        let segmentTotal = assets.filter { $0.metadata["type"] == "hls_segment" }.count
        var segmentNumber = 0
        return assets.enumerated().map { offset, asset in
            var copy = asset
            copy.filename = hlsFilename(for: copy, index: offset)
            copy.metadata["page"] = String(offset + 1)
            copy.metadata["position"] = String(offset + 1)
            copy.metadata["segment_index"] = String(offset)
            if copy.metadata["type"] == "hls_segment" {
                segmentNumber += 1
                copy.metadata["segment_number"] = String(segmentNumber)
                copy.metadata["segment_total"] = String(segmentTotal)
                copy.metadata["total_segments"] = String(segmentTotal)
            }
            return copy
        }
    }

    private static func hlsFilename(for asset: ResolvedAsset, index: Int) -> String {
        let filenameExtension = (asset.filename as NSString).pathExtension
        let remoteExtension = asset.remoteURL.pathExtension
        let ext = (filenameExtension.trimmed.isEmpty ? (remoteExtension.trimmed.isEmpty ? "ts" : remoteExtension) : filenameExtension).lowercased()
        let suffix = asset.metadata["type"] == "hls_map" ? "-map" : ""
        return String(format: "%06d%@.%@", index, suffix, ext).sanitizedFilename()
    }

    private static func clipPageInfo(fromHTML html: String, clipSlug: String, pageURL: URL) -> (id: String, title: String, displayTitle: String, uploader: String, username: String, thumbnail: URL?) {
        let rawTitle = metaContent(from: html, names: ["og:title", "twitter:title"]) ??
            firstCapture(pattern: #""title"\s*:\s*"([^"]+)""#, in: html) ??
            titleTag(fromHTML: html) ??
            "Twitch Clip \(clipSlug)"
        let title = cleanTitle(rawTitle, fallback: "Twitch Clip \(clipSlug)")
        let uploader = cleanTitle(
            firstCapture(pattern: #""broadcasterDisplayName"\s*:\s*"([^"]+)""#, in: html) ??
                firstCapture(pattern: #""broadcaster"\s*:\s*\{[^{}]*"displayName"\s*:\s*"([^"]+)""#, in: html) ??
                firstCapture(pattern: #""displayName"\s*:\s*"([^"]+)""#, in: html) ??
                firstCapture(pattern: #""channelName"\s*:\s*"([^"]+)""#, in: html) ??
                metaContent(from: html, names: ["author"]) ??
                "",
            fallback: ""
        )
        let username = cleanTitle(
            firstCapture(pattern: #""broadcasterLogin"\s*:\s*"([^"]+)""#, in: html) ??
                firstCapture(pattern: #""broadcaster"\s*:\s*\{[^{}]*"login"\s*:\s*"([^"]+)""#, in: html) ??
                firstCapture(pattern: #""login"\s*:\s*"([^"]+)""#, in: html) ??
                "",
            fallback: ""
        )
        let displayTitle = uploader.isEmpty ? title : "\(uploader) - \(title)"
        let thumbnailRaw = metaContent(from: html, names: ["og:image", "twitter:image"]) ??
            firstCapture(pattern: #""thumbnailURL"\s*:\s*"([^"]+)""#, in: html) ??
            firstCapture(pattern: #""thumbnailUrl"\s*:\s*"([^"]+)""#, in: html)
        return (clipSlug, title, displayTitle.sanitizedFilename(maxLength: 120), uploader, username, thumbnailRaw.flatMap { absoluteURL($0, baseURL: pageURL) })
    }

    private static func clipMetadata(info: (id: String, title: String, displayTitle: String, uploader: String, username: String, thumbnail: URL?), mediaURL: URL, pageURL: URL, candidate: TwitchClipCandidate) -> [String: String] {
        DownloadMetadata.clean([
            "site": "Twitch",
            "title": info.title,
            "series": info.uploader,
            "artist": info.uploader,
            "author": info.uploader,
            "creator": info.uploader,
            "uploader": info.uploader,
            "channel": info.uploader,
            "user": info.username,
            "username": info.username,
            "category": "video",
            "type": isM3U8(mediaURL) ? "hls" : "clip",
            "media_type": isM3U8(mediaURL) ? "hls" : "clip",
            "format": mediaFormat(for: mediaURL),
            "media_format": mediaFormat(for: mediaURL),
            "host": pageURL.host ?? "",
            "id": info.id,
            "clip_id": info.id,
            "video_id": info.id,
            "media_id": info.id,
            "gallery_id": info.id,
            "media_count": "1",
            "video_count": "1",
            "height": clipHeight(for: candidate).map(String.init) ?? "",
            "resolution": clipResolution(for: candidate),
            "quality": clipQualityLabel(for: candidate),
            "thumbnail": info.thumbnail?.absoluteString ?? "",
            "video_url": mediaURL.absoluteString,
            "media_url": mediaURL.absoluteString,
            "playlist_url": isM3U8(mediaURL) ? mediaURL.absoluteString : "",
            "url": pageURL.absoluteString,
            "source_url": pageURL.absoluteString,
            "page_url": pageURL.absoluteString
        ])
    }

    private static func clipMediaMetadata(
        for candidate: TwitchClipCandidate,
        info: (id: String, title: String, displayTitle: String, uploader: String, username: String, thumbnail: URL?),
        pageURL: URL
    ) -> [String: String] {
        DownloadMetadata.clean([
            "site": "Twitch",
            "title": info.title,
            "series": info.uploader,
            "artist": info.uploader,
            "author": info.uploader,
            "creator": info.uploader,
            "uploader": info.uploader,
            "channel": info.uploader,
            "user": info.username,
            "username": info.username,
            "category": "video",
            "type": isM3U8(candidate.url) ? "hls" : "clip",
            "media_type": isM3U8(candidate.url) ? "hls" : "clip",
            "format": mediaFormat(for: candidate.url),
            "media_format": mediaFormat(for: candidate.url),
            "id": info.id,
            "clip_id": info.id,
            "video_id": info.id,
            "media_id": info.id,
            "gallery_id": info.id,
            "page": "1",
            "position": "1",
            "height": clipHeight(for: candidate).map(String.init) ?? "",
            "resolution": clipResolution(for: candidate),
            "quality": clipQualityLabel(for: candidate),
            "video_url": candidate.url.absoluteString,
            "media_url": candidate.url.absoluteString,
            "source_url": pageURL.absoluteString,
            "page_url": pageURL.absoluteString
        ])
    }

    static func hlsClipAssetsWithPageMetadata(_ assets: [ResolvedAsset], candidate: TwitchClipCandidate, info: (id: String, title: String, displayTitle: String, uploader: String, username: String, thumbnail: URL?), pageURL: URL) -> [ResolvedAsset] {
        assets.enumerated().map { offset, asset in
            var enriched = asset
            enriched.metadata = asset.metadata.merging(clipSegmentMetadata(
                for: candidate,
                info: info,
                pageURL: pageURL,
                asset: asset,
                index: offset + 1
            )) { _, new in new }
            return enriched
        }
    }

    private static func clipSegmentMetadata(for candidate: TwitchClipCandidate, info: (id: String, title: String, displayTitle: String, uploader: String, username: String, thumbnail: URL?), pageURL: URL, asset: ResolvedAsset, index: Int) -> [String: String] {
        let type = asset.metadata["type"] ?? "hls_segment"
        let format = mediaFormat(for: asset.remoteURL, fallback: mediaFormat(forFilename: asset.filename, fallback: "ts"))
        return DownloadMetadata.clean([
            "site": "Twitch",
            "title": info.title,
            "series": info.uploader,
            "artist": info.uploader,
            "author": info.uploader,
            "creator": info.uploader,
            "uploader": info.uploader,
            "channel": info.uploader,
            "user": info.username,
            "username": info.username,
            "category": "video",
            "type": type,
            "media_type": type == "hls_segment" ? "segment" : type,
            "format": format,
            "media_format": format,
            "id": info.id,
            "clip_id": info.id,
            "video_id": info.id,
            "media_id": "\(info.id)-segment-\(index)",
            "gallery_id": info.id,
            "page": String(index),
            "position": String(index),
            "height": clipHeight(for: candidate).map(String.init) ?? "",
            "resolution": clipResolution(for: candidate),
            "quality": clipQualityLabel(for: candidate),
            "thumbnail": info.thumbnail?.absoluteString ?? "",
            "playlist_url": asset.metadata["playlist_url"] ?? candidate.url.absoluteString,
            "video_url": asset.remoteURL.absoluteString,
            "media_url": asset.remoteURL.absoluteString,
            "source_url": pageURL.absoluteString,
            "page_url": pageURL.absoluteString
        ])
    }

    private static func appendClipCandidate(rawURL: String, label: String, pageURL: URL, candidates: inout [TwitchClipCandidate]) {
        guard let url = absoluteURL(rawURL, baseURL: pageURL),
              isPlayableClipVideo(url) else {
            return
        }
        candidates.append(TwitchClipCandidate(url: url, quality: clipQuality(label: label, url: url), label: label))
    }

    private static func bestClipCandidate(_ candidates: [TwitchClipCandidate], preferredResolution: String = "") -> TwitchClipCandidate? {
        var pool = candidates
        if let preferredHeight = preferredHeight(from: preferredResolution) {
            let bounded = candidates.filter { candidate in
                guard let height = clipHeight(for: candidate) else { return false }
                return height <= preferredHeight
            }
            if !bounded.isEmpty {
                pool = bounded
            }
        }

        return pool.max { lhs, rhs in
            if lhs.quality != rhs.quality {
                return lhs.quality < rhs.quality
            }
            if isDirectClipVideo(lhs.url) != isDirectClipVideo(rhs.url) {
                return !isDirectClipVideo(lhs.url) && isDirectClipVideo(rhs.url)
            }
            return lhs.url.absoluteString < rhs.url.absoluteString
        }
    }

    private static func preferredHeight(from preferredResolution: String) -> Int? {
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

    private static func uniqueClipCandidates(_ candidates: [TwitchClipCandidate]) -> [TwitchClipCandidate] {
        var seen = Set<String>()
        return candidates.filter { candidate in
            let key = URLIdentity.normalize(candidate.url.absoluteString)
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }

    private static func clipQuality(label: String, url: URL) -> Int {
        let labelText = label.lowercased()
        if labelText.contains("source") || labelText.contains("chunked") || labelText.contains("original") {
            return 10_000
        }
        for source in [label, url.absoluteString] {
            let values = allCaptures(pattern: #"([0-9]{3,4})\s*p?"#, in: source)
                .compactMap(Int.init)
                .filter { (240...8640).contains($0) }
            if let best = values.max() {
                return best
            }
        }
        return 0
    }

    private static func mediaFormat(for url: URL) -> String {
        if isM3U8(url) { return "m3u8" }
        let ext = url.pathExtension.lowercased()
        return ext.isEmpty ? "mp4" : ext
    }

    private static func mediaFormat(for url: URL, fallback: String) -> String {
        let ext = url.pathExtension.lowercased()
        return ext.isEmpty ? fallback : ext
    }

    private static func mediaFormat(forFilename filename: String, fallback: String) -> String {
        let ext = (filename as NSString).pathExtension.lowercased()
        return ext.isEmpty ? fallback : ext
    }

    private static func clipHeight(for candidate: TwitchClipCandidate) -> Int? {
        if candidate.quality > 0 && candidate.quality < 10_000 {
            return candidate.quality
        }
        for source in [candidate.label, candidate.url.absoluteString] {
            let values = allCaptures(pattern: #"([0-9]{3,4})\s*p?"#, in: source)
                .compactMap(Int.init)
                .filter { (240...8640).contains($0) }
            if let best = values.max() {
                return best
            }
        }
        return nil
    }

    private static func clipResolution(for candidate: TwitchClipCandidate) -> String {
        clipHeight(for: candidate).map { "\($0)p" } ?? ""
    }

    private static func clipQualityLabel(for candidate: TwitchClipCandidate) -> String {
        let resolution = clipResolution(for: candidate)
        return resolution.isEmpty ? candidate.label : resolution
    }

    private static func isPlayableClipVideo(_ url: URL) -> Bool {
        let lower = url.absoluteString.lowercased()
        return ["mp4", "m4v", "mov", "webm", "m3u8"].contains(url.pathExtension.lowercased()) ||
            lower.contains(".mp4") ||
            lower.contains(".m3u8") ||
            lower.contains(".webm")
    }

    private static func isDirectClipVideo(_ url: URL) -> Bool {
        ["mp4", "m4v", "mov", "webm"].contains(url.pathExtension.lowercased()) ||
            url.absoluteString.lowercased().contains(".mp4")
    }

    private static func isM3U8(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "m3u8" || url.absoluteString.lowercased().contains(".m3u8")
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

    private static func attributeValue(_ name: String, in tag: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        return firstCapture(pattern: #"\b\#(escaped)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>"']+))"#, in: tag, groups: [1, 2, 3])
    }

    private static func titleTag(fromHTML html: String) -> String? {
        guard let raw = firstCapture(pattern: #"<title\b[^>]*>(.*?)</title>"#, in: html) else {
            return nil
        }
        return stripTags(raw)
    }

    private static func firstCapture(pattern: String, in text: String) -> String? {
        firstCapture(pattern: pattern, in: text, groups: [1])
    }

    private static func firstCapture(pattern: String, in text: String, groups: [Int]) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
              !groups.isEmpty else {
            return nil
        }
        for group in groups {
            guard match.numberOfRanges > group,
                  let range = Range(match.range(at: group), in: text) else {
                continue
            }
            return String(text[range])
        }
        return nil
    }

    private static func allCaptures(pattern: String, in text: String, group: Int = 1) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > group,
                  let capture = Range(match.range(at: group), in: text) else {
                return nil
            }
            return String(text[capture])
        }
    }

    private static func allCaptureGroups(pattern: String, in text: String, groups: [Int]) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            var values: [String] = []
            for group in groups {
                guard match.numberOfRanges > group,
                      let capture = Range(match.range(at: group), in: text) else {
                    return nil
                }
                values.append(String(text[capture]))
            }
            return values
        }
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
        host == "twitch.tv" ||
            host == "www.twitch.tv" ||
            host == "m.twitch.tv" ||
            host == "clips.twitch.tv" ||
            host == "twitch.test" ||
            host == "www.twitch.test" ||
            host == "m.twitch.test" ||
            host == "clips.twitch.test"
    }

    private static func isNumericID(_ value: String) -> Bool {
        value.range(of: #"^[0-9]{4,}$"#, options: .regularExpression) != nil
    }

    private static func isValidClipSlug(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z0-9][A-Za-z0-9_-]*$"#, options: .regularExpression) != nil
    }

    private static func isValidLiveLogin(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z0-9_]{3,25}$"#, options: .regularExpression) != nil
    }

    private static func cleanTitle(_ raw: String, fallback: String) -> String {
        var title = decodeHTML(stripTags(raw))
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmed
        title = title.replacingOccurrences(of: #"(?i)\s*-\s*Twitch\s*$"#, with: "", options: .regularExpression)
        title = title.replacingOccurrences(of: #"(?i)\s*\|\s*Twitch\s*$"#, with: "", options: .regularExpression)
        title = title.replacingOccurrences(of: #"(?i)^Twitch\s*[-:]\s*"#, with: "", options: .regularExpression)
        return title.isEmpty ? fallback.sanitizedFilename(maxLength: 120) : title.sanitizedFilename(maxLength: 120)
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
}
