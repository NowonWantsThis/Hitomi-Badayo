// Developed with reference to SaidBySolo's MIT-licensed extractor.
// See LICENSES/saidbysolo-MIT.txt in the source distribution.
import Foundation

final class TalkOPGGResolver {
    func canResolve(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(),
              Self.isSupportedHost(host),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return false
        }

        return !Self.isDirectMediaURL(url) && Self.canonicalArticleURL(for: url) != nil
    }

    func resolve(_ url: URL, headers: HTTPRequestOptions = HTTPRequestOptions()) async throws -> ResolvedDownload {
        let sourceURL = Self.canonicalArticleURL(for: url) ?? url
        let html = try await HTTPClient.shared.string(from: sourceURL, referer: headers.referer, userAgent: headers.userAgent)
        return try Self.resolvedDownload(fromHTML: html, pageURL: sourceURL)
    }

    static func resolvedDownload(fromHTML html: String, pageURL: URL) throws -> ResolvedDownload {
        let sourceURL = canonicalArticleURL(for: pageURL) ?? pageURL
        let title = title(fromHTML: html, pageURL: sourceURL)
        let images = imageURLs(fromHTML: html, pageURL: sourceURL)
        guard !images.isEmpty else {
            throw NativeDownloadError.noFiles
        }

        let author = authorName(fromHTML: html)
        let metadata = articleMetadata(
            author: author,
            title: title,
            pageURL: sourceURL,
            imageCount: images.count
        )
        let assets = images.enumerated().map { offset, remote in
            ResolvedAsset(
                remoteURL: remote,
                filename: filename(for: remote, index: offset + 1),
                metadata: assetMetadata(for: remote, articleMetadata: metadata, index: offset + 1),
                referer: sourceURL.absoluteString
            )
        }

        return ResolvedDownload(
            title: title.sanitizedFilename(maxLength: 120),
            folderName: "TalkOPGG \(title)".sanitizedFilename(maxLength: 120),
            assets: assets,
            metadata: metadata
        )
    }

    static func imageURLs(fromHTML html: String, pageURL: URL) -> [URL] {
        let normalizedHTML = decodeHTML(html).replacingOccurrences(of: #"\/"#, with: "/")
        let blocks = classBlocks(in: normalizedHTML, className: "article-content")
        let searchSpace = blocks.isEmpty ? normalizedHTML : blocks.joined(separator: "\n")
        var candidates = imageCandidates(fromHTML: searchSpace)
        if !blocks.isEmpty && candidates.isEmpty {
            candidates = imageCandidates(fromHTML: normalizedHTML)
        }

        var urls: [URL] = []
        var seen = Set<String>()
        for candidate in candidates {
            guard let remote = absoluteURL(candidate, baseURL: pageURL),
                  !Self.isDirectMediaURL(pageURL) || remote != pageURL,
                  Self.isDownloadableImageURL(remote) else {
                continue
            }

            let normalized = URLIdentity.normalize(remote.absoluteString)
            guard !seen.contains(normalized) else { continue }
            seen.insert(normalized)
            urls.append(remote)
        }
        return urls
    }

    static func articleID(from url: URL) -> String? {
        guard let host = url.host?.lowercased(),
              isSupportedHost(host) else {
            return nil
        }
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard parts.first?.lowercased() == "s" else { return nil }
        return parts.first { part in
            part.range(of: #"^[0-9]{3,}$"#, options: .regularExpression) != nil
        }
    }

    static func canonicalArticleURL(for url: URL) -> URL? {
        guard let id = articleID(from: url),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard let idIndex = parts.firstIndex(of: id) else { return nil }
        let endIndex = min(idIndex + 2, parts.count)
        components.path = "/" + parts[..<endIndex].joined(separator: "/")
        components.queryItems = nil
        components.fragment = nil
        return components.url
    }

    private static func imageCandidates(fromHTML html: String) -> [String] {
        guard let regex = try? NSRegularExpression(
            pattern: #"<img\b([^>]*)>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return []
        }

        var candidates: [String] = []
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        for match in regex.matches(in: html, range: range) {
            guard let attrsRange = Range(match.range(at: 1), in: html) else { continue }
            let attributes = attributeValues(from: String(html[attrsRange]))
            for key in ["data-original", "data-src", "data-lazy-src", "src"] {
                if let value = attributes[key]?.trimmed, !value.isEmpty {
                    candidates.append(value)
                }
            }
            for key in ["data-srcset", "srcset"] {
                if let value = attributes[key]?.trimmed,
                   let best = bestSrcsetCandidate(value) {
                    candidates.append(best)
                }
            }
        }
        return candidates
    }

    private static func bestSrcsetCandidate(_ srcset: String) -> String? {
        srcset
            .components(separatedBy: ",")
            .compactMap { part -> (url: String, score: Int)? in
                let pieces = part.trimmed.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
                guard let url = pieces.first else { return nil }
                let descriptor = pieces.dropFirst().first ?? ""
                let score: Int
                if descriptor.hasSuffix("w") {
                    score = Int(descriptor.dropLast()) ?? 0
                } else if descriptor.hasSuffix("x") {
                    score = Int((Double(descriptor.dropLast()) ?? 1) * 10_000)
                } else {
                    score = 0
                }
                return (url, score)
            }
            .max { $0.score < $1.score }?
            .url
    }

    private static func title(fromHTML html: String, pageURL: URL) -> String {
        let title = elementText(pattern: #"<h1\b[^>]*>(.*?)</h1>"#, in: html) ??
            metaContent(from: html, names: ["og:title", "twitter:title"]) ??
            titleTag(fromHTML: html) ??
            pageURL.lastPathComponent.replacingOccurrences(of: "-", with: " ")
        return cleanTitle(title, fallback: "Talk OP.GG")
    }

    private static func authorName(fromHTML html: String) -> String {
        let classMarkers = [
            "article-meta__name",
            "article-author",
            "author",
            "nickname",
            "user-name"
        ]
        for marker in classMarkers {
            if let text = elementText(
                pattern: #"<[^>]*\bclass\s*=\s*["'][^"']*\#(marker)[^"']*["'][^>]*>(.*?)</[^>]+>"#,
                in: html
            ) {
                return text
            }
        }
        return metaContent(from: html, names: ["author", "article:author"]) ?? ""
    }

    private static func classBlocks(in html: String, className: String) -> [String] {
        let pattern = #"<(?:article|section|div)\b[^>]*\bclass\s*=\s*["'][^"']*\#(className)[^"']*["'][^>]*>(.*?)</(?:article|section|div)>"#
        return captureGroupMatches(pattern: pattern, in: html)
    }

    private static func elementText(pattern: String, in html: String) -> String? {
        guard let raw = captureGroupMatches(pattern: pattern, in: html).first else { return nil }
        let text = cleanTitle(stripTags(raw), fallback: "")
        return text.isEmpty ? nil : text
    }

    private static func metaContent(from html: String, names: [String]) -> String? {
        for name in names {
            let patterns = [
                #"<meta\b[^>]*(?:property|name)\s*=\s*["']\#(name)["'][^>]*content\s*=\s*["']([^"']+)["'][^>]*>"#,
                #"<meta\b[^>]*content\s*=\s*["']([^"']+)["'][^>]*(?:property|name)\s*=\s*["']\#(name)["'][^>]*>"#
            ]
            for pattern in patterns {
                if let value = captureGroupMatches(pattern: pattern, in: html).first {
                    let text = cleanTitle(value, fallback: "")
                    if !text.isEmpty {
                        return text
                    }
                }
            }
        }
        return nil
    }

    private static func titleTag(fromHTML html: String) -> String? {
        guard let title = captureGroupMatches(pattern: #"<title\b[^>]*>(.*?)</title>"#, in: html).first else {
            return nil
        }
        let text = cleanTitle(title, fallback: "")
        return text.isEmpty ? nil : text
    }

    private static func attributeValues(from raw: String) -> [String: String] {
        var values: [String: String] = [:]
        guard let regex = try? NSRegularExpression(
            pattern: #"([A-Za-z_:][-A-Za-z0-9_:.]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+))"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return values
        }
        let range = NSRange(raw.startIndex..<raw.endIndex, in: raw)
        for match in regex.matches(in: raw, range: range) {
            guard let keyRange = Range(match.range(at: 1), in: raw) else { continue }
            let key = String(raw[keyRange]).lowercased()
            let value: String
            if let range = Range(match.range(at: 2), in: raw) {
                value = String(raw[range])
            } else if let range = Range(match.range(at: 3), in: raw) {
                value = String(raw[range])
            } else if let range = Range(match.range(at: 4), in: raw) {
                value = String(raw[range])
            } else {
                value = ""
            }
            values[key] = decodeHTML(value)
        }
        return values
    }

    private static func captureGroupMatches(pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > 1,
                  let resultRange = Range(match.range(at: 1), in: text) else {
                return nil
            }
            return String(text[resultRange])
        }
    }

    private static func absoluteURL(_ raw: String, baseURL: URL) -> URL? {
        var value = decodeHTML(raw)
            .replacingOccurrences(of: #"\/"#, with: "/")
            .trimmed
        guard !value.isEmpty,
              !value.lowercased().hasPrefix("data:"),
              !value.lowercased().hasPrefix("javascript:") else {
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

    private static func isDirectMediaURL(_ url: URL) -> Bool {
        isDownloadableImageURL(url)
    }

    private static func isDownloadableImageURL(_ url: URL) -> Bool {
        imageExtensions.contains(url.pathExtension.lowercased())
    }

    private static func filename(for url: URL, index: Int) -> String {
        let ext = mediaFormat(for: url)
        return String(format: "%04d.%@", index, ext).sanitizedFilename(maxLength: 180)
    }

    private static func articleMetadata(author: String, title: String, pageURL: URL, imageCount: Int) -> [String: String] {
        let id = articleID(from: pageURL) ?? ""
        return DownloadMetadata.clean([
            "artist": author,
            "author": author,
            "creator": author,
            "user": author,
            "username": author,
            "uploader": author,
            "channel": author,
            "article_id": id,
            "post_id": id,
            "id": id,
            "slug": pageURL.lastPathComponent,
            "site": "Talk OP.GG",
            "title": title,
            "series": title,
            "type": "article",
            "media_type": "image",
            "category": "image",
            "media_count": String(imageCount),
            "image_count": String(imageCount),
            "url": pageURL.absoluteString,
            "source_url": pageURL.absoluteString,
            "page_url": pageURL.absoluteString
        ])
    }

    private static func assetMetadata(for url: URL, articleMetadata: [String: String], index: Int) -> [String: String] {
        let format = mediaFormat(for: url)
        let articleID = articleMetadata["article_id"] ?? articleMetadata["id"] ?? ""
        return DownloadMetadata.clean([
            "artist": articleMetadata["artist"] ?? "",
            "author": articleMetadata["author"] ?? "",
            "creator": articleMetadata["creator"] ?? "",
            "user": articleMetadata["user"] ?? "",
            "username": articleMetadata["username"] ?? "",
            "uploader": articleMetadata["uploader"] ?? "",
            "channel": articleMetadata["channel"] ?? "",
            "article_id": articleID,
            "post_id": articleID,
            "id": articleID,
            "media_id": articleID.isEmpty ? String(index) : "\(articleID)-\(index)",
            "page": String(index),
            "position": String(index),
            "slug": articleMetadata["slug"] ?? "",
            "site": "Talk OP.GG",
            "title": articleMetadata["title"] ?? "",
            "series": articleMetadata["series"] ?? articleMetadata["title"] ?? "",
            "type": "image",
            "media_type": "image",
            "category": "image",
            "format": format,
            "media_format": format,
            "image_url": url.absoluteString,
            "media_url": url.absoluteString,
            "source_url": url.absoluteString,
            "page_url": articleMetadata["page_url"] ?? articleMetadata["url"] ?? ""
        ])
    }

    private static func mediaFormat(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        if ext == "jpeg" || ext == "bmp" {
            return "jpg"
        }
        return ext.isEmpty ? "jpg" : ext
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
        for suffix in [
            " - OP.GG Talk",
            " | OP.GG Talk",
            " - Talk OP.GG",
            " | Talk OP.GG",
            " - talk.op.gg",
            " | talk.op.gg"
        ] {
            if text.lowercased().hasSuffix(suffix.lowercased()) {
                text = String(text.dropLast(suffix.count)).trimmed
            }
        }
        return text.isEmpty ? fallback : text
    }

    private static func isSupportedHost(_ host: String) -> Bool {
        host == "talk.op.gg" ||
            host == "www.talk.op.gg" ||
            host == "talk.op.gg.test" ||
            host == "www.talk.op.gg.test"
    }

    private static let imageExtensions: Set<String> = [
        "jpg",
        "jpeg",
        "png",
        "gif",
        "webp",
        "bmp"
    ]
}
