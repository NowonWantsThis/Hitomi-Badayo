import Foundation

final class IwaraImageResolver {
    func canResolve(_ url: URL) -> Bool {
        Self.imageID(from: url) != nil
    }

    func resolve(_ url: URL, headers: HTTPRequestOptions = HTTPRequestOptions()) async throws -> ResolvedDownload {
        guard let imageID = Self.imageID(from: url) else {
            throw NativeDownloadError.invalidURL(url.absoluteString)
        }

        let html = try await HTTPClient.shared.string(from: url, referer: headers.referer, userAgent: headers.userAgent)
        return try Self.resolvedDownload(fromHTML: html, pageURL: url, imageID: imageID)
    }

    static func resolvedDownload(fromHTML html: String, pageURL: URL, imageID: String) throws -> ResolvedDownload {
        let images = imageURLs(fromHTML: html, pageURL: pageURL)
        guard !images.isEmpty else {
            throw NativeDownloadError.noFiles
        }

        let info = postInfo(fromHTML: html, imageID: imageID)
        let canonicalPageURL = canonicalURL(for: pageURL) ?? pageURL
        let assets = images.enumerated().map { index, imageURL in
            ResolvedAsset(
                remoteURL: imageURL,
                filename: filename(for: imageURL, index: index),
                metadata: assetMetadata(for: imageURL, index: index + 1, imageID: imageID, pageURL: canonicalPageURL, info: info),
                referer: pageURL.absoluteString
            )
        }
        return ResolvedDownload(
            title: info.title,
            folderName: "Iwara \(info.folderTitle)".sanitizedFilename(maxLength: 120),
            assets: assets,
            metadata: DownloadMetadata.clean([
                "site": "Iwara",
                "title": info.title,
                "series": info.title,
                "category": "image",
                "type": "image",
                "media_type": "image",
                "host": pageURL.host ?? "",
                "id": imageID,
                "image_id": imageID,
                "gallery_id": imageID,
                "media_count": String(assets.count),
                "image_count": String(assets.count),
                "artist": info.uploader,
                "author": info.uploader,
                "creator": info.uploader,
                "uploader": info.uploader,
                "thumbnail": thumbnailURL(fromHTML: html, pageURL: pageURL)?.absoluteString ?? "",
                "url": canonicalPageURL.absoluteString,
                "source_url": canonicalPageURL.absoluteString,
                "page_url": canonicalPageURL.absoluteString
            ])
        )
    }

