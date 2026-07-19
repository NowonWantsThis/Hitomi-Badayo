import Foundation

struct FacebookVideoCandidate: Equatable {
    var url: URL
    var score: Int
    var source: String
}

final class FacebookVideoResolver {
    func canResolve(_ url: URL) -> Bool {
        Self.videoID(from: url) != nil
    }

    func resolve(_ url: URL, headers: HTTPRequestOptions = HTTPRequestOptions()) async throws -> ResolvedDownload {
        guard let videoID = Self.videoID(from: url) else {
            throw NativeDownloadError.invalidURL(url.absoluteString)
        }

        let html = try await HTTPClient.shared.string(from: url, referer: headers.referer, userAgent: headers.userAgent)
        return try await Self.resolvedDownload(fromHTML: html, pageURL: url, videoID: videoID, userAgent: headers.userAgent)
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

        if isFBWatchHost(host) {
            return parts.first(where: isValidID)
        }

        if lower.first == "watch" || lower.first == "video.php" {
            return queryValue(names: ["v", "video_id", "videoId"], in: url).flatMap(validID)
        }

        if lower.first == "reel", parts.count >= 2 {
            return validID(parts[1])
        }

        if lower.first == "share", lower.count >= 3, lower[1] == "v" {
            return validID(parts[2])
        }

        if let marker = lower.firstIndex(of: "videos") {
            let after = parts[(marker + 1)...]
            if let id = after.first(where: isValidID) {
                return id
            }
        }

        if let marker = lower.firstIndex(of: "watch"),
           marker == lower.count - 1 {
            return queryValue(names: ["v", "video_id", "videoId"], in: url).flatMap(validID)
        }

        return nil
    }

    static func canonicalURL(for url: URL) -> URL? {
        guard let videoID = videoID(from: url),
              let host = url.host?.lowercased() else {
            return nil
        }

        if isFBWatchHost(host) {
            var components = URLComponents()
            components.scheme = url.scheme ?? "https"
            components.host = host == "www.fb.watch" ? "fb.watch" : host
            components.path = "/\(videoID)"
            return components.url
        }

        var components = URLComponents()
        components.scheme = url.scheme ?? "https"
        components.host = host.hasSuffix(".test") ? "www.facebook.test" : "www.facebook.com"
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        let lower = parts.map { $0.lowercased() }
        if lower.first == "reel" {
            components.path = "/reel/\(videoID)"
        } else {
            components.path = "/watch/"
            components.queryItems = [URLQueryItem(name: "v", value: videoID)]
        }
        return components.url
    }

    static func resolvedDownload(fromHTML html: String, pageURL: URL, videoID: String, userAgent: String? = nil) async throws -> ResolvedDownload {
        guard let candidate = bestVideoCandidate(fromHTML: html, pageURL: pageURL) else {
            throw NativeDownloadError.noFiles
        }

        let info = pageInfo(fromHTML: html, videoID: videoID)
        if isM3U8(candidate.url) {
            let hls = try await M3U8Resolver().resolve(
                candidate.url,
                headers: HTTPRequestOptions(referer: pageURL.absoluteString, userAgent: userAgent)
            )
            let outputFilename = "\(info.title)-\(videoID).ts".sanitizedFilename(maxLength: 180)
            return ResolvedDownload(
                title: info.displayTitle,
                folderName: "Facebook \(info.displayTitle)".sanitizedFilename(maxLength: 120),
                assets: hlsAssetsWithPageMetadata(
                    hls.assets,
                    candidate: candidate,
                    videoID: videoID,
                    title: info.title,
                    author: info.author,
                    pageURL: pageURL,
                    html: html
                ),
                packageMode: .concatenate(outputFilename: outputFilename),
                metadata: metadata(
                    videoID: videoID,
                    title: info.title,
                    author: info.author,
                    pageURL: pageURL,
                    videoURL: candidate.url,
                    html: html,
                    source: candidate.source
                ).merging(hls.metadata) { current, _ in current }
            )
        }

        let filename = filename(for: candidate.url, title: info.title, videoID: videoID)
        return ResolvedDownload(
            title: info.displayTitle,
            folderName: "Facebook \(info.displayTitle)".sanitizedFilename(maxLength: 120),
            assets: [
                ResolvedAsset(
                    remoteURL: candidate.url,
                    filename: filename,
                    metadata: mediaMetadata(
                        for: candidate,
                        videoID: videoID,
                        title: info.title,
                        author: info.author,
                        pageURL: pageURL
                    ),
                    referer: pageURL.absoluteString
                )
            ],
            packageMode: .concatenate(outputFilename: filename),
            metadata: metadata(
                videoID: videoID,
                title: info.title,
                author: info.author,
                pageURL: pageURL,
                videoURL: candidate.url,
                html: html,
                source: candidate.source
            )
        )
    }

