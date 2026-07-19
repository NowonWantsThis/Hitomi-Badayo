import Foundation

struct KakaoTVFormatCandidate {
    var url: URL
    var height: Int
    var width: Int
    var label: String
    var extensionHint: String
    var score: Int
}

final class KakaoTVResolver {
    func canResolve(_ url: URL) -> Bool {
        Self.clipID(from: url) != nil
    }

    func resolve(_ url: URL, headers: HTTPRequestOptions = HTTPRequestOptions()) async throws -> ResolvedDownload {
        guard Self.clipID(from: url) != nil else {
            throw NativeDownloadError.invalidURL(url.absoluteString)
        }
        let pageURL = Self.normalizedURL(url)
        let html = try await HTTPClient.shared.string(from: pageURL, referer: headers.referer, userAgent: headers.userAgent)
        if let resolved = try? await Self.resolvedDownload(fromHTML: html, pageURL: pageURL, userAgent: headers.userAgent) {
            return resolved
        }
        throw NativeDownloadError.noFiles
    }

    static func clipID(from url: URL) -> String? {
        guard let host = url.host?.lowercased(),
              isSupportedHost(host),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }

        let normalized = normalizedURL(url)
        let parts = normalized.path.split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        let lower = parts.map { $0.lowercased() }

        if let marker = lower.firstIndex(of: "cliplink"), marker + 1 < parts.count, isValidID(parts[marker + 1]) {
            return parts[marker + 1]
        }
        if let marker = lower.firstIndex(of: "v"), marker + 1 < parts.count, isValidID(parts[marker + 1]) {
            return parts[marker + 1]
        }
        if lower.first == "cliplink", parts.count >= 2, isValidID(parts[1]) {
            return parts[1]
        }

