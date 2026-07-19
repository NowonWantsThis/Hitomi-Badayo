import Foundation

struct VLiveVideoCandidate: Equatable {
    var url: URL
    var quality: Int
    var label: String
}

struct VLiveSubtitleCandidate: Equatable {
    var url: URL
    var language: String
    var label: String
    var format: String
}

final class VLiveResolver {
    func canResolve(_ url: URL) -> Bool {
        Self.contentID(from: url) != nil
    }

    func resolve(_ url: URL, headers: HTTPRequestOptions = HTTPRequestOptions()) async throws -> ResolvedDownload {
        guard let id = Self.contentID(from: url) else {
            throw NativeDownloadError.invalidURL(url.absoluteString)
        }
        let pageURL = Self.canonicalURL(for: url) ?? url
        let html = try await HTTPClient.shared.string(from: pageURL, referer: headers.referer, userAgent: headers.userAgent)
        return try await Self.resolvedDownload(
            fromHTML: html,
            pageURL: pageURL,
            contentID: id,
            userAgent: headers.userAgent
        )
    }

    static func contentID(from url: URL) -> String? {
        guard let host = url.host?.lowercased(),
              isSupportedHost(host),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }

        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        let lower = parts.map { $0.lowercased() }
        if ["video", "post"].contains(lower.first ?? ""),
           parts.count >= 2,
           isValidID(parts[1]) {
            return parts[1]
        }

        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        for name in ["videoSeq", "video_seq", "videoId", "video_id", "postId", "post_id"] {
            if let value = queryItems.first(where: { $0.name.lowercased() == name.lowercased() })?.value,
               isValidID(value) {
                return value
            }
        }
        return nil
    }

    static func canonicalURL(for url: URL) -> URL? {
        guard let id = contentID(from: url) else { return nil }
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).lowercased() }
        var components = URLComponents()
        components.scheme = "https"
        components.host = canonicalHost(from: url)
        components.path = parts.first == "post" ? "/post/\(id)" : "/video/\(id)"
        return components.url
    }

    static func videoCandidates(fromHTML html: String, pageURL: URL) -> [VLiveVideoCandidate] {
        let normalized = normalizeEscapes(decodeHTML(html))
        var candidates: [VLiveVideoCandidate] = []

        for tag in allCaptures(pattern: #"<(?:video|source)\b[^>]*>"#, in: normalized, group: 0) {
            let label = attributeValue("label", in: tag) ??
                attributeValue("data-quality", in: tag) ??
                attributeValue("title", in: tag) ??
                ""
            for attribute in ["src", "data-src", "data-video", "data-url", "data-file"] {
                if let raw = attributeValue(attribute, in: tag) {
                    appendVideoCandidate(rawURL: raw, label: label, pageURL: pageURL, candidates: &candidates)
                }
            }
        }

        for meta in allCaptures(pattern: #"<meta\b[^>]*>"#, in: normalized, group: 0) {
            let name = (attributeValue("property", in: meta) ?? attributeValue("name", in: meta) ?? "").lowercased()
            guard ["og:video", "og:video:url", "og:video:secure_url", "twitter:player:stream"].contains(name),
                  let content = attributeValue("content", in: meta) else {
                continue
            }
            appendVideoCandidate(rawURL: content, label: name, pageURL: pageURL, candidates: &candidates)
        }

        for pattern in [
            #""(?:videoUrl|videoURL|video_url|vodUrl|vod_url|playUrl|play_url|source|url|src|file|hls|m3u8|mp4)"\s*:\s*"([^"]+)""#,
            #"'(?:videoUrl|videoURL|video_url|vodUrl|vod_url|playUrl|play_url|source|url|src|file|hls|m3u8|mp4)'\s*:\s*'([^']+)'"#
        ] {
            for raw in allCaptures(pattern: pattern, in: normalized) {
                appendVideoCandidate(rawURL: raw, label: "", pageURL: pageURL, candidates: &candidates)
            }
        }

        for raw in allCaptures(pattern: #"(?:https?:)?//[^"'\s<>]+?\.(?:mp4|m4v|mov|webm|m3u8)(?:\?[^"'\s<>]*)?"#, in: normalized, group: 0) {
            appendVideoCandidate(rawURL: raw, label: "", pageURL: pageURL, candidates: &candidates)
        }

        return uniqueVideoCandidates(candidates)
    }

    static func subtitleCandidates(fromHTML html: String, pageURL: URL) -> [VLiveSubtitleCandidate] {
        let normalized = normalizeEscapes(decodeHTML(html))
        var candidates: [VLiveSubtitleCandidate] = []

        for tag in allCaptures(pattern: #"<track\b[^>]*>"#, in: normalized, group: 0) {
            guard let raw = attributeValue("src", in: tag) else { continue }
            let language = attributeValue("srclang", in: tag) ??
                attributeValue("lang", in: tag) ??
                attributeValue("data-lang", in: tag) ??
                attributeValue("label", in: tag) ??
                "und"
            let label = attributeValue("label", in: tag) ?? language
            appendSubtitleCandidate(rawURL: raw, language: language, label: label, pageURL: pageURL, candidates: &candidates)
        }

        for pattern in [
            #""(?:subtitleUrl|subtitle_url|captionUrl|caption_url|subtitlesUrl|subtitles_url|source|url|src|file)"\s*:\s*"([^"]+\.(?:srt|vtt|ttml|dfxp)(?:\?[^"]*)?)""#,
            #"'(?:subtitleUrl|subtitle_url|captionUrl|caption_url|subtitlesUrl|subtitles_url|source|url|src|file)'\s*:\s*'([^']+\.(?:srt|vtt|ttml|dfxp)(?:\?[^']*)?)'"#
        ] {
            for raw in allCaptures(pattern: pattern, in: normalized) {
                appendSubtitleCandidate(rawURL: raw, language: "und", label: "", pageURL: pageURL, candidates: &candidates)
            }
        }

        for raw in allCaptures(pattern: #"(?:https?:)?//[^"'\s<>]+?\.(?:srt|vtt|ttml|dfxp)(?:\?[^"'\s<>]*)?"#, in: normalized, group: 0) {
            appendSubtitleCandidate(rawURL: raw, language: "und", label: "", pageURL: pageURL, candidates: &candidates)
        }

        return uniqueSubtitleCandidates(candidates)
    }

    static func resolvedDownload(fromHTML html: String, pageURL: URL, contentID: String, userAgent: String? = nil) async throws -> ResolvedDownload {
        guard let candidate = bestVideoCandidate(videoCandidates(fromHTML: html, pageURL: pageURL)) else {
            throw NativeDownloadError.noFiles
        }
        let title = title(fromHTML: html, fallback: "V LIVE \(contentID)")
        let subtitles = subtitleCandidates(fromHTML: html, pageURL: pageURL)

        if isM3U8(candidate.url) {
            let hls = try await M3U8Resolver().resolve(
                candidate.url,
                headers: HTTPRequestOptions(referer: pageURL.absoluteString, userAgent: userAgent)
            )
            let metadata = pageMetadata(
                id: contentID,
                title: title,
                pageURL: pageURL,
                mediaURL: candidate.url,
                html: html,
                candidate: candidate,
                subtitles: subtitles,
                packageMode: "hls"
            ).merging(hls.metadata) { current, _ in current }
            return ResolvedDownload(
                title: title,
                folderName: "V LIVE \(title)".sanitizedFilename(maxLength: 120),
                assets: hls.assets.enumerated().map { offset, asset in
                    hlsAssetWithMetadata(asset, id: contentID, title: title, pageURL: pageURL, candidate: candidate, html: html, index: offset + 1)
                },
                packageMode: hls.packageMode,
                metadata: metadata
            )
        }

        let videoFilename = "\(title)-\(contentID).\(mediaFormat(for: candidate.url, fallback: "mp4"))".sanitizedFilename(maxLength: 180)
        let metadata = pageMetadata(
            id: contentID,
            title: title,
            pageURL: pageURL,
            mediaURL: candidate.url,
            html: html,
            candidate: candidate,
            subtitles: subtitles,
            packageMode: subtitles.isEmpty ? "concatenate" : "files"
        )
        var assets = [
            ResolvedAsset(
                remoteURL: candidate.url,
                filename: videoFilename,
                metadata: mediaMetadata(
                    id: contentID,
                    title: title,
                    pageURL: pageURL,
                    mediaURL: candidate.url,
                    candidate: candidate,
                    html: html,
                    index: 1
                ),
                referer: pageURL.absoluteString
            )
        ]
        assets.append(contentsOf: subtitles.enumerated().map { offset, subtitle in
            subtitleAsset(subtitle, id: contentID, title: title, pageURL: pageURL, index: offset + 2)
        })

        return ResolvedDownload(
            title: title,
            folderName: "V LIVE \(title)".sanitizedFilename(maxLength: 120),
            assets: assets,
            packageMode: subtitles.isEmpty ? .concatenate(outputFilename: videoFilename) : .files,
            metadata: metadata
        )
    }

    private static func appendVideoCandidate(rawURL: String, label: String, pageURL: URL, candidates: inout [VLiveVideoCandidate]) {
        for raw in expandedRawURLs(rawURL) {
            guard let url = absoluteURL(raw, baseURL: pageURL),
                  isPlayableVideo(url) else {
                continue
            }
            candidates.append(VLiveVideoCandidate(url: url, quality: qualityFrom(label: label, url: url), label: label))
            return
        }
    }

    private static func appendSubtitleCandidate(rawURL: String, language: String, label: String, pageURL: URL, candidates: inout [VLiveSubtitleCandidate]) {
        for raw in expandedRawURLs(rawURL) {
            guard let url = absoluteURL(raw, baseURL: pageURL),
                  isSubtitle(url) else {
                continue
            }
            let format = mediaFormat(for: url, fallback: "vtt")
            candidates.append(VLiveSubtitleCandidate(
                url: url,
                language: normalizedLanguage(language),
                label: cleanTitle(label, fallback: normalizedLanguage(language)),
                format: format
            ))
            return
        }
    }

    private static func bestVideoCandidate(_ candidates: [VLiveVideoCandidate]) -> VLiveVideoCandidate? {
        candidates.max { score($0) < score($1) }
    }

    private static func score(_ candidate: VLiveVideoCandidate) -> Int {
        let lower = candidate.url.absoluteString.lowercased()
        let urlBonus: Int
        if lower.contains(".mp4") || lower.contains(".webm") {
            urlBonus = 1_000_000_000
        } else if lower.contains(".m3u8") {
            urlBonus = 500_000_000
        } else {
            urlBonus = 0
        }
        return urlBonus + candidate.quality
    }

    private static func uniqueVideoCandidates(_ candidates: [VLiveVideoCandidate]) -> [VLiveVideoCandidate] {
        var seen = Set<String>()
        return candidates.filter { candidate in
            let key = URLIdentity.normalize(candidate.url.absoluteString)
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }

    private static func uniqueSubtitleCandidates(_ candidates: [VLiveSubtitleCandidate]) -> [VLiveSubtitleCandidate] {
        var seen = Set<String>()
        return candidates.filter { candidate in
            let key = URLIdentity.normalize(candidate.url.absoluteString)
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }

    private static func pageMetadata(
        id: String,
        title: String,
        pageURL: URL,
        mediaURL: URL,
        html: String,
        candidate: VLiveVideoCandidate,
        subtitles: [VLiveSubtitleCandidate],
        packageMode: String
    ) -> [String: String] {
        let height = candidate.quality > 0 && candidate.quality < 10_000 ? String(candidate.quality) : ""
        return DownloadMetadata.clean([
            "site": "V LIVE",
            "title": title,
            "series": title,
            "category": "video",
            "type": isM3U8(mediaURL) ? "hls" : "video",
            "media_type": isM3U8(mediaURL) ? "hls" : "video",
            "format": mediaFormat(for: mediaURL, fallback: isM3U8(mediaURL) ? "m3u8" : "mp4"),
            "media_format": mediaFormat(for: mediaURL, fallback: isM3U8(mediaURL) ? "m3u8" : "mp4"),
            "package_mode": packageMode,
            "host": pageURL.host ?? "",
            "id": id,
            "media_id": id,
            "video_id": id,
            "gallery_id": id,
            "quality": candidate.quality > 0 ? String(candidate.quality) : "",
            "height": height,
            "resolution": height.isEmpty ? "" : "\(height)p",
            "video_count": "1",
            "subtitle_count": subtitles.isEmpty ? "" : String(subtitles.count),
            "media_count": String(1 + subtitles.count),
            "video_url": mediaURL.absoluteString,
            "media_url": mediaURL.absoluteString,
            "playlist_url": isM3U8(mediaURL) ? mediaURL.absoluteString : "",
            "thumbnail": thumbnailURL(fromHTML: html, pageURL: pageURL)?.absoluteString ?? "",
            "url": pageURL.absoluteString,
            "source_url": pageURL.absoluteString,
            "page_url": pageURL.absoluteString
        ])
    }

    private static func mediaMetadata(
        id: String,
        title: String,
        pageURL: URL,
        mediaURL: URL,
        candidate: VLiveVideoCandidate,
        html: String,
        index: Int
    ) -> [String: String] {
        let height = candidate.quality > 0 && candidate.quality < 10_000 ? String(candidate.quality) : ""
        return DownloadMetadata.clean([
            "site": "V LIVE",
            "title": title,
            "series": title,
            "id": id,
            "media_id": id,
            "gallery_id": id,
            "video_id": id,
            "type": "video",
            "media_type": "video",
            "category": "video",
            "page": String(index),
            "position": String(index),
            "format": mediaFormat(for: mediaURL, fallback: "mp4"),
            "media_format": mediaFormat(for: mediaURL, fallback: "mp4"),
            "quality": candidate.quality > 0 ? String(candidate.quality) : "",
            "height": height,
            "resolution": height.isEmpty ? "" : "\(height)p",
            "thumbnail": thumbnailURL(fromHTML: html, pageURL: pageURL)?.absoluteString ?? "",
            "video_url": mediaURL.absoluteString,
            "media_url": mediaURL.absoluteString,
            "source_url": mediaURL.absoluteString,
            "page_url": pageURL.absoluteString
        ])
    }

    private static func hlsAssetWithMetadata(
        _ asset: ResolvedAsset,
        id: String,
        title: String,
        pageURL: URL,
        candidate: VLiveVideoCandidate,
        html: String,
        index: Int
    ) -> ResolvedAsset {
        var enriched = asset
        let height = candidate.quality > 0 && candidate.quality < 10_000 ? String(candidate.quality) : ""
        enriched.metadata = asset.metadata.merging(DownloadMetadata.clean([
            "site": "V LIVE",
            "title": title,
            "series": title,
            "id": id,
            "media_id": "\(id)-segment-\(index)",
            "gallery_id": id,
            "video_id": id,
            "type": asset.metadata["type"] ?? "hls_segment",
            "media_type": "segment",
            "category": "video",
            "page": String(index),
            "position": String(index),
            "format": mediaFormat(for: asset.remoteURL, fallback: "ts"),
            "media_format": mediaFormat(for: asset.remoteURL, fallback: "ts"),
            "quality": candidate.quality > 0 ? String(candidate.quality) : "",
            "height": height,
            "resolution": height.isEmpty ? "" : "\(height)p",
            "thumbnail": thumbnailURL(fromHTML: html, pageURL: pageURL)?.absoluteString ?? "",
            "playlist_url": candidate.url.absoluteString,
            "video_url": asset.remoteURL.absoluteString,
            "media_url": asset.remoteURL.absoluteString,
            "source_url": pageURL.absoluteString,
            "page_url": pageURL.absoluteString
        ])) { _, new in new }
        return enriched
    }

    private static func subtitleAsset(_ subtitle: VLiveSubtitleCandidate, id: String, title: String, pageURL: URL, index: Int) -> ResolvedAsset {
        let language = normalizedLanguage(subtitle.language)
        let filename = "\(title)-\(id)-\(language).\(subtitle.format)".sanitizedFilename(maxLength: 180)
        return ResolvedAsset(
            remoteURL: subtitle.url,
            filename: filename,
            metadata: DownloadMetadata.clean([
                "site": "V LIVE",
                "title": title,
                "series": title,
                "id": id,
                "media_id": "\(id)-subtitle-\(language)",
                "gallery_id": id,
                "video_id": id,
                "type": "subtitle",
                "media_type": "subtitle",
                "category": "subtitle",
                "page": String(index),
                "position": String(index),
                "language": language,
                "subtitle_language": language,
                "label": subtitle.label,
                "format": subtitle.format,
                "media_format": subtitle.format,
                "subtitle_url": subtitle.url.absoluteString,
                "media_url": subtitle.url.absoluteString,
                "source_url": subtitle.url.absoluteString,
                "page_url": pageURL.absoluteString
            ]),
            referer: pageURL.absoluteString
        )
    }

    private static func title(fromHTML html: String, fallback: String) -> String {
        let raw = metaContent(from: html, names: ["og:title", "twitter:title"]) ??
            elementText(pattern: #"<h1\b[^>]*>(.*?)</h1>"#, in: html) ??
            elementText(pattern: #"<title\b[^>]*>(.*?)</title>"#, in: html) ??
            fallback
        return cleanTitle(raw, fallback: fallback)
    }

    private static func cleanTitle(_ raw: String, fallback: String) -> String {
        var value = stripTags(decodeHTML(raw))
            .replacingOccurrences(of: #"[\r\n\t]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmed
        for suffix in [" - V LIVE", " | V LIVE", " - VLIVE", " | VLIVE", " - Vlive", " | Vlive"] where value.hasSuffix(suffix) {
            value.removeLast(suffix.count)
            value = value.trimmed
        }
        return value.isEmpty ? fallback : value
    }

    private static func thumbnailURL(fromHTML html: String, pageURL: URL) -> URL? {
        if let raw = metaContent(from: html, names: ["og:image", "twitter:image"]),
           let url = absoluteURL(raw, baseURL: pageURL) {
            return url
        }
        return nil
    }

    private static func metaContent(from html: String, names: [String]) -> String? {
        for name in names {
            let patterns = [
                #"<meta\b[^>]*(?:property|name)\s*=\s*["']\#(name)["'][^>]*content\s*=\s*["']([^"']+)["'][^>]*>"#,
                #"<meta\b[^>]*content\s*=\s*["']([^"']+)["'][^>]*(?:property|name)\s*=\s*["']\#(name)["'][^>]*>"#
            ]
            for pattern in patterns {
                if let value = capture(pattern: pattern, in: html, group: 2) ?? capture(pattern: pattern, in: html, group: 1) {
                    return decodeHTML(value).trimmed
                }
            }
        }
        return nil
    }

    private static func elementText(pattern: String, in html: String) -> String? {
        guard let raw = firstCapture(pattern: pattern, in: html) else { return nil }
        let text = cleanTitle(raw, fallback: "")
        return text.isEmpty ? nil : text
    }

    private static func attributeValue(_ name: String, in tag: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        return firstCapture(pattern: #"\b\#(escaped)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>"']+))"#, in: tag, groups: [1, 2, 3])
    }

    private static func expandedRawURLs(_ raw: String) -> [String] {
        let cleaned = normalizeEscapes(decodeHTML(raw)).trimmed
        var values = [cleaned]
        if let decoded = cleaned.removingPercentEncoding, decoded != cleaned {
            values.append(decoded)
        }
        return values
    }

    private static func absoluteURL(_ raw: String, baseURL: URL) -> URL? {
        var value = normalizeEscapes(decodeHTML(raw)).trimmed
        guard !value.isEmpty,
              !value.lowercased().hasPrefix("javascript:"),
              !value.lowercased().hasPrefix("data:") else {
            return nil
        }
        if value.hasPrefix("//") {
            value = (baseURL.scheme ?? "https") + ":" + value
        }
        guard let url = URL(string: value, relativeTo: baseURL)?.absoluteURL,
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }
        return url
    }

    private static func isPlayableVideo(_ url: URL) -> Bool {
        let lower = url.absoluteString.lowercased()
        return ["mp4", "m4v", "mov", "webm", "m3u8"].contains(url.pathExtension.lowercased()) ||
            lower.contains(".mp4") ||
            lower.contains(".m3u8") ||
            lower.contains(".webm")
    }

    private static func isSubtitle(_ url: URL) -> Bool {
        let lower = url.absoluteString.lowercased()
        return ["srt", "vtt", "ttml", "dfxp"].contains(url.pathExtension.lowercased()) ||
            lower.contains(".srt") ||
            lower.contains(".vtt") ||
            lower.contains(".ttml") ||
            lower.contains(".dfxp")
    }

    private static func isM3U8(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "m3u8" || url.absoluteString.lowercased().contains(".m3u8")
    }

    private static func mediaFormat(for url: URL, fallback: String) -> String {
        let ext = url.pathExtension.lowercased()
        if !ext.isEmpty { return ext }
        let lower = url.absoluteString.lowercased()
        for value in ["m3u8", "mp4", "m4v", "mov", "webm", "srt", "vtt", "ttml", "dfxp", "ts"] where lower.contains(".\(value)") {
            return value
        }
        return fallback
    }

    private static func qualityFrom(label: String, url: URL) -> Int {
        let labelText = label.lowercased()
        if labelText.contains("source") || labelText.contains("original") {
            return 10_000
        }
        let labelValues = qualityNumbers(in: label, requireQualityContext: false)
        if let best = labelValues.max() {
            return best
        }
        let urlValues = qualityNumbers(in: url.absoluteString, requireQualityContext: true)
        if let best = urlValues.max() {
            return best
        }
        return 0
    }

    private static func qualityNumbers(in text: String, requireQualityContext: Bool) -> [Int] {
        let trimmed = text.trimmed.lowercased()
        if !requireQualityContext,
           let value = Int(trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "p"))),
           (144...8640).contains(value) {
            return [value]
        }
        let pattern = requireQualityContext
            ? #"(?i)(?:^|[^0-9])([0-9]{3,4})p?(?=\.(?:mp4|m4v|mov|webm|m3u8)|[^0-9])"#
            : #"(?i)(?:^|[^0-9])([0-9]{3,4})\s*p(?:[^0-9]|$)"#
        return allCaptures(pattern: pattern, in: text)
            .compactMap(Int.init)
            .filter { (144...8640).contains($0) }
    }

    private static func normalizedLanguage(_ raw: String) -> String {
        let value = raw.trimmed.lowercased()
            .replacingOccurrences(of: #"[^a-z0-9._-]+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".-_"))
        return value.isEmpty ? "und" : value
    }

    private static func isSupportedHost(_ host: String) -> Bool {
        host == "vlive.tv" || host.hasSuffix(".vlive.tv")
    }

    private static func canonicalHost(from url: URL) -> String {
        guard let host = url.host?.lowercased(),
              isSupportedHost(host) else {
            return "www.vlive.tv"
        }
        return host.hasPrefix("m.") ? "www.vlive.tv" : host
    }

    private static func isValidID(_ id: String) -> Bool {
        !id.isEmpty && id.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil
    }

    private static func firstCapture(pattern: String, in text: String) -> String? {
        firstCapture(pattern: pattern, in: text, groups: [1])
    }

    private static func firstCapture(pattern: String, in text: String, groups: [Int]) -> String? {
        for group in groups {
            if let value = capture(pattern: pattern, in: text, group: group) {
                return value
            }
        }
        return nil
    }

    private static func capture(pattern: String, in text: String, group: Int) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > group,
              let capture = Range(match.range(at: group), in: text) else {
            return nil
        }
        return String(text[capture])
    }

    private static func allCaptures(pattern: String, in text: String) -> [String] {
        allCaptures(pattern: pattern, in: text, group: 1)
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

    private static func stripTags(_ raw: String) -> String {
        raw.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
    }

    private static func decodeHTML(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }

    private static func normalizeEscapes(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: #"\/"#, with: "/")
            .replacingOccurrences(of: #"\\/"#, with: "/")
            .replacingOccurrences(of: #"\u002F"#, with: "/")
            .replacingOccurrences(of: #"\u002f"#, with: "/")
    }
}