    static func bestVideoCandidate(fromHTML html: String, pageURL: URL) -> FacebookVideoCandidate? {
        var candidates: [FacebookVideoCandidate] = []
        candidates.append(contentsOf: keyedURLCandidates(fromHTML: html, pageURL: pageURL))
        candidates.append(contentsOf: metaCandidates(fromHTML: html, pageURL: pageURL))
        candidates.append(contentsOf: sourceCandidates(fromHTML: html, pageURL: pageURL))
        candidates.append(contentsOf: directURLCandidates(fromHTML: html, pageURL: pageURL))

        var seen = Set<String>()
        let unique = candidates.compactMap { candidate -> FacebookVideoCandidate? in
            let normalized = URLIdentity.normalize(candidate.url.absoluteString)
            guard !seen.contains(normalized) else { return nil }
            seen.insert(normalized)
            return candidate
        }

        return unique.max {
            if $0.score == $1.score {
                return $0.url.absoluteString < $1.url.absoluteString
            }
            return $0.score < $1.score
        }
    }

    private static func keyedURLCandidates(fromHTML html: String, pageURL: URL) -> [FacebookVideoCandidate] {
        let keys: [(name: String, score: Int)] = [
            ("browser_native_hd_url", 4_000_000),
            ("playable_url_quality_hd", 3_900_000),
            ("hd_src", 3_800_000),
            ("browser_native_sd_url", 3_000_000),
            ("playable_url", 2_800_000),
            ("sd_src", 2_700_000),
            ("hls_playlist_url", 2_500_000),
            ("stream_url", 2_300_000),
            ("video_url", 2_100_000),
            ("contentUrl", 2_000_000)
        ]

        return keys.flatMap { key -> [FacebookVideoCandidate] in
            let escaped = NSRegularExpression.escapedPattern(for: key.name)
            let patterns = [
                #""\#(escaped)"\s*:\s*"([^"]+)""#,
                #"'\#(escaped)'\s*:\s*'([^']+)'"#,
                #"\b\#(escaped)\s*=\s*["']([^"']+)["']"#
            ]
            return patterns.flatMap { pattern -> [FacebookVideoCandidate] in
                captures(pattern: pattern, in: html).compactMap { raw -> FacebookVideoCandidate? in
                    guard let url = absoluteURL(raw, baseURL: pageURL),
                          isPlayableVideo(url) else {
                        return nil
                    }
                    return FacebookVideoCandidate(
                        url: url,
                        score: key.score + qualityScore(url) + directVideoScore(url),
                        source: key.name
                    )
                }
            }
        }
    }

    private static func metaCandidates(fromHTML html: String, pageURL: URL) -> [FacebookVideoCandidate] {
        ["og:video", "og:video:url", "og:video:secure_url", "twitter:player:stream"].compactMap { name in
            guard let raw = metaContent(from: html, names: [name]),
                  let url = absoluteURL(raw, baseURL: pageURL),
                  isPlayableVideo(url) else {
                return nil
            }
            return FacebookVideoCandidate(url: url, score: 1_500_000 + qualityScore(url) + directVideoScore(url), source: name)
        }
    }

