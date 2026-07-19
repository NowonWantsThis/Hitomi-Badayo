import Foundation

final class AsmHentaiResolver {
    private let maxGalleryPages = 1000

    func canResolve(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(),
              Self.isSupportedHost(host),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return false
        }
        return Self.galleryID(from: url) != nil
    }

    func resolve(_ url: URL, headers: HTTPRequestOptions = HTTPRequestOptions()) async throws -> ResolvedDownload {
        let sourceURL = Self.galleryID(from: url).flatMap { Self.canonicalGalleryURL(for: $0, sourceURL: Optional(url)) } ?? url
        let html = try await HTTPClient.shared.string(from: sourceURL, referer: headers.referer, userAgent: headers.userAgent)
        if let id = Self.galleryID(from: sourceURL),
           let pageCount = Self.totalPageCount(fromHTML: html),
           pageCount > 0 {
            var pages: [(pageURL: URL, html: String)] = []
            for page in 1...min(pageCount, maxGalleryPages) {
                let pageURL = Self.galleryImagePageURL(for: id, page: page, sourceURL: sourceURL)
                let pageHTML = try await HTTPClient.shared.string(from: pageURL, referer: sourceURL.absoluteString, userAgent: headers.userAgent)
                pages.append((pageURL, pageHTML))
            }
            if let resolved = try? Self.resolvedDownload(
                fromHTMLPages: pages,
                galleryHTML: html,
                pageURL: sourceURL,
                userAgent: headers.userAgent
            ) {
                return resolved
            }
        }

        return try Self.resolvedDownload(
            fromHTML: html,
            pageURL: sourceURL,
            userAgent: headers.userAgent
        )
    }

    static func resolvedDownload(
        fromHTML html: String,
        pageURL: URL,
        userAgent: String? = nil
    ) throws -> ResolvedDownload {
        let galleryID = galleryID(from: pageURL) ?? "gallery"
        let sourceURL = canonicalGalleryURL(for: galleryID, sourceURL: Optional(pageURL)) ?? pageURL
        let title = galleryTitle(fromHTML: html, pageURL: pageURL)
        let images = imageURLs(fromHTML: html, baseURL: sourceURL)
        guard !images.isEmpty else {
            throw NativeDownloadError.noFiles
        }

        let info = galleryInfo(fromHTML: html)
        let assets = images.enumerated().map { offset, remote in
            asset(
                for: remote,
                index: offset + 1,
                referer: sourceURL.absoluteString,
                metadata: assetMetadata(for: remote, galleryID: galleryID, title: title, info: info, pageURL: sourceURL, index: offset + 1),
                userAgent: userAgent
            )
        }

        let folderTitle: String
        if let artist = info["artist"], !artist.isEmpty {
            folderTitle = "\(artist) - \(title)"
        } else {
            folderTitle = title
        }

        return ResolvedDownload(
            title: "\(title) (asmhentai_\(galleryID))".sanitizedFilename(maxLength: 120),
            folderName: "AsmHentai \(folderTitle)".sanitizedFilename(maxLength: 120),
            assets: assets,
            metadata: galleryMetadata(
                title: title,
                galleryID: galleryID,
                info: info,
                pageCount: totalPageCount(fromHTML: html),
                assetCount: assets.count,
                pageURL: sourceURL
            )
        )
    }

    static func resolvedDownload(
        fromHTMLPages pages: [(pageURL: URL, html: String)],
        galleryHTML: String,
        pageURL: URL,
        userAgent: String? = nil
    ) throws -> ResolvedDownload {
        let galleryID = galleryID(from: pageURL) ?? "gallery"
        let sourceURL = canonicalGalleryURL(for: galleryID, sourceURL: Optional(pageURL)) ?? pageURL
        let title = galleryTitle(fromHTML: galleryHTML, pageURL: pageURL)
        let info = galleryInfo(fromHTML: galleryHTML)
        var assets: [ResolvedAsset] = []
        var seen = Set<String>()

        for page in pages {
            for remote in imageURLs(fromHTML: page.html, baseURL: page.pageURL) {
                let normalized = URLIdentity.normalize(remote.absoluteString)
                guard !seen.contains(normalized) else { continue }
                seen.insert(normalized)
                assets.append(asset(
                    for: remote,
                    index: assets.count + 1,
                    referer: page.pageURL.absoluteString,
                    metadata: assetMetadata(for: remote, galleryID: galleryID, title: title, info: info, pageURL: page.pageURL, index: assets.count + 1),
                    userAgent: userAgent
                ))
            }
        }

        guard !assets.isEmpty else {
            throw NativeDownloadError.noFiles
        }

        let folderTitle: String
        if let artist = info["artist"], !artist.isEmpty {
            folderTitle = "\(artist) - \(title)"
        } else {
            folderTitle = title
        }

        return ResolvedDownload(
            title: "\(title) (asmhentai_\(galleryID))".sanitizedFilename(maxLength: 120),
            folderName: "AsmHentai \(folderTitle)".sanitizedFilename(maxLength: 120),
            assets: assets,
            metadata: galleryMetadata(
                title: title,
                galleryID: galleryID,
                info: info,
                pageCount: pages.count,
                assetCount: assets.count,
                pageURL: sourceURL
            )
        )
    }

    static func galleryID(from url: URL) -> String? {
        let parts = pathParts(from: url)
        for marker in ["g", "gallery"] {
            guard let index = parts.firstIndex(where: { $0.lowercased() == marker }),
                  index + 1 < parts.count else {
                continue
            }
            let id = parts[index + 1].trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
            if !id.isEmpty, id.range(of: #"^[0-9]+$"#, options: .regularExpression) != nil {
                return id
            }
        }
        return nil
    }

    static func canonicalGalleryURL(for id: String, sourceURL: URL) -> URL {
        canonicalGalleryURL(for: id, sourceURL: Optional(sourceURL))!
    }

    static func canonicalGalleryURL(for id: String, sourceURL: URL? = nil) -> URL? {
        guard id.range(of: #"^[0-9]+$"#, options: .regularExpression) != nil else {
            return nil
        }
        var components = URLComponents()
        components.scheme = sourceURL?.scheme ?? "https"
        components.host = sourceURL?.host?.lowercased().hasSuffix(".test") == true ? "asmhentai.test" : "asmhentai.com"
        components.path = "/gallery/\(id)"
        return components.url
    }

    static func galleryImagePageURL(for id: String, page: Int, sourceURL: URL) -> URL {
        var components = URLComponents()
        components.scheme = sourceURL.scheme ?? "https"
        components.host = sourceURL.host?.lowercased().hasSuffix(".test") == true ? "asmhentai.test" : "asmhentai.com"
        components.path = "/gallery/\(id)/\(max(1, page))"
        return components.url!
    }

    static func totalPageCount(fromHTML html: String) -> Int? {
        for attrs in tagAttributes(tag: "input", html: html) {
            let values = attributeValues(from: attrs)
            guard values["name"]?.lowercased() == "t_pages",
                  let value = values["value"]?.trimmed,
                  let count = Int(value),
                  count > 0 else {
                continue
            }
            return count
        }
        return nil
    }

    static func galleryTitle(fromHTML html: String, pageURL: URL) -> String {
        let title = elementText(pattern: #"<h1\b[^>]*>(.*?)</h1>"#, in: html) ??
            metaContent(from: html, names: ["og:title", "twitter:title"]) ??
            titleTag(fromHTML: html) ??
            galleryID(from: pageURL) ??
            "AsmHentai Gallery"
        return cleanTitle(title, fallback: "AsmHentai \(galleryID(from: pageURL) ?? "gallery")")
    }

    static func galleryInfo(fromHTML html: String) -> [String: String] {
        let labels = [
            "artist": ["artist", "artists", "group", "groups", "circle"],
            "language": ["language", "lang"],
            "parody": ["parody", "series"],
            "category": ["category", "type"]
        ]

        var info: [String: String] = [:]
        for attrs in tagAttributes(tag: "span", html: html) {
            let values = attributeValues(from: attrs)
            guard let className = values["class"]?.lowercased() else { continue }
            for (key, aliases) in labels where aliases.contains(where: { className.contains($0) }) {
                let fullTag = tagWithAttributes(tag: "span", attributes: attrs, html: html) ?? ""
                let text = cleanTitle(fullTag, fallback: "")
                if !text.isEmpty, info[key] == nil {
                    info[key] = text
                }
            }
        }

        for attrs in tagAttributes(tag: "a", html: html) {
            let values = attributeValues(from: attrs)
            let href = values["href"]?.lowercased() ?? ""
            for (key, aliases) in labels where aliases.contains(where: { href.contains("/\($0)/") || href.contains("\($0)=") }) {
                let fullTag = tagWithAttributes(tag: "a", attributes: attrs, html: html) ?? ""
                let text = cleanTitle(fullTag, fallback: "")
                if !text.isEmpty, info[key] == nil {
                    info[key] = text
                }
            }
        }
        return info
    }

    static func imageURLs(fromHTML html: String, baseURL: URL) -> [URL] {
        var results: [URL] = []
        var seen = Set<String>()

        func append(_ raw: String?) {
            guard let raw,
                  let remote = absoluteURL(raw, baseURL: baseURL),
                  isLikelyImage(remote) else {
                return
            }
            let normalized = URLIdentity.normalize(remote.absoluteString)
            guard !seen.contains(normalized) else { return }
            seen.insert(normalized)
            results.append(remote)
        }

        for attrs in tagAttributes(tag: "img", html: html) {
            let values = attributeValues(from: attrs)
            let className = values["class"]?.lowercased() ?? ""
            guard className.contains("fimg") || hasDedicatedImageAttribute(values) else {
                continue
            }
            for candidate in imageCandidateValues(from: values) {
                append(candidate)
            }
        }

        for attrs in tagAttributes(tag: "source", html: html) {
            let values = attributeValues(from: attrs)
            guard hasDedicatedImageAttribute(values) else {
                continue
            }
            for candidate in imageCandidateValues(from: values) {
                append(candidate)
            }
        }
        return results
    }

    private static func imageCandidateValues(from values: [String: String]) -> [String] {
        for key in preferredImageAttributeNames {
            if let value = values[key]?.trimmed, !value.isEmpty {
                return [value]
            }
        }

        for key in srcsetImageAttributeNames {
            if let srcset = values[key]?.trimmed,
               let best = bestSrcsetCandidate(srcset) {
                return [best]
            }
        }

        if let value = values["src"]?.trimmed, !value.isEmpty {
            return [value]
        }
        return []
    }

    private static func hasDedicatedImageAttribute(_ values: [String: String]) -> Bool {
        preferredImageAttributeNames.contains { values[$0]?.trimmed.isEmpty == false } ||
            srcsetImageAttributeNames.contains { values[$0]?.trimmed.isEmpty == false }
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
                return (url, Int((Double(descriptor.dropLast()) ?? 1) * 10_000))
            }
            return (url, 0)
        }
        return entries.max { $0.score < $1.score }?.url
    }

    private static let preferredImageAttributeNames = [
        "data-full",
        "data-full-url",
        "data-original",
        "data-src",
        "data-lazy-src",
        "data-lazyload-src",
        "data-url",
        "data-image",
        "data-image-url"
    ]

    private static let srcsetImageAttributeNames = [
        "data-srcset",
        "data-lazy-srcset",
        "srcset"
    ]

    static func asset(
        for url: URL,
        index: Int,
        referer: String,
        metadata: [String: String] = [:],
        userAgent: String? = nil
    ) -> ResolvedAsset {
        let basename = url.deletingPathExtension().lastPathComponent
        let ext = mediaFormat(for: url)
        let namePart = basename.isEmpty ? String(format: "%04d", index) : basename
        let filename = "\(String(format: "%04d", index))-\(namePart).\(ext)".sanitizedFilename(maxLength: 180)
        return ResolvedAsset(
            remoteURL: url,
            filename: filename,
            metadata: metadata,
            referer: referer,
            userAgent: userAgent
        )
    }

    static func galleryMetadata(title: String, galleryID: String, info: [String: String], pageCount: Int?, assetCount: Int, pageURL: URL) -> [String: String] {
        DownloadMetadata.clean([
            "artist": info["artist"] ?? "",
            "author": info["artist"] ?? "",
            "creator": info["artist"] ?? "",
            "language": info["language"] ?? "",
            "parody": info["parody"] ?? "",
            "series": info["parody"] ?? title,
            "category": info["category"] ?? "",
            "page_count": pageCount.map(String.init) ?? "",
            "gallery_id": galleryID,
            "id": galleryID,
            "slug": galleryID,
            "site": "AsmHentai",
            "title": title,
            "type": "gallery",
            "media_type": "image",
            "media_count": String(assetCount),
            "image_count": String(assetCount),
            "url": pageURL.absoluteString,
            "source_url": pageURL.absoluteString,
            "page_url": pageURL.absoluteString
        ])
    }

    static func assetMetadata(for url: URL, galleryID: String, title: String, info: [String: String], pageURL: URL, index: Int) -> [String: String] {
        let format = mediaFormat(for: url)
        return DownloadMetadata.clean([
            "artist": info["artist"] ?? "",
            "author": info["artist"] ?? "",
            "creator": info["artist"] ?? "",
            "language": info["language"] ?? "",
            "parody": info["parody"] ?? "",
            "series": info["parody"] ?? title,
            "category": info["category"] ?? "",
            "gallery_id": galleryID,
            "id": galleryID,
            "media_id": "\(galleryID)-\(index)",
            "page": String(index),
            "position": String(index),
            "slug": galleryID,
            "site": "AsmHentai",
            "title": title,
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

    private static func tagWithAttributes(tag: String, attributes: String, html: String) -> String? {
        let escapedTag = NSRegularExpression.escapedPattern(for: tag)
        let escapedAttrs = NSRegularExpression.escapedPattern(for: attributes)
        guard let regex = try? NSRegularExpression(
            pattern: #"<\#(escapedTag)\b\#(escapedAttrs)>(.*?)</\#(escapedTag)>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return nil
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, range: range),
              let capture = Range(match.range(at: 1), in: html) else {
            return nil
        }
        return String(html[capture])
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
        guard ext != "svg", !path.contains("placeholder"), !path.contains("loading") else {
            return false
        }
        return ["jpg", "jpeg", "png", "webp", "gif", "avif"].contains(ext) ||
            (url.host?.lowercased().contains("asmhentai") ?? false)
    }

    private static func pathParts(from url: URL) -> [String] {
        url.path.split(separator: "/").map { String($0).removingPercentEncoding ?? String($0) }
    }

    private static func cleanTitle(_ raw: String, fallback: String) -> String {
        var title = decodeHTML(stripTags(raw))
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmed
        for suffix in [" - AsmHentai", " | AsmHentai", " - asmhentai.com", " | asmhentai.com"] {
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
        host == "asmhentai.com" ||
            host == "www.asmhentai.com" ||
            host == "asmhentai.test" ||
            host == "www.asmhentai.test"
    }
}