    static func imageID(from url: URL) -> String? {
        guard let host = url.host?.lowercased(),
              isSupportedHost(host),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }

        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true).map { String($0).removingPercentEncoding ?? String($0) }
        let lower = parts.map { $0.lowercased() }
        guard let imageIndex = lower.firstIndex(of: "image"),
              imageIndex + 1 < parts.count else {
            return nil
        }
        let id = parts[imageIndex + 1].trimmed
        guard id.range(of: #"^[0-9A-Za-z_-]+$"#, options: .regularExpression) != nil else {
            return nil
        }
        return id
    }

    static func canonicalURL(for imageID: String, sourceURL: URL) -> URL {
        var components = URLComponents()
        components.scheme = sourceURL.scheme ?? "https"
        components.host = sourceURL.host?.lowercased().hasSuffix(".test") == true ? "iwara.test" : "iwara.tv"
        components.path = "/image/\(imageID)"
        return components.url!
    }

    static func canonicalURL(for url: URL) -> URL? {
        guard let imageID = imageID(from: url) else { return nil }
        return canonicalURL(for: imageID, sourceURL: url)
    }

    static func imageURLs(fromHTML html: String, pageURL: URL) -> [URL] {
        let scope = imageScope(fromHTML: html)
        var urls: [URL] = []
        var seen = Set<String>()

        func append(_ raw: String?) {
            appendImageURL(raw, pageURL: pageURL, urls: &urls, seen: &seen)
        }

        for styleURL in allCaptures(pattern: #"url\((?:&quot;|["']?)(.+?)(?:&quot;|["']?)\)"#, in: scope) {
            append(styleURL)
        }

        for tag in allCaptures(pattern: #"<img\b[^>]*>"#, in: scope, group: 0) {
            for attribute in ["data-full", "data-original", "data-src", "data-lazy-src", "src"] {
                if let value = attributeValue(attribute, in: tag) {
                    append(value)
                    break
                }
            }
            if let srcset = attributeValue("srcset", in: tag) ?? attributeValue("data-srcset", in: tag) {
                append(bestSrcsetURL(from: srcset))
            }
        }

        for raw in allCaptures(pattern: #""(?:original|image|imageUrl|url|src)"\s*:\s*"([^"]+\.(?:jpg|jpeg|png|webp)(?:\?[^"]*)?)""#, in: scope) {
            append(raw)
        }

        for object in scriptJSONObjects(fromHTML: html) {
            collectImageURLs(
                in: object,
                pageURL: pageURL,
                insideMediaContainer: false,
                insideIgnoredContext: false,
                urls: &urls,
                seen: &seen
            )
        }

        return urls
    }

    private static func postInfo(fromHTML html: String, imageID: String) -> (title: String, folderTitle: String, uploader: String) {
        let title = cleanTitle(
            elementText(pattern: #"<[^>]*\bclass\s*=\s*["'][^"']*text--h1[^"']*["'][^>]*>(.*?)</[^>]+>"#, in: html) ??
                metaContent(from: html, names: ["og:title", "twitter:title"]) ??
                elementText(pattern: #"<title\b[^>]*>(.*?)</title>"#, in: html) ??
                "Iwara \(imageID)",
            fallback: "Iwara \(imageID)"
        )
        let uploader = cleanTitle(
            elementText(pattern: #"<[^>]*\bclass\s*=\s*["'][^"']*page-profile__header[^"']*["'][^>]*>(.*?)</[^>]+>"#, in: html) ??
                metaContent(from: html, names: ["profile:username", "author"]) ??
                "",
            fallback: ""
        )
        let folder = [uploader, title].filter { !$0.isEmpty }.joined(separator: " - ")
        return (title, folder.isEmpty ? title : folder, uploader)
    }

    private static func thumbnailURL(fromHTML html: String, pageURL: URL) -> URL? {
        guard let raw = metaContent(from: html, names: ["og:image", "twitter:image"]) else { return nil }
        return absoluteURL(raw, baseURL: pageURL)
    }

    private static func filename(for url: URL, index: Int) -> String {
        let ext = url.pathExtension.trimmed.isEmpty ? "jpg" : url.pathExtension
        return String(format: "%03d.%@", index + 1, ext).sanitizedFilename(maxLength: 180)
    }

    private static func assetMetadata(for imageURL: URL, index: Int, imageID: String, pageURL: URL, info: (title: String, folderTitle: String, uploader: String)) -> [String: String] {
        let format = mediaFormat(for: imageURL)
        return DownloadMetadata.clean([
            "site": "Iwara",
            "title": info.title,
            "series": info.title,
            "artist": info.uploader,
            "author": info.uploader,
            "creator": info.uploader,
            "uploader": info.uploader,
            "id": imageID,
            "image_id": imageID,
            "gallery_id": imageID,
            "media_id": "\(imageID)-\(index)",
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

    private static func imageScope(fromHTML html: String) -> String {
        guard let marker = html.range(of: "page-image__slideshow", options: [.caseInsensitive]) else {
            return html
        }
        return String(html[marker.lowerBound...])
    }

    private static func appendImageURL(_ raw: String?, pageURL: URL, urls: inout [URL], seen: inout Set<String>) {
        guard let raw else { return }
        for base in preferredImageBases(for: raw, pageURL: pageURL) {
            guard let url = absoluteURL(raw, baseURL: base),
                  isImage(url) else {
                continue
            }
            let key = url.absoluteString
            guard !seen.contains(key) else { return }
            seen.insert(key)
            urls.append(url)
            return
        }
    }

    private static func collectImageURLs(
        in object: Any,
        pageURL: URL,
        insideMediaContainer: Bool,
        insideIgnoredContext: Bool,
        urls: inout [URL],
        seen: inout Set<String>
    ) {
        if let dictionary = object as? [String: Any] {
            for (key, value) in dictionary {
                let normalizedKey = normalizedJSONKey(key)
                let childIgnored = insideIgnoredContext || isIgnoredImageContext(normalizedKey)
                let childMediaContainer = insideMediaContainer || isImageMediaContainer(normalizedKey)
                if !childIgnored,
                   shouldCollectImageValue(forKey: normalizedKey, insideMediaContainer: childMediaContainer),
                   let raw = stringValue(value) {
                    appendImageURL(raw, pageURL: pageURL, urls: &urls, seen: &seen)
                }
                collectImageURLs(
                    in: value,
                    pageURL: pageURL,
                    insideMediaContainer: childMediaContainer,
                    insideIgnoredContext: childIgnored,
                    urls: &urls,
                    seen: &seen
                )
            }
        } else if let array = object as? [Any] {
            for value in array {
                collectImageURLs(
                    in: value,
                    pageURL: pageURL,
                    insideMediaContainer: insideMediaContainer,
                    insideIgnoredContext: insideIgnoredContext,
                    urls: &urls,
                    seen: &seen
                )
            }
        }
    }

    private static func preferredImageBases(for raw: String, pageURL: URL) -> [URL] {
        let value = decodeHTML(raw)
            .replacingOccurrences(of: #"\/"#, with: "/")
            .replacingOccurrences(of: #"\\/"#, with: "/")
            .trimmed
        if value.hasPrefix("/image/") || value.hasPrefix("image/") || value.hasPrefix("./image/") {
            return [imageBaseURL(for: pageURL), pageURL]
        }
        return [pageURL, imageBaseURL(for: pageURL)]
    }

    private static func imageBaseURL(for pageURL: URL) -> URL {
        var components = URLComponents()
        components.scheme = pageURL.scheme ?? "https"
        components.host = pageURL.host?.lowercased().hasSuffix(".test") == true ? "i.iwara.test" : "i.iwara.tv"
        components.path = "/"
        return components.url!
    }

    private static func shouldCollectImageValue(forKey key: String, insideMediaContainer: Bool) -> Bool {
        if ["image", "imageurl", "imageuri", "original", "originalurl", "originaluri", "source", "sourceurl", "download", "downloadurl", "view"].contains(key) {
            return true
        }
        return insideMediaContainer && ["url", "src", "path", "file", "fileurl", "fileuri"].contains(key)
    }

    private static func isImageMediaContainer(_ key: String) -> Bool {
        [
            "asset", "assets", "attachment", "attachments", "file", "files",
            "gallery", "galleryitem", "galleryitems", "image", "images",
            "item", "items", "media", "medias", "original", "originals",
            "photo", "photos", "picture", "pictures"
        ].contains(key)
    }

    private static func isIgnoredImageContext(_ key: String) -> Bool {
        key.contains("avatar") ||
            key.contains("cover") ||
            key.contains("icon") ||
            key.contains("poster") ||
            key.contains("preview") ||
            key.contains("profile") ||
            key.contains("thumb")
    }

    private static func normalizedJSONKey(_ key: String) -> String {
        key.lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
    }

    private static func scriptJSONObjects(fromHTML html: String) -> [Any] {
        let scripts = allCaptures(pattern: #"<script\b[^>]*>(.*?)</script>"#, in: html)
        var payloads: [String] = []
        for script in scripts {
            let decoded = decodeHTML(script).trimmed
            if decoded.hasPrefix("{") || decoded.hasPrefix("[") {
                payloads.append(decoded)
            }
            for pattern in [
                #"window\.__NUXT__\s*="#,
                #"window\.__INITIAL_STATE__\s*="#,
                #"__NUXT__\s*="#,
                #"__INITIAL_STATE__\s*="#
            ] {
                guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                    continue
                }
                let range = NSRange(decoded.startIndex..<decoded.endIndex, in: decoded)
                for match in regex.matches(in: decoded, range: range) {
                    guard let matchRange = Range(match.range, in: decoded),
                          let payload = balancedValue(startingAtOrAfter: matchRange.upperBound, in: decoded) else {
                        continue
                    }
                    payloads.append(payload)
                }
            }
        }

        return payloads.compactMap { payload in
            guard let data = payload.data(using: .utf8) else { return nil }
            return try? JSONSerialization.jsonObject(with: data)
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

    private static func stringValue(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            return number.stringValue
        default:
            return nil
        }
    }

    private static func isImage(_ url: URL) -> Bool {
        ["jpg", "jpeg", "png", "webp"].contains(url.pathExtension.lowercased())
    }

    private static func isSupportedHost(_ host: String) -> Bool {
        host == "iwara.tv" ||
            host == "www.iwara.tv" ||
            host == "iwara.test" ||
            host == "www.iwara.test"
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
        for suffix in [" - Iwara", " | Iwara", " - iwara.tv", " | iwara.tv"] {
            if text.lowercased().hasSuffix(suffix.lowercased()) {
                text = String(text.dropLast(suffix.count)).trimmed
            }
        }
        return (text.isEmpty ? fallback : text).sanitizedFilename(maxLength: 120)
    }
}