    private static func sourceCandidates(fromHTML html: String, pageURL: URL) -> [FacebookVideoCandidate] {
        let patterns = [
            #"<source\b[^>]*\bsrc\s*=\s*["']([^"']+)["'][^>]*>"#,
            #"<video\b[^>]*\bsrc\s*=\s*["']([^"']+)["'][^>]*>"#
        ]
        return patterns.flatMap { pattern in
            captures(pattern: pattern, in: html).compactMap { raw in
                guard let url = absoluteURL(raw, baseURL: pageURL),
                      isPlayableVideo(url) else {
                    return nil
                }
                return FacebookVideoCandidate(url: url, score: 1_000_000 + qualityScore(url) + directVideoScore(url), source: "source")
            }
        }
    }

    private static func directURLCandidates(fromHTML html: String, pageURL: URL) -> [FacebookVideoCandidate] {
        let patterns = [
            #"https?:\\/\\/[^'"\s<>]+?\.(?:mp4|m3u8|webm|m4v|mov)(?:\?[^'"\s<>]*)?"#,
            #"https?://[^'"\s<>]+?\.(?:mp4|m3u8|webm|m4v|mov)(?:\?[^'"\s<>]*)?"#
        ]
        return patterns.flatMap { pattern in
            allCaptures(pattern: pattern, in: html, group: 0).compactMap { raw in
                guard let url = absoluteURL(raw, baseURL: pageURL),
                      isPlayableVideo(url) else {
                    return nil
                }
                return FacebookVideoCandidate(url: url, score: 500_000 + qualityScore(url) + directVideoScore(url), source: "direct-url")
            }
        }
    }

    private static func metadata(videoID: String, title: String, author: String, pageURL: URL, videoURL: URL, html: String, source: String) -> [String: String] {
        let height = videoHeight(from: videoURL)
        let resolution = height.map { "\($0)p" } ?? ""
        return DownloadMetadata.clean([
            "site": "Facebook",
            "title": title,
            "series": title,
            "artist": author,
            "author": author,
            "creator": author,
            "uploader": author,
            "channel": author,
            "category": "video",
            "type": isM3U8(videoURL) ? "hls" : "video",
            "media_type": isM3U8(videoURL) ? "hls" : "video",
            "format": mediaFormat(for: videoURL),
            "media_format": mediaFormat(for: videoURL),
            "height": height ?? "",
            "resolution": resolution,
            "quality": resolution,
            "host": pageURL.host ?? "",
            "id": videoID,
            "video_id": videoID,
            "media_id": videoID,
            "gallery_id": videoID,
            "media_count": "1",
            "video_count": "1",
            "video_url": videoURL.absoluteString,
            "media_url": videoURL.absoluteString,
            "thumbnail": thumbnailURL(fromHTML: html, pageURL: pageURL)?.absoluteString ?? "",
            "source": source,
            "media_source": source,
            "url": pageURL.absoluteString,
            "source_url": pageURL.absoluteString,
            "page_url": pageURL.absoluteString
        ])
    }

    private static func mediaMetadata(
        for candidate: FacebookVideoCandidate,
        videoID: String,
        title: String,
        author: String,
        pageURL: URL
    ) -> [String: String] {
        let height = videoHeight(from: candidate.url)
        let resolution = height.map { "\($0)p" } ?? ""
        return DownloadMetadata.clean([
            "site": "Facebook",
            "title": title,
            "artist": author,
            "author": author,
            "creator": author,
            "uploader": author,
            "channel": author,
            "category": "video",
            "type": isM3U8(candidate.url) ? "hls" : "video",
            "media_type": isM3U8(candidate.url) ? "hls" : "video",
            "format": mediaFormat(for: candidate.url),
            "media_format": mediaFormat(for: candidate.url),
            "height": height ?? "",
            "resolution": resolution,
            "quality": resolution,
            "id": videoID,
            "video_id": videoID,
            "media_id": videoID,
            "gallery_id": videoID,
            "page": "1",
            "position": "1",
            "video_url": candidate.url.absoluteString,
            "media_url": candidate.url.absoluteString,
            "source": candidate.source,
            "media_source": candidate.source,
            "source_url": pageURL.absoluteString,
            "page_url": pageURL.absoluteString
        ])
    }

