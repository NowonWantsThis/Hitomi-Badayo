import Foundation

final class V2PHResolver {
    private let maxPages = 1_000

    func canResolve(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(),
              Self.isSupportedHost(host),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return false
        }
        return Self.albumID(from: url) != nil
    }

    func resolve(
        _ url: URL,
        headers: HTTPRequestOptions = HTTPRequestOptions(),
        assetLimit: Int? = nil
    ) async throws -> ResolvedDownload {
        let albumURL = Self.canonicalAlbumURL(for: url) ?? url
        let firstHTML = try await HTTPClient.shared.string(from: albumURL, referer: headers.referer, userAgent: headers.userAgent)
        if Self.isLoginRequiredHTML(firstHTML) {
            throw NativeDownloadError.unsupported("V2PH login is required for this album.")
        }

        let title = Self.albumTitle(fromHTML: firstHTML, pageURL: albumURL)
        let albumMetadata = Self.albumMetadata(fromHTML: firstHTML, pageURL: albumURL, title: title)
        let finiteAssetLimit = assetLimit.flatMap { $0 > 0 ? $0 : nil }

        var assets: [ResolvedAsset] = []
        var seen = Set<String>()
        var page = 1
        var resolvedPageCount = 0
        while page <= maxPages {
            try Task.checkCancellation()
            guard let pageURL = Self.pageURL(page: page, baseURL: albumURL) else { break }
            let html = page == 1
                ? firstHTML
                : try await HTTPClient.shared.string(
                    from: pageURL,
                    referer: albumURL.absoluteString,
                    userAgent: headers.userAgent
                )
            if Self.isLoginRequiredHTML(html) {
                if page == 1 {
                    throw NativeDownloadError.unsupported("V2PH login is required for this album.")
                }
                break
            }
            guard Self.hasPhotosList(fromHTML: html) else {
                if page == 1 {
                    throw NativeDownloadError.noFiles
                }
                break
            }
            resolvedPageCount += 1

            for remote in Self.imageURLs(fromHTML: html, baseURL: pageURL) {
                let normalized = URLIdentity.normalize(remote.absoluteString)
                guard !seen.contains(normalized) else { continue }
                seen.insert(normalized)
                assets.append(Self.asset(
                    for: remote,
                    index: assets.count + 1,
                    referer: pageURL.absoluteString,
                    metadata: Self.assetMetadata(for: remote, albumMetadata: albumMetadata, pageURL: pageURL, index: assets.count + 1)
                ))
                if let finiteAssetLimit, assets.count >= finiteAssetLimit { break }
            }
            if let finiteAssetLimit, assets.count >= finiteAssetLimit { break }

            let pages = Self.paginationPageNumbers(fromHTML: html, baseURL: albumURL)
            guard let maximumPage = pages.max(), page < maximumPage else { break }
            page += 1
        }

        guard !assets.isEmpty else {
            throw NativeDownloadError.noFiles
        }

        var metadata = Self.downloadMetadata(from: albumMetadata, pageURL: albumURL, assetCount: assets.count)
        metadata["resolved_page_count"] = String(resolvedPageCount)
        metadata["resolved_media_count"] = String(assets.count)

        return ResolvedDownload(
            title: title,
            folderName: "V2PH \(title)".sanitizedFilename(maxLength: 120),
            assets: assets,
            metadata: metadata
        )
    }

    static func albumID(from url: URL) -> String? {
        let parts = pathParts(from: url)
        guard let index = parts.firstIndex(where: { $0.lowercased() == "album" }),
              index + 1 < parts.count else {
            return nil
        }
        let id = parts[index + 1].trimmed
        return id.isEmpty ? nil : id
    }

    static func canonicalAlbumURL(for url: URL) -> URL? {
        guard let albumID = albumID(from: url),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.path = "/album/\(albumID)"
        components.query = nil
        components.fragment = nil
        return components.url
    }

    static func albumTitle(fromHTML html: String, pageURL: URL) -> String {
        let title = elementText(pattern: #"<h1\b[^>]*>(.*?)</h1>"#, in: html) ??
            metaContent(from: html, names: ["og:title", "twitter:title"]) ??
            titleTag(fromHTML: html) ??
            albumID(from: pageURL) ??
            "V2PH Album"
        return cleanTitle(title, fallback: "V2PH \(albumID(from: pageURL) ?? "album")")
    }

    static func imageURLs(fromHTML html: String, baseURL: URL) -> [URL] {
        let scoped = firstCapture(patterns: [
            #"<(?:div|ul|section)\b[^>]*\bclass\s*=\s*["'][^"']*photos-list[^"']*["'][^>]*>(.*?)</(?:div|ul|section)>"#
        ], in: html) ?? html

        var results: [URL] = []
        var seen = Set<String>()
        for attrs in tagAttributes(tag: "img", html: scoped) {
            let values = attributeValues(from: attrs)
            let raw = values["data-src"] ??
                values["data-original"] ??
                values["data-lazy-src"] ??
                values["src"]
            guard let raw,
                  let url = absoluteURL(raw, baseURL: baseURL),
                  isLikelyImage(url) else {
                continue
            }
            let normalized = URLIdentity.normalize(url.absoluteString)
            guard !seen.contains(normalized) else { continue }
            seen.insert(normalized)
            results.append(url)
        }
        return results
    }

    static func hasPhotosList(fromHTML html: String) -> Bool {
        html.range(
            of: #"<(?:div|ul|section)\b[^>]*\bclass\s*=\s*[\"'][^\"']*\bphotos-list\b[^\"']*[\"']"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    static func pageURLs(fromHTML html: String, baseURL: URL) -> [URL] {
        var results: [URL] = []
        var seen = Set<String>()
        let baseAlbumID = albumID(from: baseURL)

        if let first = pageURL(page: 1, baseURL: baseURL) {
            let normalized = URLIdentity.normalize(first.absoluteString)
            seen.insert(normalized)
            results.append(first)
        }

        for href in anchorHREFs(fromHTML: html) {
            guard let url = absoluteURL(href, baseURL: baseURL),
                  albumID(from: url) == baseAlbumID,
                  queryPageNumber(from: url) != nil else {
                continue
            }
            let normalized = URLIdentity.normalize(url.absoluteString)
            guard !seen.contains(normalized) else { continue }
            seen.insert(normalized)
            results.append(url)
        }

        let maxPage = paginationPageNumbers(fromHTML: html, baseURL: baseURL)
            .max()
        if let maxPage, maxPage > 1 {
            for page in 2...maxPage {
                guard let url = pageURL(page: page, baseURL: baseURL) else { continue }
                let normalized = URLIdentity.normalize(url.absoluteString)
                guard !seen.contains(normalized) else { continue }
                seen.insert(normalized)
                results.append(url)
            }
        }

        return results.sorted { lhs, rhs in
            (queryPageNumber(from: lhs) ?? 1) < (queryPageNumber(from: rhs) ?? 1)
        }
    }

    static func pageURL(page: Int, baseURL: URL) -> URL? {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.queryItems = page > 1
            ? [URLQueryItem(name: "page", value: String(page))]
            : nil
        components?.fragment = nil
        return components?.url
    }

    static func queryPageNumber(from url: URL) -> Int? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name.lowercased() == "page" })?
            .value
            .flatMap(Int.init)
    }

    static func asset(for url: URL, index: Int, referer: String, metadata: [String: String] = [:]) -> ResolvedAsset {
        let ext = url.pathExtension.trimmed.isEmpty ? "jpg" : url.pathExtension.lowercased()
        let filename = String(format: "%04d.%@", index, ext).sanitizedFilename(maxLength: 180)
        return ResolvedAsset(remoteURL: url, filename: filename, metadata: metadata, referer: referer)
    }

    static func albumMetadata(fromHTML html: String, pageURL: URL, title: String? = nil) -> [String: String] {
        let links = anchorTexts(fromHTML: html)
        let model = firstLinkText(links, markers: ["model", "models", "girl", "girls", "star", "stars"])
        let tags = linkTexts(links, markers: ["tag", "tags"])
        let categories = linkTexts(links, markers: ["category", "categories"])
        let album = albumID(from: pageURL) ?? ""
        let resolvedTitle = title ?? albumTitle(fromHTML: html, pageURL: pageURL)

        return DownloadMetadata.clean([
            "artist": model,
            "author": model,
            "creator": model,
            "uploader": model,
            "channel": model,
            "series": resolvedTitle,
            "category": categories.joined(separator: ", "),
            "tag": tags.joined(separator: ", "),
            "tags": tags.joined(separator: ", "),
            "album_id": album,
            "gallery_id": album,
            "slug": album,
            "site": "V2PH",
            "title": resolvedTitle,
            "type": "album"
        ])
    }

    static func downloadMetadata(from metadata: [String: String], pageURL: URL? = nil, assetCount: Int) -> [String: String] {
        var result = metadata
        result["media_type"] = "image"
        result["media_count"] = String(assetCount)
        result["image_count"] = String(assetCount)
        if let pageURL {
            result["url"] = pageURL.absoluteString
            result["source_url"] = pageURL.absoluteString
            result["page_url"] = pageURL.absoluteString
        }
        return DownloadMetadata.clean(result)
    }

    static func assetMetadata(for url: URL, albumMetadata: [String: String], pageURL: URL, index: Int) -> [String: String] {
        let format = mediaFormat(for: url)
        let albumID = albumMetadata["album_id"] ?? albumMetadata["gallery_id"] ?? ""
        return DownloadMetadata.clean([
            "artist": albumMetadata["artist"] ?? "",
            "author": albumMetadata["author"] ?? "",
            "creator": albumMetadata["creator"] ?? "",
            "uploader": albumMetadata["uploader"] ?? "",
            "channel": albumMetadata["channel"] ?? "",
            "series": albumMetadata["series"] ?? albumMetadata["title"] ?? "",
            "category": albumMetadata["category"] ?? "",
            "tag": albumMetadata["tag"] ?? "",
            "tags": albumMetadata["tags"] ?? "",
            "album_id": albumID,
            "gallery_id": albumMetadata["gallery_id"] ?? albumID,
            "id": albumID,
            "media_id": albumID.isEmpty ? String(index) : "\(albumID)-\(index)",
            "page": String(index),
            "position": String(index),
            "slug": albumMetadata["slug"] ?? "",
            "site": "V2PH",
            "title": albumMetadata["title"] ?? "",
            "type": "image",
            "media_type": "image",
            "format": format,
            "media_format": format,
            "image_url": url.absoluteString,
            "media_url": url.absoluteString,
            "source_url": url.absoluteString,
            "page_url": pageURL.absoluteString
        ])
    }

    static func mediaFormat(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        if ext == "jpeg" {
            return "jpg"
        }
        return ext.isEmpty ? "jpg" : ext
    }

    static func isLoginRequiredHTML(_ html: String) -> Bool {
        let lowered = html.lowercased()
        return lowered.contains("https://www.v2ph.com/login") ||
            lowered.contains("/login") && lowered.contains("password") && lowered.contains("v2ph")
    }

    private static func tagAttributes(tag: String, html: String) -> [String] {
        let escaped = NSRegularExpression.escapedPattern(for: tag)
        guard let regex = try? NSRegularExpression(
            pattern: #"<\#(escaped)\b([^>]*)>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return []
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        return regex.matches(in: html, range: range).compactMap { match in
            guard let capture = Range(match.range(at: 1), in: html) else { return nil }
            return String(html[capture])
        }
    }

    private static func anchorHREFs(fromHTML html: String) -> [String] {
        guard let regex = try? NSRegularExpression(
            pattern: #"<a\b[^>]*\bhref\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>"']+))"#,
            options: [.caseInsensitive]
        ) else {
            return []
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        return regex.matches(in: html, range: range).compactMap { match in
            for group in 1...3 {
                guard let capture = Range(match.range(at: group), in: html) else { continue }
                return decodeHTML(String(html[capture])).trimmed
            }
            return nil
        }
    }

    private static func paginationPageNumbers(fromHTML html: String, baseURL: URL) -> [Int] {
        let scopes = captureMatches(
            pattern: #"<(?:ul|nav|div)\b[^>]*\bclass\s*=\s*["'][^"']*\bpagination\b[^"']*["'][^>]*>(.*?)</(?:ul|nav|div)>"#,
            in: html
        )
        let searchHTML = scopes.isEmpty ? [html] : scopes
        var numbers: [Int] = []
        var seen = Set<Int>()
        let baseAlbumID = albumID(from: baseURL)

        for scope in searchHTML {
            for anchor in anchorEntries(fromHTML: scope) {
                let number = queryPageNumberFromHref(anchor.href, baseURL: baseURL, baseAlbumID: baseAlbumID) ??
                    Int(anchor.text.trimmed)
                guard let number, number > 1, !seen.contains(number) else { continue }
                seen.insert(number)
                numbers.append(number)
            }
        }
        return numbers
    }

    private static func queryPageNumberFromHref(_ href: String, baseURL: URL, baseAlbumID: String?) -> Int? {
        guard let url = absoluteURL(href, baseURL: baseURL),
              albumID(from: url) == baseAlbumID else {
            return nil
        }
        return queryPageNumber(from: url)
    }

    private static func anchorTexts(fromHTML html: String) -> [(href: String, text: String)] {
        anchorEntries(fromHTML: html)
    }

    private static func anchorEntries(fromHTML html: String) -> [(href: String, text: String)] {
        guard let regex = try? NSRegularExpression(
            pattern: #"<a\b([^>]*)>(.*?)</a>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return []
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        return regex.matches(in: html, range: range).compactMap { match in
            guard let attributesRange = Range(match.range(at: 1), in: html),
                  let textRange = Range(match.range(at: 2), in: html) else {
                return nil
            }
            let values = attributeValues(from: String(html[attributesRange]))
            let text = cleanTitle(String(html[textRange]), fallback: "")
            guard !text.isEmpty else { return nil }
            return (values["href"]?.lowercased() ?? "", text)
        }
    }

    private static func linkTexts(_ links: [(href: String, text: String)], markers: [String]) -> [String] {
        uniqueStrings(links.compactMap { link in
            markers.contains { link.href.contains("/\($0)/") || link.href.contains("\($0)=") } ? link.text : nil
        })
    }

    private static func firstLinkText(_ links: [(href: String, text: String)], markers: [String]) -> String {
        linkTexts(links, markers: markers).first ?? ""
    }

    private static func uniqueStrings(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values {
            let key = value.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(value)
        }
        return result
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

    private static func elementText(pattern: String, in html: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, range: range),
              let capture = Range(match.range(at: 1), in: html) else {
            return nil
        }
        return decodeHTML(stripTags(String(html[capture]))).trimmed
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
            return String(text[capture])
        }
        return nil
    }

    private static func captureMatches(pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let capture = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[capture])
        }
    }

    private static func metaContent(from html: String, names: Set<String>) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"<meta\b([^>]*)>"#, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        for match in regex.matches(in: html, range: range) {
            guard let attributesRange = Range(match.range(at: 1), in: html) else { continue }
            let values = attributeValues(from: String(html[attributesRange]))
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
        elementText(pattern: #"<title\b[^>]*>(.*?)</title>"#, in: html)
    }

    private static func absoluteURL(_ raw: String, baseURL: URL) -> URL? {
        let value = raw.trimmed
        guard !value.isEmpty,
              !value.hasPrefix("#"),
              !value.lowercased().hasPrefix("javascript:"),
              !value.lowercased().hasPrefix("mailto:") else {
            return nil
        }
        if value.hasPrefix("//") {
            return URL(string: "\(baseURL.scheme ?? "https"):\(value)")
        }
        return URL(string: value, relativeTo: baseURL)?.absoluteURL
    }

    private static func isLikelyImage(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        let path = url.path.lowercased()
        if ext == "svg" || path.contains("placeholder") || path.contains("loading") {
            return false
        }
        if ["jpg", "jpeg", "png", "webp", "gif", "avif"].contains(ext) {
            return true
        }
        let host = url.host?.lowercased() ?? ""
        return host.contains("v2ph") || host.contains("cdn") || host.contains("img")
    }

    private static func pathParts(from url: URL) -> [String] {
        url.path.split(separator: "/").map { String($0).removingPercentEncoding ?? String($0) }
    }

    private static func cleanTitle(_ raw: String, fallback: String) -> String {
        var title = decodeHTML(stripTags(raw))
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmed
        for suffix in [" - V2PH", " | V2PH", " - v2ph.com", " | v2ph.com"] {
            if title.lowercased().hasSuffix(suffix.lowercased()) {
                title.removeLast(suffix.count)
                title = title.trimmed
            }
        }
        return title.isEmpty ? fallback : title.sanitizedFilename(maxLength: 120)
    }

    private static func stripTags(_ text: String) -> String {
        text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
    }

    private static func decodeHTML(_ text: String) -> String {
        var output = text
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")

        guard let regex = try? NSRegularExpression(pattern: #"&#(x?[0-9A-Fa-f]+);"#) else {
            return output
        }
        let matches = regex.matches(in: output, range: NSRange(output.startIndex..<output.endIndex, in: output)).reversed()
        for match in matches {
            guard let whole = Range(match.range(at: 0), in: output),
                  let digitsRange = Range(match.range(at: 1), in: output) else {
                continue
            }
            let digits = String(output[digitsRange])
            let radix = digits.lowercased().hasPrefix("x") ? 16 : 10
            let value = radix == 16 ? String(digits.dropFirst()) : digits
            if let scalarValue = UInt32(value, radix: radix),
               let scalar = UnicodeScalar(scalarValue) {
                output.replaceSubrange(whole, with: String(Character(scalar)))
            }
        }
        return output
    }

    private static func isSupportedHost(_ host: String) -> Bool {
        host == "v2ph.com" ||
            host == "www.v2ph.com" ||
            host == "v2ph.test" ||
            host == "www.v2ph.test"
    }
}