        let items = URLComponents(url: normalized, resolvingAgainstBaseURL: false)?.queryItems ?? []
        for name in ["cliplink", "clipLink", "clipId", "clipid", "videoId", "videoid"] {
            if let value = items.first(where: { $0.name.lowercased() == name.lowercased() })?.value,
               isValidID(value) {
                return value
            }
        }
        return nil
    }

    static func normalizedURL(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        let path = components.path
        if path == "/m" {
            components.path = "/"
        } else if path.hasPrefix("/m/") {
            components.path = String(path.dropFirst(2))
        }
        return components.url ?? url
    }

    static func canonicalURL(for url: URL) -> URL? {
        guard let clipID = clipID(from: url) else { return nil }
        var components = URLComponents()
        components.scheme = url.scheme ?? "https"
        components.host = url.host?.lowercased().hasSuffix(".test") == true ? "tv.kakao.test" : "tv.kakao.com"
        components.path = "/v/\(clipID)"
        return components.url
    }

    static func formatCandidates(fromHTML html: String, pageURL: URL) -> [KakaoTVFormatCandidate] {
        var candidates: [KakaoTVFormatCandidate] = []
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

    static func bestCandidate(_ candidates: [KakaoTVFormatCandidate]) -> KakaoTVFormatCandidate? {
        let mp4Candidates = candidates.filter(\.isDirectMP4)
        let pool = mp4Candidates.isEmpty ? candidates : mp4Candidates
        return pool.max { lhs, rhs in
            if lhs.height != rhs.height { return lhs.height < rhs.height }
            if lhs.isDirectMP4 != rhs.isDirectMP4 { return !lhs.isDirectMP4 && rhs.isDirectMP4 }
            return lhs.score < rhs.score
        }
    }

    static func resolvedDownload(fromHTML html: String, pageURL: URL, userAgent: String? = nil) async throws -> ResolvedDownload {
        guard let clipID = clipID(from: pageURL) else {
            throw NativeDownloadError.invalidURL(pageURL.absoluteString)
        }
        guard let candidate = bestCandidate(formatCandidates(fromHTML: html, pageURL: pageURL)) else {
            throw NativeDownloadError.noFiles
        }
        let info = videoInfo(fromHTML: html, pageURL: pageURL, fallbackID: clipID)
        if isM3U8(candidate.url) {
            let hls = try await M3U8Resolver().resolve(
                candidate.url,
                headers: HTTPRequestOptions(referer: pageURL.absoluteString, userAgent: userAgent)
            )
            return ResolvedDownload(
                title: info.displayTitle,
                folderName: "KakaoTV \(info.displayTitle)".sanitizedFilename(maxLength: 120),
                assets: hlsAssetsWithPageMetadata(hls.assets, info: info, pageURL: pageURL),
                packageMode: .concatenate(outputFilename: "\(info.title)-\(info.id).ts".sanitizedFilename(maxLength: 180)),
                metadata: hls.metadata.merging(metadata(info: info, candidate: candidate, pageURL: pageURL)) { _, new in new }
            )
        }

        let ext = candidate.url.pathExtension.trimmed.isEmpty ? (candidate.extensionHint.isEmpty ? "mp4" : candidate.extensionHint) : candidate.url.pathExtension
        let filename = "\(info.title)-\(info.id).\(ext)".sanitizedFilename(maxLength: 180)
        return ResolvedDownload(
            title: info.displayTitle,
            folderName: "KakaoTV \(info.displayTitle)".sanitizedFilename(maxLength: 120),
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

    static func videoInfo(fromHTML html: String, pageURL: URL, fallbackID: String) -> (id: String, title: String, displayTitle: String, uploader: String, thumbnail: URL?) {
        var infoObjects = jsonObjects(fromHTML: html)
        if infoObjects.isEmpty, let data = "{}".data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data) {
            infoObjects = [object]
        }
        let id = firstRecursiveString(in: infoObjects, keys: ["id", "clip_id", "clipId", "video_id", "videoId"]) ?? fallbackID
        let title = cleanTitle(
            firstRecursiveString(in: infoObjects, keys: ["title", "fulltitle", "display_title", "displayTitle"]) ??
                metaContent(from: html, names: ["og:title", "twitter:title"]) ??
                titleTag(fromHTML: html) ??
                "KakaoTV \(fallbackID)",
            fallback: "KakaoTV \(fallbackID)"
        )
        let uploader = cleanTitle(
            firstRecursiveString(in: infoObjects, keys: ["uploader", "artist", "author", "channel", "channel_name", "channelName"]) ?? "",
            fallback: ""
        )
        let thumbnailRaw = bestThumbnail(from: infoObjects, pageURL: pageURL)?.absoluteString ??
            metaContent(from: html, names: ["og:image", "twitter:image"])
        let displayTitle = uploader.isEmpty ? title : "\(uploader) - \(title)"
        return (id, title, displayTitle.sanitizedFilename(maxLength: 120), uploader, thumbnailRaw.flatMap { absoluteURL($0, baseURL: pageURL) })
    }

    private static func metadata(info: (id: String, title: String, displayTitle: String, uploader: String, thumbnail: URL?), candidate: KakaoTVFormatCandidate, pageURL: URL) -> [String: String] {
        DownloadMetadata.clean([
            "site": "KakaoTV",
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
            "clip_id": info.id,
            "video_id": info.id,
            "media_id": info.id,
            "gallery_id": info.id,
            "media_count": isM3U8(candidate.url) ? "" : "1",
            "video_count": "1",
            "height": candidate.height > 0 ? String(candidate.height) : "",
            "width": candidate.width > 0 ? String(candidate.width) : "",
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

    private static func mediaMetadata(for candidate: KakaoTVFormatCandidate, info: (id: String, title: String, displayTitle: String, uploader: String, thumbnail: URL?), pageURL: URL) -> [String: String] {
        DownloadMetadata.clean([
            "site": "KakaoTV",
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
            "clip_id": info.id,
            "video_id": info.id,
            "media_id": info.id,
            "gallery_id": info.id,
            "page": "1",
            "position": "1",
            "height": candidate.height > 0 ? String(candidate.height) : "",
            "width": candidate.width > 0 ? String(candidate.width) : "",
            "resolution": resolution(for: candidate),
            "quality": qualityLabel(for: candidate),
            "video_url": candidate.url.absoluteString,
            "media_url": candidate.url.absoluteString,
            "playlist_url": isM3U8(candidate.url) ? candidate.url.absoluteString : "",
            "source_url": pageURL.absoluteString,
            "page_url": pageURL.absoluteString
        ])
    }

    static func hlsAssetsWithPageMetadata(_ assets: [ResolvedAsset], info: (id: String, title: String, displayTitle: String, uploader: String, thumbnail: URL?), pageURL: URL) -> [ResolvedAsset] {
        assets.enumerated().map { offset, asset in
            var enriched = asset
            enriched.metadata = asset.metadata.merging(segmentMetadata(info: info, asset: asset, pageURL: pageURL, index: offset + 1)) { _, new in new }
            return enriched
        }
    }

    private static func segmentMetadata(info: (id: String, title: String, displayTitle: String, uploader: String, thumbnail: URL?), asset: ResolvedAsset, pageURL: URL, index: Int) -> [String: String] {
        let format = mediaFormat(for: asset.remoteURL, fallback: mediaFormat(forFilename: asset.filename, fallback: "ts"))
        return DownloadMetadata.clean([
            "site": "KakaoTV",
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
            "clip_id": info.id,
            "video_id": info.id,
            "media_id": "\(info.id)-segment-\(index)",
            "gallery_id": info.id,
            "page": String(index),
            "position": String(index),
            "video_url": asset.remoteURL.absoluteString,
            "media_url": asset.remoteURL.absoluteString,
            "source_url": pageURL.absoluteString,
            "page_url": pageURL.absoluteString
        ])
    }

    private static func mediaFormat(for candidate: KakaoTVFormatCandidate) -> String {
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

    private static func resolution(for candidate: KakaoTVFormatCandidate) -> String {
        if candidate.height > 0 { return "\(candidate.height)p" }
        if let height = heightFromText(candidate.label) { return "\(height)p" }
        return ""
    }

    private static func qualityLabel(for candidate: KakaoTVFormatCandidate) -> String {
        let resolution = resolution(for: candidate)
        return resolution.isEmpty ? candidate.label : resolution
    }

    private static func collectFormatCandidates(in value: Any, pageURL: URL, keyPath: [String], candidates: inout [KakaoTVFormatCandidate]) {
        if let raw = stringValue(value),
           let url = absoluteURL(raw, baseURL: pageURL),
           isLikelyVideoURL(url) {
            candidates.append(KakaoTVFormatCandidate(
                url: url,
                height: heightFromText((keyPath + [raw]).joined(separator: " ")) ?? 0,
                width: 0,
                label: keyPath.last ?? "",
                extensionHint: url.pathExtension.lowercased(),
                score: score(raw: raw, keyPath: keyPath)
            ))
            return
        }

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

    private static func candidate(from dict: [String: Any], pageURL: URL, keyPath: [String]) -> KakaoTVFormatCandidate? {
        let urlKeys = ["url", "file", "src", "video_url", "videoUrl", "play_url", "playUrl", "download_url", "downloadUrl"]
        for key in urlKeys {
            guard let raw = stringValue(dict[key]),
                  let url = absoluteURL(raw, baseURL: pageURL),
                  isLikelyVideoURL(url) else {
                continue
            }
            let height = intValue(dict["height"]) ??
                intValue(dict["format_height"]) ??
                intValue(dict["resolution"]) ??
                stringValue(dict["format_note"]).flatMap(heightFromText) ??
                stringValue(dict["quality"]).flatMap(heightFromText) ??
                heightFromText(raw) ??
                0
            let width = intValue(dict["width"]) ?? intValue(dict["format_width"]) ?? 0
            let label = cleanTitle(
                stringValue(dict["format"]) ??
                    stringValue(dict["format_id"]) ??
                    stringValue(dict["format_note"]) ??
                    stringValue(dict["quality"]) ??
                    "",
                fallback: ""
            )
            let ext = stringValue(dict["ext"]) ?? stringValue(dict["extension"]) ?? url.pathExtension.lowercased()
            return KakaoTVFormatCandidate(url: url, height: height, width: width, label: label, extensionHint: ext, score: score(raw: raw, keyPath: keyPath + [label]))
        }
        return nil
    }

    private static func directVideoCandidates(fromHTML html: String, pageURL: URL) -> [KakaoTVFormatCandidate] {
        let patterns = [
            #"\b(?:src|href)\s*=\s*["']([^"']+\.(?:mp4|m3u8)(?:\?[^"']*)?)["']"#,
            #""(?:url|file|videoUrl|playUrl)"\s*:\s*"([^"]+\.(?:mp4|m3u8)(?:\?[^"]*)?)""#
        ]
        return patterns.flatMap { pattern in
            captures(pattern: pattern, in: html).compactMap { raw in
                guard let url = absoluteURL(raw, baseURL: pageURL), isLikelyVideoURL(url) else { return nil }
                return KakaoTVFormatCandidate(url: url, height: heightFromText(raw) ?? 0, width: 0, label: "", extensionHint: url.pathExtension.lowercased(), score: score(raw: raw, keyPath: []))
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
            guard raw.hasPrefix("{") || raw.hasPrefix("[") else { return nil }
            return raw
        }
    }

    private static func assignmentPayloads(fromHTML html: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"(?:window\.[\w$]+|window\[[^\]]+\]|(?:var|let|const)\s+[\w$]+)\s*="#, options: [.caseInsensitive]) else {
            return []
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        return regex.matches(in: html, range: range).compactMap { match in
            guard let matchRange = Range(match.range, in: html) else { return nil }
            return balancedValue(startingAtOrAfter: matchRange.upperBound, in: html)
        }
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

    private static func bestThumbnail(from objects: [Any], pageURL: URL) -> URL? {
        for object in objects {
            if let originalStyle = firstThumbnail(in: object, pageURL: pageURL) {
                return originalStyle
            }
        }

        var candidates: [(url: URL, score: Int)] = []
        for object in objects {
            collectThumbnails(in: object, pageURL: pageURL, keyPath: [], candidates: &candidates)
        }
        return candidates.max { lhs, rhs in lhs.score < rhs.score }?.url
    }

    private static func firstThumbnail(in value: Any, pageURL: URL) -> URL? {
        if let dict = value as? [String: Any] {
            for key in ["thumbnails", "thumbnailList", "thumbs"] {
                if let array = dict[key] as? [Any] {
                    for item in array {
                        if let url = firstThumbnail(in: item, pageURL: pageURL) {
                            return url
                        }
                    }
                }
            }

            for key in ["url", "src", "thumbnail", "thumbnail_url", "thumbnailUrl", "thumb_url", "thumbUrl", "thumb"] {
                guard let raw = stringValue(dict[key]),
                      let url = absoluteURL(raw, baseURL: pageURL),
                      isImageURL(url) else {
                    continue
                }
                return url
            }

            for child in dict.values {
                if let url = firstThumbnail(in: child, pageURL: pageURL) {
                    return url
                }
            }
        }

        if let array = value as? [Any] {
            for item in array {
                if let url = firstThumbnail(in: item, pageURL: pageURL) {
                    return url
                }
            }
        }

        return nil
    }

    private static func collectThumbnails(in value: Any, pageURL: URL, keyPath: [String], candidates: inout [(url: URL, score: Int)]) {
        if let raw = stringValue(value),
           keyPath.map({ $0.lowercased() }).joined(separator: ".").contains("thumb"),
           let url = absoluteURL(raw, baseURL: pageURL),
           isImageURL(url) {
            candidates.append((url, thumbnailScore(raw: raw, keyPath: keyPath)))
            return
        }
        if let dict = value as? [String: Any] {
            if let raw = stringValue(dict["url"]) ?? stringValue(dict["src"]),
               let url = absoluteURL(raw, baseURL: pageURL),
               isImageURL(url),
               keyPath.map({ $0.lowercased() }).joined(separator: ".").contains("thumb") || dict["width"] != nil {
                candidates.append((url, thumbnailScore(raw: raw, keyPath: keyPath) + (intValue(dict["width"]) ?? 0)))
            }
            for (key, child) in dict {
                collectThumbnails(in: child, pageURL: pageURL, keyPath: keyPath + [key], candidates: &candidates)
            }
        }
        if let array = value as? [Any] {
            for child in array {
                collectThumbnails(in: child, pageURL: pageURL, keyPath: keyPath, candidates: &candidates)
            }
        }
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
        score += heightFromText(text) ?? 0
        return score
    }

    private static func thumbnailScore(raw: String, keyPath: [String]) -> Int {
        var score = 0
        let text = (keyPath.joined(separator: ".") + " " + raw).lowercased()
        if text.contains("thumbnail") || text.contains("thumb") { score += 100_000 }
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
        host == "tv.kakao.com" ||
            host.hasSuffix(".tv.kakao.com") ||
            host == "kakao.tv" ||
            host.hasSuffix(".kakao.tv") ||
            host == "kakaotv.daum.net" ||
            host.hasSuffix(".kakaotv.daum.net") ||
            host == "tv.kakao.test" ||
            host.hasSuffix(".tv.kakao.test") ||
            host == "kakao.test" ||
            host.hasSuffix(".kakao.test") ||
            host == "kakaotv.daum.test" ||
            host.hasSuffix(".kakaotv.daum.test")
    }

    private static func isLikelyVideoURL(_ url: URL) -> Bool {
        let text = url.absoluteString.lowercased()
        return ["mp4", "m3u8", "webm", "m4v", "mov"].contains(url.pathExtension.lowercased()) ||
            text.contains(".mp4") ||
            text.contains(".m3u8") ||
            text.contains("videofarm") ||
            text.contains("kakao") && text.contains("video")
    }

    private static func isImageURL(_ url: URL) -> Bool {
        let text = url.absoluteString.lowercased()
        return ["jpg", "jpeg", "png", "webp"].contains(url.pathExtension.lowercased()) ||
            text.contains(".jpg") ||
            text.contains(".jpeg") ||
            text.contains(".png") ||
            text.contains(".webp")
    }

    private static func isM3U8(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "m3u8" || url.absoluteString.lowercased().contains(".m3u8")
    }

    private static func isValidID(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z0-9_-]{2,}$"#, options: .regularExpression) != nil
    }

    private static func cleanTitle(_ raw: String, fallback: String) -> String {
        var value = decodeHTML(stripTags(raw))
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmed
        value = value.replacingOccurrences(of: #"(?i)\s*[-|]\s*KakaoTV\s*$"#, with: "", options: .regularExpression)
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

private extension KakaoTVFormatCandidate {
    var isDirectMP4: Bool {
        url.pathExtension.lowercased() == "mp4" || extensionHint.lowercased() == "mp4"
    }
}