    static func hlsAssetsWithPageMetadata(_ assets: [ResolvedAsset], candidate: FacebookVideoCandidate, videoID: String, title: String, author: String, pageURL: URL, html: String) -> [ResolvedAsset] {
        let thumbnail = thumbnailURL(fromHTML: html, pageURL: pageURL)
        return assets.enumerated().map { offset, asset in
            var enriched = asset
            enriched.metadata = asset.metadata.merging(segmentMetadata(
                for: candidate,
                videoID: videoID,
                title: title,
                author: author,
                pageURL: pageURL,
                asset: asset,
                index: offset + 1,
                thumbnail: thumbnail
            )) { _, new in new }
            return enriched
        }
    }

    private static func segmentMetadata(
        for candidate: FacebookVideoCandidate,
        videoID: String,
        title: String,
        author: String,
        pageURL: URL,
        asset: ResolvedAsset,
        index: Int,
        thumbnail: URL?
    ) -> [String: String] {
        let type = asset.metadata["type"] ?? "hls_segment"
        let format = mediaFormat(for: asset.remoteURL, fallback: mediaFormat(forFilename: asset.filename, fallback: "ts"))
        let height = videoHeight(from: candidate.url)
        let resolution = height.map { "\($0)p" } ?? ""
        return DownloadMetadata.clean([
            "site": "Facebook",
            "title": title,
            "series": title,
            "artist": author,
            "author": author,
            "creator": author,
            "uploader": author,
            "channel": author,
            "category": "video",
            "type": type,
            "media_type": type == "hls_segment" ? "segment" : type,
            "format": format,
            "media_format": format,
            "height": height ?? "",
            "resolution": resolution,
            "quality": resolution,
            "id": videoID,
            "video_id": videoID,
            "media_id": "\(videoID)-segment-\(index)",
            "gallery_id": videoID,
            "page": String(index),
            "position": String(index),
            "thumbnail": thumbnail?.absoluteString ?? "",
            "playlist_url": asset.metadata["playlist_url"] ?? candidate.url.absoluteString,
            "video_url": asset.remoteURL.absoluteString,
            "media_url": asset.remoteURL.absoluteString,
            "source": candidate.source,
            "media_source": candidate.source,
            "source_url": pageURL.absoluteString,
            "page_url": pageURL.absoluteString
        ])
    }

