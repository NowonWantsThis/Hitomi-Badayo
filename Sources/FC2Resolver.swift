import Foundation

final class FC2Resolver {
    func canResolve(_ url: URL) -> Bool {
        Self.contentID(from: url) != nil
    }

    func resolve(_ url: URL, headers: HTTPRequestOptions = HTTPRequestOptions()) async throws -> ResolvedDownload {
        guard let id = Self.contentID(from: url),
              let pageURL = Self.canonicalURL(for: url) else {
            throw NativeDownloadError.unsupported("Unsupported FC2 URL.")
        }

        let pageHeaders = await Self.ageConsentHeaders(for: pageURL)
        let html = try await HTTPClient.shared.string(
            from: pageURL,
            referer: headers.referer,
            userAgent: headers.userAgent,
            additionalHeaders: pageHeaders
        )
        guard let token = Self.accessToken(fromHTML: html) else {
            throw NativeDownloadError.unsupported("FC2 video access token was not found.")
        }

        let apiURL = Self.playlistAPIURL(contentID: id, sourceURL: pageURL)
        var apiHeaders = await Self.ageConsentHeaders(for: apiURL)
        apiHeaders["X-FC2-Video-Access-Token"] = token
        let data = try await HTTPClient.shared.data(
            from: apiURL,
            referer: headers.referer ?? pageURL.absoluteString,
            userAgent: headers.userAgent,
            additionalHeaders: apiHeaders
        )
        let videoURL = try Self.videoURL(fromAPIData: data, sourceURL: pageURL)
        let title = Self.title(fromHTML: html, contentID: id)

        if Self.isM3U8(videoURL) {
            let hlsHeaders = await Self.ageConsentHeaders(for: videoURL)
            let hls = try await M3U8Resolver().resolve(
                videoURL,
                headers: HTTPRequestOptions(referer: pageURL.absoluteString, userAgent: headers.userAgent),
                additionalHeaders: hlsHeaders,
                originBoundHeaderNames: ["Cookie"]
            )
            return ResolvedDownload(
                title: title,
                folderName: "FC2 \(title)".sanitizedFilename(maxLength: 120),
                assets: Self.hlsAssetsWithPageMetadata(
                    hls.assets,
                    contentID: id,
                    title: title,
                    pageURL: pageURL,
                    playlistURL: videoURL,
                    html: html
                ),
                packageMode: .concatenate(outputFilename: Self.outputFilename(
                    title: title,
                    contentID: id,
                    fileExtension: "ts"
                )),
                metadata: Self.metadata(contentID: id, title: title, pageURL: pageURL, videoURL: videoURL, html: html)
                    .merging(hls.metadata) { current, _ in current }
            )
        }

        return Self.resolvedDirectDownload(
            videoURL: videoURL,
            pageURL: pageURL,
            pageHTML: html,
            contentID: id,
            additionalHeaders: await Self.ageConsentHeaders(for: videoURL)
        )
    }

