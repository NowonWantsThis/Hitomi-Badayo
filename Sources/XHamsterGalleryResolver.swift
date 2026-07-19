import Foundation

final class XHamsterGalleryResolver {
    func canResolve(_ url: URL) -> Bool {
        Self.galleryID(from: url) != nil
    }

    func resolve(_ url: URL, headers: HTTPRequestOptions = HTTPRequestOptions()) async throws -> ResolvedDownload {
        guard let galleryID = Self.galleryID(from: url) else {
            throw NativeDownloadError.invalidURL(url.absoluteString)
        }

        let html = try await HTTPClient.shared.string(from: url, referer: headers.referer, userAgent: headers.userAgent)
        return try Self.resolvedDownload(fromHTML: html, pageURL: url, galleryID: galleryID)
    }

    static func resolvedDownload(fromHTML html: String, pageURL url: URL, galleryID: String) throws -> ResolvedDownload {
        let images = Self.imageURLs(fromHTML: html, pageURL: url)
        guard !images.isEmpty else {
            throw NativeDownloadError.noFiles
        }

        let title = Self.title(fromHTML: html, galleryID: galleryID)
        let canonicalPageURL = Self.canonicalGalleryURL(for: galleryID, sourceURL: url)
        let assets = images.enumerated().map { index, imageURL in
            ResolvedAsset(
                remoteURL: imageURL,
                filename: Self.filename(for: imageURL, index: index),
                metadata: Self.assetMetadata(
                    for: imageURL,
                    index: index + 1,
                    galleryID: galleryID,
                    title: title,
                    pageURL: canonicalPageURL
                ),
                referer: url.absoluteString
            )
        }
        return ResolvedDownload(
            title: title,
            folderName: "xHamster \(title)".sanitizedFilename(maxLength: 120),
            assets: assets,
            metadata: DownloadMetadata.clean([
                "site": "xHamster",
                "title": title,
                "series": title,
                "category": "image",
                "type": "gallery",
                "media_type": "gallery",
                "host": url.host ?? "",
                "id": galleryID,
                "gallery_id": galleryID,
                "media_count": String(assets.count),
                "image_count": String(assets.count),
                "thumbnail": Self.thumbnailURL(fromHTML: html, pageURL: url)?.absoluteString ?? "",
                "url": canonicalPageURL.absoluteString,
                "source_url": canonicalPageURL.absoluteString,
                "page_url": canonicalPageURL.absoluteString
            ])
        )
    }

