import Foundation

struct NaverBlogID: Hashable {
    var username: String
    var postID: String
}

struct NaverBlogVideoPair: Hashable {
    var videoID: String
    var key: String
}

private struct NaverBlogVideoCandidate {
    var url: URL
    var info: [String: Any]
}

final class NaverBlogResolver {
    func canResolve(_ url: URL) -> Bool {
        Self.postID(from: url) != nil
    }

    func resolve(_ url: URL, headers: HTTPRequestOptions = HTTPRequestOptions()) async throws -> ResolvedDownload {
        guard let id = Self.postID(from: url) else {
            throw NativeDownloadError.invalidURL(url.absoluteString)
        }

        let pageURL = Self.mobilePostURL(for: id, sourceURL: url)
        let html = try await resolvedHTML(from: pageURL, headers: headers, depth: 0)
        var resolved = try Self.resolvedDownload(fromHTML: html, pageURL: pageURL, id: id)
        let videoPairs = Self.videoPairs(fromHTML: html)
        if !videoPairs.isEmpty {
            var assets = resolved.assets
            var seen = Set(assets.map { URLIdentity.normalize($0.remoteURL.absoluteString) })
            for pair in videoPairs {
                let apiURL = Self.videoAPIURL(for: pair, sourceURL: pageURL)
                let data = try await HTTPClient.shared.data(from: apiURL, referer: pageURL.absoluteString, userAgent: headers.userAgent)
                guard let candidate = try Self.videoCandidate(fromAPIData: data, sourceURL: apiURL) else { continue }
                let remote = candidate.url
                let normalized = URLIdentity.normalize(remote.absoluteString)
                guard !seen.contains(normalized) else { continue }
                seen.insert(normalized)
                let filename = String(format: "video_%04d.%@", assets.count + 1, remote.pathExtension.trimmed.isEmpty ? "mp4" : remote.pathExtension).sanitizedFilename(maxLength: 120)
                assets.append(ResolvedAsset(
                    remoteURL: remote,
                    filename: filename,
                    metadata: Self.assetMetadata(for: remote, id: id, title: resolved.metadata["title"] ?? resolved.title, pageURL: pageURL, index: assets.count + 1, mediaType: "video", videoInfo: candidate.info, filename: filename),
                    referer: pageURL.absoluteString
                ))
            }
            resolved = ResolvedDownload(
                title: resolved.title,
                folderName: resolved.folderName,
                assets: assets,
                metadata: Self.naverBlogMetadata(id: id, title: resolved.metadata["title"] ?? resolved.title, html: html, pageURL: pageURL, assets: assets)
            )
        }

        guard !resolved.assets.isEmpty else {
            throw NativeDownloadError.noFiles
        }
        return resolved
    }

    private func resolvedHTML(from url: URL, headers: HTTPRequestOptions, depth: Int) async throws -> String {
        guard depth <= 10 else {
            throw NativeDownloadError.unsupported("Naver Blog frame nesting is too deep.")
        }

        let html = try await HTTPClient.shared.string(from: url, referer: headers.referer, userAgent: headers.userAgent)
        if Self.hasViewerContainer(in: html) {
            return html
        }

        if html.count < 5_000,
           let id = Self.postID(fromHTML: html, fallbackURL: url) {
            let mobileURL = Self.mobilePostURL(for: id, sourceURL: url)
            if URLIdentity.normalize(mobileURL.absoluteString) != URLIdentity.normalize(url.absoluteString) {
                return try await resolvedHTML(from: mobileURL, headers: headers, depth: depth + 1)
            }
        }

        if let frameURL = Self.frameURL(fromHTML: html, baseURL: url) {
            return try await resolvedHTML(from: frameURL, headers: headers, depth: depth + 1)
        }

        return html
    }

