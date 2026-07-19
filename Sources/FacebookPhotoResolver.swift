import Foundation

struct FacebookPhotoCandidate {
    var url: URL
    var score: Int
    var source: String
}

final class FacebookPhotoResolver {
    func canResolve(_ url: URL) -> Bool {
        Self.photoID(from: url) != nil
    }

    func resolve(_ url: URL, headers: HTTPRequestOptions = HTTPRequestOptions()) async throws -> ResolvedDownload {
        let html = try await HTTPClient.shared.string(from: url, referer: headers.referer, userAgent: headers.userAgent)
        return try Self.resolvedDownload(fromHTML: html, pageURL: url)
    }

    static func photoID(from url: URL) -> String? {
        guard let host = url.host?.lowercased(),
              isSupportedHost(host),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }

        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        let lower = parts.map { $0.lowercased() }

        if lower.contains("videos") || lower.first == "watch" || lower.first == "video.php" || lower.first == "reel" {
            return nil
        }

        if let queryID = queryValue(names: ["fbid", "photo_id", "photoId"], in: url),
           isNumericID(queryID) {
            return queryID
        }

        if let marker = lower.firstIndex(of: "photos") {
            let after = parts[(marker + 1)...]
            if let id = after.reversed().first(where: { isNumericID($0) }) {
                return id
            }
        }

