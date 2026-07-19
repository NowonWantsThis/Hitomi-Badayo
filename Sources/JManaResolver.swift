import Foundation

struct JManaPage: Hashable {
    var title: String
    var url: URL
    var id: Int
}

final class JManaResolver {
    func canResolve(_ url: URL) -> Bool {
        Self.canonicalURL(for: url) != nil
    }

    func resolve(_ url: URL, headers: HTTPRequestOptions = HTTPRequestOptions()) async throws -> ResolvedDownload {
        guard let pageURL = Self.canonicalURL(for: url) else {
            throw NativeDownloadError.invalidURL(url.absoluteString)
        }

        let html = try await HTTPClient.shared.string(from: pageURL, referer: headers.referer, userAgent: headers.userAgent)
        let detailID = Self.detailID(from: pageURL)
        let selectedID = Self.selectedDetailID(fromHTML: html) ?? detailID
        let listURL = Self.listURL(fromHTML: html, baseURL: pageURL)
        let listBaseURL = listURL ?? pageURL
        let listHTML: String
        if let listURL, URLIdentity.normalize(listURL.absoluteString) != URLIdentity.normalize(pageURL.absoluteString) {
            listHTML = try await HTTPClient.shared.string(from: listURL, referer: pageURL.absoluteString, userAgent: headers.userAgent)
        } else {
            listHTML = html
        }

        var pages = Self.chapterPages(fromHTML: listHTML, baseURL: listBaseURL)
        if let selectedID, detailID != nil {
            pages = pages.filter { $0.id == selectedID }
        }
        if pages.isEmpty, let detailID {
            pages = [JManaPage(title: Self.chapterTitle(fromHTML: html, fallbackURL: pageURL), url: pageURL, id: detailID)]
        }

        var assets: [ResolvedAsset] = []
        var seen = Set<String>()
        let title = Self.seriesTitle(fromHTML: listHTML, fallbackURL: listBaseURL)
        let artist = Self.artist(fromHTML: listHTML) ?? Self.artist(fromHTML: html)
        for (pageOffset, page) in pages.enumerated() {
            try Task.checkCancellation()
            let pageHTML = pageOffset == 0 && URLIdentity.normalize(page.url.absoluteString) == URLIdentity.normalize(pageURL.absoluteString)
                ? html
                : try await HTTPClient.shared.string(from: page.url, referer: listBaseURL.absoluteString, userAgent: headers.userAgent)
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
                        artist: artist,
                        chapter: page.title,
                        chapterID: String(page.id),
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

        var metadata = Self.metadata(title: title, artist: artist, pageURL: pageURL, pageCount: pages.count, imageCount: assets.count)
        metadata["listed_page_count"] = String(pages.count)
        metadata["resolved_page_count"] = String(pages.count)
        metadata["resolved_media_count"] = String(assets.count)
        return ResolvedDownload(
            title: title,
            folderName: "JMana \(title)".sanitizedFilename(maxLength: 120),
            assets: assets,
            metadata: metadata
        )
    }

    static func resolvedDownload(fromHTML html: String, pageURL: URL) throws -> ResolvedDownload {
        let images = imageURLs(fromHTML: html, pageURL: pageURL)
        guard !images.isEmpty else {
            throw NativeDownloadError.noFiles
        }

        let title = seriesTitle(fromHTML: html, fallbackURL: pageURL)
        let chapter = chapterTitle(fromHTML: html, fallbackURL: pageURL)
        let artist = artist(fromHTML: html)
        let chapterID = identifier(from: pageURL)
        let assets = images.enumerated().map { offset, remote in
            let index = offset + 1
            return ResolvedAsset(
                remoteURL: remote,
                filename: filename(for: remote, pageTitle: chapter, index: index),
                metadata: assetMetadata(
                    title: title,
                    artist: artist,
                    chapter: chapter,
                    chapterID: chapterID,
                    pageURL: pageURL,
                    remote: remote,
                    index: index
                ),
                referer: pageURL.absoluteString
            )
        }
        return ResolvedDownload(
            title: title,
            folderName: "JMana \(title)".sanitizedFilename(maxLength: 120),
            assets: assets,
            metadata: metadata(title: title, artist: artist, pageURL: pageURL, pageCount: 1, imageCount: assets.count)
        )
    }

    static func canonicalURL(for url: URL) -> URL? {
        guard isSupportedURL(url),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.fragment = nil
        return components.url
    }

    static func detailID(from url: URL) -> Int? {
        guard isSupportedHost(url.host?.lowercased() ?? "") else { return nil }
        return queryValue("bookdetailid", in: url).flatMap(Int.init)
    }

    static func chapterPages(fromHTML html: String, baseURL: URL) -> [JManaPage] {
        let containers = captureFullMatches(
            pattern: #"<div\b[^>]*\bclass\s*=\s*["'][^"']*inner[^"']*["'][^>]*>.*?</div>"#,
            in: html
        )
        let searchBlocks = containers.isEmpty ? [html] : containers
        var pages: [JManaPage] = []
        var seen = Set<Int>()

        for block in searchBlocks {
            for anchor in anchorEntries(fromHTML: block) {
                guard !anchor.html.lowercased().contains("<img"),
                      let href = anchor.attributes["href"],
                      let url = absoluteURL(href, baseURL: baseURL),
                      let id = detailID(from: url),
                      let canonical = canonicalURL(for: url),
                      !seen.contains(id) else {
                    continue
                }
                seen.insert(id)
                let title = anchor.text.isEmpty ? "Page \(id)" : cleanTitle(anchor.text, fallback: "Page \(id)")
                pages.append(JManaPage(title: title, url: canonical, id: id))
            }
        }

        return pages.reversed()
    }

    static func imageURLs(fromHTML html: String, pageURL: URL) -> [URL] {
        let inserted = insertedIndexes(fromHTML: html)
        let body = firstTagBody(className: "pdf-wrap", in: html) ?? html
        let imageTags = captureFullMatches(pattern: #"<img\b[^>]*>"#, in: body)
        var urls: [URL] = []
        var seen = Set<String>()

        for (index, tag) in imageTags.enumerated() {
            guard !inserted.contains(index) else { continue }
            let values = attributeValues(from: tag)
            let raw = nonEmpty(values["data-src"]) ?? nonEmpty(values["src"])
            guard let raw,
                  let remote = absoluteURL(raw, baseURL: pageURL),
                  shouldDownload(remote) else {
                continue
            }
            let normalized = URLIdentity.normalize(remote.absoluteString)
            guard !seen.contains(normalized) else { continue }
            seen.insert(normalized)
            urls.append(remote)
        }

        return urls
    }

    static func listURL(fromHTML html: String, baseURL: URL) -> URL? {
        for anchor in anchorEntries(fromHTML: html) {
            guard let href = anchor.attributes["href"],
                  let url = absoluteURL(href, baseURL: baseURL),
                  isListURL(url),
                  let canonical = canonicalURL(for: url) else {
                continue
            }
            return canonical
        }
        return nil
    }

    static func selectedDetailID(fromHTML html: String) -> Int? {
        let selectBody = firstTagBody(tag: "select", className: "bookselect", in: html) ?? html
        let optionTags = captureFullMatches(pattern: #"<option\b[^>]*>"#, in: selectBody)
        for tag in optionTags {
            let values = attributeValues(from: tag)
            guard values["selected"] != nil || tag.lowercased().contains(" selected") else { continue }
            return values["value"].flatMap(Int.init)
        }
        return nil
    }

    private static func isSupportedURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              isSupportedHost(host) else {
            return false
        }
        return isJManaPath(url)
    }

    private static func isSupportedHost(_ host: String) -> Bool {
        host.range(of: #"(^|\.)jmana[0-9]*(\.|$)"#, options: .regularExpression) != nil
    }

    private static func isJManaPath(_ url: URL) -> Bool {
        let name = url.path.split(separator: "/").last.map(String.init)?.lowercased() ?? ""
        switch name {
        case "comic_list_title", "book":
            return queryValue("book", in: url) != nil
        case "bookdetail":
            return queryValue("book", in: url) != nil || queryValue("bookdetailid", in: url) != nil
        case "book_by_title":
            return queryValue("title", in: url) != nil
        default:
            return false
        }
    }

    private static func isListURL(_ url: URL) -> Bool {
        let name = url.path.split(separator: "/").last.map(String.init)?.lowercased() ?? ""
        return isSupportedHost(url.host?.lowercased() ?? "") &&
            ["comic_list_title", "book"].contains(name) &&
            queryValue("book", in: url) != nil
    }

    private static func insertedIndexes(fromHTML html: String) -> Set<Int> {
        guard let raw = captureMatches(pattern: #"var\s*inserted\s*=\s*['"](.*?)['"]"#, in: html).first else {
            return []
        }
        return Set(raw.split(separator: ",").compactMap { Int(String($0).trimmed) })
    }

    private static func shouldDownload(_ url: URL) -> Bool {
        let absolute = url.absoluteString.lowercased()
        if absolute.contains("/adimg/") || absolute.contains("/notice") {
            return false
        }
        let ext = url.pathExtension.lowercased()
        return ext.isEmpty || ["jpg", "jpeg", "png", "gif", "webp"].contains(ext)
    }

    private static func seriesTitle(fromHTML html: String, fallbackURL: URL) -> String {
        let titleAnchor = captureMatches(
            pattern: #"<a\b[^>]*\bclass\s*=\s*["'][^"']*tit[^"']*["'][^>]*>(.*?)</a>"#,
            in: html
        ).first
        let text = stripTags(html)
        let koreanTitle = firstCapture(patterns: [#"제목\s*[:：]\s*([^\n\r<]+)"#], in: text)
        return cleanTitle(titleAnchor ?? koreanTitle ?? titleTag(fromHTML: html) ?? fallbackURL.lastPathComponent, fallback: fallbackURL.lastPathComponent)
    }

    private static func chapterTitle(fromHTML html: String, fallbackURL: URL) -> String {
        let title = captureMatches(pattern: #"<h1\b[^>]*>(.*?)</h1>"#, in: html).first ??
            captureMatches(pattern: #"<h2\b[^>]*>(.*?)</h2>"#, in: html).first ??
            titleTag(fromHTML: html) ??
            fallbackURL.lastPathComponent
        return cleanTitle(title, fallback: fallbackURL.lastPathComponent)
    }

    private static func artist(fromHTML html: String) -> String? {
        firstCapture(patterns: [#"작가\s*[:：]\s*([^\n\r<]+)"#], in: stripTags(html))
            .map { cleanTitle($0, fallback: "") }
            .flatMap { $0.isEmpty || $0 == "N/A" ? nil : $0 }
    }

    private static func metadata(title: String, artist: String?, pageURL: URL, pageCount: Int, imageCount: Int) -> [String: String] {
        let id = identifier(from: pageURL)
        return DownloadMetadata.clean([
            "artist": artist ?? "",
            "author": artist ?? "",
            "creator": artist ?? "",
            "series": title,
            "category": "manga",
            "type": "manga",
            "media_type": "image",
            "media_count": String(imageCount),
            "image_count": String(imageCount),
            "site": "JMana",
            "host": pageURL.host ?? "",
            "gallery_id": id,
            "id": id,
            "post_id": detailID(from: pageURL).map(String.init) ?? "",
            "page_count": String(pageCount)
        ])
    }

    private static func assetMetadata(title: String, artist: String?, chapter: String, chapterID: String, pageURL: URL, remote: URL, index: Int) -> [String: String] {
        let format = mediaFormat(for: remote)
        return DownloadMetadata.clean([
            "artist": artist ?? "",
            "author": artist ?? "",
            "creator": artist ?? "",
            "series": title,
            "chapter": chapter,
            "chapter_id": chapterID,
            "category": "manga",
            "collection_type": "manga",
            "type": "image",
            "media_type": "image",
            "site": "JMana",
            "host": pageURL.host ?? "",
            "gallery_id": chapterID,
            "id": chapterID,
            "post_id": detailID(from: pageURL).map(String.init) ?? chapterID,
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

    private static func identifier(from pageURL: URL) -> String {
        detailID(from: pageURL).map(String.init) ??
            queryValue("book", in: pageURL) ??
            queryValue("title", in: pageURL) ??
            pageURL.lastPathComponent
    }

    private static func queryValue(_ name: String, in url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name.lowercased() == name.lowercased() }?
            .value?
            .trimmed
            .nilIfEmpty
    }

    private static func firstTagBody(tag: String, className: String, in html: String) -> String? {
        let escapedTag = NSRegularExpression.escapedPattern(for: tag)
        let pattern = #"<\#(escapedTag)\b[^>]*\bclass\s*=\s*["'][^"']*"# +
            NSRegularExpression.escapedPattern(for: className) +
            #"[^"']*["'][^>]*>(.*?)</\#(escapedTag)>"#
        return captureMatches(pattern: pattern, in: html).first
    }

    private static func firstTagBody(className: String, in html: String) -> String? {
        let pattern = #"<([A-Za-z0-9]+)\b[^>]*\bclass\s*=\s*["'][^"']*"# +
            NSRegularExpression.escapedPattern(for: className) +
            #"[^"']*["'][^>]*>(.*?)</\1>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, range: range),
              match.numberOfRanges > 2,
              let capture = Range(match.range(at: 2), in: html) else {
            return nil
        }
        return String(html[capture])
    }

    private static func titleTag(fromHTML html: String) -> String? {
        captureMatches(pattern: #"<title\b[^>]*>(.*?)</title>"#, in: html).first
    }

    private static func anchorEntries(fromHTML html: String) -> [(html: String, attributes: [String: String], text: String)] {
        captureFullMatches(pattern: #"<a\b[^>]*>.*?</a>"#, in: html).map { anchor in
            let attrs = captureMatches(pattern: #"<a\b([^>]*)>"#, in: anchor).first ?? ""
            let text = captureMatches(pattern: #"<a\b[^>]*>(.*?)</a>"#, in: anchor).first ?? ""
            return (anchor, attributeValues(from: attrs), cleanTitle(text, fallback: ""))
        }
    }

    private static func attributeValues(from text: String) -> [String: String] {
        guard let regex = try? NSRegularExpression(
            pattern: #"\b([A-Za-z_:][-A-Za-z0-9_:.]*)\s*(?:=\s*(?:"([^"]*)"|'([^']*)'|([^\s>"']+)))?"#,
            options: [.caseInsensitive]
        ) else {
            return [:]
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        var values: [String: String] = [:]
        for match in regex.matches(in: text, range: range) {
            guard let nameRange = Range(match.range(at: 1), in: text) else { continue }
            let name = String(text[nameRange]).lowercased()
            var value = ""
            for group in 2...4 {
                guard let valueRange = Range(match.range(at: group), in: text) else { continue }
                value = decodeHTML(String(text[valueRange])).trimmed
                break
            }
            values[name] = value.isEmpty ? name : value
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

    private static func firstCapture(patterns: [String], in text: String) -> String? {
        for pattern in patterns {
            guard let value = captureMatches(pattern: pattern, in: text).first?.trimmed,
                  !value.isEmpty else { continue }
            return value
        }
        return nil
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
        let title = decodeHTML(stripTags(raw))
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmed
        return title.isEmpty ? fallback : title.sanitizedFilename(maxLength: 120)
    }

    private static func stripTags(_ text: String) -> String {
        text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
    }

    private static func decodeHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmed, !value.isEmpty else {
            return nil
        }
        return value
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
