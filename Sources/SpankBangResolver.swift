import Foundation

final class SpankBangResolver {
    func canResolve(_ url: URL) -> Bool {
        Self.videoID(from: url) != nil
    }

    func resolve(_ url: URL, headers: HTTPRequestOptions = HTTPRequestOptions()) async throws -> ResolvedDownload {
        guard let videoID = Self.videoID(from: url) else {
            throw NativeDownloadError.invalidURL(url.absoluteString)
        }

        let pageURL = Self.canonicalURL(for: videoID, sourceURL: url)
        let html = try await HTTPClient.shared.string(from: pageURL, referer: headers.referer, userAgent: headers.userAgent)
        guard let candidate = Self.bestVideoCandidate(fromHTML: html, pageURL: pageURL) else {
            throw NativeDownloadError.noFiles
        }

        if Self.isM3U8(candidate.url) {
            let hls = try await M3U8Resolver().resolve(
                candidate.url,
                headers: HTTPRequestOptions(referer: pageURL.absoluteString, userAgent: headers.userAgent)
            )
            let info = Self.videoInfo(fromHTML: html, fallbackID: videoID)
            return ResolvedDownload(
                title: info.title,
                folderName: "SpankBang \(info.folderTitle)".sanitizedFilename(maxLength: 120),
                assets: hls.assets.enumerated().map { offset, asset in
                    var enriched = asset
                    enriched.metadata = asset.metadata.merging(Self.segmentMetadata(
                        title: info.title,
                        videoID: videoID,
                        pageURL: pageURL,
                        asset: asset,
                        index: offset + 1
                    )) { _, new in new }
                    return enriched
                },
                packageMode: .concatenate(outputFilename: "\(info.title)-\(videoID).ts".sanitizedFilename(maxLength: 180)),
                metadata: Self.metadata(videoID: videoID, title: info.title, pageURL: pageURL, videoURL: candidate.url, html: html, quality: candidate.quality)
                    .merging(hls.metadata) { current, _ in current }
            )
        }

        return Self.resolvedDirectDownload(videoURL: candidate.url, pageURL: pageURL, pageHTML: html, videoID: videoID, quality: candidate.quality)
    }