        if lower.first == "photo", parts.count >= 2, isNumericID(parts[1]) {
            return parts[1]
        }
        return nil
    }

    static func canonicalURL(photoID: String, sourceURL: URL) -> URL {
        var components = URLComponents()
        components.scheme = sourceURL.scheme ?? "https"
        components.host = sourceURL.host?.lowercased().hasSuffix(".test") == true ? "www.facebook.test" : "www.facebook.com"
        components.path = "/photo.php"
        components.queryItems = [URLQueryItem(name: "fbid", value: photoID)]
        return components.url!
    }

    static func canonicalURL(for url: URL) -> URL? {
        guard let photoID = photoID(from: url) else { return nil }
        return canonicalURL(photoID: photoID, sourceURL: url)
    }

    static func resolvedDownload(fromHTML html: String, pageURL: URL) throws -> ResolvedDownload {
        guard let photoID = photoID(from: pageURL) else {
            throw NativeDownloadError.invalidURL(pageURL.absoluteString)
        }
        guard let best = bestPhotoCandidate(fromHTML: html, pageURL: pageURL) else {
            throw NativeDownloadError.noFiles
        }

        let info = pageInfo(fromHTML: html, photoID: photoID)
        let ext = best.url.pathExtension.trimmed.isEmpty ? "jpg" : best.url.pathExtension.lowercased()
        let filename = "\(info.title)-\(photoID).\(ext)".sanitizedFilename(maxLength: 180)
        return ResolvedDownload(
            title: info.displayTitle,
            folderName: "Facebook \(info.displayTitle)".sanitizedFilename(maxLength: 120),
            assets: [
                ResolvedAsset(
                    remoteURL: best.url,
                    filename: filename,
                    metadata: assetMetadata(
                        photoID: photoID,
                        title: info.title,
                        author: info.author,
                        pageURL: pageURL,
                        candidate: best,
                        format: ext
                    ),
                    referer: pageURL.absoluteString
                )
            ],
            metadata: DownloadMetadata.clean([
                "site": "Facebook",
                "title": info.title,
                "artist": info.author,
                "author": info.author,
                "creator": info.author,
                "uploader": info.author,
                "channel": info.author,
                "category": "image",
                "type": "photo",
                "media_type": "image",
                "format": ext,
                "media_format": ext,
                "id": photoID,
                "photo_id": photoID,
                "media_id": photoID,
                "gallery_id": photoID,
                "media_count": "1",
                "image_count": "1",
                "thumbnail": best.url.absoluteString,
                "image_url": best.url.absoluteString,
                "media_url": best.url.absoluteString,
                "source": best.source,
                "media_source": best.source,
                "url": pageURL.absoluteString,
                "source_url": pageURL.absoluteString,
                "page_url": pageURL.absoluteString
            ])
        )
    }

    private static func assetMetadata(
        photoID: String,
        title: String,
        author: String,
        pageURL: URL,
        candidate: FacebookPhotoCandidate,
        format: String
    ) -> [String: String] {
        DownloadMetadata.clean([
            "site": "Facebook",
            "title": title,
            "artist": author,
            "author": author,
            "creator": author,
            "uploader": author,
            "channel": author,
            "category": "image",
            "type": "image",
            "media_type": "image",
            "format": format,
            "media_format": format,
            "id": photoID,
            "photo_id": photoID,
            "media_id": photoID,
            "gallery_id": photoID,
            "page": "1",
            "position": "1",
            "image_url": candidate.url.absoluteString,
            "media_url": candidate.url.absoluteString,
            "source": candidate.source,
            "media_source": candidate.source,
            "source_url": pageURL.absoluteString,
            "page_url": pageURL.absoluteString
        ])
    }

    static func bestPhotoCandidate(fromHTML html: String, pageURL: URL) -> FacebookPhotoCandidate? {
        var candidates: [FacebookPhotoCandidate] = []
        candidates.append(contentsOf: attributeCandidates(fromHTML: html, pageURL: pageURL, attribute: "data-full-size-href", score: 3_000_000, source: "data-full-size-href"))
        candidates.append(contentsOf: jsonImageCandidates(fromHTML: html, pageURL: pageURL))
        candidates.append(contentsOf: metaCandidates(fromHTML: html, pageURL: pageURL))
        candidates.append(contentsOf: attributeCandidates(fromHTML: html, pageURL: pageURL, attribute: "href", score: 400_000, source: "href"))
        candidates.append(contentsOf: attributeCandidates(fromHTML: html, pageURL: pageURL, attribute: "src", score: 300_000, source: "src"))

        var seen = Set<String>()
        let unique = candidates.compactMap { candidate -> FacebookPhotoCandidate? in
            let normalized = URLIdentity.normalize(candidate.url.absoluteString)
            guard !seen.contains(normalized) else { return nil }
            seen.insert(normalized)
            return candidate
        }
        return unique.max { lhs, rhs in lhs.score < rhs.score }
    }

    private static func attributeCandidates(fromHTML html: String, pageURL: URL, attribute: String, score: Int, source: String) -> [FacebookPhotoCandidate] {
        let escaped = NSRegularExpression.escapedPattern(for: attribute)
        let pattern = #"\b"# + escaped + #"\s*=\s*["']([^"']+)["']"#
        return captures(pattern: pattern, in: html).compactMap { raw in
            guard let url = absoluteURL(raw, baseURL: pageURL),
                  isLikelyPhotoURL(url) else {
                return nil
            }
            return FacebookPhotoCandidate(url: url, score: score + urlScore(url), source: source)
        }
    }

    private static func jsonImageCandidates(fromHTML html: String, pageURL: URL) -> [FacebookPhotoCandidate] {
        let patterns = [
            #""image"\s*:\s*\{[^{}]*"uri"\s*:\s*"((?:https?:)?\\?/\\?/[^"]+)""#,
            #""currMedia"\s*:\s*\{.*?"image"\s*:\s*\{.*?"uri"\s*:\s*"((?:https?:)?\\?/\\?/[^"]+)""#,
            #""uri"\s*:\s*"((?:https?:)?\\?/\\?/[^"]+\.(?:jpg|jpeg|png|webp)(?:\?[^"]*)?)""#,
            #""url"\s*:\s*"((?:https?:)?\\?/\\?/[^"]+\.(?:jpg|jpeg|png|webp)(?:\?[^"]*)?)""#
        ]
        return patterns.enumerated().flatMap { offset, pattern -> [FacebookPhotoCandidate] in
            captures(pattern: pattern, in: html).compactMap { raw in
                guard let url = absoluteURL(raw, baseURL: pageURL),
                      isLikelyPhotoURL(url) else {
                    return nil
                }
                return FacebookPhotoCandidate(url: url, score: 2_000_000 - offset * 100_000 + urlScore(url), source: "json")
            }
        }
    }

    private static func metaCandidates(fromHTML html: String, pageURL: URL) -> [FacebookPhotoCandidate] {
        ["og:image", "twitter:image"].compactMap { name in
            guard let raw = metaContent(from: html, names: [name]),
                  let url = absoluteURL(raw, baseURL: pageURL),
                  isLikelyPhotoURL(url) else {
                return nil
            }
            return FacebookPhotoCandidate(url: url, score: 800_000 + urlScore(url), source: name)
        }
    }

    private static func pageInfo(fromHTML html: String, photoID: String) -> (title: String, displayTitle: String, author: String) {
        let rawTitle = metaContent(from: html, names: ["og:title", "twitter:title"]) ??
            titleTag(fromHTML: html) ??
            "Facebook photo \(photoID)"
        let title = cleanTitle(rawTitle, fallback: "Facebook photo \(photoID)")
        let author = cleanTitle(
            firstCapture(pattern: #""owner"\s*:\s*\{[^{}]*"name"\s*:\s*"([^"]+)""#, in: html) ??
                firstCapture(pattern: #""author"\s*:\s*"([^"]+)""#, in: html) ??
                "",
            fallback: ""
        )
        let displayTitle = author.isEmpty ? title : "\(author) - \(title)"
        return (title, displayTitle, author)
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

    private static func absoluteURL(_ raw: String, baseURL: URL) -> URL? {
        var value = decodeHTML(normalizeEscapes(raw))
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'").union(.whitespacesAndNewlines))
        guard !value.isEmpty else { return nil }
        if value.hasPrefix("//") {
            value = "\(baseURL.scheme ?? "https"):\(value)"
        }
        return URL(string: value, relativeTo: baseURL)?.absoluteURL
    }

    private static func isLikelyPhotoURL(_ url: URL) -> Bool {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            return false
        }
        let value = url.absoluteString.lowercased()
        let host = url.host?.lowercased() ?? ""
        let ext = url.pathExtension.lowercased()
        let imageExtension = ["jpg", "jpeg", "png", "webp"].contains(ext) ||
            value.contains(".jpg") ||
            value.contains(".jpeg") ||
            value.contains(".png") ||
            value.contains(".webp")
        guard imageExtension else { return false }
        if host.contains("fbcdn") || host.contains("fbsbx") || host.contains("facebook.test") || host.contains("fbcdn.test") {
            return true
        }
        return value.contains("scontent") || value.contains("safe_image.php")
    }

    private static func urlScore(_ url: URL) -> Int {
        let value = url.absoluteString.lowercased()
        var score = 0
        if value.contains("scontent") { score += 30_000 }
        if value.contains("oh=") || value.contains("oe=") { score += 10_000 }
        if value.contains("_n.") { score += 5_000 }
        return score
    }

    private static func isSupportedHost(_ host: String) -> Bool {
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

    private static func cleanTitle(_ raw: String, fallback: String) -> String {
        var title = decodeHTML(stripTags(raw))
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmed
        title = title.replacingOccurrences(of: #"(?i)\s*\|\s*Facebook.*$"#, with: "", options: .regularExpression)
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

    private static func isNumericID(_ value: String) -> Bool {
        value.range(of: #"^[0-9]{4,}$"#, options: .regularExpression) != nil
    }
}