    static func contentID(from url: URL) -> String? {
        guard let host = url.host?.lowercased(),
              isSupportedHost(host),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }

        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard let contentIndex = parts.firstIndex(where: { $0.lowercased() == "content" }),
              contentIndex + 1 < parts.count else {
            return nil
        }
        let id = parts[contentIndex + 1].removingPercentEncoding ?? parts[contentIndex + 1]
        return isValidID(id) ? id : nil
    }

    static func canonicalURL(for url: URL) -> URL? {
        guard let id = contentID(from: url) else { return nil }
        return canonicalURL(contentID: id, sourceURL: url)
    }

    static func canonicalURL(contentID id: String, sourceURL: URL? = nil) -> URL? {
        guard isValidID(id) else { return nil }
        var components = URLComponents()
        components.scheme = sourceURL?.scheme ?? "https"
        components.host = sourceURL?.host?.lowercased().hasSuffix(".test") == true ? "video.fc2.com.test" : "video.fc2.com"
        components.path = "/content/\(id)"
        return components.url
    }

    static func playlistAPIURL(contentID: String, sourceURL: URL) -> URL {
        var components = URLComponents()
        components.scheme = sourceURL.scheme ?? "https"
        components.host = sourceURL.host?.lowercased().hasSuffix(".test") == true ? "video.fc2.com.test" : "video.fc2.com"
        components.path = "/api/v3/videoplaylist/\(contentID)"
        components.queryItems = [
            URLQueryItem(name: "sh", value: "1"),
            URLQueryItem(name: "fs", value: "0")
        ]
        return components.url!
    }

    static func accessToken(fromHTML html: String) -> String? {
        firstCapture(
            pattern: #"window\.FC2VideoObject\.push\(\[\[['"]ae['"]\s*,\s*['"]([^'"]+)['"]"#,
            in: html
        )
    }

    static func videoURL(fromAPIData data: Data, sourceURL: URL) throws -> URL {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NativeDownloadError.unsupported("Invalid FC2 playlist JSON.")
        }

        if let original = originalPlaylistURL(from: object, sourceURL: sourceURL) {
            return original
        }

        let candidates = videoCandidates(
            from: object,
            sourceURL: sourceURL,
            preferredKeys: ["playlist", "file", "url", "src", "path", "video", "video_url", "videoUrl"],
            fallbackKeys: ["sample"]
        )
        if let best = bestCandidate(candidates) {
            return best.url
        }

        let fallback = videoCandidates(
            from: object,
            sourceURL: sourceURL,
            preferredKeys: ["sample"],
            fallbackKeys: [],
            includeLooseURLs: false
        )
        if let best = bestCandidate(fallback) {
            return best.url
        }

        throw NativeDownloadError.noFiles
    }

    static func resolvedDirectDownload(
        videoURL: URL,
        pageURL: URL,
        pageHTML: String,
        contentID: String,
        additionalHeaders: [String: String] = [:]
    ) -> ResolvedDownload {
        let title = title(fromHTML: pageHTML, contentID: contentID)
        let pageMetadata = metadata(contentID: contentID, title: title, pageURL: pageURL, videoURL: videoURL, html: pageHTML)
        return ResolvedDownload(
            title: title,
            folderName: "FC2 \(title)".sanitizedFilename(maxLength: 120),
            assets: [
                ResolvedAsset(
                    remoteURL: videoURL,
                    filename: outputFilename(
                        title: title,
                        contentID: contentID,
                        fileExtension: videoURL.pathExtension.trimmed.isEmpty ? "mp4" : videoURL.pathExtension
                    ),
                    metadata: assetMetadata(for: videoURL, pageMetadata: pageMetadata, pageURL: pageURL, index: 1),
                    referer: pageURL.absoluteString,
                    additionalHeaders: resolvedHeaders(additionalHeaders)
                )
            ],
            metadata: pageMetadata
        )
    }

    static func ageConsentCookieHeader(existing: String?) -> String {
        let retained = (existing ?? "")
            .split(separator: ";", omittingEmptySubsequences: true)
            .map { String($0).trimmed }
            .filter { part in
                guard let separator = part.firstIndex(of: "=") else { return !part.isEmpty }
                return String(part[..<separator]).trimmed.caseInsensitiveCompare("_ac") != .orderedSame
            }
        return (retained + ["_ac=1"]).joined(separator: "; ")
    }

    static func ageConsentHeaders(for url: URL) async -> [String: String] {
        guard isAgeConsentHost(url.host?.lowercased() ?? "") else { return [:] }
        let existing = await CookieStore.shared.cookieHeader(for: url)
        return ["Cookie": ageConsentCookieHeader(existing: existing)]
    }

    private static func originalPlaylistURL(from object: [String: Any], sourceURL: URL) -> URL? {
        guard let playlist = firstValue(in: object, matching: "playlist") as? [String: Any] else {
            return nil
        }
        for key in ["hq", "nq", "sample"] {
            guard let raw = stringValue(firstValue(in: playlist, matching: key))?.trimmed,
                  !raw.isEmpty,
                  let url = absoluteURL(raw, baseURL: sourceURL) else {
                continue
            }
            return url
        }
        return nil
    }

    private struct FC2VideoCandidate {
        let url: URL
        let height: Int
        let score: Int64
    }

    private static func videoCandidates(
        from value: Any,
        sourceURL: URL,
        preferredKeys: [String],
        fallbackKeys: Set<String> = [],
        includeLooseURLs: Bool = true
    ) -> [FC2VideoCandidate] {
        var candidates: [FC2VideoCandidate] = []
        collectVideoCandidates(
            from: value,
            sourceURL: sourceURL,
            preferredKeys: preferredKeys.map { $0.lowercased() },
            fallbackKeys: Set(fallbackKeys.map { $0.lowercased() }),
            keyPath: [],
            isPreferredPath: false,
            includeLooseURLs: includeLooseURLs,
            into: &candidates
        )
        var bestByURL: [String: FC2VideoCandidate] = [:]
        for candidate in candidates {
            let key = candidate.url.absoluteString.lowercased()
            if let current = bestByURL[key], current.score >= candidate.score {
                continue
            }
            bestByURL[key] = candidate
        }
        return Array(bestByURL.values)
    }

    private static func collectVideoCandidates(
        from value: Any,
        sourceURL: URL,
        preferredKeys: [String],
        fallbackKeys: Set<String>,
        keyPath: [String],
        isPreferredPath: Bool,
        includeLooseURLs: Bool,
        into candidates: inout [FC2VideoCandidate]
    ) {
        if let dict = value as? [String: Any] {
            if let url = candidateURL(from: dict, sourceURL: sourceURL) {
                candidates.append(candidate(from: url, dictionary: dict, keyPath: keyPath))
            }

            for key in preferredKeys {
                if let nested = firstValue(in: dict, matching: key) {
                    collectVideoCandidates(
                        from: nested,
                        sourceURL: sourceURL,
                        preferredKeys: preferredKeys,
                        fallbackKeys: fallbackKeys,
                        keyPath: keyPath + [key],
                        isPreferredPath: true,
                        includeLooseURLs: includeLooseURLs,
                        into: &candidates
                    )
                }
            }
            for (key, child) in dict {
                let normalizedKey = key.lowercased()
                guard !preferredKeys.contains(normalizedKey),
                      !fallbackKeys.contains(normalizedKey) else {
                    continue
                }
                collectVideoCandidates(
                    from: child,
                    sourceURL: sourceURL,
                    preferredKeys: preferredKeys,
                    fallbackKeys: fallbackKeys,
                    keyPath: keyPath + [key],
                    isPreferredPath: isPreferredPath,
                    includeLooseURLs: includeLooseURLs,
                    into: &candidates
                )
            }
        } else if let array = value as? [Any] {
            for child in array {
                collectVideoCandidates(
                    from: child,
                    sourceURL: sourceURL,
                    preferredKeys: preferredKeys,
                    fallbackKeys: fallbackKeys,
                    keyPath: keyPath,
                    isPreferredPath: isPreferredPath,
                    includeLooseURLs: includeLooseURLs,
                    into: &candidates
                )
            }
        } else if (includeLooseURLs || isPreferredPath),
                  let raw = stringValue(value),
                  let url = absoluteURL(raw, baseURL: sourceURL),
                  isPlayableVideo(url) {
            candidates.append(candidate(from: url, dictionary: nil, keyPath: keyPath))
        }
    }

    private static func bestCandidate(_ candidates: [FC2VideoCandidate]) -> FC2VideoCandidate? {
        candidates.max { lhs, rhs in
            if lhs.score != rhs.score {
                return lhs.score < rhs.score
            }
            if lhs.height != rhs.height {
                return lhs.height < rhs.height
            }
            return lhs.url.absoluteString < rhs.url.absoluteString
        }
    }

    private static func candidateURL(from dict: [String: Any], sourceURL: URL) -> URL? {
        for key in ["playlist", "file", "url", "src", "path", "video", "video_url", "videoUrl", "m3u8", "mp4"] {
            guard let raw = stringValue(firstValue(in: dict, matching: key)),
                  let url = absoluteURL(raw, baseURL: sourceURL),
                  isPlayableVideo(url) else {
                continue
            }
            return url
        }
        return nil
    }

    private static func candidate(from url: URL, dictionary: [String: Any]?, keyPath: [String]) -> FC2VideoCandidate {
        let context = ([url.absoluteString] + keyPath + labelValues(from: dictionary)).joined(separator: " ")
        let height = height(from: dictionary, context: context)
        let bitrate = numericValue(from: dictionary, keys: ["bitrate", "video_bitrate", "videoBitrate", "bandwidth", "tbr", "br"])
        let byteCount = numericValue(from: dictionary, keys: ["filesize", "file_size", "fileSize", "size", "size_bytes", "sizeBytes", "contentLength"])
        let quality = qualityScore(from: context)
        let formatBonus: Int64
        if isM3U8(url) {
            formatBonus = 3_000_000_000
        } else if isPlayableVideo(url) {
            formatBonus = 2_000_000_000
        } else {
            formatBonus = 0
        }
        let samplePenalty: Int64 = context.range(of: #"(?i)\b(sample|preview|trailer)\b"#, options: .regularExpression) == nil ? 0 : -1_000_000_000
        let score = formatBonus +
            samplePenalty +
            Int64(quality) * 1_000_000 +
            Int64(height) * 10_000 +
            min(bitrate, 50_000_000) +
            min(byteCount / 1024, 50_000_000)
        return FC2VideoCandidate(url: url, height: height, score: score)
    }

    private static func firstValue(in dict: [String: Any], matching key: String) -> Any? {
        if let exact = dict[key] {
            return exact
        }
        return dict.first { $0.key.caseInsensitiveCompare(key) == .orderedSame }?.value
    }

    private static func labelValues(from dict: [String: Any]?) -> [String] {
        guard let dict else { return [] }
        return ["quality", "label", "name", "type", "profile", "resolution", "format"]
            .compactMap { stringValue(firstValue(in: dict, matching: $0)) }
    }

    private static func height(from dict: [String: Any]?, context: String) -> Int {
        let explicit = numericValue(from: dict, keys: ["height", "h", "video_height", "videoHeight"])
        if explicit > 0 {
            return Int(min(explicit, Int64(Int.max)))
        }
        if let widthHeight = firstCapture(pattern: #"(?i)(?:^|[^0-9])([0-9]{3,5})\s*[x×]\s*([0-9]{3,5})(?:[^0-9]|$)"#, in: context, captureIndex: 2),
           let height = Int(widthHeight) {
            return height
        }
        if let explicit = firstCapture(pattern: #"(?i)([0-9]{3,4})\s*p\b"#, in: context).flatMap(Int.init) ??
            firstCapture(pattern: #"(?i)\b(hd|src|source|high|hq)[^0-9]{0,8}([0-9]{3,4})\b"#, in: context, captureIndex: 2).flatMap(Int.init) {
            return explicit
        }
        return 0
    }

    private static func qualityScore(from context: String) -> Int {
        let lower = context.lowercased()
        if lower.contains("source") || lower.contains("original") || lower.contains("full") {
            return 10_000
        }
        if let explicit = firstCapture(pattern: #"(?i)([0-9]{3,4})\s*p\b"#, in: context).flatMap(Int.init) {
            return explicit
        }
        if let explicit = firstCapture(pattern: #"(?i)(?:^|[^0-9])([0-9]{3,5})\s*[x×]\s*([0-9]{3,5})(?:[^0-9]|$)"#, in: context, captureIndex: 2).flatMap(Int.init) {
            return explicit
        }
        if lower.contains("fhd") || lower.contains("fullhd") {
            return 1080
        }
        if lower.contains("hd") || lower.contains("high") || lower.contains("hq") {
            return 720
        }
        if lower.contains("sd") || lower.contains("medium") {
            return 480
        }
        if lower.contains("low") {
            return 240
        }
        return 0
    }

    private static func numericValue(from dict: [String: Any]?, keys: [String]) -> Int64 {
        guard let dict else { return 0 }
        for key in keys {
            guard let value = firstValue(in: dict, matching: key) else { continue }
            if let number = value as? NSNumber {
                return number.int64Value
            }
            if let text = stringValue(value)?.replacingOccurrences(of: ",", with: ""),
               let match = firstCapture(pattern: #"([0-9]+(?:\.[0-9]+)?)"#, in: text),
               let parsed = Double(match) {
                let lower = text.lowercased()
                if lower.contains("gb") || lower.contains("gib") {
                    return Int64(parsed * 1_073_741_824)
                }
                if lower.contains("mb") || lower.contains("mib") {
                    return Int64(parsed * 1_048_576)
                }
                if lower.contains("kb") || lower.contains("kib") {
                    return Int64(parsed * 1024)
                }
                return Int64(parsed)
            }
        }
        return 0
    }

    private static func title(fromHTML html: String, contentID: String) -> String {
        let title = elementText(pattern: #"<[^>]*\bclass\s*=\s*["'][^"']*videoCnt_title[^"']*["'][^>]*>(.*?)</[^>]+>"#, in: html) ??
            metaContent(from: html, names: ["og:title", "twitter:title"]) ??
            elementText(pattern: #"<title\b[^>]*>(.*?)</title>"#, in: html) ??
            "FC2 \(contentID)"
        return cleanTitle(title, fallback: "FC2 \(contentID)")
    }

    private static func thumbnailURL(fromHTML html: String, pageURL: URL) -> URL? {
        guard let raw = metaContent(from: html, names: ["og:image", "twitter:image"]) else { return nil }
        return absoluteURL(raw, baseURL: pageURL)
    }

    private static func uploaderName(fromHTML html: String) -> String {
        let raw = metaContent(from: html, names: ["author", "article:author", "twitter:creator"]) ??
            firstCapture(pattern: #""(?:uploader|uploaderName|uploader_name|owner|ownerName|owner_name|memberName|member_name|userName|user_name|nickname|channelName|channel_name)"\s*:\s*"([^"]+)""#, in: html) ??
            elementText(pattern: #"<a\b[^>]*href\s*=\s*["'][^"']*(?:/a/member|/member|/user|/profile)[^"']*["'][^>]*>(.*?)</a>"#, in: html) ??
            elementText(pattern: #"<[^>]*\bclass\s*=\s*["'][^"']*(?:uploader|owner|member|user|profile|channel)[^"']*(?:name|Name)?[^"']*["'][^>]*>(.*?)</[^>]+>"#, in: html)
        let cleaned = raw.map { cleanTitle($0, fallback: "") } ?? ""
        let lower = cleaned.lowercased()
        if cleaned.isEmpty || lower == "fc2" || lower == "fc2 video" || lower == "video.fc2.com" {
            return ""
        }
        return cleaned
    }

    private static func uploaderID(fromHTML html: String) -> String {
        let raw = firstCapture(pattern: #""(?:uploaderId|uploaderID|uploader_id|ownerId|ownerID|owner_id|memberId|memberID|member_id|userId|userID|user_id|channelId|channelID|channel_id)"\s*:\s*"?([A-Za-z0-9_-]+)"?"#, in: html) ??
            firstCapture(pattern: ##"\b(?:member_id|user_id|owner_id|channel_id|mid|uid)\s*=\s*["']?([A-Za-z0-9_-]+)["']?"##, in: html) ??
            firstCapture(pattern: ##"\bhref\s*=\s*["'][^"']*(?:/a/member/|/member/|/user/|/profile/)([A-Za-z0-9_-]+)"##, in: html)
        guard let raw else { return "" }
        return raw.trimmed.sanitizedFilename(maxLength: 120)
    }

    private static func metadata(contentID: String, title: String, pageURL: URL, videoURL: URL, html: String) -> [String: String] {
        let uploader = uploaderName(fromHTML: html)
        let uploaderID = uploaderID(fromHTML: html)
        return DownloadMetadata.clean([
            "site": "FC2",
            "title": title,
            "series": title,
            "category": "video",
            "id": contentID,
            "video_id": contentID,
            "gallery_id": contentID,
            "media_id": contentID,
            "media_count": "1",
            "video_count": "1",
            "type": isM3U8(videoURL) ? "hls" : "video",
            "media_type": isM3U8(videoURL) ? "hls" : "video",
            "format": mediaFormat(for: videoURL),
            "media_format": mediaFormat(for: videoURL),
            "host": pageURL.host ?? "",
            "artist": uploader,
            "author": uploader,
            "creator": uploader,
            "uploader": uploader,
            "channel": uploader,
            "user": uploader,
            "username": uploader,
            "artistid": uploaderID,
            "artist_id": uploaderID,
            "author_id": uploaderID,
            "creator_id": uploaderID,
            "uploader_id": uploaderID,
            "channel_id": uploaderID,
            "user_id": uploaderID,
            "uid": uploaderID,
            "video_url": videoURL.absoluteString,
            "media_url": videoURL.absoluteString,
            "thumbnail": thumbnailURL(fromHTML: html, pageURL: pageURL)?.absoluteString ?? "",
            "url": pageURL.absoluteString,
            "source_url": pageURL.absoluteString,
            "page_url": pageURL.absoluteString
        ])
    }

    private static func assetMetadata(for videoURL: URL, pageMetadata: [String: String], pageURL: URL, index: Int) -> [String: String] {
        DownloadMetadata.clean([
            "site": "FC2",
            "title": pageMetadata["title"] ?? "",
            "series": pageMetadata["series"] ?? "",
            "id": pageMetadata["id"] ?? "",
            "video_id": pageMetadata["video_id"] ?? "",
            "gallery_id": pageMetadata["gallery_id"] ?? "",
            "media_id": pageMetadata["media_id"] ?? "",
            "artist": pageMetadata["artist"] ?? "",
            "author": pageMetadata["author"] ?? "",
            "creator": pageMetadata["creator"] ?? "",
            "uploader": pageMetadata["uploader"] ?? "",
            "channel": pageMetadata["channel"] ?? "",
            "user": pageMetadata["user"] ?? "",
            "username": pageMetadata["username"] ?? "",
            "artistid": pageMetadata["artistid"] ?? "",
            "artist_id": pageMetadata["artist_id"] ?? "",
            "author_id": pageMetadata["author_id"] ?? "",
            "creator_id": pageMetadata["creator_id"] ?? "",
            "uploader_id": pageMetadata["uploader_id"] ?? "",
            "channel_id": pageMetadata["channel_id"] ?? "",
            "user_id": pageMetadata["user_id"] ?? "",
            "uid": pageMetadata["uid"] ?? "",
            "type": isM3U8(videoURL) ? "hls" : "video",
            "media_type": isM3U8(videoURL) ? "hls" : "video",
            "category": "video",
            "page": String(index),
            "position": String(index),
            "format": mediaFormat(for: videoURL),
            "media_format": mediaFormat(for: videoURL),
            "video_url": videoURL.absoluteString,
            "media_url": videoURL.absoluteString,
            "source_url": videoURL.absoluteString,
            "page_url": pageURL.absoluteString
        ])
    }

    static func hlsAssetsWithPageMetadata(_ assets: [ResolvedAsset], contentID: String, title: String, pageURL: URL, playlistURL: URL, html: String) -> [ResolvedAsset] {
        let pageMetadata = metadata(contentID: contentID, title: title, pageURL: pageURL, videoURL: playlistURL, html: html)
        return assets.enumerated().map { offset, asset in
            var enriched = asset
            enriched.metadata = asset.metadata.merging(Self.segmentMetadata(
                contentID: contentID,
                pageMetadata: pageMetadata,
                pageURL: pageURL,
                playlistURL: playlistURL,
                asset: asset,
                index: offset + 1
            )) { _, new in new }
            if !isAgeConsentHost(asset.remoteURL.host?.lowercased() ?? "") {
                enriched.additionalHeaders.removeAll { $0.name.caseInsensitiveCompare("Cookie") == .orderedSame }
            }
            return enriched
        }
    }

    private static func segmentMetadata(contentID: String, pageMetadata: [String: String], pageURL: URL, playlistURL: URL, asset: ResolvedAsset, index: Int) -> [String: String] {
        let type = asset.metadata["type"] ?? "hls_segment"
        let format = mediaFormat(for: asset.remoteURL, fallback: mediaFormat(forFilename: asset.filename, fallback: "ts"))
        return DownloadMetadata.clean([
            "site": "FC2",
            "title": pageMetadata["title"] ?? "",
            "series": pageMetadata["series"] ?? "",
            "id": contentID,
            "video_id": contentID,
            "gallery_id": contentID,
            "media_id": "\(contentID)-segment-\(index)",
            "artist": pageMetadata["artist"] ?? "",
            "author": pageMetadata["author"] ?? "",
            "creator": pageMetadata["creator"] ?? "",
            "uploader": pageMetadata["uploader"] ?? "",
            "channel": pageMetadata["channel"] ?? "",
            "user": pageMetadata["user"] ?? "",
            "username": pageMetadata["username"] ?? "",
            "artistid": pageMetadata["artistid"] ?? "",
            "artist_id": pageMetadata["artist_id"] ?? "",
            "author_id": pageMetadata["author_id"] ?? "",
            "creator_id": pageMetadata["creator_id"] ?? "",
            "uploader_id": pageMetadata["uploader_id"] ?? "",
            "channel_id": pageMetadata["channel_id"] ?? "",
            "user_id": pageMetadata["user_id"] ?? "",
            "uid": pageMetadata["uid"] ?? "",
            "type": type,
            "media_type": type == "hls_segment" ? "segment" : type,
            "category": "video",
            "page": String(index),
            "position": String(index),
            "format": format,
            "media_format": format,
            "thumbnail": pageMetadata["thumbnail"] ?? "",
            "playlist_url": asset.metadata["playlist_url"] ?? playlistURL.absoluteString,
            "video_url": asset.remoteURL.absoluteString,
            "media_url": asset.remoteURL.absoluteString,
            "source_url": pageURL.absoluteString,
            "page_url": pageURL.absoluteString
        ])
    }

    private static func metaContent(from html: String, names: [String]) -> String? {
        for name in names {
            let patterns = [
                #"<meta\b[^>]*(?:property|name)\s*=\s*["']\#(name)["'][^>]*content\s*=\s*["']([^"']+)["'][^>]*>"#,
                #"<meta\b[^>]*content\s*=\s*["']([^"']+)["'][^>]*(?:property|name)\s*=\s*["']\#(name)["'][^>]*>"#
            ]
            for pattern in patterns {
                if let value = firstCapture(pattern: pattern, in: html) {
                    return decodeHTML(value).trimmed
                }
            }
        }
        return nil
    }

    private static func elementText(pattern: String, in html: String) -> String? {
        guard let raw = firstCapture(pattern: pattern, in: html) else { return nil }
        let text = cleanTitle(stripTags(raw), fallback: "")
        return text.isEmpty ? nil : text
    }

    private static func firstCapture(pattern: String, in text: String, captureIndex: Int = 1) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > captureIndex,
              let capture = Range(match.range(at: captureIndex), in: text) else {
            return nil
        }
        return String(text[capture])
    }

    private static func absoluteURL(_ raw: String, baseURL: URL) -> URL? {
        var value = decodeHTML(raw)
            .replacingOccurrences(of: #"\/"#, with: "/")
            .trimmed
        guard !value.isEmpty,
              !value.lowercased().hasPrefix("javascript:"),
              !value.lowercased().hasPrefix("data:") else {
            return nil
        }
        if value.hasPrefix("//") {
            value = (baseURL.scheme ?? "https") + ":" + value
        }
        if let url = URL(string: value, relativeTo: baseURL)?.absoluteURL,
           let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            return url
        }
        return nil
    }

    private static func outputFilename(title: String, contentID: String, fileExtension ext: String) -> String {
        let safeExtension = ext.trimmed.isEmpty ? "mp4" : ext
        return "\(title)-\(contentID).\(safeExtension)".sanitizedFilename(maxLength: 180)
    }

    private static func resolvedHeaders(_ fields: [String: String]) -> [ResolvedRequestHeader] {
        fields
            .filter { !["referer", "user-agent"].contains($0.key.lowercased()) }
            .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
            .map { ResolvedRequestHeader(name: $0.key, value: $0.value) }
    }

    private static func mediaFormat(for url: URL) -> String {
        let pathExtension = url.pathExtension.lowercased()
        if !pathExtension.isEmpty {
            return pathExtension
        }
        let lower = url.absoluteString.lowercased()
        for value in ["m3u8", "mp4", "webm", "mov", "m4v"] where lower.contains(".\(value)") {
            return value
        }
        return ""
    }

    private static func mediaFormat(for url: URL, fallback: String) -> String {
        let format = mediaFormat(for: url)
        return format.isEmpty ? fallback : format
    }

    private static func mediaFormat(forFilename filename: String, fallback: String) -> String {
        let ext = (filename as NSString).pathExtension.lowercased()
        return ext.isEmpty ? fallback : ext
    }

    private static func isPlayableVideo(_ url: URL) -> Bool {
        ["m3u8", "mp4", "webm", "mov", "m4v"].contains(url.pathExtension.lowercased()) ||
            url.absoluteString.lowercased().contains(".m3u8")
    }

    private static func isLikelyVideoURL(_ raw: String) -> Bool {
        let lower = raw.lowercased()
        return lower.contains(".m3u8") ||
            lower.contains(".mp4") ||
            lower.contains(".webm") ||
            lower.contains(".mov") ||
            lower.contains(".m4v")
    }

    private static func isM3U8(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "m3u8" || url.absoluteString.lowercased().contains(".m3u8")
    }

    private static func isSupportedHost(_ host: String) -> Bool {
        host == "fc2.com" ||
            host == "www.fc2.com" ||
            host == "video.fc2.com" ||
            host == "fc2.com.test" ||
            host == "www.fc2.com.test" ||
            host == "video.fc2.com.test"
    }

    private static func isAgeConsentHost(_ host: String) -> Bool {
        host == "video.fc2.com" ||
            host.hasSuffix(".video.fc2.com") ||
            host == "video.fc2.com.test" ||
            host.hasSuffix(".video.fc2.com.test")
    }

    private static func isValidID(_ id: String) -> Bool {
        !id.isEmpty && id.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let string = value as? String {
            return string
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return nil
    }

    private static func stripTags(_ raw: String) -> String {
        raw.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
    }

    private static func decodeHTML(_ raw: String) -> String {
        var text = raw
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#34;", with: "\"")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
        guard let regex = try? NSRegularExpression(pattern: #"&#(?:x([0-9A-Fa-f]+)|([0-9]+));"#) else {
            return text
        }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)).reversed()
        for match in matches {
            guard let whole = Range(match.range(at: 0), in: text) else { continue }
            let scalarValue: UInt32?
            if let hexRange = Range(match.range(at: 1), in: text) {
                scalarValue = UInt32(String(text[hexRange]), radix: 16)
            } else if let decimalRange = Range(match.range(at: 2), in: text) {
                scalarValue = UInt32(String(text[decimalRange]), radix: 10)
            } else {
                scalarValue = nil
            }
            if let scalarValue, let scalar = UnicodeScalar(scalarValue) {
                text.replaceSubrange(whole, with: String(Character(scalar)))
            }
        }
        return text
    }

    private static func cleanTitle(_ raw: String, fallback: String) -> String {
        var text = decodeHTML(stripTags(raw))
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmed
        for suffix in [" - FC2 Video", " | FC2 Video", " - FC2", " | FC2", " - video.fc2.com", " | video.fc2.com"] {
            if text.lowercased().hasSuffix(suffix.lowercased()) {
                text = String(text.dropLast(suffix.count)).trimmed
            }
        }
        return text.isEmpty ? fallback : text
    }
}
