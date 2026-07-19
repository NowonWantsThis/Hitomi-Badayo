// Developed with reference to SaidBySolo's MIT-licensed extractor.
// See LICENSES/saidbysolo-MIT.txt in the source distribution.
import Foundation

final class NaverPostResolver {
    func canResolve(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(),
              Self.isNaverPostHost(host),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return false
        }

        return Self.isViewerURL(url) || Self.isCollectionURL(url)
    }

    func resolve(_ url: URL, headers: HTTPRequestOptions = HTTPRequestOptions()) async throws -> ResolvedDownload {
        let html = try await HTTPClient.shared.string(from: url, referer: headers.referer, userAgent: headers.userAgent)
        if Self.isViewerURL(url) {
            return try Self.resolvedPostDownload(fromHTML: html, pageURL: url)
        }

        var postURLs: [URL] = []
        let asyncURLs = Self.asyncListURLs(for: url, totalCount: Self.totalCount(fromHTML: html))
        let isSeries = url.path.lowercased().hasPrefix("/my/series")
        for pageURL in asyncURLs {
            try Task.checkCancellation()
            let pageHTML = try await HTTPClient.shared.string(from: pageURL, referer: url.absoluteString, userAgent: headers.userAgent)
            postURLs.append(contentsOf: Self.collectionPostPageURLs(fromHTML: pageHTML, baseURL: pageURL, isSeries: isSeries))
        }

        if postURLs.isEmpty {
            postURLs = Self.postPageURLs(fromHTML: html, baseURL: url).reversed()
        }
        postURLs = Self.uniqueURLs(postURLs)
        var assets: [ResolvedAsset] = []
        var seen = Set<String>()
        var resolvedPostCount = 0

        for (postOffset, postURL) in postURLs.enumerated() {
            try Task.checkCancellation()
            let postHTML = try await HTTPClient.shared.string(from: postURL, referer: url.absoluteString, userAgent: headers.userAgent)
            guard let resolved = try? Self.resolvedPostDownload(fromHTML: postHTML, pageURL: postURL) else { continue }
            resolvedPostCount += 1
            for asset in resolved.assets {
                let normalized = URLIdentity.normalize(asset.remoteURL.absoluteString)
                guard !seen.contains(normalized) else { continue }
                seen.insert(normalized)
                var metadata = asset.metadata
                metadata["post_index"] = String(postOffset + 1)
                metadata["collection_index"] = String(assets.count + 1)
                assets.append(ResolvedAsset(
                    remoteURL: asset.remoteURL,
                    filename: String(format: "%04d-%@", postOffset + 1, asset.filename).sanitizedFilename(maxLength: 180),
                    metadata: metadata,
                    referer: asset.referer ?? postURL.absoluteString
                ))
            }
        }

        guard !assets.isEmpty else {
            throw NativeDownloadError.noFiles
        }

        let title = Self.collectionTitle(fromHTML: html, pageURL: url)
        var metadata = Self.naverPostMetadata(author: title, pageURL: url, title: title, assets: assets, type: "collection")
        metadata["listed_page_count"] = String(asyncURLs.count)
        metadata["listed_post_count"] = String(postURLs.count)
        metadata["resolved_post_count"] = String(resolvedPostCount)
        metadata["resolved_media_count"] = String(assets.count)
        return ResolvedDownload(
            title: title,
            folderName: "Naver Post \(title)".sanitizedFilename(maxLength: 120),
            assets: assets,
            metadata: metadata
        )
    }

    static func resolvedPostDownload(fromHTML html: String, pageURL: URL) throws -> ResolvedDownload {
        let body = postBodyHTML(fromHTML: html) ?? html
        let imageURLs = extractImageURLs(fromHTML: body, pageURL: pageURL)
        guard !imageURLs.isEmpty else {
            throw NativeDownloadError.noFiles
        }

        let combinedHTML = html + "\n" + body
        let author = postAuthor(fromHTML: combinedHTML)
        let title = postTitle(fromHTML: combinedHTML, pageURL: pageURL).sanitizedFilename(maxLength: 120)
        let assets = imageURLs.enumerated().map { offset, remote in
            let index = offset + 1
            return ResolvedAsset(
                remoteURL: remote,
                filename: filename(for: remote, index: index),
                metadata: assetMetadata(for: remote, author: author, pageURL: pageURL, title: title, index: index),
                referer: pageURL.absoluteString
            )
        }

        return ResolvedDownload(
            title: title,
            folderName: "Naver Post \(title)".sanitizedFilename(maxLength: 120),
            assets: assets,
            metadata: naverPostMetadata(author: author, pageURL: pageURL, title: title, assets: assets, type: "post")
        )
    }

    static func extractImageURLs(fromHTML html: String, pageURL: URL) -> [URL] {
        let normalizedHTML = normalizeEscapes(html)
        var candidates = dataLinkImageCandidates(fromHTML: normalizedHTML)
        candidates.append(contentsOf: imageTagCandidates(fromHTML: normalizedHTML))
        candidates.append(contentsOf: scriptImageCandidates(fromHTML: normalizedHTML))

        var output: [URL] = []
        var seen = Set<String>()
        for candidate in candidates {
            guard let remote = absoluteURL(candidate, baseURL: pageURL),
                  isImageURL(remote) else {
                continue
            }

            let normalized = URLIdentity.normalize(remote.absoluteString)
            guard !seen.contains(normalized) else { continue }
            seen.insert(normalized)
            output.append(remote)
        }
        return output
    }

    static func postBodyHTML(fromHTML html: String) -> String? {
        let patterns = [
            #""html"\s*:\s*"((?:\\.|[^"\\])*)""#,
            #"\\"html\\"\s*:\s*\\"((?:\\\\.|\\.|[^"\\])*)\\""#,
            #""html"\s*:\s*(.+?)(?:\n|\s)\}"#
        ]

        for pattern in patterns {
            guard let raw = captureMatches(pattern: pattern, in: html).first?.trimmed, !raw.isEmpty else {
                continue
            }
            let decoded = decodeJSONStringFragment(raw)
            if !decoded.isEmpty {
                return normalizeEscapes(decoded)
            }
        }
        return nil
    }

    static func postPageURLs(fromHTML html: String, baseURL: URL) -> [URL] {
        var urls: [URL] = []
        for href in anchorHREFs(fromHTML: html) {
            guard let url = absoluteURL(href, baseURL: baseURL),
                  isViewerURL(url) else {
                continue
            }
            urls.append(canonicalViewerURL(url) ?? url)
        }
        return uniqueURLs(urls)
    }

    static func collectionPostPageURLs(fromHTML html: String, baseURL: URL, isSeries: Bool) -> [URL] {
        guard let regex = try? NSRegularExpression(
            pattern: #"<a\b([^>]*)>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return []
        }

        let requiredClass = isSeries ? "spot_post_area" : "link_end"
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        var urls: [URL] = []
        for match in regex.matches(in: html, range: range) {
            guard let attributesRange = Range(match.range(at: 1), in: html) else { continue }
            let values = attributeValues(from: String(html[attributesRange]))
            let classes = Set((values["class"] ?? "").lowercased().split(whereSeparator: \.isWhitespace).map(String.init))
            guard classes.contains(requiredClass),
                  let href = values["href"],
                  let url = absoluteURL(href, baseURL: baseURL),
                  isViewerURL(url) else {
                continue
            }
            urls.append(canonicalViewerURL(url) ?? url)
        }

        let scoped = uniqueURLs(urls)
        if !scoped.isEmpty {
            return scoped.reversed()
        }
        return postPageURLs(fromHTML: html, baseURL: baseURL).reversed()
    }

    static func asyncListURLs(for sourceURL: URL, totalCount: Int?) -> [URL] {
        guard isCollectionURL(sourceURL),
              let components = URLComponents(url: sourceURL, resolvingAgainstBaseURL: false),
              let memberNo = components.queryItems?.first(where: { $0.name == "memberNo" })?.value,
              !memberNo.isEmpty else {
            return []
        }

        let pageCount = originalListPageCount(totalCount: totalCount)
        var output: [URL] = []

        for page in 1...pageCount {
            guard var async = URLComponents(url: sourceURL, resolvingAgainstBaseURL: false) else { continue }
            async.host = apiHost(for: sourceURL.host)
            async.fragment = nil

            if sourceURL.path.lowercased().hasPrefix("/my/series"),
               let seriesNo = components.queryItems?.first(where: { $0.name == "seriesNo" })?.value,
               !seriesNo.isEmpty {
                async.path = "/my/series/detail/more.nhn"
                async.queryItems = [
                    URLQueryItem(name: "memberNo", value: memberNo),
                    URLQueryItem(name: "seriesNo", value: seriesNo),
                    URLQueryItem(name: "fromNo", value: String(page))
                ]
            } else {
                async.path = sourceURL.path.hasPrefix("/async") ? sourceURL.path : "/async" + sourceURL.path
                async.queryItems = [
                    URLQueryItem(name: "memberNo", value: memberNo),
                    URLQueryItem(name: "fromNo", value: String(page))
                ]
            }

            if let url = async.url {
                output.append(url)
            }
        }
        return output
    }

    static func originalListPageCount(totalCount: Int?) -> Int {
        let total = max(1, totalCount ?? 20)
        if total % 20 == 0 {
            return max(1, total / 20)
        }
        let rounded = (Double(total) / 20.0).rounded(.toNearestOrEven)
        return max(1, Int(rounded) + 1)
    }

    static func totalCount(fromHTML html: String) -> Int? {
        let normalized = decodeHTML(stripTags(html))
        let numbers = captureMatches(pattern: #"([0-9][0-9,]*)"#, in: normalized)
            .compactMap { Int($0.replacingOccurrences(of: ",", with: "")) }
        return numbers.max()
    }

    static func isViewerURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(), isNaverPostHost(host) else { return false }
        return url.path.lowercased().hasPrefix("/viewer")
    }

    static func isCollectionURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(), isNaverPostHost(host) else { return false }
        let path = url.path.lowercased()
        return path.hasPrefix("/my.nhn") || path.hasPrefix("/my/series")
    }

    static func canonicalInputURL(for url: URL) -> URL? {
        guard let host = url.host?.lowercased(),
              isNaverPostHost(host),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }

        if isViewerURL(url) {
            return canonicalViewerURL(url)
        }

        guard isCollectionURL(url),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        components.host = apiHost(for: url.host)
        components.fragment = nil
        return components.url
    }

    private static func dataLinkImageCandidates(fromHTML html: String) -> [String] {
        guard let tagRegex = try? NSRegularExpression(pattern: #"<a\b([^>]*)>"#, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }

        var candidates: [String] = []
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        for match in tagRegex.matches(in: html, range: range) {
            guard let attributesRange = Range(match.range(at: 1), in: html) else { continue }
            let values = attributeValues(from: String(html[attributesRange]))
            guard values["data-linktype"]?.lowercased() == "img",
                  let linkData = values["data-linkdata"] else {
                continue
            }
            guard let object = jsonObject(from: linkData),
                  boolValue(object["linkUse"]) != false,
                  let src = stringValue(object["src"])?.trimmed,
                  !src.isEmpty else {
                continue
            }
            candidates.append(src)
        }
        return candidates
    }

    private static func imageTagCandidates(fromHTML html: String) -> [String] {
        guard let tagRegex = try? NSRegularExpression(pattern: #"<img\b([^>]*)>"#, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }

        var candidates: [String] = []
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        for match in tagRegex.matches(in: html, range: range) {
            guard let attributesRange = Range(match.range(at: 1), in: html) else { continue }
            let values = attributeValues(from: String(html[attributesRange]))
            for key in ["data-lazy-src", "data-src", "data-original", "data-url", "src"] {
                if let value = values[key]?.trimmed, !value.isEmpty {
                    candidates.append(value)
                    break
                }
            }
        }
        return candidates
    }

    private static func scriptImageCandidates(fromHTML html: String) -> [String] {
        let patterns = [
            #""src"\s*:\s*"([^"]+\.(?:jpg|jpeg|png|gif|webp)(?:\?[^"]*)?)""#,
            #"'src'\s*:\s*'([^']+\.(?:jpg|jpeg|png|gif|webp)(?:\?[^']*)?)'"#
        ]
        return patterns.flatMap { captureMatches(pattern: $0, in: html) }
    }

    private static func postTitle(fromHTML html: String, pageURL: URL) -> String {
        let title: String
        if let textareaTitle = textForClass("se_textarea", tag: "h3", in: html) {
            title = textareaTitle.replacingOccurrences(of: " ", with: "")
        } else {
            title = metaContent(from: html, names: ["og:title", "twitter:title"]) ??
                titleTag(fromHTML: html) ??
                fallbackTitle(from: pageURL)
        }
        let author = postAuthor(fromHTML: html)
        return cleanTitle(title, author: author, fallback: fallbackTitle(from: pageURL))
    }

    private static func postAuthor(fromHTML html: String) -> String? {
        textForClass("se_author", tag: "span", in: html) ??
            metaContent(from: html, names: ["article:author", "author"])
    }

    private static func collectionTitle(fromHTML html: String, pageURL: URL) -> String {
        let title = textForClass("nick_name", tag: "p", in: html) ??
            textForClass("tit_series", tag: "h2", in: html) ??
            metaContent(from: html, names: ["og:title", "twitter:title"]) ??
            titleTag(fromHTML: html) ??
            pageURL.host ??
            "Naver Post"
        return cleanTitle(title, author: nil, fallback: "Naver Post")
    }

    private static func textForClass(_ className: String, tag: String, in html: String) -> String? {
        let pattern = #"<\#(tag)\b[^>]*\bclass\s*=\s*["'][^"']*"# +
            NSRegularExpression.escapedPattern(for: className) +
            #"[^"']*["'][^>]*>(.*?)</\#(tag)>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, range: range),
              let capture = Range(match.range(at: 1), in: html) else {
            return nil
        }
        let text = stripTags(String(html[capture])).trimmed
        return text.isEmpty ? nil : text
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
            guard let key,
                  names.contains(key),
                  let content = values["content"]?.trimmed,
                  !content.isEmpty else {
                continue
            }
            return content
        }
        return nil
    }

    private static func titleTag(fromHTML html: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: #"<title\b[^>]*>(.*?)</title>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return nil
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, range: range),
              let capture = Range(match.range(at: 1), in: html) else {
            return nil
        }
        let title = stripTags(String(html[capture])).trimmed
        return title.isEmpty ? nil : title
    }

    private static func cleanTitle(_ raw: String, author: String?, fallback: String) -> String {
        var title = decodeHTML(stripTags(raw))
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmed
        for suffix in [" : 네이버 포스트", " | 네이버 포스트", " - 네이버 포스트", " : Naver Post", " | Naver Post", " - Naver Post"] {
            if title.lowercased().hasSuffix(suffix.lowercased()) {
                title.removeLast(suffix.count)
                title = title.trimmed
            }
        }

        if let author = author?.trimmed, !author.isEmpty, !title.contains(author) {
            title += " (\(author))"
        }
        return title.isEmpty ? fallback : title
    }

    private static func fallbackTitle(from url: URL) -> String {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if let volume = items.first(where: { $0.name == "volumeNo" })?.value {
            return "Post \(volume)"
        }
        return "Naver Post"
    }

    private static func naverPostMetadata(
        author: String?,
        pageURL: URL,
        title: String,
        assets: [ResolvedAsset],
        type: String
    ) -> [String: String] {
        let memberNo = queryValue("memberNo", from: pageURL)
        let volumeNo = queryValue("volumeNo", from: pageURL)
        let seriesNo = queryValue("seriesNo", from: pageURL)
        let identifier = volumeNo ?? seriesNo ?? memberNo ?? ""
        let count = assets.isEmpty ? "" : String(assets.count)
        return DownloadMetadata.clean([
            "site": "Naver Post",
            "title": title,
            "type": type,
            "media_type": "image",
            "media_count": count,
            "image_count": count,
            "id": identifier,
            "volume_no": volumeNo ?? "",
            "post_id": volumeNo ?? "",
            "gallery_id": identifier,
            "series_no": seriesNo ?? "",
            "artist": author ?? "",
            "author": author ?? "",
            "creator": author ?? "",
            "user": memberNo ?? author ?? "",
            "username": memberNo ?? author ?? "",
            "user_id": memberNo ?? "",
            "uploader": author ?? "",
            "uploader_id": memberNo ?? "",
            "channel": author ?? "",
            "channel_id": memberNo ?? "",
            "member_no": memberNo ?? "",
            "source_url": canonicalInputURL(for: pageURL)?.absoluteString ?? pageURL.absoluteString,
            "page_url": pageURL.absoluteString
        ])
    }

    private static func assetMetadata(
        for url: URL,
        author: String?,
        pageURL: URL,
        title: String,
        index: Int
    ) -> [String: String] {
        let memberNo = queryValue("memberNo", from: pageURL)
        let volumeNo = queryValue("volumeNo", from: pageURL)
        let mediaID = volumeNo.map { "\($0)-\(index)" } ?? String(index)
        let format = url.pathExtension.trimmed.isEmpty ? "jpg" : url.pathExtension.lowercased()
        return DownloadMetadata.clean([
            "site": "Naver Post",
            "title": title,
            "type": "image",
            "media_type": "image",
            "id": volumeNo ?? "",
            "volume_no": volumeNo ?? "",
            "post_id": volumeNo ?? "",
            "gallery_id": volumeNo ?? "",
            "media_id": mediaID,
            "page": String(index),
            "position": String(index),
            "format": format,
            "media_format": format,
            "image_url": url.absoluteString,
            "media_url": url.absoluteString,
            "artist": author ?? "",
            "author": author ?? "",
            "creator": author ?? "",
            "user": memberNo ?? author ?? "",
            "username": memberNo ?? author ?? "",
            "user_id": memberNo ?? "",
            "uploader": author ?? "",
            "uploader_id": memberNo ?? "",
            "channel": author ?? "",
            "channel_id": memberNo ?? "",
            "member_no": memberNo ?? "",
            "source_url": canonicalInputURL(for: pageURL)?.absoluteString ?? pageURL.absoluteString,
            "page_url": pageURL.absoluteString
        ])
    }

    private static func queryValue(_ name: String, from url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name == name }?
            .value
    }

    private static func filename(for url: URL, index: Int) -> String {
        let ext = url.pathExtension.trimmed.isEmpty ? "jpg" : url.pathExtension
        return String(format: "%04d.%@", index, ext).sanitizedFilename(maxLength: 120)
    }

    private static func anchorHREFs(fromHTML html: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"<a\b([^>]*)>"#, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        return regex.matches(in: html, range: range).compactMap { match in
            guard let attributesRange = Range(match.range(at: 1), in: html) else { return nil }
            return attributeValues(from: String(html[attributesRange]))["href"]
        }
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
                values[name] = normalizeEscapes(decodeHTML(String(attributes[valueRange]))).trimmed
                break
            }
        }
        return values
    }

    private static func jsonObject(from raw: String) -> [String: Any]? {
        let normalized = normalizeEscapes(decodeHTML(raw))
        guard let data = normalized.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object
    }

    private static func decodeJSONStringFragment(_ raw: String) -> String {
        let trimmed = raw.trimmed
        let literal = trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"") ? trimmed : "\"\(trimmed)\""
        if let data = literal.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(String.self, from: data) {
            return decoded
        }
        return normalizeEscapes(trimmed)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    }

    private static func boolValue(_ value: Any?) -> Bool? {
        if let bool = value as? Bool { return bool }
        if let number = value as? NSNumber { return number.boolValue }
        if let string = value as? String {
            let lowered = string.trimmed.lowercased()
            if ["true", "y", "yes", "1"].contains(lowered) { return true }
            if ["false", "n", "no", "0"].contains(lowered) { return false }
        }
        return nil
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
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

    private static func canonicalViewerURL(_ url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.host = apiHost(for: url.host)
        components.fragment = nil
        return components.url
    }

    private static func absoluteURL(_ raw: String, baseURL: URL) -> URL? {
        let value = normalizeEscapes(decodeHTML(raw)).trimmed
        if value.hasPrefix("//") {
            return URL(string: "\(baseURL.scheme ?? "https"):\(value)")
        }
        return URL(string: value, relativeTo: baseURL)?.absoluteURL
    }

    private static func isImageURL(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if ["jpg", "jpeg", "png", "gif", "webp"].contains(ext) {
            return true
        }
        let host = url.host?.lowercased() ?? ""
        return host.contains("pstatic") || host.contains("postfiles")
    }

    private static func apiHost(for host: String?) -> String {
        host?.lowercased().hasSuffix(".test") == true ? "post.naver.test" : "post.naver.com"
    }

    private static func isNaverPostHost(_ host: String) -> Bool {
        host == "post.naver.com" ||
            host == "m.post.naver.com" ||
            host == "post.naver.test" ||
            host == "m.post.naver.test"
    }

    private static func normalizeEscapes(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"\\u002F"#, with: "/", options: .caseInsensitive)
            .replacingOccurrences(of: #"\/"#, with: "/")
            .replacingOccurrences(of: #"\\/"#, with: "/")
            .replacingOccurrences(of: #"\\u0026"#, with: "&", options: .caseInsensitive)
            .replacingOccurrences(of: #"\""#, with: "\"")
    }

    private static func stripTags(_ text: String) -> String {
        text
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
    }
}
