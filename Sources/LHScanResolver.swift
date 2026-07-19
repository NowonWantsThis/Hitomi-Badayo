import Foundation

struct LHScanPage: Hashable {
    var title: String
    var url: URL
}

final class LHScanResolver {
    func canResolve(_ url: URL) -> Bool {
        Self.isSupportedURL(url) && Self.contentPath(from: url) != nil
    }

    func resolve(_ url: URL, headers: HTTPRequestOptions = HTTPRequestOptions()) async throws -> ResolvedDownload {
        guard let pageURL = Self.canonicalURL(for: url) else {
            throw NativeDownloadError.invalidURL(url.absoluteString)
        }

        let html = try await HTTPClient.shared.string(from: pageURL, referer: headers.referer, userAgent: headers.userAgent)
        try Self.throwIfLoginCookieRequired(html)
        var pages = Self.chapterPages(fromHTML: html, baseURL: pageURL)
        if pages.isEmpty {
            pages = [LHScanPage(title: Self.chapterTitle(fromHTML: html, fallbackURL: pageURL), url: pageURL)]
        }

        var assets: [ResolvedAsset] = []
        var seen = Set<String>()
        let title = Self.seriesTitle(fromHTML: html, fallbackURL: pageURL)
        for (pageOffset, page) in pages.enumerated() {
            try Task.checkCancellation()
            let pageHTML = pageOffset == 0 && URLIdentity.normalize(page.url.absoluteString) == URLIdentity.normalize(pageURL.absoluteString)
                ? html
                : try await HTTPClient.shared.string(from: page.url, referer: pageURL.absoluteString, userAgent: headers.userAgent)
            try Self.throwIfLoginCookieRequired(pageHTML)
            let images = Self.imageURLs(fromHTML: pageHTML, pageURL: page.url)
            for remote in images {
                let normalized = URLIdentity.normalize(remote.absoluteString)
                guard !seen.contains(normalized) else { continue }
                seen.insert(normalized)
                let index = assets.count + 1
                assets.append(ResolvedAsset(
                    remoteURL: remote,
                    filename: Self.filename(for: remote, pageTitle: page.title, index: index),
                    metadata: Self.assetMetadata(
                        title: title,
                        chapter: page.title,
                        pageURL: page.url,
                        remote: remote,
                        index: index
                    ),
                    referer: page.url.absoluteString
                ))
            }
        }

        guard !assets.isEmpty else {
            throw NativeDownloadError.noFiles
        }

        var metadata = Self.metadata(title: title, pageURL: pageURL, pageCount: pages.count, imageCount: assets.count)
        metadata["listed_page_count"] = String(pages.count)
        metadata["resolved_page_count"] = String(pages.count)
        metadata["resolved_media_count"] = String(assets.count)
        return ResolvedDownload(
            title: title,
            folderName: "LHScan \(title)".sanitizedFilename(maxLength: 120),
            assets: assets,
            metadata: metadata
        )
    }

    static func resolvedDownload(fromHTML html: String, pageURL: URL) throws -> ResolvedDownload {
        try throwIfLoginCookieRequired(html)
        let images = imageURLs(fromHTML: html, pageURL: pageURL)
        guard !images.isEmpty else {
            throw NativeDownloadError.noFiles
        }
        let title = seriesTitle(fromHTML: html, fallbackURL: pageURL)
        let chapter = chapterTitle(fromHTML: html, fallbackURL: pageURL)
        let assets = images.enumerated().map { offset, remote in
            let index = offset + 1
            return ResolvedAsset(
                remoteURL: remote,
                filename: filename(for: remote, pageTitle: chapter, index: index),
                metadata: assetMetadata(
                    title: title,
                    chapter: chapter,
                    pageURL: pageURL,
                    remote: remote,
                    index: index
                ),
                referer: pageURL.absoluteString
            )
        }
        return ResolvedDownload(
            title: title,
            folderName: "LHScan \(title)".sanitizedFilename(maxLength: 120),
            assets: assets,
            metadata: metadata(title: title, pageURL: pageURL, pageCount: 1, imageCount: assets.count)
        )
    }