    static func galleryID(from url: URL) -> String? {
        guard let host = url.host?.lowercased(),
              isSupportedHost(host),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }

        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true).map { String($0).removingPercentEncoding ?? String($0) }
        let lower = parts.map { $0.lowercased() }
        guard let photosIndex = lower.firstIndex(of: "photos"),
              photosIndex + 2 < parts.count,
              lower[photosIndex + 1] == "gallery" else {
            return nil
        }

        let slug = parts[photosIndex + 2].trimmed
        guard !slug.isEmpty,
              slug.range(of: #"^[0-9A-Za-z_-]+$"#, options: .regularExpression) != nil else {
            return nil
        }
        return slug
    }

    static func canonicalGalleryURL(for galleryID: String, sourceURL: URL) -> URL {
        var components = URLComponents()
        components.scheme = sourceURL.scheme ?? "https"
        components.host = sourceURL.host?.lowercased().hasSuffix(".test") == true ? "xhamster.test" : "xhamster.com"
        components.path = "/photos/gallery/\(galleryID)"
        return components.url!
    }

    static func imageURLs(fromHTML html: String, pageURL: URL) -> [URL] {
        let scope = photoScope(fromHTML: html)
        var urls: [URL] = []
        var seen = Set<String>()

        func append(_ raw: String?) {
            guard let raw,
                  let url = absoluteURL(raw, baseURL: pageURL),
                  isImage(url) else {
                return
            }
            let key = url.absoluteString
            guard !seen.contains(key) else { return }
            seen.insert(key)
            urls.append(url)
        }

        for tag in allCaptures(pattern: #"<img\b[^>]*>"#, in: scope, group: 0) {
            for attribute in ["data-full", "data-large", "data-original", "data-src", "data-lazy-src", "src"] {
                if let value = attributeValue(attribute, in: tag) {
                    append(value)
                    break
                }
            }
            if let srcset = attributeValue("srcset", in: tag) ?? attributeValue("data-srcset", in: tag) {
                append(bestSrcsetURL(from: srcset))
            }
        }

        for pattern in [
            #"<a\b[^>]*\bhref\s*=\s*["']([^"']+\.(?:jpg|jpeg|png|webp)(?:\?[^"']*)?)["']"#,
            #""(?:image|imageURL|imageUrl|url)"\s*:\s*"([^"]+\.(?:jpg|jpeg|png|webp)(?:\?[^"]*)?)""#
        ] {
            for raw in allCaptures(pattern: pattern, in: scope) {
                append(raw)
            }
        }

        return urls
    }

    private static func title(fromHTML html: String, galleryID: String) -> String {
        let raw = metaContent(from: html, names: ["og:title", "twitter:title"]) ??
            elementText(pattern: #"<h1\b[^>]*>(.*?)</h1>"#, in: html) ??
            elementText(pattern: #"<title\b[^>]*>(.*?)</title>"#, in: html) ??
            "xHamster gallery \(galleryID)"
        return cleanTitle(raw, fallback: "xHamster gallery \(galleryID)")
    }

    private static func thumbnailURL(fromHTML html: String, pageURL: URL) -> URL? {
        guard let raw = metaContent(from: html, names: ["og:image", "twitter:image"]) else { return nil }
        return absoluteURL(raw, baseURL: pageURL)
    }

    private static func filename(for url: URL, index: Int) -> String {
        let ext = url.pathExtension.trimmed.isEmpty ? "jpg" : url.pathExtension
        return String(format: "%03d.%@", index + 1, ext).sanitizedFilename(maxLength: 180)
    }

    private static func assetMetadata(for imageURL: URL, index: Int, galleryID: String, title: String, pageURL: URL) -> [String: String] {
        let format = mediaFormat(for: imageURL)
        return DownloadMetadata.clean([
            "site": "xHamster",
            "title": title,
            "series": title,
            "id": galleryID,
            "gallery_id": galleryID,
            "media_id": "\(galleryID)-\(index)",
            "type": "image",
            "media_type": "image",
            "category": "image",
            "page": String(index),
            "position": String(index),
            "format": format,
            "media_format": format,
            "image_url": imageURL.absoluteString,
            "media_url": imageURL.absoluteString,
            "source_url": imageURL.absoluteString,
            "page_url": pageURL.absoluteString
        ])
    }

    private static func mediaFormat(for url: URL) -> String {
        let pathExtension = url.pathExtension.lowercased()
        if !pathExtension.isEmpty {
            return pathExtension
        }
        let lower = url.absoluteString.lowercased()
        for value in ["jpg", "jpeg", "png", "webp"] where lower.contains(".\(value)") {
            return value
        }
        return ""
    }

    private static func photoScope(fromHTML html: String) -> String {
        guard let marker = html.range(of: "photo-slider", options: [.caseInsensitive]) else {
            return html
        }
        return String(html[marker.lowerBound...])
    }

    private static func attributeValue(_ name: String, in tag: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        return firstCapture(pattern: #"\b\#(escaped)\s*=\s*["']([^"']+)["']"#, in: tag)
    }

    private static func bestSrcsetURL(from srcset: String) -> String? {
        let candidates = srcset
            .split(separator: ",")
            .map { item -> (url: String, width: Int) in
                let pieces = item.split(separator: " ").map(String.init)
                let url = pieces.first ?? ""
                let width = pieces.dropFirst().first(where: { $0.hasSuffix("w") }).flatMap { Int($0.dropLast()) } ?? 0
                return (url, width)
            }
            .filter { !$0.url.isEmpty }
        return candidates.max { $0.width < $1.width }?.url
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

    private static func isImage(_ url: URL) -> Bool {
        ["jpg", "jpeg", "png", "webp"].contains(url.pathExtension.lowercased())
    }

    private static func isSupportedHost(_ host: String) -> Bool {
        if host == "xhamster.test" || host == "www.xhamster.test" {
            return true
        }
        guard let labels = hostLabels(host), labels.count >= 2 else { return false }
        let base = labels[labels.count - 2]
        let topLevelDomain = labels[labels.count - 1]
        guard topLevelDomain.range(of: #"^[a-z0-9]{2,24}$"#, options: .regularExpression) != nil else {
            return false
        }
        return base.range(
            of: #"^(xhamster|xhwebsite|xhofficial|xhlocal|xhopen|xhtotal|megaxh|xhwide|xhtab|xhtime)[0-9]*$"#,
            options: .regularExpression
        ) != nil
    }

    private static func hostLabels(_ host: String) -> [String]? {
        let labels = host
            .lowercased()
            .split(separator: ".")
            .map(String.init)
            .filter { !$0.isEmpty }
        return labels.count >= 2 ? labels : nil
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
        for suffix in [" - xHamster", " | xHamster", " - xHamster.com", " | xHamster.com"] {
            if text.lowercased().hasSuffix(suffix.lowercased()) {
                text = String(text.dropLast(suffix.count)).trimmed
            }
        }
        return (text.isEmpty ? fallback : text).sanitizedFilename(maxLength: 120)
    }
}
