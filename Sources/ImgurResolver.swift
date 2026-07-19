import Foundation

final class ImgurResolver {
    func canResolve(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(),
              host == "imgur.com" || host == "www.imgur.com" || host == "m.imgur.com" || host == "imgur.test",
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return false
        }

        let parts = url.path.split(separator: "/").map(String.init)
        guard let first = parts.first?.lowercased() else { return false }

        if ["a", "gallery"].contains(first) {
            return parts.count >= 2 && !parts[1].trimmed.isEmpty
        }

        if first == "t" {
            return parts.count >= 3 && !parts[2].trimmed.isEmpty
        }

        return parts.count == 1 && !first.trimmed.isEmpty
    }

    func resolve(_ url: URL, headers: HTTPRequestOptions = HTTPRequestOptions()) async throws -> ResolvedDownload {
        let html = try await HTTPClient.shared.string(from: url, referer: headers.referer, userAgent: headers.userAgent)
        return try Self.resolvedDownload(fromHTML: html, pageURL: url)
    }

    static func resolvedDownload(fromHTML html: String, pageURL: URL) throws -> ResolvedDownload {
        let mediaURLs = extractMediaURLs(from: html, pageURL: pageURL)
        guard !mediaURLs.isEmpty else {
            throw NativeDownloadError.noFiles
        }

        let title = title(from: html, pageURL: pageURL).sanitizedFilename(maxLength: 120)
        let metadata = imgurMetadata(fromHTML: html, pageURL: pageURL, title: title, mediaURLs: mediaURLs)
        let assets = mediaURLs.enumerated().map { index, remoteURL in
            ResolvedAsset(
                remoteURL: remoteURL,
                filename: filename(for: remoteURL, index: index + 1),
                metadata: assetMetadata(for: remoteURL, index: index + 1, pageMetadata: metadata, pageURL: pageURL),
                referer: pageURL.absoluteString
            )
        }

        return ResolvedDownload(
            title: title,
            folderName: "Imgur \(title)".sanitizedFilename(maxLength: 120),
            assets: assets,
            metadata: metadata
        )
    }

    static func imgurMetadata(fromHTML html: String, pageURL: URL, title: String? = nil, mediaURLs: [URL] = []) -> [String: String] {
        let normalized = normalizeEscapes(decodeHTML(html))
        let uploader = metaContent(from: html, names: ["author"]) ??
            firstCapture(patterns: [
                #""account_url"\s*:\s*"([^"]+)""#,
                #""account_username"\s*:\s*"([^"]+)""#,
                #""author"\s*:\s*"([^"]+)""#
            ], in: normalized) ?? ""
        let kind = contentKind(from: pageURL)
        let id = contentID(from: pageURL)
        let resolvedTitle = title ?? Self.title(from: html, pageURL: pageURL)
        let imageCount = mediaURLs.filter { mediaType(for: $0) == "image" }.count
        let videoCount = mediaURLs.filter { mediaType(for: $0) == "video" }.count

        return DownloadMetadata.clean([
            "artist": uploader,
            "author": uploader,
            "creator": uploader,
            "uploader": uploader,
            "channel": uploader,
            "username": uploader,
            "series": resolvedTitle,
            "category": kind,
            "type": kind,
            "album_id": kind == "album" || kind == "gallery" ? id : "",
            "gallery_id": kind == "album" || kind == "gallery" ? id : "",
            "media_id": kind == "media" ? id : "",
            "tag": kind == "tag" ? id : "",
            "slug": id,
            "site": "Imgur",
            "title": resolvedTitle,
            "media_count": mediaURLs.isEmpty ? "" : String(mediaURLs.count),
            "image_count": imageCount > 0 ? String(imageCount) : "",
            "video_count": videoCount > 0 ? String(videoCount) : "",
            "source_url": pageURL.absoluteString,
            "page_url": pageURL.absoluteString
        ])
    }

    static func assetMetadata(for url: URL, index: Int, pageMetadata: [String: String], pageURL: URL) -> [String: String] {
        let mediaType = mediaType(for: url)
        let format = mediaFormat(for: url)
        let mediaID = mediaHash(from: url) ?? pageMetadata["media_id"] ?? String(index)
        return DownloadMetadata.clean([
            "artist": pageMetadata["artist"] ?? "",
            "author": pageMetadata["author"] ?? "",
            "creator": pageMetadata["creator"] ?? "",
            "uploader": pageMetadata["uploader"] ?? "",
            "channel": pageMetadata["channel"] ?? "",
            "username": pageMetadata["username"] ?? "",
            "series": pageMetadata["series"] ?? "",
            "category": mediaType,
            "type": mediaType,
            "media_type": mediaType,
            "album_id": pageMetadata["album_id"] ?? "",
            "gallery_id": pageMetadata["gallery_id"] ?? "",
            "media_id": mediaID,
            "tag": pageMetadata["tag"] ?? "",
            "slug": pageMetadata["slug"] ?? "",
            "site": "Imgur",
            "title": pageMetadata["title"] ?? "",
            "page": String(index),
            "position": String(index),
            "format": format,
            "media_format": format,
            "image_url": mediaType == "image" ? url.absoluteString : "",
            "video_url": mediaType == "video" ? url.absoluteString : "",
            "media_url": url.absoluteString,
            "source_url": url.absoluteString,
            "page_url": pageURL.absoluteString
        ])
    }

    static func extractMediaURLs(from html: String, pageURL: URL) -> [URL] {
        let normalized = normalizeEscapes(decodeHTML(html))
        var urls: [URL] = []
        urls.append(contentsOf: mediaURLsFromExplicitLinks(in: normalized, pageURL: pageURL))
        urls.append(contentsOf: mediaURLsFromHashExtensionPairs(in: normalized, pageURL: pageURL))

        var seen = Set<String>()
        return urls.compactMap { rawURL in
            let mediaURL = normalizedMediaURL(rawURL)
            let normalized = URLIdentity.normalize(mediaURL.absoluteString)
            guard !seen.contains(normalized) else { return nil }
            seen.insert(normalized)
            return mediaURL
        }
    }

    private static func mediaURLsFromExplicitLinks(in text: String, pageURL: URL) -> [URL] {
        let patterns = [
            #"(?:https?:)?//i\.imgur\.com/[A-Za-z0-9][A-Za-z0-9_-]*\.(?:jpg|jpeg|png|gifv|gif|mp4|webm|webp|avif)"#,
            #"\bi\.imgur\.com/[A-Za-z0-9][A-Za-z0-9_-]*\.(?:jpg|jpeg|png|gifv|gif|mp4|webm|webp|avif)"#
        ]

        return patterns.flatMap { pattern in
            matches(pattern: pattern, in: text).compactMap { absoluteURL($0, pageURL: pageURL) }
        }
    }

    private static func mediaURLsFromHashExtensionPairs(in text: String, pageURL: URL) -> [URL] {
        let patterns: [(String, Int, Int)] = [
            (#""hash"\s*:\s*"([A-Za-z0-9]{5,})"[^{}]{0,600}?"(?:ext|extension)"\s*:\s*"\.?(jpg|jpeg|png|gif|gifv|mp4|webm|webp|avif)""#, 1, 2),
            (#""(?:ext|extension)"\s*:\s*"\.?(jpg|jpeg|png|gif|gifv|mp4|webm|webp|avif)"[^{}]{0,600}?"hash"\s*:\s*"([A-Za-z0-9]{5,})""#, 2, 1)
        ]

        var urls: [URL] = []
        for (pattern, hashGroup, extGroup) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
                continue
            }

            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            for match in regex.matches(in: text, range: range) {
                guard let hashRange = Range(match.range(at: hashGroup), in: text),
                      let extRange = Range(match.range(at: extGroup), in: text) else {
                    continue
                }
                let ext = String(text[extRange]).lowercased()
                let raw = "//i.imgur.com/\(text[hashRange]).\(ext)"
                if let url = absoluteURL(raw, pageURL: pageURL) {
                    urls.append(url)
                }
            }
        }
        return urls
    }

    private static func title(from html: String, pageURL: URL) -> String {
        let metaTitle = metaContent(from: html, names: ["og:title", "twitter:title"])
        let documentTitle = titleTag(from: html)
        let fallback = fallbackTitle(from: pageURL)

        return cleanTitle(metaTitle ?? documentTitle ?? fallback, fallback: fallback)
    }

    private static func metaContent(from html: String, names: Set<String>) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"<meta\b([^>]*)>"#, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        for match in regex.matches(in: html, range: range) {
            guard let attributesRange = Range(match.range(at: 1), in: html) else { continue }
            let values = attributeValues(from: String(html[attributesRange]))
            let key = (values["property"] ?? values["name"])?.lowercased()
            guard let key, names.contains(key),
                  let content = values["content"]?.trimmed,
                  !content.isEmpty else {
                continue
            }
            return content
        }

        return nil
    }

    private static func titleTag(from html: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: #"<title\b[^>]*>(.*?)</title>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return nil
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, range: range),
              let titleRange = Range(match.range(at: 1), in: html) else {
            return nil
        }

        let title = decodeHTML(stripTags(String(html[titleRange]))).trimmed
        return title.isEmpty ? nil : title
    }

    private static func fallbackTitle(from url: URL) -> String {
        let parts = url.path.split(separator: "/").map(String.init)
        if let first = parts.first?.lowercased(), ["a", "gallery"].contains(first), parts.count >= 2 {
            return parts[1]
        }
        if let first = parts.first?.lowercased(), first == "t", parts.count >= 3 {
            return parts[2]
        }
        return parts.last ?? "Imgur Media"
    }

    private static func contentID(from url: URL) -> String {
        let parts = url.path.split(separator: "/").map(String.init)
        if let first = parts.first?.lowercased(), ["a", "gallery"].contains(first), parts.count >= 2 {
            return parts[1]
        }
        if let first = parts.first?.lowercased(), first == "t", parts.count >= 3 {
            return parts[2]
        }
        return parts.last ?? ""
    }

    private static func contentKind(from url: URL) -> String {
        let parts = url.path.split(separator: "/").map(String.init)
        guard let first = parts.first?.lowercased() else { return "media" }
        if first == "a" { return "album" }
        if first == "gallery" { return "gallery" }
        if first == "t" { return "tag" }
        return "media"
    }

    private static func cleanTitle(_ raw: String, fallback: String) -> String {
        var title = decodeHTML(raw)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmed

        for suffix in [" - Imgur", " | Imgur", " - Album on Imgur", " - GIF on Imgur"] {
            if title.lowercased().hasSuffix(suffix.lowercased()) {
                title.removeLast(suffix.count)
                title = title.trimmed
            }
        }

        if title.lowercased() == "imgur: the magic of the internet" {
            title = fallback
        }

        return title.isEmpty ? fallback : title
    }

    private static func filename(for url: URL, index: Int) -> String {
        let rawName = url.lastPathComponent.removingPercentEncoding ?? url.lastPathComponent
        let cleanName = rawName.sanitizedFilename(maxLength: 160)
        if cleanName != "download", cleanName.contains(".") {
            return String(format: "%04d-%@", index, cleanName).sanitizedFilename(maxLength: 180)
        }

        let ext = url.pathExtension.trimmed.isEmpty ? "bin" : url.pathExtension
        return String(format: "%04d-imgur.%@", index, ext).sanitizedFilename(maxLength: 180)
    }

    private static func mediaHash(from url: URL) -> String? {
        let name = url.deletingPathExtension().lastPathComponent.trimmed
        return name.isEmpty ? nil : name
    }

    private static func mediaType(for url: URL) -> String {
        ["mp4", "webm", "m4v", "mov"].contains(mediaFormat(for: url)) ? "video" : "image"
    }

    private static func mediaFormat(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        if ext == "jpeg" || ext == "bmp" {
            return "jpg"
        }
        return ext.isEmpty ? "bin" : ext
    }

    private static func normalizedMediaURL(_ url: URL) -> URL {
        guard url.pathExtension.lowercased() == "gifv",
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }

        let path = components.percentEncodedPath
        components.percentEncodedPath = String(path.dropLast(5)) + ".mp4"
        return components.url ?? url
    }

    private static func absoluteURL(_ raw: String, pageURL: URL) -> URL? {
        let value = raw.trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "\"'(),;"))
        guard !value.isEmpty else { return nil }

        if value.hasPrefix("//") {
            return URL(string: "\(pageURL.scheme ?? "https"):\(value)")
        }

        if value.lowercased().hasPrefix("i.imgur.com/") {
            return URL(string: "\(pageURL.scheme ?? "https")://\(value)")
        }

        return URL(string: value, relativeTo: pageURL)?.absoluteURL
    }

    private static func matches(pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let resultRange = Range(match.range(at: 0), in: text) else { return nil }
            return String(text[resultRange])
        }
    }

    private static func firstCapture(patterns: [String], in text: String) -> String? {
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
                continue
            }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            guard let match = regex.firstMatch(in: text, range: range),
                  let capture = Range(match.range(at: 1), in: text) else {
                continue
            }
            let value = String(text[capture]).trimmed
            if !value.isEmpty {
                return value
            }
        }
        return nil
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
                values[name] = decodeHTML(String(attributes[valueRange])).trimmed
                break
            }
        }

        return values
    }

    private static func normalizeEscapes(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\/", with: "/")
            .replacingOccurrences(of: "\\u002F", with: "/", options: .caseInsensitive)
            .replacingOccurrences(of: "\\u003A", with: ":", options: .caseInsensitive)
            .replacingOccurrences(of: "\\u0026", with: "&", options: .caseInsensitive)
    }

    private static func stripTags(_ text: String) -> String {
        text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
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
