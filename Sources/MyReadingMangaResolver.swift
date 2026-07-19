import Foundation

final class MyReadingMangaResolver {
    private struct ImageCandidateEntry {
        var location: Int
        var candidates: [String]
        var attributes: [String: String]
    }

    func canResolve(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(),
              Self.isSupportedHost(host),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return false
        }

        let parts = url.path.split(separator: "/").map(String.init)
        return !parts.isEmpty && !["tag", "category", "author", "page"].contains(parts.first?.lowercased() ?? "")
    }

    func resolve(_ url: URL, headers: HTTPRequestOptions = HTTPRequestOptions()) async throws -> ResolvedDownload {
        let html = try await HTTPClient.shared.string(from: url, referer: headers.referer, userAgent: headers.userAgent)
        return try Self.resolvedDownload(fromHTML: html, pageURL: url)
    }

    static func resolvedDownload(fromHTML html: String, pageURL: URL) throws -> ResolvedDownload {
        let title = pageTitle(fromHTML: html, pageURL: pageURL)
        let imageURLs = imageURLs(fromHTML: html, pageURL: pageURL)
        guard !imageURLs.isEmpty else {
            if isCloudflareProtectionPage(html) {
                throw NativeDownloadError.unsupported("MyReadingManga returned a Cloudflare protection page. Open the page in a browser or import browser cookies, then retry.")
            }
            throw NativeDownloadError.noFiles
        }

        let metadata = pageMetadata(fromHTML: html, pageURL: pageURL, title: title, imageCount: imageURLs.count)
        let assets = imageURLs.enumerated().map { offset, remote in
            ResolvedAsset(
                remoteURL: remote,
                filename: filename(for: remote, index: offset + 1),
                metadata: assetMetadata(for: remote, pageMetadata: metadata, pageURL: pageURL, index: offset + 1),
                referer: pageURL.absoluteString
            )
        }

        return ResolvedDownload(
            title: title,
            folderName: "MyReadingManga \(title)".sanitizedFilename(maxLength: 120),
            assets: assets,
            metadata: metadata
        )
    }

    static func imageURLs(fromHTML html: String, pageURL: URL) -> [URL] {
        let body = primaryContentHTML(from: html)
        let entries = (linkedImageCandidateEntries(fromHTML: body) + imageTagCandidateEntries(fromHTML: body) + rawImageCandidateEntries(fromHTML: body))
            .sorted { $0.location < $1.location }
        var urls: [URL] = []
        var seen = Set<String>()
        for entry in entries {
            for candidate in entry.candidates {
                guard let remote = absoluteURL(candidate, baseURL: pageURL),
                      isContentImage(remote, attributes: entry.attributes) else {
                    continue
                }

                let normalized = contentImageIdentity(for: remote)
                guard !seen.contains(normalized) else { continue }
                seen.insert(normalized)
                urls.append(remote)
                break
            }
        }

        return urls
    }

    private static func imageTagCandidateEntries(fromHTML html: String) -> [ImageCandidateEntry] {
        guard let regex = try? NSRegularExpression(
            pattern: #"<(?:img|source)\b([^>]*)>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return []
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        return regex.matches(in: html, range: range).compactMap { match in
            guard let attributesRange = Range(match.range(at: 1), in: html) else { return nil }
            let attributes = attributeValues(from: String(html[attributesRange]))
            let candidates = imageCandidates(from: attributes)
            guard !candidates.isEmpty else { return nil }
            return ImageCandidateEntry(location: match.range.location, candidates: candidates, attributes: attributes)
        }
    }

    private static func rawImageCandidateEntries(fromHTML html: String) -> [ImageCandidateEntry] {
        let normalized = normalizeEscapedText(decodeHTML(html))
        let patterns = [
            #"(https?:\\?/\\?/[^"'\\\s<>]+\.(?:jpg|jpeg|png|gif|webp|avif)(?:\?[^"'\\\s<>]*)?)"#,
            #"((?://)[^"'\\\s<>]+\.(?:jpg|jpeg|png|gif|webp|avif)(?:\?[^"'\\\s<>]*)?)"#,
            #"((?:/|\.\./)[^"'\\\s<>]*/wp-content/uploads/[^"'\\\s<>]+\.(?:jpg|jpeg|png|gif|webp|avif)(?:\?[^"'\\\s<>]*)?)"#
        ]
        var entries: [ImageCandidateEntry] = []
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
            for match in regex.matches(in: normalized, range: range) {
                guard let valueRange = Range(match.range(at: 1), in: normalized) else { continue }
                let value = String(normalized[valueRange])
                var candidates: [String] = []
                appendCandidate(value, to: &candidates, preferWordPressOriginal: true)
                guard !candidates.isEmpty else { continue }
                entries.append(ImageCandidateEntry(location: match.range.location, candidates: candidates, attributes: [:]))
            }
        }
        return entries
    }

    private static func linkedImageCandidateEntries(fromHTML html: String) -> [ImageCandidateEntry] {
        guard let regex = try? NSRegularExpression(
            pattern: #"<a\b([^>]*)>(.*?)</a>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return []
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        return regex.matches(in: html, range: range).compactMap { match in
            guard let attributesRange = Range(match.range(at: 1), in: html),
                  let bodyRange = Range(match.range(at: 2), in: html) else {
                return nil
            }
            var attributes = attributeValues(from: String(html[attributesRange]))
            let anchorBody = String(html[bodyRange])
            guard anchorBody.range(of: #"<(?:img|picture|source)\b"#, options: [.regularExpression, .caseInsensitive]) != nil,
                  let href = attributes["href"]?.trimmed,
                  !href.isEmpty else {
                return nil
            }

            if let imageAttributes = firstImageAttributes(fromHTML: anchorBody) {
                for (key, value) in imageAttributes where attributes[key] == nil {
                    attributes[key] = value
                }
            }

            var candidates: [String] = []
            appendCandidate(href, to: &candidates, preferWordPressOriginal: true)
            return ImageCandidateEntry(location: match.range.location, candidates: candidates, attributes: attributes)
        }
    }

    private static func firstImageAttributes(fromHTML html: String) -> [String: String]? {
        guard let regex = try? NSRegularExpression(
            pattern: #"<(?:img|source)\b([^>]*)>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return nil
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, range: range),
              let attributesRange = Range(match.range(at: 1), in: html) else {
            return nil
        }
        return attributeValues(from: String(html[attributesRange]))
    }

    private static func imageCandidates(from attributes: [String: String]) -> [String] {
        var candidates: [String] = []

        for key in [
            "data-orig-file",
            "data-full-url",
            "data-large-file",
            "data-large_image",
            "data-large-image",
            "data-full",
            "data-src-full",
            "data-hires",
            "data-original-src"
        ] {
            if let value = attributes[key]?.trimmed, !value.isEmpty {
                appendCandidate(value, to: &candidates, preferWordPressOriginal: true)
            }
        }

        for key in [
            "data-original-srcset",
            "data-lazyload-srcset",
            "data-lazy-srcset",
            "data-srcset",
            "srcset"
        ] {
            if let value = attributes[key]?.trimmed, !value.isEmpty,
               let best = bestSrcsetCandidate(value) {
                appendCandidate(best, to: &candidates, preferWordPressOriginal: true)
            }
        }

        for key in [
            "data-cfsrc",
            "data-cf-src",
            "data-lazy-src",
            "data-lazyload",
            "data-lazy",
            "data-src",
            "data-original",
            "data-lazy-original",
            "data-echo",
            "data-echo-src",
            "data-ks-lazyload",
            "data-image",
            "data-image-src",
            "data-img-url",
            "data-jpibfi-src",
            "src"
        ] {
            if let value = attributes[key]?.trimmed, !value.isEmpty {
                appendCandidate(value, to: &candidates, preferWordPressOriginal: true)
            }
        }

        return candidates
    }

    private static func appendCandidate(_ value: String, to candidates: inout [String], preferWordPressOriginal: Bool = false) {
        if preferWordPressOriginal,
           let original = wordpressOriginalImageCandidate(from: value) {
            appendUnique(original, to: &candidates)
        }
        appendUnique(value, to: &candidates)
    }

    private static func appendUnique(_ value: String, to candidates: inout [String]) {
        let trimmed = value.trimmed
        guard !trimmed.isEmpty, !candidates.contains(trimmed) else { return }
        candidates.append(trimmed)
    }

    private static func wordpressOriginalImageCandidate(from raw: String) -> String? {
        let value = raw.trimmed
        guard value.lowercased().contains("/wp-content/uploads/"),
              let regex = try? NSRegularExpression(
                pattern: #"^(.*?/wp-content/uploads/.*)-[0-9]{2,5}x[0-9]{2,5}(\.(?:jpe?g|png|gif|webp))(.*)$"#,
                options: [.caseInsensitive]
              ) else {
            return nil
        }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        guard let match = regex.firstMatch(in: value, range: range),
              let prefixRange = Range(match.range(at: 1), in: value),
              let extRange = Range(match.range(at: 2), in: value),
              let suffixRange = Range(match.range(at: 3), in: value) else {
            return nil
        }
        return "\(value[prefixRange])\(value[extRange])\(value[suffixRange])"
    }

    private static func contentImageIdentity(for url: URL) -> String {
        let normalized = URLIdentity.normalize(url.absoluteString)
        guard normalized.lowercased().contains("/wp-content/uploads/"),
              let regex = try? NSRegularExpression(
                pattern: #"^(.*?/wp-content/uploads/.*?)(?:-[0-9]{2,5}x[0-9]{2,5})?\.(?:jpe?g|png|gif|webp|avif)(?:[?#].*)?$"#,
                options: [.caseInsensitive]
              ) else {
            return normalized
        }
        let range = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
        guard let match = regex.firstMatch(in: normalized, range: range),
              let prefixRange = Range(match.range(at: 1), in: normalized) else {
            return normalized
        }
        return String(normalized[prefixRange])
    }

    private static func bestSrcsetCandidate(_ srcset: String) -> String? {
        let entries = srcset
            .components(separatedBy: ",")
            .compactMap { part -> (url: String, score: Int)? in
                let pieces = part.trimmed.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
                guard let url = pieces.first, !url.isEmpty else { return nil }
                let descriptor = pieces.dropFirst().first ?? ""
                let score: Int
                if descriptor.hasSuffix("w") {
                    score = Int(descriptor.dropLast()) ?? 0
                } else if descriptor.hasSuffix("x") {
                    let scale = Double(descriptor.dropLast()) ?? 1
                    score = Int(scale * 10_000)
                } else {
                    score = 0
                }
                return (url, score)
            }

        return entries.max { $0.score < $1.score }?.url
    }

    private static func primaryContentHTML(from html: String) -> String {
        let patterns = [
            #"<div\b[^>]*\bclass\s*=\s*["'][^"']*(?:entry-content|post-content|the-content)[^"']*["'][^>]*>(.*?)<div\b[^>]*\bclass\s*=\s*["'][^"']*(?:sharedaddy|post-navigation|yarpp|comments)[^"']*["']"#,
            #"<div\b[^>]*\bclass\s*=\s*["'][^"']*(?:entry-content|post-content|the-content)[^"']*["'][^>]*>(.*?)</article>"#,
            #"<article\b[^>]*>(.*?)</article>"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
                continue
            }
            let range = NSRange(html.startIndex..<html.endIndex, in: html)
            if let match = regex.firstMatch(in: html, range: range),
               let capture = Range(match.range(at: 1), in: html) {
                return String(html[capture])
            }
        }

        return html
    }

    private static func pageTitle(fromHTML html: String, pageURL: URL) -> String {
        let title = elementText(pattern: #"<h1\b[^>]*\bclass\s*=\s*["'][^"']*entry-title[^"']*["'][^>]*>(.*?)</h1>"#, in: html) ??
            metaContent(from: html, names: ["og:title", "twitter:title"]) ??
            titleTag(fromHTML: html) ??
            pageURL.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "-", with: " ")
        return cleanTitle(title)
    }

    private static func pageMetadata(fromHTML html: String, pageURL: URL, title: String, imageCount: Int) -> [String: String] {
        let tags = taxonomyLinks(fromHTML: html, marker: "tag")
        let categories = taxonomyLinks(fromHTML: html, marker: "category")
        let author = authorName(fromHTML: html) ?? ""
        let tagText = tags.joined(separator: ", ")
        let categoryText = categories.joined(separator: ", ")
        let language = languageName(from: tags + categories)
        let slug = pageURL.deletingPathExtension().lastPathComponent
        let date = publishedDate(fromHTML: html) ?? ""

        return DownloadMetadata.clean([
            "id": slug,
            "gallery_id": slug,
            "post_id": slug,
            "media_id": slug,
            "artist": author,
            "author": author,
            "creator": author,
            "uploader": author,
            "channel": author,
            "language": language,
            "category": categoryText,
            "tag": tagText,
            "tags": tagText,
            "slug": slug,
            "date": date,
            "published_date": date,
            "site": "MyReadingManga",
            "title": title,
            "series": title,
            "type": "post",
            "media_type": "image",
            "media_count": String(imageCount),
            "image_count": String(imageCount),
            "source_url": pageURL.absoluteString,
            "page_url": pageURL.absoluteString
        ])
    }

    private static func filename(for url: URL, index: Int) -> String {
        let ext = mediaFormat(for: url)
        return String(format: "%04d.%@", index, ext).sanitizedFilename(maxLength: 180)
    }

    private static func assetMetadata(for url: URL, pageMetadata: [String: String], pageURL: URL, index: Int) -> [String: String] {
        let format = mediaFormat(for: url)
        let postID = pageMetadata["post_id"] ?? ""
        return DownloadMetadata.clean([
            "id": pageMetadata["id"] ?? "",
            "gallery_id": pageMetadata["gallery_id"] ?? "",
            "post_id": postID,
            "media_id": postID.isEmpty ? String(index) : "\(postID)-\(index)",
            "artist": pageMetadata["artist"] ?? "",
            "author": pageMetadata["author"] ?? "",
            "creator": pageMetadata["creator"] ?? "",
            "uploader": pageMetadata["uploader"] ?? "",
            "channel": pageMetadata["channel"] ?? "",
            "language": pageMetadata["language"] ?? "",
            "category": pageMetadata["category"] ?? "",
            "tag": pageMetadata["tag"] ?? "",
            "tags": pageMetadata["tags"] ?? "",
            "slug": pageMetadata["slug"] ?? "",
            "date": pageMetadata["date"] ?? "",
            "published_date": pageMetadata["published_date"] ?? "",
            "site": "MyReadingManga",
            "title": pageMetadata["title"] ?? "",
            "series": pageMetadata["series"] ?? pageMetadata["title"] ?? "",
            "type": "image",
            "media_type": "image",
            "page": String(index),
            "position": String(index),
            "format": format,
            "media_format": format,
            "image_url": url.absoluteString,
            "media_url": url.absoluteString,
            "source_url": url.absoluteString,
            "page_url": pageURL.absoluteString
        ])
    }

    private static func mediaFormat(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        if ext == "jpeg" || ext == "bmp" {
            return "jpg"
        }
        return ext.isEmpty ? "jpg" : ext
    }

    private static func taxonomyLinks(fromHTML html: String, marker: String) -> [String] {
        uniqueStrings(anchorTexts(fromHTML: html).compactMap { anchor in
            let href = anchor.attributes["href"]?.lowercased() ?? ""
            guard href.contains("/\(marker)/") || href.contains("/\(marker)s/") else {
                return nil
            }
            return anchor.text
        })
    }

    private static func authorName(fromHTML html: String) -> String? {
        if let author = metaContent(from: html, names: ["author"]), !author.isEmpty {
            return cleanTitle(author)
        }

        for anchor in anchorTexts(fromHTML: html) {
            let rel = anchor.attributes["rel"]?.lowercased() ?? ""
            let href = anchor.attributes["href"]?.lowercased() ?? ""
            if rel.contains("author") || href.contains("/author/") {
                return anchor.text
            }
        }
        return nil
    }

    private static func languageName(from values: [String]) -> String {
        let aliases = [
            "english",
            "japanese",
            "korean",
            "chinese",
            "spanish",
            "french",
            "german",
            "translated"
        ]
        return values.first { value in
            aliases.contains(value.lowercased())
        } ?? ""
    }

    private static func publishedDate(fromHTML html: String) -> String? {
        let raw = metaContent(
            from: html,
            names: ["article:published_time", "datepublished", "date", "pubdate", "publishdate"]
        ) ?? firstTimeDateTime(fromHTML: html)
        return normalizedDate(raw)
    }

    private static func firstTimeDateTime(fromHTML html: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"<time\b([^>]*)>"#, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        for match in regex.matches(in: html, range: range) {
            guard let attributesRange = Range(match.range(at: 1), in: html) else { continue }
            let values = attributeValues(from: String(html[attributesRange]))
            if let datetime = values["datetime"]?.trimmed, !datetime.isEmpty {
                return datetime
            }
        }
        return nil
    }

    private static func normalizedDate(_ raw: String?) -> String? {
        guard let value = raw?.trimmed, !value.isEmpty else { return nil }
        if let match = value.range(of: #"[0-9]{4}-[0-9]{2}-[0-9]{2}"#, options: .regularExpression) {
            return String(value[match])
        }
        if value.range(of: #"^[0-9]{8}$"#, options: .regularExpression) != nil {
            let monthStart = value.index(value.startIndex, offsetBy: 4)
            let dayStart = value.index(value.startIndex, offsetBy: 6)
            return "\(value.prefix(4))-\(value[monthStart..<dayStart])-\(value[dayStart..<value.endIndex])"
        }
        return nil
    }

    private static func anchorTexts(fromHTML html: String) -> [(attributes: [String: String], text: String)] {
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
            let text = cleanTitle(String(html[textRange]))
            guard !text.isEmpty else { return nil }
            return (attributeValues(from: String(html[attributesRange])), text)
        }
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

    private static func isContentImage(_ url: URL, attributes: [String: String]) -> Bool {
        let absolute = url.absoluteString.lowercased()
        let ext = url.pathExtension.lowercased()
        guard ["jpg", "jpeg", "png", "gif", "webp", "avif"].contains(ext) else {
            return false
        }

        if absolute.contains("wp-content/uploads/") {
            return false
        }

        if absolute.contains("gravatar.com") ||
            absolute.contains("/avatar") ||
            absolute.contains("/logo") ||
            absolute.contains("/icon") ||
            absolute.contains("/banner") {
            return false
        }

        let classText = (attributes["class"] ?? "").lowercased()
        let altText = (attributes["alt"] ?? "").lowercased()
        if classText.contains("avatar") ||
            classText.contains("logo") ||
            classText.contains("emoji") ||
            altText.contains("avatar") ||
            altText.contains("logo") {
            return false
        }

        let filename = url.deletingPathExtension().lastPathComponent.lowercased()
        if filename.range(of: #"-[0-9]{2,5}x[0-9]{2,5}$"#, options: .regularExpression) != nil {
            return false
        }

        return true
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

    private static func absoluteURL(_ raw: String, baseURL: URL) -> URL? {
        let value = raw.trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "\"'(),;"))
        guard !value.isEmpty,
              !value.lowercased().hasPrefix("data:"),
              !value.lowercased().hasPrefix("blob:"),
              !value.lowercased().hasPrefix("javascript:") else {
            return nil
        }

        if value.hasPrefix("//") {
            return URL(string: "\(baseURL.scheme ?? "https"):\(value)")
        }
        return URL(string: value, relativeTo: baseURL)?.absoluteURL
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

    private static func cleanTitle(_ raw: String) -> String {
        var title = decodeHTML(stripTags(raw))
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmed
        for suffix in [" - MyReadingManga", " | MyReadingManga", " – MyReadingManga"] {
            if title.lowercased().hasSuffix(suffix.lowercased()) {
                title.removeLast(suffix.count)
                title = title.trimmed
            }
        }
        return title.isEmpty ? "MyReadingManga" : title.sanitizedFilename(maxLength: 120)
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

        guard let numericRegex = try? NSRegularExpression(pattern: #"&#(x?[0-9A-Fa-f]+);"#) else {
            return output
        }
        let matches = numericRegex.matches(in: output, range: NSRange(output.startIndex..<output.endIndex, in: output)).reversed()
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

    private static func normalizeEscapedText(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"\/"#, with: "/")
            .replacingOccurrences(of: #"\\/"#, with: "/")
            .replacingOccurrences(of: #"\\u002F"#, with: "/", options: .caseInsensitive)
            .replacingOccurrences(of: #"\u002F"#, with: "/", options: .caseInsensitive)
            .replacingOccurrences(of: #"\\u0026"#, with: "&", options: .caseInsensitive)
            .replacingOccurrences(of: #"\u0026"#, with: "&", options: .caseInsensitive)
    }

    private static func isCloudflareProtectionPage(_ html: String) -> Bool {
        let lowered = html.lowercased()
        let markers = [
            "cf-browser-verification",
            "cf-challenge",
            "cf_chl_",
            "challenge-platform",
            "cloudflare ray id",
            "checking your browser",
            "verify you are human",
            "attention required! | cloudflare",
            "/cdn-cgi/challenge-platform/",
            "__cf_chl_"
        ]
        return markers.contains { lowered.contains($0) }
    }

    private static func isSupportedHost(_ host: String) -> Bool {
        host == "myreadingmanga.info" ||
            host == "www.myreadingmanga.info" ||
            host == "myreadingmanga.test" ||
            host == "www.myreadingmanga.test"
    }
}