    static func resolvedDownload(fromHTML html: String, pageURL: URL, id: NaverBlogID? = nil) throws -> ResolvedDownload {
        let postID = id ?? postID(from: pageURL) ?? NaverBlogID(username: pageURL.host ?? "blog", postID: fallbackPostID(from: pageURL))
        let title = postTitle(fromHTML: html, fallback: postID.postID)
        let imageURLs = imageURLs(fromHTML: html, pageURL: pageURL)

        let assets = imageURLs.enumerated().map { offset, remote in
            let filename = filename(for: remote, index: offset + 1)
            return ResolvedAsset(
                remoteURL: remote,
                filename: filename,
                metadata: assetMetadata(for: remote, id: postID, title: title, pageURL: pageURL, index: offset + 1, mediaType: "image", filename: filename),
                referer: pageURL.absoluteString
            )
        }

        let folderTitle = "[\(postID.username)] \(title) (\(postID.postID))"
        return ResolvedDownload(
            title: folderTitle.sanitizedFilename(maxLength: 120),
            folderName: "Naver Blog \(folderTitle)".sanitizedFilename(maxLength: 120),
            assets: assets,
            metadata: naverBlogMetadata(id: postID, title: title, html: html, pageURL: pageURL, assets: assets)
        )
    }

    static func imageURLs(fromHTML html: String, pageURL: URL) -> [URL] {
        let targetHTML = viewerHTML(fromHTML: html) ?? html
        let normalizedHTML = normalizeEscapes(targetHTML)
        var candidates = mediaTagCandidates(fromHTML: normalizedHTML)
        candidates.append(contentsOf: scriptImageCandidates(fromHTML: normalizedHTML))

        var output: [URL] = []
        var seen = Set<String>()
        for candidate in candidates {
            guard let rawRemote = absoluteURL(candidate, baseURL: pageURL) else {
                continue
            }
            let remote = originalStyleImageURL(rawRemote)
            guard shouldDownload(remote) else {
                continue
            }
            let normalized = URLIdentity.normalize(remote.absoluteString)
            guard !seen.contains(normalized) else { continue }
            seen.insert(normalized)
            output.append(remote)
        }
        return output
    }

    private static func originalStyleImageURL(_ url: URL) -> URL {
        let promotedString = url.absoluteString.replacingOccurrences(
            of: "mblogthumb-phinf",
            with: "blogfiles",
            options: .caseInsensitive
        )
        let promotedURL = URL(string: promotedString) ?? url
        guard promotedURL.absoluteString.lowercased().contains("blogfiles"),
              var components = URLComponents(url: promotedURL, resolvingAgainstBaseURL: false) else {
            return promotedURL
        }
        components.query = nil
        components.fragment = nil
        return components.url ?? promotedURL
    }