    static func requiresLoginCookie(fromHTML html: String) -> Bool {
        let text = stripTags(html)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .folding(options: String.CompareOptions([.caseInsensitive, .diacriticInsensitive]), locale: .current)
            .lowercased()
        let compact = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        let hasLoginCue = compact.contains("login") ||
            compact.contains("log in") ||
            compact.contains("sign in") ||
            compact.contains("로그인") ||
            compact.contains("회원")
        let hasCookieCue = compact.contains("cookie") ||
            compact.contains("cookies") ||
            compact.contains("쿠키")
        let hasLoginForm = html.range(
            of: #"<input\b[^>]*(?:type=["']?password|name=["']?(?:password|passwd|pw))"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
        return (hasLoginCue && hasCookieCue) || hasLoginForm
    }

    static func throwIfLoginCookieRequired(_ html: String) throws {
        guard requiresLoginCookie(fromHTML: html) else { return }
        throw NativeDownloadError.unsupported("LHScan requires a logged-in cookie. Import browser cookies or use the login browser, then retry.")
    }

    static func canonicalURL(for url: URL) -> URL? {
        guard isSupportedURL(url),
              let path = contentPath(from: url),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.host = canonicalHost(for: url.host?.lowercased())
        components.path = path
        components.queryItems = nil
        components.fragment = nil
        return components.url
    }

    static func chapterPages(fromHTML html: String, baseURL: URL) -> [LHScanPage] {
        let listHTML = firstTagBody(tag: "ul", className: "list-chapters", in: html) ?? html
        let anchors = anchorEntries(fromHTML: listHTML)
        var pages: [LHScanPage] = []
        var seen = Set<String>()

        for anchor in anchors {
            guard let href = anchor.attributes["href"],
                  let url = absoluteURL(href, baseURL: baseURL),
                  isSupportedURL(url),
                  contentPath(from: url) != nil,
                  let canonical = canonicalURL(for: url) else {
                continue
            }
            let normalized = URLIdentity.normalize(canonical.absoluteString)
            guard !seen.contains(normalized) else { continue }
            seen.insert(normalized)
            let title = anchor.text.isEmpty ? chapterTitle(fromURL: canonical) : cleanTitle(anchor.text, fallback: chapterTitle(fromURL: canonical))
            pages.append(LHScanPage(title: title, url: canonical))
        }

        return pages.reversed()
    }

    static func imageURLs(fromHTML html: String, pageURL: URL) -> [URL] {
        var urls: [URL] = []
        var seen = Set<String>()

        for tag in captureFullMatches(pattern: #"<img\b[^>]*>"#, in: html) {
            let values = attributeValues(from: tag)
            let className = values["class"]?.lowercased() ?? ""
            guard className.contains("chapter-img") ||
                imageAttributes.contains(where: { values[$0] != nil }) else {
                continue
            }

            for raw in imageCandidates(from: values) {
                guard let remote = absoluteURL(raw, baseURL: pageURL),
                      shouldDownload(remote) else {
                    continue
                }
                let normalized = URLIdentity.normalize(remote.absoluteString)
                guard !seen.contains(normalized) else { break }
                seen.insert(normalized)
                urls.append(remote)
                break
            }
        }

        return urls
    }

    private static let imageAttributes = [
        "data-pagespeed-lazy-src",
        "data-src",
        "data-srcset",
        "data-aload",
        "data-original",
        "src"
    ]

    private static func imageCandidates(from attributes: [String: String]) -> [String] {
        var candidates: [String] = []
        for key in imageAttributes {
            guard let value = attributes[key]?.trimmed, !value.isEmpty else { continue }
            if key.hasSuffix("srcset"), let best = bestSrcsetCandidate(value) {
                candidates.append(best)
            } else {
                candidates.append(value)
            }
        }
        return candidates
    }

    private static func bestSrcsetCandidate(_ srcset: String) -> String? {
        let entries = srcset.components(separatedBy: ",").compactMap { part -> (url: String, score: Int)? in
            let pieces = part.trimmed.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
            guard let url = pieces.first, !url.isEmpty else { return nil }
            let descriptor = pieces.dropFirst().first ?? ""
            if descriptor.hasSuffix("w") {
                return (url, Int(descriptor.dropLast()) ?? 0)
            }
            if descriptor.hasSuffix("x") {
                return (url, Int((Double(descriptor.dropLast()) ?? 1.0) * 10_000))
            }
            return (url, 0)
        }
        return entries.max { $0.score < $1.score }?.url
    }

    private static func shouldDownload(_ url: URL) -> Bool {
        let absolute = url.absoluteString.lowercased()
        let skipped = [
            "credit_lhscan_",
            "5e1ad960d67b2_5e1ad962338c7",
            "fe132b3d32acc39f5adcea9075bedad4loveheaven",
            "lovehug_600cfd96e98ff.jpg",
            "image_5f0ecf23aed2e.png",
            "/uploads/lazy_loading.gif",
            "/xstaff.jpg.pagespeed.ic.gpq2sgcyan.webp",
            "/uploads/loading-mm.gif"
        ]
        if skipped.contains(where: { absolute.contains($0) }) {
            return false
        }

        let ext = url.pathExtension.lowercased()
        return ["jpg", "jpeg", "png", "gif", "webp"].contains(ext)
    }

    private static func seriesTitle(fromHTML html: String, fallbackURL: URL) -> String {
        let info = firstTagBody(tag: "ul", className: "manga-info", in: html) ?? html
        let h3 = captureMatches(pattern: #"<h3\b[^>]*>(.*?)</h3>"#, in: info).first
        return cleanTitle(h3 ?? titleTag(fromHTML: html) ?? fallbackURL.lastPathComponent, fallback: fallbackURL.lastPathComponent)
    }

    private static func chapterTitle(fromHTML html: String, fallbackURL: URL) -> String {
        let title = captureMatches(pattern: #"<h1\b[^>]*>(.*?)</h1>"#, in: html).first ??
            titleTag(fromHTML: html) ??
            chapterTitle(fromURL: fallbackURL)
        return cleanTitle(title, fallback: chapterTitle(fromURL: fallbackURL))
    }

    private static func chapterTitle(fromURL url: URL) -> String {
        let last = url.lastPathComponent
        return last.isEmpty ? "chapter" : last.replacingOccurrences(of: "-", with: " ")
    }

    private static func metadata(title: String, pageURL: URL, pageCount: Int, imageCount: Int) -> [String: String] {
        DownloadMetadata.clean([
            "series": title,
            "category": "manga",
            "type": "manga",
            "media_type": "image",
            "media_count": String(imageCount),
            "image_count": String(imageCount),
            "site": "LHScan",
            "host": pageURL.host ?? "",
            "slug": pageURL.lastPathComponent,
            "gallery_id": pageURL.lastPathComponent,
            "id": pageURL.lastPathComponent,
            "page_count": String(pageCount)
        ])
    }

    private static func assetMetadata(title: String, chapter: String, pageURL: URL, remote: URL, index: Int) -> [String: String] {
        let format = mediaFormat(for: remote)
        return DownloadMetadata.clean([
            "series": title,
            "chapter": chapter,
            "chapter_id": pageURL.lastPathComponent,
            "category": "manga",
            "collection_type": "manga",
            "type": "image",
            "media_type": "image",
            "site": "LHScan",
            "host": pageURL.host ?? "",
            "slug": pageURL.lastPathComponent,
            "gallery_id": pageURL.lastPathComponent,
            "id": pageURL.lastPathComponent,
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

    private static func filename(for url: URL, pageTitle: String, index: Int) -> String {
        let ext = mediaFormat(for: url)
        let prefix = pageTitle.sanitizedFilename(maxLength: 80)
        return "\(prefix)/\(String(format: "%04d", index)).\(ext)".sanitizedFilename(maxLength: 180)
    }

    private static func mediaFormat(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        if ext == "jpeg" {
            return "jpg"
        }
        return ext.isEmpty ? "jpg" : ext
    }

    private static func contentPath(from url: URL) -> String? {
        let path = url.path
            .replacingOccurrences(of: "/+", with: "/", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !path.isEmpty else { return nil }
        let first = path.split(separator: "/").first.map(String.init)?.lowercased() ?? ""
        guard !["app", "assets", "cdn-cgi", "contact", "dmca", "genres", "uploads"].contains(first) else {
            return nil
        }
        return "/" + path
    }

    private static func isSupportedURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return false
        }
        return isSupportedHost(host)
    }

    private static func isSupportedHost(_ host: String) -> Bool {
        host == "lovehug.net" ||
            host == "welovemanga.one" ||
            host == "welovemanga.net" ||
            host.hasSuffix(".welovemanga.one") ||
            host.hasSuffix(".welovemanga.net") ||
            host == "nicomanga.com" ||
            host.hasSuffix(".nicomanga.com") ||
            host == "lhscan.test" ||
            host == "welovemanga.test" ||
            host == "nicomanga.test"
    }

    private static func canonicalHost(for host: String?) -> String? {
        guard let host else { return nil }
        if host == "lovehug.net" || host == "welovemanga.net" {
            return "welovemanga.one"
        }
        return host
    }

    private static func firstTagBody(tag: String, className: String, in html: String) -> String? {
        let pattern = #"<\#(tag)\b[^>]*\bclass\s*=\s*["'][^"']*"# +
            NSRegularExpression.escapedPattern(for: className) +
            #"[^"']*["'][^>]*>(.*?)</\#(tag)>"#
        return captureMatches(pattern: pattern, in: html).first
    }

    private static func titleTag(fromHTML html: String) -> String? {
        captureMatches(pattern: #"<title\b[^>]*>(.*?)</title>"#, in: html).first
    }

    private static func anchorEntries(fromHTML html: String) -> [(attributes: [String: String], text: String)] {
        captureFullMatches(pattern: #"<a\b[^>]*>.*?</a>"#, in: html).map { anchor in
            let attrs = captureMatches(pattern: #"<a\b([^>]*)>"#, in: anchor).first ?? ""
            let text = captureMatches(pattern: #"<a\b[^>]*>(.*?)</a>"#, in: anchor).first ?? ""
            return (attributeValues(from: attrs), cleanTitle(text, fallback: ""))
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
                values[name] = decodeHTML(String(text[valueRange])).trimmed
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
            return String(text[capture])
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

    private static func absoluteURL(_ raw: String, baseURL: URL) -> URL? {
        let value = decodeHTML(raw).trimmed
        if value.hasPrefix("//") {
            return URL(string: "\(baseURL.scheme ?? "https"):\(value)")
        }
        return URL(string: value, relativeTo: baseURL)?.absoluteURL
    }

    private static func cleanTitle(_ raw: String, fallback: String) -> String {
        let title = decodeHTML(raw)
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmed
            .sanitizedFilename(maxLength: 120)
        return title.isEmpty ? fallback : title
    }

    private static func stripTags(_ text: String) -> String {
        text
            .replacingOccurrences(of: "<script\\b[^>]*>.*?</script>", with: " ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "<style\\b[^>]*>.*?</style>", with: " ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
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
            .replacingOccurrences(of: "&nbsp;", with: " ")
    }
}