    static func videoID(from url: URL) -> String? {
        guard let host = url.host?.lowercased(),
              isSupportedHost(host),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }

        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true).map { String($0).removingPercentEncoding ?? String($0) }
        guard let first = parts.first?.trimmed, isValidID(first) else {
            return nil
        }
        let reserved = Set(["s", "search", "tag", "tags", "category", "categories", "users", "user", "channels", "channel", "pornstars", "playlist"])
        guard !reserved.contains(first.lowercased()) else {
            return nil
        }
        return first
    }

    static func canonicalURL(for videoID: String, sourceURL: URL) -> URL {
        var components = URLComponents()
        components.scheme = sourceURL.scheme ?? "https"
        components.host = sourceURL.host?.lowercased().hasSuffix(".test") == true ? "spankbang.test" : "spankbang.com"
        components.path = "/\(videoID)/video"
        return components.url!
    }

    static func canonicalURL(for url: URL) -> URL? {
        guard let videoID = videoID(from: url) else { return nil }
        return canonicalURL(for: videoID, sourceURL: url)
    }

    static func bestVideoCandidate(fromHTML html: String, pageURL: URL) -> (quality: Int, url: URL)? {
        let stream = streamDataBlock(fromHTML: html) ?? html
        var candidates: [(quality: Int, url: URL)] = []
        candidates.append(contentsOf: formatObjectCandidates(in: stream, pageURL: pageURL))
        for pattern in [
            #"['"]?([0-9]{3,4})p['"]?\s*:\s*(?:\[\s*)?['"]([^'"]+)['"]"#,
            #"['"]?([0-9]{3,4})['"]?\s*:\s*(?:\[\s*)?['"]([^'"]+)['"]"#
        ] {
            for match in captures(pattern: pattern, in: stream, groups: [1, 2]) {
                guard match.count == 2,
                      let quality = Int(match[0]),
                      let url = absoluteURL(match[1], baseURL: pageURL),
                      isPlayableVideo(url) else {
                    continue
                }
                candidates.append((quality, url))
            }
        }

        if candidates.isEmpty {
            let urlPattern = #"https?:\\/\\/[^'"\s<>]+?\.(?:mp4|m3u8)(?:\?[^'"\s<>]*)?"#
            for raw in allCaptures(pattern: urlPattern, in: stream, group: 0) {
                guard let url = absoluteURL(raw, baseURL: pageURL),
                      isPlayableVideo(url) else {
                    continue
                }
                candidates.append((qualityFromURL(url), url))
            }
        }

        var seen = Set<String>()
        let unique = candidates.filter { candidate in
            let key = candidate.url.absoluteString
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
        return unique.max {
            if $0.quality == $1.quality {
                return $0.url.absoluteString < $1.url.absoluteString
            }
            return $0.quality < $1.quality
        }
    }

    static func resolvedDirectDownload(videoURL: URL, pageURL: URL, pageHTML: String, videoID: String, quality: Int? = nil) -> ResolvedDownload {
        let info = videoInfo(fromHTML: pageHTML, fallbackID: videoID)
        let filename = "\(info.title)-\(videoID).\(videoURL.pathExtension.trimmed.isEmpty ? "mp4" : videoURL.pathExtension)"
            .sanitizedFilename(maxLength: 180)
        return ResolvedDownload(
            title: info.title,
            folderName: "SpankBang \(info.folderTitle)".sanitizedFilename(maxLength: 120),
            assets: [
                ResolvedAsset(remoteURL: videoURL, filename: filename, metadata: mediaMetadata(for: videoURL, title: info.title, videoID: videoID, pageURL: pageURL, quality: quality), referer: pageURL.absoluteString)
            ],
            packageMode: .concatenate(outputFilename: filename),
            metadata: metadata(videoID: videoID, title: info.title, pageURL: pageURL, videoURL: videoURL, html: pageHTML, quality: quality)
        )
    }

    private static func videoInfo(fromHTML html: String, fallbackID: String) -> (title: String, folderTitle: String) {
        let title = cleanTitle(
            elementText(pattern: #"<h1\b[^>]*>(.*?)</h1>"#, in: html) ??
                metaContent(from: html, names: ["og:title", "twitter:title"]) ??
                elementText(pattern: #"<title\b[^>]*>(.*?)</title>"#, in: html) ??
                "SpankBang \(fallbackID)",
            fallback: "SpankBang \(fallbackID)"
        )
        return (title, title)
    }

    private static func metadata(videoID: String, title: String, pageURL: URL, videoURL: URL, html: String, quality: Int? = nil) -> [String: String] {
        let height = videoHeight(from: videoURL, fallbackQuality: quality)
        let resolution = height.map { "\($0)p" } ?? ""
        return DownloadMetadata.clean([
            "site": "SpankBang",
            "title": title,
            "series": title,
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
            "media_count": isM3U8(videoURL) ? "" : "1",
            "video_count": "1",
            "video_url": videoURL.absoluteString,
            "media_url": videoURL.absoluteString,
            "playlist_url": isM3U8(videoURL) ? videoURL.absoluteString : "",
            "thumbnail": thumbnailURL(fromHTML: html, pageURL: pageURL)?.absoluteString ?? "",
            "url": pageURL.absoluteString,
            "source_url": pageURL.absoluteString,
            "page_url": pageURL.absoluteString
        ])
    }

    private static func mediaMetadata(for videoURL: URL, title: String, videoID: String, pageURL: URL, quality: Int? = nil) -> [String: String] {
        let height = videoHeight(from: videoURL, fallbackQuality: quality)
        let resolution = height.map { "\($0)p" } ?? ""
        return DownloadMetadata.clean([
            "site": "SpankBang",
            "title": title,
            "series": title,
            "category": "video",
            "type": isM3U8(videoURL) ? "hls" : "video",
            "media_type": isM3U8(videoURL) ? "hls" : "video",
            "format": mediaFormat(for: videoURL),
            "media_format": mediaFormat(for: videoURL),
            "id": videoID,
            "video_id": videoID,
            "media_id": videoID,
            "gallery_id": videoID,
            "page": "1",
            "position": "1",
            "height": height ?? "",
            "resolution": resolution,
            "quality": resolution,
            "video_url": videoURL.absoluteString,
            "media_url": videoURL.absoluteString,
            "playlist_url": isM3U8(videoURL) ? videoURL.absoluteString : "",
            "source_url": pageURL.absoluteString,
            "page_url": pageURL.absoluteString
        ])
    }

    private static func segmentMetadata(title: String, videoID: String, pageURL: URL, asset: ResolvedAsset, index: Int) -> [String: String] {
        let format = mediaFormat(for: asset.remoteURL, fallback: mediaFormat(forFilename: asset.filename, fallback: "ts"))
        return DownloadMetadata.clean([
            "site": "SpankBang",
            "title": title,
            "series": title,
            "category": "video",
            "type": "hls_segment",
            "media_type": "segment",
            "format": format,
            "media_format": format,
            "id": videoID,
            "video_id": videoID,
            "media_id": "\(videoID)-segment-\(index)",
            "gallery_id": videoID,
            "page": String(index),
            "position": String(index),
            "video_url": asset.remoteURL.absoluteString,
            "media_url": asset.remoteURL.absoluteString,
            "source_url": pageURL.absoluteString,
            "page_url": pageURL.absoluteString
        ])
    }

    private static func streamDataBlock(fromHTML html: String) -> String? {
        balancedScriptValue(named: "stream_data", in: html) ??
            quotedScriptValue(named: "stream_data", in: html)
    }

    private static func formatObjectCandidates(in text: String, pageURL: URL) -> [(quality: Int, url: URL)] {
        allCaptures(pattern: #"\{[^{}]*\}"#, in: text, group: 0).compactMap { object in
            guard let rawURL = firstCapture(
                pattern: #"['"](?:url|file|src|video_url|videoUrl)['"]\s*:\s*['"]([^'"]+)['"]"#,
                in: object
            ) ?? firstCapture(
                pattern: #"\b(?:url|file|src|video_url|videoUrl)\s*:\s*['"]([^'"]+)['"]"#,
                in: object
            ),
                  let url = absoluteURL(rawURL, baseURL: pageURL),
                  isPlayableVideo(url) else {
                return nil
            }

            let quality = firstCapture(pattern: #"['"](?:height|quality|resolution)['"]\s*:\s*['"]?([0-9]{3,4})p?['"]?"#, in: object)
                .flatMap(Int.init) ??
                firstCapture(pattern: #"\b(?:height|quality|resolution)\s*:\s*['"]?([0-9]{3,4})p?['"]?"#, in: object)
                .flatMap(Int.init) ??
                qualityFromURL(url)
            return (quality, url)
        }
    }

    private static func balancedScriptValue(named name: String, in html: String) -> String? {
        let assignmentPattern = #"(?:var\s+)?\#(NSRegularExpression.escapedPattern(for: name))\s*="#
        guard let regex = try? NSRegularExpression(pattern: assignmentPattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..<html.endIndex, in: html)),
              let matchRange = Range(match.range, in: html) else {
            return nil
        }

        var index = matchRange.upperBound
        while index < html.endIndex, html[index].isWhitespace {
            index = html.index(after: index)
        }
        guard index < html.endIndex,
              html[index] == "{" || html[index] == "[" else {
            return nil
        }

        let opener = html[index]
        let closer: Character = opener == "{" ? "}" : "]"
        var depth = 0
        var inString: Character?
        var escaped = false
        var cursor = index
        while cursor < html.endIndex {
            let char = html[cursor]
            if let quote = inString {
                if escaped {
                    escaped = false
                } else if char == "\\" {
                    escaped = true
                } else if char == quote {
                    inString = nil
                }
                cursor = html.index(after: cursor)
                continue
            }

            if char == "\"" || char == "'" {
                inString = char
            } else if char == opener {
                depth += 1
            } else if char == closer {
                depth -= 1
                if depth == 0 {
                    return String(html[index...cursor])
                }
            }
            cursor = html.index(after: cursor)
        }
        return nil
    }

    private static func quotedScriptValue(named name: String, in html: String) -> String? {
        let assignmentPattern = #"(?:var\s+)?\#(NSRegularExpression.escapedPattern(for: name))\s*="#
        guard let regex = try? NSRegularExpression(pattern: assignmentPattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..<html.endIndex, in: html)),
              let matchRange = Range(match.range, in: html) else {
            return nil
        }

        var index = matchRange.upperBound
        while index < html.endIndex, html[index].isWhitespace {
            index = html.index(after: index)
        }
        guard index < html.endIndex, html[index] == "\"" || html[index] == "'" else {
            return nil
        }

        let quote = html[index]
        var escaped = false
        var cursor = html.index(after: index)
        while cursor < html.endIndex {
            let char = html[cursor]
            if escaped {
                escaped = false
            } else if char == "\\" {
                escaped = true
            } else if char == quote {
                let literal = String(html[index...cursor])
                return decodedScriptString(literal, quote: quote)
            }
            cursor = html.index(after: cursor)
        }
        return nil
    }

    private static func decodedScriptString(_ literal: String, quote: Character) -> String? {
        if quote == "\"",
           let data = literal.data(using: .utf8),
           let value = try? JSONSerialization.jsonObject(with: data) as? String {
            return decodeHTML(value)
        }
        var value = literal
        if value.count >= 2 {
            value.removeFirst()
            value.removeLast()
        }
        return decodeHTML(value)
            .replacingOccurrences(of: #"\""#, with: #"""#)
            .replacingOccurrences(of: #"\'"#, with: "'")
            .replacingOccurrences(of: #"\/"#, with: "/")
            .replacingOccurrences(of: #"\\/"#, with: "/")
            .replacingOccurrences(of: #"\u002F"#, with: "/", options: .caseInsensitive)
            .replacingOccurrences(of: #"\u003A"#, with: ":", options: .caseInsensitive)
            .replacingOccurrences(of: #"\u0026"#, with: "&", options: .caseInsensitive)
    }

    private static func thumbnailURL(fromHTML html: String, pageURL: URL) -> URL? {
        guard let raw = metaContent(from: html, names: ["og:image", "twitter:image"]) else { return nil }
        return absoluteURL(raw, baseURL: pageURL)
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

    private static func firstCapture(pattern: String, in text: String) -> String? {
        capture(pattern: pattern, in: text, group: 1)
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

    private static func captures(pattern: String, in text: String, groups: [Int]) -> [[String]] {
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

    private static func absoluteURL(_ raw: String, baseURL: URL) -> URL? {
        var value = decodeHTML(raw)
            .replacingOccurrences(of: #"\/"#, with: "/")
            .replacingOccurrences(of: #"\\/"#, with: "/")
            .trimmed
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

    private static func isSupportedHost(_ host: String) -> Bool {
        host == "spankbang.com" ||
            host == "www.spankbang.com" ||
            host == "spankbang.test" ||
            host == "www.spankbang.test"
    }

    private static func isValidID(_ value: String) -> Bool {
        value.range(of: #"^[0-9A-Za-z_-]+$"#, options: .regularExpression) != nil
    }

    private static func isPlayableVideo(_ url: URL) -> Bool {
        ["mp4", "webm", "m4v", "mov", "m3u8"].contains(url.pathExtension.lowercased()) ||
            url.absoluteString.lowercased().contains(".m3u8")
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
        let ext = url.pathExtension.trimmed
        return (ext.isEmpty ? fallback : ext).lowercased()
    }

    private static func mediaFormat(forFilename filename: String, fallback: String) -> String {
        let ext = URL(fileURLWithPath: filename).pathExtension.trimmed
        return ext.isEmpty ? fallback : ext.lowercased()
    }

    private static func videoHeight(from url: URL, fallbackQuality: Int? = nil) -> String? {
        let source = url.absoluteString.lowercased()
        let patterns = [
            #"(?<![0-9])([1-9][0-9]{2,3})p(?![0-9])"#,
            #"(?<![0-9])([1-9][0-9]{2,3})[xX][1-9][0-9]{2,4}(?![0-9])"#,
            #"(?<![0-9])[1-9][0-9]{2,4}[xX]([1-9][0-9]{2,3})(?![0-9])"#,
            #"(?:height|res|resolution|quality)[=_-]([1-9][0-9]{2,3})(?:p)?(?:&|$)"#
        ]
        for pattern in patterns {
            guard let value = firstCapture(pattern: pattern, in: source),
                  let number = Int(value),
                  number >= 144,
                  number <= 4320 else {
                continue
            }
            return String(number)
        }
        guard let fallbackQuality,
              fallbackQuality >= 144,
              fallbackQuality <= 4320 else {
            return nil
        }
        return String(fallbackQuality)
    }

    private static func qualityFromURL(_ url: URL) -> Int {
        firstCapture(pattern: #"([0-9]{3,4})p"#, in: url.absoluteString).flatMap(Int.init) ?? 0
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
        for suffix in [" - SpankBang", " | SpankBang", " - SpankBang.com", " | SpankBang.com"] {
            if text.lowercased().hasSuffix(suffix.lowercased()) {
                text = String(text.dropLast(suffix.count)).trimmed
            }
        }
        return (text.isEmpty ? fallback : text).sanitizedFilename(maxLength: 120)
    }
}