    static func videoPairs(fromHTML html: String) -> [NaverBlogVideoPair] {
        let normalized = normalizeEscapes(decodeHTML(html))
        var pairs: [NaverBlogVideoPair] = []
        var seen = Set<NaverBlogVideoPair>()

        let objectPattern = #"\{[^{}]*(?:"vid"|"videoId"|"video_id"|"videoNo"|'vid'|'videoId'|'video_id'|'videoNo')[^{}]*(?:"inkey"|"inKey"|"in_key"|"videoKey"|"movieKey"|"key"|'inkey'|'inKey'|'in_key'|'videoKey'|'movieKey'|'key')[^{}]*\}"#
        for object in captureFullMatches(pattern: objectPattern, in: normalized) {
            let videoID = firstCapture(patterns: [
                #""vid"\s*:\s*"([^"]+)""#,
                #""videoId"\s*:\s*"([^"]+)""#,
                #""video_id"\s*:\s*"([^"]+)""#,
                #""videoNo"\s*:\s*"([^"]+)""#,
                #"'vid'\s*:\s*'([^']+)'"#,
                #"'videoId'\s*:\s*'([^']+)'"#,
                #"'video_id'\s*:\s*'([^']+)'"#,
                #"'videoNo'\s*:\s*'([^']+)'"#
            ], in: object)
            let key = firstCapture(patterns: [
                #""inkey"\s*:\s*"([^"]+)""#,
                #""inKey"\s*:\s*"([^"]+)""#,
                #""in_key"\s*:\s*"([^"]+)""#,
                #""videoKey"\s*:\s*"([^"]+)""#,
                #""movieKey"\s*:\s*"([^"]+)""#,
                #""key"\s*:\s*"([^"]+)""#,
                #"'inkey'\s*:\s*'([^']+)'"#,
                #"'inKey'\s*:\s*'([^']+)'"#,
                #"'in_key'\s*:\s*'([^']+)'"#,
                #"'videoKey'\s*:\s*'([^']+)'"#,
                #"'movieKey'\s*:\s*'([^']+)'"#,
                #"'key'\s*:\s*'([^']+)'"#
            ], in: object)
            guard let videoID, let key else { continue }
            let pair = NaverBlogVideoPair(videoID: videoID, key: key)
            if seen.insert(pair).inserted {
                pairs.append(pair)
            }
        }

        let looseVideoIDs = captureMatches(pattern: #"(?:vid|videoId|video_id|videoNo)\s*[:=]\s*["']([^"']+)["']"#, in: normalized)
        let looseKeys = captureMatches(pattern: #"(?:inkey|inKey|in_key|videoKey|movieKey|key)\s*[:=]\s*["']([^"']+)["']"#, in: normalized)
        for (videoID, key) in zip(looseVideoIDs, looseKeys) {
            let pair = NaverBlogVideoPair(videoID: videoID, key: key)
            if seen.insert(pair).inserted {
                pairs.append(pair)
            }
        }

        return pairs
    }

    static func videoAPIURL(for pair: NaverBlogVideoPair, sourceURL: URL) -> URL {
        var components = URLComponents()
        components.scheme = sourceURL.scheme ?? "https"
        components.host = sourceURL.host?.lowercased().hasSuffix(".test") == true ? "apis.naver.test" : "apis.naver.com"
        components.path = "/rmcnmv/rmcnmv/vod/play/v2.0/\(pair.videoID)"
        components.queryItems = [URLQueryItem(name: "key", value: pair.key)]
        return components.url!
    }

    static func videoURL(fromAPIData data: Data, sourceURL: URL) throws -> URL? {
        try videoCandidate(fromAPIData: data, sourceURL: sourceURL)?.url
    }

    private static func videoCandidate(fromAPIData data: Data, sourceURL: URL) throws -> NaverBlogVideoCandidate? {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NativeDownloadError.invalidGalleryData
        }

        let videos = videoDictionaries(in: object)
        let best = videos.max { lhs, rhs in
            (intValue(lhs["size"]) ?? 0) < (intValue(rhs["size"]) ?? 0)
        }
        guard let raw = stringValue(best?["source"]) ?? stringValue(best?["url"]) else {
            return nil
        }
        guard let remote = absoluteURL(raw, baseURL: sourceURL) else {
            return nil
        }
        return NaverBlogVideoCandidate(url: remote, info: best ?? [:])
    }

    static func postID(from url: URL) -> NaverBlogID? {
        guard let host = url.host?.lowercased() else { return nil }

        if host == "blog.naver.com" || host == "m.blog.naver.com" || host == "blog.naver.test" || host == "m.blog.naver.test" {
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let items = components?.queryItems ?? []
            let blogID = items.first { $0.name == "blogId" }?.value
            let logNo = items.first { $0.name == "logNo" }?.value
            if let blogID, let logNo, !blogID.isEmpty, !logNo.isEmpty {
                return NaverBlogID(username: blogID, postID: logNo)
            }

            let parts = url.path.split(separator: "/").map(String.init)
            if parts.count >= 2,
               parts[1].range(of: #"^[0-9]+$"#, options: .regularExpression) != nil {
                return NaverBlogID(username: parts[0], postID: parts[1])
            }
        }

        if host.hasSuffix(".blog.me") || host.hasSuffix(".blog.test") {
            let username = host.split(separator: ".").first.map(String.init) ?? ""
            let parts = url.path.split(separator: "/").map(String.init)
            if let first = parts.first,
               first.range(of: #"^[0-9]+$"#, options: .regularExpression) != nil {
                return NaverBlogID(username: username, postID: first)
            }
        }

        return nil
    }

    static func mobilePostURL(for id: NaverBlogID, sourceURL: URL) -> URL {
        var components = URLComponents()
        components.scheme = sourceURL.scheme ?? "https"
        components.host = sourceURL.host?.lowercased().hasSuffix(".test") == true ? "m.blog.naver.test" : "m.blog.naver.com"
        components.path = "/PostView.nhn"
        components.queryItems = [
            URLQueryItem(name: "blogId", value: id.username),
            URLQueryItem(name: "logNo", value: id.postID),
            URLQueryItem(name: "proxyReferer", value: "")
        ]
        return components.url!
    }

    static func canonicalInputURL(for url: URL) -> URL? {
        guard let id = postID(from: url) else { return nil }
        return canonicalPostURL(for: id, sourceURL: url)
    }

    private static func postID(fromHTML html: String, fallbackURL: URL) -> NaverBlogID? {
        let logNo = firstCapture(patterns: [#"logNo=([0-9]+)"#, #""logNo"\s*:\s*"([0-9]+)""#], in: html)
        let blogID = firstCapture(patterns: [#"blogId=([0-9A-Za-z_-]+)"#, #""blogId"\s*:\s*"([^"]+)""#], in: html) ??
            firstCapture(patterns: [#"blog\.naver\.(?:com|test)/([0-9A-Za-z_-]+)"#], in: fallbackURL.absoluteString)
        guard let logNo, let blogID else { return nil }
        return NaverBlogID(username: blogID, postID: logNo)
    }

    private static func postTitle(fromHTML html: String, fallback: String) -> String {
        let title = metaContent(from: html, names: ["og:title", "twitter:title"]) ??
            titleTag(fromHTML: html) ??
            fallback
        return cleanTitle(title, fallback: fallback)
    }

    private static func viewerHTML(fromHTML html: String) -> String? {
        let patterns = [
            #"<div\b[^>]*\bid\s*=\s*["'](?:viewTypeSelector|postViewArea)["'][^>]*>"#,
            #"<div\b[^>]*\bclass\s*=\s*["'][^"']*\bse-main-container\b[^"']*["'][^>]*>"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(
                pattern: pattern,
                options: [.caseInsensitive, .dotMatchesLineSeparators]
            ) else { continue }
            let fullRange = NSRange(html.startIndex..<html.endIndex, in: html)
            guard let opening = regex.firstMatch(in: html, range: fullRange) else { continue }
            return balancedDivHTML(from: html, openingRange: opening.range)
        }
        return nil
    }

    private static func balancedDivHTML(from html: String, openingRange: NSRange) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: #"</?div\b[^>]*>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return nil
        }
        let searchRange = NSRange(
            location: openingRange.location,
            length: (html as NSString).length - openingRange.location
        )
        var depth = 0
        for match in regex.matches(in: html, range: searchRange) {
            guard let tokenRange = Range(match.range, in: html) else { continue }
            let token = html[tokenRange].lowercased()
            depth += token.hasPrefix("</div") ? -1 : 1
            if depth == 0 {
                let containerRange = NSRange(
                    location: openingRange.location,
                    length: NSMaxRange(match.range) - openingRange.location
                )
                guard let range = Range(containerRange, in: html) else { return nil }
                return String(html[range])
            }
        }
        guard let start = Range(openingRange, in: html)?.lowerBound else { return nil }
        return String(html[start...])
    }

    private static func hasViewerContainer(in html: String) -> Bool {
        html.range(of: #"id\s*=\s*["']viewTypeSelector["']"#, options: [.regularExpression, .caseInsensitive]) != nil ||
            html.range(of: #"id\s*=\s*["']postViewArea["']"#, options: [.regularExpression, .caseInsensitive]) != nil ||
            html.range(of: #"class\s*=\s*["'][^"']*\bse-main-container\b[^"']*["']"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func frameURL(fromHTML html: String, baseURL: URL) -> URL? {
        guard let regex = try? NSRegularExpression(pattern: #"<frame\b([^>]*)>"#, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, range: range),
              let attrRange = Range(match.range(at: 1), in: html) else {
            return nil
        }
        let values = attributeValues(from: String(html[attrRange]))
        return values["src"].flatMap { absoluteURL($0, baseURL: baseURL) }
    }

    private static func mediaTagCandidates(fromHTML html: String) -> [String] {
        guard let regex = try? NSRegularExpression(
            pattern: #"<(span|img|video|source)\b([^>]*)>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return []
        }

        var candidates: [String] = []
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        for match in regex.matches(in: html, range: range) {
            guard let attrRange = Range(match.range(at: 2), in: html) else { continue }
            let values = attributeValues(from: String(html[attrRange]))
            let className = values["class"]?.lowercased() ?? ""
            let isLikelyBlogImage = className.contains("_img") ||
                !directMediaAttributeCandidates(from: values).isEmpty ||
                !embeddedMediaAttributeCandidates(from: values).isEmpty
            guard isLikelyBlogImage else { continue }

            let animated = animatedMediaAttributeCandidates(from: values)
            let direct = directMediaAttributeCandidates(from: values)
            let embedded = embeddedMediaAttributeCandidates(from: values)
            if let animated = animated.first {
                candidates.append(animated)
            } else if let animatedEmbedded = embedded.first(where: isAnimatedImageCandidate) {
                candidates.append(animatedEmbedded)
            } else if let firstDirect = direct.first {
                candidates.append(firstDirect)
            } else if let firstEmbedded = embedded.first {
                candidates.append(firstEmbedded)
            }
        }
        return candidates
    }

    private static func scriptImageCandidates(fromHTML html: String) -> [String] {
        let scriptBlocks = captureMatches(pattern: #"<script\b[^>]*>(.*?)</script>"#, in: html)
        let body = scriptBlocks.isEmpty ? html : scriptBlocks.joined(separator: "\n")
        return embeddedMediaCandidates(from: body)
    }

    private static func animatedMediaAttributeCandidates(from values: [String: String]) -> [String] {
        let keys = [
            "data-gif-url",
            "data-animated-url",
            "data-animation-url",
            "data-original-gif-url",
            "data-origin-gif-url",
            "data-gif-src"
        ]
        return mediaAttributeCandidates(keys: keys, from: values)
    }

    private static func directMediaAttributeCandidates(from values: [String: String]) -> [String] {
        let keys = [
            "data-full-size-src",
            "data-fullsrc",
            "data-full-src",
            "data-lazy-src",
            "data-lazy-url",
            "data-src",
            "data-source",
            "data-original",
            "data-original-src",
            "data-origin-src",
            "data-url",
            "data-image-url",
            "data-imageurl",
            "src",
            "originalsrc",
            "origin-src",
            "data-thumburl",
            "thumburl"
        ]
        return mediaAttributeCandidates(keys: keys, from: values)
    }

    private static func mediaAttributeCandidates(keys: [String], from values: [String: String]) -> [String] {
        return keys.compactMap { key in
            let value = values[key]?.trimmed ?? ""
            return value.isEmpty ? nil : value
        }
    }

    private static func embeddedMediaAttributeCandidates(from values: [String: String]) -> [String] {
        let keys = [
            "data-linkdata",
            "data-link-data",
            "data-media",
            "data-module",
            "data-module-v2",
            "data-json",
            "data-extra",
            "data-animated",
            "data-log"
        ]
        return keys.flatMap { key in
            values[key].map(embeddedMediaCandidates(from:)) ?? []
        }
    }

    private static func embeddedMediaCandidates(from text: String) -> [String] {
        let decoded = normalizeEscapes(decodeHTML(text))
        let patterns = [
            #""(?:url|src|source|sourceUrl|source_url|originalUrl|original_url|originalSrc|original_src|imageUrl|image_url|gifUrl|gif_url|animatedUrl|animated_url|animatedGifUrl|animated_gif_url|originalGifUrl|original_gif_url|gifOriginalUrl|gif_original_url|originUrl|origin_url|originSrc|origin_src)"\s*:\s*"([^"]+\.(?:jpg|jpeg|png|gif|webp)(?:\?[^"]*)?)""#,
            #"'(?:url|src|source|sourceUrl|source_url|originalUrl|original_url|originalSrc|original_src|imageUrl|image_url|gifUrl|gif_url|animatedUrl|animated_url|animatedGifUrl|animated_gif_url|originalGifUrl|original_gif_url|gifOriginalUrl|gif_original_url|originUrl|origin_url|originSrc|origin_src)'\s*:\s*'([^']+\.(?:jpg|jpeg|png|gif|webp)(?:\?[^']*)?)'"#,
            #"(https?:\\?/\\?/[^"'\\\s<>]+\.(?:jpg|jpeg|png|gif|webp)(?:\?[^"'\\\s<>]*)?)"#,
            #"((?://)[^"'\\\s<>]+\.(?:jpg|jpeg|png|gif|webp)(?:\?[^"'\\\s<>]*)?)"#
        ]
        return patterns.flatMap { captureMatches(pattern: $0, in: decoded) }
    }

    private static func isAnimatedImageCandidate(_ value: String) -> Bool {
        let lowercased = value.lowercased()
        return lowercased.contains(".gif") ||
            lowercased.contains("image/gif") ||
            lowercased.contains("type=gif") ||
            lowercased.contains("format=gif")
    }

    private static func shouldDownload(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        let skippedHosts = [
            "ssl.pstatic.net",
            "blogpfthumb-phinf.pstatic.net",
            "dthumb-phinf.pstatic.net",
            "storep-phinf.pstatic.net"
        ]
        if skippedHosts.contains(host) { return false }

        let ext = url.pathExtension.lowercased()
        if ["jpg", "jpeg", "png", "gif", "webp"].contains(ext) {
            return true
        }
        return host.contains("pstatic") || host.contains("blogfiles") || host.contains("postfiles")
    }

    private static func videoDictionaries(in object: Any) -> [[String: Any]] {
        if let dict = object as? [String: Any] {
            if let videos = dict["videos"] as? [String: Any],
               let list = videos["list"] as? [[String: Any]] {
                return list
            }
            if let list = dict["list"] as? [[String: Any]] {
                return list
            }
            for value in dict.values {
                let found = videoDictionaries(in: value)
                if !found.isEmpty { return found }
            }
        } else if let list = object as? [[String: Any]] {
            return list
        } else if let array = object as? [Any] {
            for value in array {
                let found = videoDictionaries(in: value)
                if !found.isEmpty { return found }
            }
        }
        return []
    }

    private static func filename(for url: URL, index: Int) -> String {
        let ext = url.pathExtension.trimmed.isEmpty ? "jpg" : url.pathExtension
        return String(format: "%04d.%@", index, ext).sanitizedFilename(maxLength: 120)
    }

    private static func fallbackPostID(from url: URL) -> String {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name == "logNo" }?
            .value ?? url.lastPathComponent
    }

    private static func naverBlogMetadata(id: NaverBlogID, title: String, html: String, pageURL: URL, assets: [ResolvedAsset] = []) -> [String: String] {
        let date = publishedDate(fromHTML: html) ?? ""
        let canonicalURL = canonicalPostURL(for: id, sourceURL: pageURL).absoluteString
        let imageCount = assets.filter { ($0.metadata["media_type"] ?? $0.metadata["type"]) == "image" }.count
        let videoCount = assets.filter { ($0.metadata["media_type"] ?? $0.metadata["type"]) == "video" }.count
        return DownloadMetadata.clean([
            "id": id.postID,
            "blog_id": id.username,
            "log_no": id.postID,
            "post_id": id.postID,
            "gallery_id": id.postID,
            "media_id": id.postID,
            "artist": id.username,
            "author": id.username,
            "creator": id.username,
            "user": id.username,
            "username": id.username,
            "user_id": id.username,
            "uploader": id.username,
            "uploader_id": id.username,
            "channel": id.username,
            "channel_id": id.username,
            "series": title,
            "title": title,
            "category": "blog",
            "type": "post",
            "media_type": videoCount > 0 && imageCount == 0 ? "video" : "image",
            "media_count": assets.isEmpty ? "" : String(assets.count),
            "image_count": imageCount > 0 ? String(imageCount) : "",
            "video_count": videoCount > 0 ? String(videoCount) : "",
            "date": date,
            "published_date": date,
            "url": canonicalURL,
            "source": canonicalURL,
            "source_url": canonicalURL,
            "page_url": pageURL.absoluteString,
            "site": "Naver Blog"
        ])
    }

    private static func assetMetadata(for url: URL, id: NaverBlogID, title: String, pageURL: URL, index: Int, mediaType: String, videoInfo: [String: Any] = [:], filename: String? = nil) -> [String: String] {
        let format = url.pathExtension.trimmed.isEmpty ? (mediaType == "video" ? "mp4" : "jpg") : url.pathExtension.lowercased()
        let width = stringValue(videoInfo["width"]) ?? stringValue(videoInfo["w"]) ?? ""
        let height = stringValue(videoInfo["height"]) ?? stringValue(videoInfo["h"]) ?? ""
        let quality = stringValue(videoInfo["quality"]) ?? stringValue(videoInfo["label"]) ?? (height.isEmpty ? "" : "\(height)p")
        let canonicalURL = canonicalPostURL(for: id, sourceURL: pageURL).absoluteString
        let outputFilename = filename ?? self.filename(for: url, index: index)
        let sourceFilename = originalFilename(for: url, fallbackExtension: format)
        var metadata = DownloadMetadata.clean([
            "site": "Naver Blog",
            "title": title,
            "type": mediaType,
            "media_type": mediaType,
            "id": id.postID,
            "blog_id": id.username,
            "log_no": id.postID,
            "post_id": id.postID,
            "gallery_id": id.postID,
            "media_id": "\(id.postID)-\(index)",
            "page": String(index),
            "position": String(index),
            "format": format,
            "media_format": format,
            "width": width,
            "height": height,
            "resolution": height.isEmpty ? "" : "\(height)p",
            "quality": quality,
            "byte_count": stringValue(videoInfo["size"]) ?? stringValue(videoInfo["filesize"]) ?? "",
            "filename": outputFilename,
            "basename": (outputFilename as NSString).deletingPathExtension,
            "ext": (outputFilename as NSString).pathExtension,
            "source_filename": sourceFilename,
            "source_basename": (sourceFilename as NSString).deletingPathExtension,
            "source_ext": (sourceFilename as NSString).pathExtension,
            "media_url": url.absoluteString,
            "source_url": canonicalURL,
            "page_url": pageURL.absoluteString,
            "artist": id.username,
            "author": id.username,
            "creator": id.username,
            "username": id.username,
            "uploader": id.username
        ])
        if mediaType == "video" {
            metadata["video_url"] = url.absoluteString
        } else {
            metadata["image_url"] = url.absoluteString
        }
        return metadata
    }

    private static func originalFilename(for url: URL, fallbackExtension: String) -> String {
        let pathName = url.lastPathComponent.removingPercentEncoding ?? url.lastPathComponent
        let candidate = pathName.trimmed.isEmpty ? "naver_blog_media.\(fallbackExtension)" : pathName
        return candidate.sanitizedFilename(maxLength: 180)
    }

    private static func canonicalPostURL(for id: NaverBlogID, sourceURL: URL) -> URL {
        var components = URLComponents()
        components.scheme = sourceURL.scheme ?? "https"
        components.host = sourceURL.host?.lowercased().hasSuffix(".test") == true ? "blog.naver.test" : "blog.naver.com"
        components.path = "/\(id.username)/\(id.postID)"
        return components.url!
    }

    private static func publishedDate(fromHTML html: String) -> String? {
        let raw = metaContent(
            from: html,
            names: [
                "article:published_time",
                "article:modified_time",
                "og:regdate",
                "naverblog:postingdate",
                "date",
                "datepublished",
                "pubdate"
            ]
        ) ??
            firstCapture(
                patterns: [
                    #"<(?:span|p|em|time)\b[^>]*(?:se_publishdate|se_publishDate|postdate|date)[^>]*>(.*?)</(?:span|p|em|time)>"#,
                    #"\b(?:addDate|postDate|postingDate|publishedDate)\s*[:=]\s*["']([^"']+)["']"#
                ],
                in: html
            )
        return normalizedDate(raw)
    }

    private static func normalizedDate(_ raw: String?) -> String? {
        guard var value = raw.map({ decodeHTML(stripTags($0)).trimmed }), !value.isEmpty else { return nil }
        value = value.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        if let match = value.range(of: #"[0-9]{4}-[0-9]{2}-[0-9]{2}"#, options: .regularExpression) {
            return String(value[match])
        }
        if value.range(of: #"^[0-9]{8}$"#, options: .regularExpression) != nil {
            let monthStart = value.index(value.startIndex, offsetBy: 4)
            let dayStart = value.index(value.startIndex, offsetBy: 6)
            return "\(value.prefix(4))-\(value[monthStart..<dayStart])-\(value[dayStart..<value.endIndex])"
        }
        if let regex = try? NSRegularExpression(pattern: #"([0-9]{4})\s*[./년]\s*([0-9]{1,2})\s*[./월]\s*([0-9]{1,2})"#),
           let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..<value.endIndex, in: value)),
           let yearRange = Range(match.range(at: 1), in: value),
           let monthRange = Range(match.range(at: 2), in: value),
           let dayRange = Range(match.range(at: 3), in: value) {
            let year = String(value[yearRange])
            let month = String(format: "%02d", Int(value[monthRange]) ?? 0)
            let day = String(format: "%02d", Int(value[dayRange]) ?? 0)
            guard month != "00", day != "00" else { return nil }
            return "\(year)-\(month)-\(day)"
        }
        return nil
    }

    private static func metaContent(from html: String, names: Set<String>) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"<meta\b([^>]*)>"#, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        for match in regex.matches(in: html, range: range) {
            guard let attrRange = Range(match.range(at: 1), in: html) else { continue }
            let values = attributeValues(from: String(html[attrRange]))
            let key = (values["property"] ?? values["name"] ?? values["itemprop"])?.lowercased()
            guard let key, names.contains(key),
                  let content = values["content"]?.trimmed,
                  !content.isEmpty else {
                continue
            }
            return content
        }
        return nil
    }

    private static func titleTag(fromHTML html: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: #"<title\b[^>]*>(.*?)</title>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return nil
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, range: range),
              let capture = Range(match.range(at: 1), in: html) else {
            return nil
        }
        return String(html[capture])
    }

    private static func cleanTitle(_ raw: String, fallback: String) -> String {
        var title = decodeHTML(stripTags(raw))
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmed
        for suffix in [" : 네이버 블로그", " | 네이버 블로그", " - 네이버 블로그", " : Naver Blog", " | Naver Blog", " - Naver Blog"] {
            if title.lowercased().hasSuffix(suffix.lowercased()) {
                title.removeLast(suffix.count)
                title = title.trimmed
            }
        }
        return title.isEmpty ? fallback : title
    }

    private static func attributeValues(from attributes: String) -> [String: String] {
        guard let regex = try? NSRegularExpression(
            pattern: #"\b([A-Za-z_:][-A-Za-z0-9_:.]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>"']+))"#,
            options: [.caseInsensitive]
        ) else {
            return [:]
        }
        let range = NSRange(attributes.startIndex..<attributes.endIndex, in: attributes)
        var values: [String: String] = [:]
        for match in regex.matches(in: attributes, range: range) {
            guard let nameRange = Range(match.range(at: 1), in: attributes) else { continue }
            let name = String(attributes[nameRange]).lowercased()
            for group in 2...4 {
                guard let valueRange = Range(match.range(at: group), in: attributes) else { continue }
                values[name] = normalizeEscapes(decodeHTML(String(attributes[valueRange]))).trimmed
                break
            }
        }
        return values
    }

    private static func captureMatches(pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > 1,
                  let capture = Range(match.range(at: 1), in: text) else {
                return nil
            }
            return normalizeEscapes(String(text[capture]))
        }
    }

    private static func captureFullMatches(pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let capture = Range(match.range(at: 0), in: text) else { return nil }
            return String(text[capture])
        }
    }

    private static func firstCapture(patterns: [String], in text: String) -> String? {
        for pattern in patterns {
            if let value = captureMatches(pattern: pattern, in: text).first {
                return value
            }
        }
        return nil
    }

    private static func absoluteURL(_ raw: String, baseURL: URL) -> URL? {
        let value = normalizeEscapes(decodeHTML(raw)).trimmed
        if value.hasPrefix("//") {
            return URL(string: "\(baseURL.scheme ?? "https"):\(value)")
        }
        return URL(string: value, relativeTo: baseURL)?.absoluteURL
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) }
        return nil
    }

    private static func normalizeEscapes(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"\\u002F"#, with: "/", options: .caseInsensitive)
            .replacingOccurrences(of: #"\/"#, with: "/")
            .replacingOccurrences(of: #"\\/"#, with: "/")
            .replacingOccurrences(of: #"\\u0026"#, with: "&", options: .caseInsensitive)
            .replacingOccurrences(of: #"\""#, with: "\"")
    }

    private static func stripTags(_ text: String) -> String {
        text
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmed
    }

    private static func decodeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }
}
