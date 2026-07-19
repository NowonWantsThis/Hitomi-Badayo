import Foundation

struct ManatokiContentID: Hashable {
    var section: String
    var id: String
}

final class ManatokiResolver {
    func canResolve(_ url: URL) -> Bool {
        Self.contentID(from: url) != nil
    }

    func resolve(_ url: URL, headers: HTTPRequestOptions = HTTPRequestOptions()) async throws -> ResolvedDownload {
        guard let id = Self.contentID(from: url),
              let pageURL = Self.canonicalURL(for: url) else {
            throw NativeDownloadError.invalidURL(url.absoluteString)
        }

        let html = try await HTTPClient.shared.string(from: pageURL, referer: headers.referer, userAgent: headers.userAgent)
        var pageURLs = Self.pageURLs(fromHTML: html, baseURL: pageURL)
        if pageURLs.isEmpty {
            pageURLs = [pageURL]
        }

        var assets: [ResolvedAsset] = []
        var seen = Set<String>()
        let title = Self.title(fromHTML: html, fallback: "\(id.section) \(id.id)")
        let artist = Self.artist(fromHTML: html)
        for (pageIndex, currentURL) in pageURLs.enumerated() {
            try Task.checkCancellation()
            let pageHTML = pageIndex == 0 && URLIdentity.normalize(currentURL.absoluteString) == URLIdentity.normalize(pageURL.absoluteString)
                ? html
                : try await HTTPClient.shared.string(from: currentURL, referer: pageURL.absoluteString, userAgent: headers.userAgent)
            let images = Self.imageURLs(fromHTML: pageHTML, pageURL: currentURL)
            for remote in images {
                let normalized = URLIdentity.normalize(remote.absoluteString)
                guard !seen.contains(normalized) else { continue }
                seen.insert(normalized)
                let index = assets.count + 1
                assets.append(ResolvedAsset(
                    remoteURL: remote,
                    filename: Self.filename(for: remote, index: index),
                    metadata: Self.assetMetadata(
                        id: id,
                        title: title,
                        artist: artist,
                        remote: remote,
                        pageURL: currentURL,
                        index: index
                    ),
                    referer: currentURL.absoluteString
                ))
            }
        }

        guard !assets.isEmpty else {
            throw NativeDownloadError.noFiles
        }

        var metadata = Self.metadata(id: id, title: title, artist: artist, pageCount: pageURLs.count, imageCount: assets.count)
        metadata["listed_page_count"] = String(pageURLs.count)
        metadata["resolved_page_count"] = String(pageURLs.count)
        metadata["resolved_media_count"] = String(assets.count)
        return ResolvedDownload(
            title: title,
            folderName: "Manatoki \(title)".sanitizedFilename(maxLength: 120),
            assets: assets,
            metadata: metadata
        )
    }

    static func resolvedDownload(fromHTML html: String, pageURL: URL, id: ManatokiContentID? = nil) throws -> ResolvedDownload {
        let contentID = id ?? contentID(from: pageURL) ?? ManatokiContentID(section: pageURL.path.split(separator: "/").first.map(String.init) ?? "comic", id: pageURL.lastPathComponent)
        let images = imageURLs(fromHTML: html, pageURL: pageURL)
        guard !images.isEmpty else {
            throw NativeDownloadError.noFiles
        }

        let title = title(fromHTML: html, fallback: "\(contentID.section) \(contentID.id)")
        let artist = artist(fromHTML: html)
        let assets = images.enumerated().map { offset, remote in
            let index = offset + 1
            return ResolvedAsset(
                remoteURL: remote,
                filename: filename(for: remote, index: index),
                metadata: assetMetadata(
                    id: contentID,
                    title: title,
                    artist: artist,
                    remote: remote,
                    pageURL: pageURL,
                    index: index
                ),
                referer: pageURL.absoluteString
            )
        }
        return ResolvedDownload(
            title: title,
            folderName: "Manatoki \(title)".sanitizedFilename(maxLength: 120),
            assets: assets,
            metadata: metadata(id: contentID, title: title, artist: artist, pageCount: 1, imageCount: assets.count)
        )
    }

    static func contentID(from url: URL) -> ManatokiContentID? {
        guard let host = url.host?.lowercased(),
              isManatokiHost(host),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }

        let parts = url.path.split(separator: "/").map(String.init)
        if parts.count >= 2,
           ["comic", "webtoon"].contains(parts[0].lowercased()),
           isNumeric(parts[1]) {
            return ManatokiContentID(section: parts[0].lowercased(), id: parts[1])
        }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let items = components?.queryItems ?? []
        if url.path.lowercased().hasSuffix("/board.php"),
           let section = items.first(where: { $0.name.lowercased() == "bo_table" })?.value,
           let id = items.first(where: { $0.name.lowercased() == "wr_id" })?.value,
           isValidSection(section),
           isNumeric(id) {
            return ManatokiContentID(section: section.lowercased(), id: id)
        }