    private static func pageInfo(fromHTML html: String, videoID: String) -> (title: String, displayTitle: String, author: String) {
        let fallback = "Facebook video \(videoID)"
        let rawTitle = metaContent(from: html, names: ["og:title", "twitter:title"]) ??
            titleTag(fromHTML: html) ??
            fallback
        let title = cleanTitle(rawTitle, fallback: fallback)
        let author = cleanTitle(
            firstCapture(pattern: #""owner"\s*:\s*\{[^{}]*"name"\s*:\s*"([^"]+)""#, in: html) ??
                firstCapture(pattern: #""author"\s*:\s*"([^"]+)""#, in: html) ??
                firstCapture(pattern: #""publisher"\s*:\s*\{[^{}]*"name"\s*:\s*"([^"]+)""#, in: html) ??
                "",
            fallback: ""
        )
        let displayTitle = author.isEmpty ? title : "\(author) - \(title)"
        return (title, displayTitle, author)
    }

    private static func filename(for url: URL, title: String, videoID: String) -> String {
        let ext = url.pathExtension.trimmed.isEmpty ? "mp4" : url.pathExtension.lowercased()
        return "\(title)-\(videoID).\(ext)".sanitizedFilename(maxLength: 180)
    }

    private static func thumbnailURL(fromHTML html: String, pageURL: URL) -> URL? {
        guard let raw = metaContent(from: html, names: ["og:image", "twitter:image"]) ??
            firstCapture(pattern: #""thumbnail(?:Image|Url|_url)?"\s*:\s*"([^"]+)""#, in: html) ??
            firstCapture(pattern: #""preferred_thumbnail"\s*:\s*\{[^{}]*"image"\s*:\s*\{[^{}]*"uri"\s*:\s*"([^"]+)""#, in: html),
            let url = absoluteURL(raw, baseURL: pageURL) else {
            return nil
        }
        return url
    }

    private static func isPlayableVideo(_ url: URL) -> Bool {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            return false
        }
        let host = url.host?.lowercased() ?? ""
        let value = url.absoluteString.lowercased()
        guard value.contains(".mp4") ||
            value.contains(".m3u8") ||
            value.contains(".webm") ||
            value.contains(".m4v") ||
            value.contains(".mov") else {
            return false
        }
        if host.contains("fbcdn") || host.contains("fbsbx") || host.contains("facebook.test") || host.contains("fbcdn.test") {
            return true
        }
        return value.contains("scontent") || value.contains("video")
    }

    private static func isM3U8(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "m3u8" || url.absoluteString.lowercased().contains(".m3u8")
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

    private static func videoHeight(from url: URL) -> String? {
        let value = url.absoluteString.lowercased()
        let patterns = [
            #"([0-9]{3,4})p"#,
            #"(?:height|h)=([0-9]{3,4})"#,
            #"/([0-9]{3,4})/"#
        ]
        for pattern in patterns {
            guard let raw = firstCapture(pattern: pattern, in: value),
                  let height = Int(raw),
                  height >= 144,
                  height <= 4320 else {
                continue
            }
            return String(height)
        }
        return nil
    }

    private static func qualityScore(_ url: URL) -> Int {
        let value = url.absoluteString.lowercased()
        let patterns = [
            #"([0-9]{3,4})p"#,
            #"(?:height|h)=([0-9]{3,4})"#,
            #"/([0-9]{3,4})/"#
        ]
        for pattern in patterns {
            if let raw = firstCapture(pattern: pattern, in: value), let quality = Int(raw) {
                return quality * 100
            }
        }
        if value.contains("_hd") || value.contains("hd_src") { return 100_000 }
        if value.contains("_sd") || value.contains("sd_src") { return 40_000 }
        return 0
    }

    private static func directVideoScore(_ url: URL) -> Int {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "mp4", "m4v", "mov":
            return 20_000
        case "webm":
            return 10_000
        case "m3u8":
            return 5_000
        default:
            return url.absoluteString.lowercased().contains(".mp4") ? 20_000 : 0
        }
    }

    private static func queryValue(names: [String], in url: URL) -> String? {
        guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else {
            return nil
        }
        for name in names {
            if let value = items.first(where: { $0.name.lowercased() == name.lowercased() })?.value?.trimmed,
               !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func validID(_ value: String) -> String? {
        isValidID(value) ? value : nil
    }

    private static func isValidID(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z0-9._-]{3,}$"#, options: .regularExpression) != nil &&
            !["watch", "videos", "video.php", "reel", "reels", "photos", "photo.php", "share"].contains(value.lowercased())
    }

    private static func isSupportedHost(_ host: String) -> Bool {
        if isFBWatchHost(host) { return true }
        if host == "facebook.test" ||
            host == "www.facebook.test" ||
            host == "m.facebook.test" ||
            host == "mbasic.facebook.test" {
            return true
        }
        let labels = host.split(separator: ".").map(String.init)
        guard labels.count >= 2,
              labels[labels.count - 2] == "facebook" else {
            return false
        }
        let topLevelDomain = labels[labels.count - 1]
        return topLevelDomain.range(of: #"^[a-z]{2,12}$"#, options: .regularExpression) != nil
    }

    private static func isFBWatchHost(_ host: String) -> Bool {
        host == "fb.watch" || host == "www.fb.watch"
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

    private static func allCaptures(pattern: String, in text: String, group: Int) -> [String] {
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

    private static func firstCapture(pattern: String, in text: String) -> String? {
        captures(pattern: pattern, in: text).first
    }

    private static func cleanTitle(_ raw: String, fallback: String) -> String {
        var title = decodeHTML(stripTags(normalizeEscapes(raw)))
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmed
        title = title.replacingOccurrences(of: #"(?i)\s*\|\s*Facebook.*$"#, with: "", options: .regularExpression)
        title = title.replacingOccurrences(of: #"(?i)\s*-\s*Facebook Watch.*$"#, with: "", options: .regularExpression)
        title = title.replacingOccurrences(of: #"(?i)^Facebook\s*[-:]\s*"#, with: "", options: .regularExpression)
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
            .replacingOccurrences(of: "\\u0025", with: "%", options: .caseInsensitive)
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
}