        return nil
    }

    static func canonicalURL(for url: URL) -> URL? {
        guard let id = contentID(from: url),
              let host = url.host?.lowercased() else {
            return nil
        }

        var components = URLComponents()
        components.scheme = url.scheme ?? "https"
        components.host = host
        components.path = "/\(id.section)/\(id.id)"
        return components.url
    }

    static func pageURLs(fromHTML html: String, baseURL: URL) -> [URL] {
        let navHTML = firstTagBody(className: "toon-nav", in: html) ?? html
        var candidates: [URL] = []

        let optionTags = captureFullMatches(pattern: #"<option\b[^>]*>"#, in: navHTML)
        for tag in optionTags {
            let values = attributeValues(from: tag)
            guard let raw = values["value"]?.trimmed, !raw.isEmpty else { continue }
            if let url = pageURL(from: raw, baseURL: baseURL) {
                candidates.append(url)
            }
        }

        if candidates.isEmpty {
            for href in anchorHREFs(fromHTML: navHTML) {
                guard let url = absoluteURL(href, baseURL: baseURL),
                      contentID(from: url) != nil else {
                    continue
                }
                candidates.append(canonicalURL(for: url) ?? url)
            }
        }

        return uniqueURLs(candidates).reversed()
    }

    static func imageURLs(fromHTML html: String, pageURL: URL) -> [URL] {
        let body = firstTagBody(className: "view-content", in: html) ??
            firstTagBody(className: "view-padding", in: html) ??
            html
        let dataKey = firstCapture(patterns: [#"data_attribute\s*:\s*['"](.+?)['"]"#], in: html)
        let imgTags = captureFullMatches(pattern: #"<img\b[^>]*>"#, in: body)

        var output: [URL] = []
        var seen = Set<String>()
        for tag in imgTags {
            guard isVisibleImageTag(tag) else { continue }
            let values = attributeValues(from: tag)
            let keys = imageAttributeKeys(dataKey: dataKey)
            for key in keys {
                guard let raw = values[key]?.trimmed,
                      !raw.isEmpty,
                      let remote = absoluteURL(raw, baseURL: pageURL),
                      shouldDownload(remote) else {
                    continue
                }
                let normalized = URLIdentity.normalize(remote.absoluteString)
                guard !seen.contains(normalized) else { break }
                seen.insert(normalized)
                output.append(remote)
                break
            }
        }
        return output
    }

    private static func pageURL(from raw: String, baseURL: URL) -> URL? {
        if let url = absoluteURL(raw, baseURL: baseURL),
           contentID(from: url) != nil {
            return canonicalURL(for: url) ?? url
        }
        guard isNumeric(raw),
              let current = contentID(from: baseURL) else {
            return nil
        }
        var components = URLComponents()
        components.scheme = baseURL.scheme ?? "https"
        components.host = baseURL.host
        components.path = "/\(current.section)/\(raw)"
        return components.url
    }

    private static func imageAttributeKeys(dataKey: String?) -> [String] {
        var keys: [String] = []
        if let dataKey, !dataKey.isEmpty {
            keys.append("data-\(dataKey.lowercased())")
        }
        keys.append(contentsOf: ["data-original", "data-src", "data-lazy-src", "data-url", "src"])
        return keys
    }

    private static func isVisibleImageTag(_ tag: String) -> Bool {
        let values = attributeValues(from: tag)
        let style = values["style"]?.lowercased() ?? ""
        if style.range(of: #"display\s*:\s*none"#, options: .regularExpression) != nil {
            return false
        }
        return true
    }

    private static func shouldDownload(_ url: URL) -> Bool {
        let path = url.path.lowercased()
        if path.contains("/img/cang") || path.contains("/img/blank.gif") {
            return false
        }
        let ext = url.pathExtension.lowercased()
        if ["jpg", "jpeg", "png", "gif", "webp"].contains(ext) {
            return true
        }
        return url.host?.lowercased().contains("toki") == true
    }

    private static func title(fromHTML html: String, fallback: String) -> String {
        let title = metaContent(from: html, names: ["subject", "og:title", "twitter:title"]) ??
            textForClass("view-title", in: html) ??
            titleTag(fromHTML: html) ??
            fallback
        return cleanTitle(title, fallback: fallback)
    }

    private static func artist(fromHTML html: String) -> String? {
        firstCapture(patterns: [#"작가[ #]*:[ #]*(.+?)#"#, #"작가\s*[:：]\s*([^<\n\r]+)"#], in: stripTags(html))
            .map { cleanTitle($0, fallback: "") }
            .flatMap { $0.isEmpty ? nil : $0 }
    }

    private static func metadata(id: ManatokiContentID, title: String, artist: String?, pageCount: Int, imageCount: Int) -> [String: String] {
        DownloadMetadata.clean([
            "artist": artist ?? "",
            "author": artist ?? "",
            "creator": artist ?? "",
            "series": title,
            "category": id.section,
            "type": id.section,
            "media_type": "image",
            "media_count": String(imageCount),
            "image_count": String(imageCount),
            "site": "Manatoki",
            "gallery_id": id.id,
            "id": id.id,
            "post_id": id.id,
            "section": id.section,
            "page_count": String(pageCount)
        ])
    }

    private static func assetMetadata(id: ManatokiContentID, title: String, artist: String?, remote: URL, pageURL: URL, index: Int) -> [String: String] {
        let format = mediaFormat(for: remote)
        return DownloadMetadata.clean([
            "artist": artist ?? "",
            "author": artist ?? "",
            "creator": artist ?? "",
            "series": title,
            "category": id.section,
            "collection_type": id.section,
            "type": "image",
            "media_type": "image",
            "site": "Manatoki",
            "gallery_id": id.id,
            "id": id.id,
            "post_id": id.id,
            "section": id.section,
            "page": String(index),
            "position": String(index),
            "format": format,
            "media_format": format,
            "image_url": remote.absoluteString,
            "media_url": remote.absoluteString,
            "source_url": remote.absoluteString,
            "page_url": pageURL.absoluteString
        ])
    }

    private static func filename(for url: URL, index: Int) -> String {
        let ext = mediaFormat(for: url)
        return String(format: "%04d.%@", index, ext).sanitizedFilename(maxLength: 120)
    }

    private static func mediaFormat(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        if ext == "jpeg" {
            return "jpg"
        }
        return ext.isEmpty ? "jpg" : ext
    }

    private static func isManatokiHost(_ host: String) -> Bool {
        let regex = #"^(?:.*\.)?(?:mana|new)toki[0-9]*\.(?:com|net|test)$"#
        return host.range(of: regex, options: .regularExpression) != nil
    }

    private static func isValidSection(_ value: String) -> Bool {
        value.range(of: #"^[0-9A-Za-z_]+$"#, options: .regularExpression) != nil
    }

    private static func isNumeric(_ text: String) -> Bool {
        !text.isEmpty && text.allSatisfy { $0 >= "0" && $0 <= "9" }
    }

    private static func uniqueURLs(_ urls: [URL]) -> [URL] {
        var output: [URL] = []
        var seen = Set<String>()
        for url in urls {
            let normalized = URLIdentity.normalize(url.absoluteString)
            guard !seen.contains(normalized) else { continue }
            seen.insert(normalized)
            output.append(url)
        }
        return output
    }

    private static func firstTagBody(className: String, in html: String) -> String? {
        let pattern = #"<(?:(?:div)|(?:section)|(?:article))\b[^>]*\bclass\s*=\s*["'][^"']*"# +
            NSRegularExpression.escapedPattern(for: className) +
            #"[^"']*["'][^>]*>(.*?)</(?:(?:div)|(?:section)|(?:article))>"#
        return captureMatches(pattern: pattern, in: html).first
    }

    private static func textForClass(_ className: String, in html: String) -> String? {
        let pattern = #"<[^>]+\bclass\s*=\s*["'][^"']*"# +
            NSRegularExpression.escapedPattern(for: className) +
            #"[^"']*["'][^>]*>(.*?)</[^>]+>"#
        return captureMatches(pattern: pattern, in: html).first.map(stripTags)
    }

    private static func metaContent(from html: String, names: Set<String>) -> String? {
        let metas = captureFullMatches(pattern: #"<meta\b[^>]*>"#, in: html)
        for tag in metas {
            let values = attributeValues(from: tag)
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
        captureMatches(pattern: #"<title\b[^>]*>(.*?)</title>"#, in: html).first
    }

    private static func anchorHREFs(fromHTML html: String) -> [String] {
        captureFullMatches(pattern: #"<a\b[^>]*>"#, in: html).compactMap { tag in
            attributeValues(from: tag)["href"]
        }
    }

    private static func attributeValues(from text: String) -> [String: String] {
        guard let regex = try? NSRegularExpression(
            pattern: #"\b([A-Za-z_:][-A-Za-z0-9_:.]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>"']+))"#,
            options: [.caseInsensitive]
        ) else {
            return [:]
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        var values: [String: String] = [:]
        for match in regex.matches(in: text, range: range) {
            guard let nameRange = Range(match.range(at: 1), in: text) else { continue }
            let name = String(text[nameRange]).lowercased()
            for group in 2...4 {
                guard let valueRange = Range(match.range(at: group), in: text) else { continue }
                values[name] = normalizeEscapes(decodeHTML(String(text[valueRange]))).trimmed
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

    private static func cleanTitle(_ raw: String, fallback: String) -> String {
        let title = stripTags(raw)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmed
        return title.isEmpty ? fallback : title.sanitizedFilename(maxLength: 120)
    }

    private static func stripTags(_ text: String) -> String {
        decodeHTML(text)
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmed
    }

    private static func normalizeEscapes(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"\\u002F"#, with: "/", options: .caseInsensitive)
            .replacingOccurrences(of: #"\/"#, with: "/")
            .replacingOccurrences(of: #"\\/"#, with: "/")
            .replacingOccurrences(of: #"\\u0026"#, with: "&", options: .caseInsensitive)
            .replacingOccurrences(of: #"\""#, with: "\"")
    }

    private static func decodeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
    }
}
