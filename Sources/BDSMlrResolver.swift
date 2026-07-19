import Foundation

struct BDSMlrMediaAsset {
    var remoteURL: URL
    var postID: String
    var postMediaIndex: Int
    var referer: String
}

final class BDSMlrResolver {
    private let maxBlogAPIRequests = 1_000

    func canResolve(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(),
              Self.isSupportedHost(host),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return false
        }
        let path = url.path.lowercased()
        guard !path.contains("/login"),
              !path.contains("/signup"),
              !path.contains("/register") else {
            return false
        }
        return Self.blogName(from: url) != nil || Self.postID(from: url) != nil
    }

    func resolve(
        _ url: URL,
        headers: HTTPRequestOptions = HTTPRequestOptions(),
        assetLimit: Int? = nil
    ) async throws -> ResolvedDownload {
        let html = try await HTTPClient.shared.string(from: url, referer: headers.referer, userAgent: headers.userAgent)
        if Self.postID(from: url) == nil, let blogName = Self.blogName(from: url) {
            let canonical = Self.canonicalBlogURL(blogName: blogName, sourceURL: url)
            let pages = try await blogAPIHTMLPages(
                initialHTML: html,
                blogName: blogName,
                pageURL: canonical,
                headers: headers,
                assetLimit: assetLimit
            )
            let combined = Self.combinedBlogHTML(initialHTML: html, apiPages: pages)
            return try Self.resolvedDownload(fromHTML: combined, pageURL: canonical)
        }
        return try Self.resolvedDownload(fromHTML: html, pageURL: url)
    }

    private func blogAPIHTMLPages(
        initialHTML: String,
        blogName: String,
        pageURL: URL,
        headers: HTTPRequestOptions,
        assetLimit: Int?
    ) async throws -> [String] {
        let token = Self.csrfToken(fromHTML: initialHTML)
        var pages: [String] = []
        var seenPostIDs = Set(Self.postIDs(fromHTML: initialHTML))
        var seenMediaURLs = Set<String>()
        var mediaCount = 0
        var lastID = Self.lastPostID(fromHTML: initialHTML)
        var scroll = 0

        for requestIndex in 0..<maxBlogAPIRequests {
            try Task.checkCancellation()
            let apiURL = requestIndex == 0
                ? Self.loadFirstAPIURL(blogName: blogName, sourceURL: pageURL)
                : Self.infiniteAPIURL(blogName: blogName, sourceURL: pageURL)
            var fields = [
                "scroll": String(scroll),
                "timenow": Self.apiTimestamp()
            ]
            if let lastID, !lastID.isEmpty {
                fields["last"] = lastID
            }
            let page = try await apiString(
                from: apiURL,
                fields: fields,
                referer: pageURL.absoluteString,
                csrfToken: token,
                headers: headers
            )
            let ids = Self.postIDs(fromHTML: page)
            let newIDs = ids.filter { !seenPostIDs.contains($0) }
            guard !page.trimmed.isEmpty, !newIDs.isEmpty else { break }
            pages.append(page)
            seenPostIDs.formUnion(newIDs)
            lastID = ids.last
            scroll += scroll == 0 ? 5 : 20

            for asset in Self.mediaAssets(fromHTML: page, pageURL: pageURL) {
                let identity = URLIdentity.normalize(asset.remoteURL.absoluteString)
                if seenMediaURLs.insert(identity).inserted {
                    mediaCount += 1
                }
            }
            if let assetLimit, assetLimit > 0, mediaCount > assetLimit {
                break
            }
        }

        return pages
    }

    private func apiString(
        from url: URL,
        fields: [String: String],
        referer: String,
        csrfToken: String?,
        headers: HTTPRequestOptions
    ) async throws -> String {
        var additionalHeaders: [String: String] = [:]
        if let csrfToken, !csrfToken.isEmpty {
            additionalHeaders["X-CSRF-TOKEN"] = csrfToken
        }
        var lastError: Error?
        for _ in 0..<4 {
            try Task.checkCancellation()
            do {
                let data = try await HTTPClient.shared.postForm(
                    to: url,
                    fields: fields,
                    referer: headers.referer ?? referer,
                    userAgent: headers.userAgent,
                    additionalHeaders: additionalHeaders
                )
                if let text = String(data: data, encoding: .utf8) {
                    return text
                }
                return String(decoding: data, as: UTF8.self)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
            }
        }
        throw lastError ?? NativeDownloadError.noFiles
    }

    static func resolvedDownload(fromHTML html: String, pageURL: URL) throws -> ResolvedDownload {
        if isUnavailableHTML(html) {
            throw NativeDownloadError.unsupported("BDSMlr blog or post is unavailable.")
        }

        let blog = blogName(from: pageURL) ?? "blog"
        let title = pageTitle(fromHTML: html, pageURL: pageURL, blogName: blog)
        let assets = mediaAssets(fromHTML: html, pageURL: pageURL)
        guard !assets.isEmpty else {
            throw NativeDownloadError.noFiles
        }

        let resolvedAssets = assets.enumerated().map { offset, asset in
            ResolvedAsset(
                remoteURL: asset.remoteURL,
                filename: filename(for: asset, index: offset + 1),
                metadata: assetMetadata(for: asset, blogName: blog, title: title, pageURL: pageURL, index: offset + 1),
                referer: asset.referer
            )
        }

        return ResolvedDownload(
            title: "\(title) (bdsmlr_\(blog))".sanitizedFilename(maxLength: 120),
            folderName: "BDSMlr \(blog) - \(title)".sanitizedFilename(maxLength: 120),
            assets: resolvedAssets,
            metadata: bdsmlrMetadata(blogName: blog, title: title, pageURL: pageURL, assets: assets, html: html)
        )
    }

    static func blogName(from url: URL) -> String? {
        guard let host = url.host?.lowercased() else { return nil }
        let pathParts = pathParts(from: url)

        if host == "bdsmlr.com" || host == "www.bdsmlr.com" || host == "bdsmlr.test" || host == "www.bdsmlr.test" {
            if let first = pathParts.first,
               !["post", "posts", "tagged", "search"].contains(first.lowercased()) {
                return cleanBlogName(first)
            }
            return nil
        }

        if host.hasSuffix(".bdsmlr.com") || host.hasSuffix(".bdsmlr.test") {
            guard let subdomain = host.split(separator: ".").first.map(String.init),
                  subdomain != "www" else {
                return nil
            }
            return cleanBlogName(subdomain)
        }
        return nil
    }

    static func postID(from url: URL) -> String? {
        let parts = pathParts(from: url)
        guard let index = parts.firstIndex(where: { ["post", "posts"].contains($0.lowercased()) }),
              index + 1 < parts.count else {
            return nil
        }
        let id = parts[index + 1]
        return id.range(of: #"^[0-9]+$"#, options: .regularExpression) == nil ? nil : id
    }

    static func canonicalBlogURL(blogName: String, sourceURL: URL) -> URL {
        var components = URLComponents()
        components.scheme = sourceURL.scheme ?? "https"
        components.host = "\(cleanBlogName(blogName)).\(sourceURL.host?.lowercased().hasSuffix(".test") == true ? "bdsmlr.test" : "bdsmlr.com")"
        components.path = "/"
        return components.url!
    }

    static func loadFirstAPIURL(blogName: String, sourceURL: URL) -> URL {
        canonicalBlogURL(blogName: blogName, sourceURL: sourceURL)
            .appendingPathComponent("loadfirst")
    }

    static func infiniteAPIURL(blogName: String, lastPostID: String, sourceURL: URL) -> URL {
        infiniteAPIURL(blogName: blogName, sourceURL: sourceURL)
    }

    static func infiniteAPIURL(blogName: String, sourceURL: URL) -> URL {
        canonicalBlogURL(blogName: blogName, sourceURL: sourceURL)
            .appendingPathComponent("infinitepb2")
            .appendingPathComponent(cleanBlogName(blogName))
    }

    static func combinedBlogHTML(initialHTML: String, apiPages: [String]) -> String {
        ([initialHTML] + apiPages).joined(separator: "\n")
    }

    static func mediaAssets(fromHTML html: String, pageURL: URL) -> [BDSMlrMediaAsset] {
        var assets: [BDSMlrMediaAsset] = []
        var seen = Set<String>()
        let defaultPostID = postID(from: pageURL) ?? "post"

        func append(_ remote: URL, postID: String, postMediaIndex: Int, referer: String) {
            guard isLikelyMedia(remote) else { return }
            let normalized = URLIdentity.normalize(remote.absoluteString)
            guard !seen.contains(normalized) else { return }
            seen.insert(normalized)
            assets.append(BDSMlrMediaAsset(
                remoteURL: remote,
                postID: postID,
                postMediaIndex: postMediaIndex,
                referer: referer
            ))
        }

        let blocks = postBlocks(fromHTML: html)
        for block in blocks where !isReblogPostHTML(block) {
            let postID = postID(fromPostHTML: block) ?? defaultPostID
            for (postMediaIndex, raw) in mediaURLStrings(fromHTML: block).enumerated() {
                guard let remote = absoluteURL(raw, baseURL: pageURL) else { continue }
                append(
                    remote,
                    postID: postID,
                    postMediaIndex: postMediaIndex,
                    referer: postReferer(postID: postID, pageURL: pageURL)
                )
            }
        }

        if blocks.isEmpty {
            for (postMediaIndex, raw) in mediaURLStrings(fromHTML: html).enumerated() {
                guard let remote = absoluteURL(raw, baseURL: pageURL) else { continue }
                append(
                    remote,
                    postID: defaultPostID,
                    postMediaIndex: postMediaIndex,
                    referer: pageURL.absoluteString
                )
            }
        }

        return assets
    }

    static func pageTitle(fromHTML html: String, pageURL: URL, blogName: String) -> String {
        let title = metaContent(from: html, names: ["og:title", "twitter:title"]) ??
            titleTag(fromHTML: html) ??
            blogName
        return cleanTitle(title, fallback: blogName)
    }

    static func postID(fromPostHTML html: String) -> String? {
        if let id = firstCapture(patterns: [
            #"data-(?:post-)?id\s*=\s*["']?([0-9]+)"#,
            #"\bid\s*=\s*["'](?:post-|posts-)?([0-9]+)["']"#,
            #"\bclass\s*=\s*["'][^"']*\b([0-9]{4,})\b[^"']*["']"#
        ], in: html) {
            return id
        }
        return firstCapture(patterns: [#"/post/([0-9]+)"#, #"/posts/([0-9]+)"#], in: html)
    }

    static func postIDs(fromHTML html: String) -> [String] {
        var ids = postBlocks(fromHTML: html).compactMap(postID(fromPostHTML:))
        if ids.isEmpty {
            ids = captureMatches(patterns: [#"/post/([0-9]+)"#, #"/posts/([0-9]+)"#], in: html)
        }
        return uniqueValues(ids)
    }

    static func lastPostID(fromHTML html: String) -> String? {
        postIDs(fromHTML: html).last
    }

    static func csrfToken(fromHTML html: String) -> String? {
        metaContent(from: html, names: ["csrf-token"])
    }

    static func mediaURLStrings(fromHTML html: String) -> [String] {
        var results: [String] = []
        var seen = Set<String>()

        func append(_ raw: String?) {
            guard let raw = raw?.trimmed, !raw.isEmpty else { return }
            let normalized = raw.lowercased()
            guard !seen.contains(normalized) else { return }
            seen.insert(normalized)
            results.append(raw)
        }

        let magnifyBlocks = tags(named: "a", html: html).filter { attrs in
            let values = attributeValues(from: attrs)
            return (values["class"]?.lowercased().contains("magnify") ?? false) ||
                (values["href"]?.lowercased().contains("magnify") ?? false)
        }
        for attrs in magnifyBlocks {
            append(attributeValues(from: attrs)["href"])
        }

        for attrs in tags(named: "img", html: html) {
            let values = attributeValues(from: attrs)
            append(values["data-src"] ?? values["data-original"] ?? values["data-lazy-src"] ?? values["src"])
        }

        for tag in ["source", "video"] {
            for attrs in tags(named: tag, html: html) {
                let values = attributeValues(from: attrs)
                append(values["src"] ?? values["data-src"])
            }
        }

        for value in metaContents(from: html, names: ["og:image", "og:image:url", "og:image:secure_url", "og:video", "og:video:url", "og:video:secure_url", "twitter:image", "twitter:player:stream"]) {
            append(value)
        }

        return results
    }

    private static func postBlocks(fromHTML html: String) -> [String] {
        let blocks = elementBlocks(classContaining: "wrap-post", in: html)
        return blocks.isEmpty ? [] : blocks
    }

    private static func isReblogPostHTML(_ html: String) -> Bool {
        html.range(
            of: #"<div\b[^>]*\bclass\s*=\s*["'][^"']*\bogname\b[^"']*["']"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    private static func elementBlocks(classContaining className: String, in html: String) -> [String] {
        guard let regex = try? NSRegularExpression(
            pattern: #"<(?:article|div)\b[^>]*\bclass\s*=\s*["'][^"']*\#(NSRegularExpression.escapedPattern(for: className))[^"']*["'][^>]*>(.*?)</(?:article|div)>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return []
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        return regex.matches(in: html, range: range).compactMap { match in
            guard let full = Range(match.range(at: 0), in: html) else { return nil }
            return String(html[full])
        }
    }

    private static func postReferer(postID: String, pageURL: URL) -> String {
        if let blog = blogName(from: pageURL) {
            var components = URLComponents()
            components.scheme = pageURL.scheme ?? "https"
            components.host = "\(blog).\(pageURL.host?.lowercased().hasSuffix(".test") == true ? "bdsmlr.test" : "bdsmlr.com")"
            components.path = "/post/\(postID)"
            return components.url?.absoluteString ?? pageURL.absoluteString
        }
        return pageURL.absoluteString
    }

    private static func filename(for asset: BDSMlrMediaAsset, index: Int) -> String {
        let ext = asset.remoteURL.pathExtension.trimmed.isEmpty ? "jpg" : asset.remoteURL.pathExtension.lowercased()
        return "\(asset.postID)_p\(asset.postMediaIndex).\(ext)".sanitizedFilename(maxLength: 180)
    }

    private static func apiTimestamp(now: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: now)
    }

    static func bdsmlrMetadata(blogName: String, title: String, pageURL: URL, assets: [BDSMlrMediaAsset], html: String) -> [String: String] {
        let postIDs = uniqueValues(assets.map(\.postID).filter { $0 != "post" })
        let firstPostID = postID(from: pageURL) ?? postIDs.first ?? ""
        let tags = joinMetadata(tagNames(fromHTML: html))
        let type = postID(from: pageURL) == nil ? "blog" : "post"
        let imageCount = assets.filter { mediaType(for: $0.remoteURL) == "image" }.count
        let videoCount = assets.filter { mediaType(for: $0.remoteURL) == "video" }.count
        return DownloadMetadata.clean([
            "artist": blogName,
            "author": blogName,
            "creator": blogName,
            "user": blogName,
            "username": blogName,
            "uploader": blogName,
            "channel": blogName,
            "blog": blogName,
            "blog_id": blogName,
            "series": blogName,
            "category": type,
            "type": type,
            "media_type": mediaType(for: assets),
            "post_id": firstPostID,
            "gallery_id": postIDs.count == 1 ? postIDs[0] : blogName,
            "post_count": postIDs.isEmpty ? "" : String(postIDs.count),
            "media_count": String(assets.count),
            "image_count": imageCount > 0 ? String(imageCount) : "",
            "video_count": videoCount > 0 ? String(videoCount) : "",
            "tag": tags,
            "tags": tags,
            "slug": postID(from: pageURL) ?? blogName,
            "site": "BDSMlr",
            "title": title,
            "source_url": pageURL.absoluteString,
            "page_url": pageURL.absoluteString
        ])
    }

    static func assetMetadata(for asset: BDSMlrMediaAsset, blogName: String, title: String, pageURL: URL, index: Int) -> [String: String] {
        let mediaType = mediaType(for: asset.remoteURL)
        let format = mediaFormat(for: asset.remoteURL)
        return DownloadMetadata.clean([
            "artist": blogName,
            "author": blogName,
            "creator": blogName,
            "user": blogName,
            "username": blogName,
            "uploader": blogName,
            "channel": blogName,
            "blog": blogName,
            "blog_id": blogName,
            "series": blogName,
            "category": mediaType,
            "type": mediaType,
            "media_type": mediaType,
            "post_id": asset.postID,
            "media_id": asset.postID == "post" ? String(index) : "\(asset.postID)-\(index)",
            "gallery_id": asset.postID == "post" ? blogName : asset.postID,
            "slug": postID(from: pageURL) ?? blogName,
            "site": "BDSMlr",
            "title": title,
            "page": String(index),
            "position": String(index),
            "format": format,
            "media_format": format,
            "image_url": mediaType == "image" ? asset.remoteURL.absoluteString : "",
            "video_url": mediaType == "video" ? asset.remoteURL.absoluteString : "",
            "media_url": asset.remoteURL.absoluteString,
            "source_url": asset.remoteURL.absoluteString,
            "page_url": asset.referer
        ])
    }

    private static func mediaType(for assets: [BDSMlrMediaAsset]) -> String {
        let types = Set(assets.map { mediaType(for: $0.remoteURL) })
        if types.count == 1 {
            return types.first ?? ""
        }
        return types.isEmpty ? "" : "mixed"
    }

    private static func mediaType(for url: URL) -> String {
        ["mp4", "webm", "m4v", "mov", "m3u8"].contains(mediaFormat(for: url)) ? "video" : "image"
    }

    private static func mediaFormat(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        if ext == "jpeg" || ext == "bmp" {
            return "jpg"
        }
        return ext.isEmpty ? "jpg" : ext
    }

    private static func tagNames(fromHTML html: String) -> [String] {
        guard let regex = try? NSRegularExpression(
            pattern: #"<a\b([^>]*)>(.*?)</a>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return []
        }

        var tags: [String] = []
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        for match in regex.matches(in: html, range: range) {
            guard let attrsRange = Range(match.range(at: 1), in: html),
                  let bodyRange = Range(match.range(at: 2), in: html) else {
                continue
            }
            let values = attributeValues(from: String(html[attrsRange]))
            let href = values["href"] ?? ""
            let marker = [href, values["class"] ?? "", values["rel"] ?? ""].joined(separator: " ").lowercased()
            guard marker.contains("/tagged/") ||
                    marker.contains("/tag/") ||
                    marker.contains("tag=") ||
                    marker.contains("tags=") ||
                    marker.contains("tag") else {
                continue
            }

            appendTag(from: href, into: &tags)
            let text = cleanTitle(String(html[bodyRange]), fallback: "")
            if !text.isEmpty {
                tags.append(text.replacingOccurrences(of: "^#+", with: "", options: .regularExpression))
            }
        }
        return uniqueValues(tags)
    }

    private static func appendTag(from raw: String, into tags: inout [String]) {
        let decoded = (decodeHTML(raw).removingPercentEncoding ?? raw)
            .replacingOccurrences(of: "+", with: " ")
        if let pathMatch = firstCapture(patterns: [#"/(?:tagged|tag)/([^/?#]+)"#], in: decoded) {
            tags.append(pathMatch.replacingOccurrences(of: "+", with: " "))
        }
        for name in ["tag", "tags"] {
            if let value = firstCapture(patterns: [#"[?&]\#(name)=([^&#]+)"#], in: decoded) {
                tags.append(value.replacingOccurrences(of: "+", with: " "))
            }
        }
    }

    private static func joinMetadata(_ values: [String]) -> String {
        uniqueValues(values).joined(separator: ", ")
    }

    private static func uniqueValues(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values {
            let cleaned = decodeHTML(value)
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmed
            guard !cleaned.isEmpty else { continue }
            let key = cleaned.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(cleaned)
        }
        return result
    }

    private static func isUnavailableHTML(_ html: String) -> Bool {
        let lowered = html.lowercased()
        return lowered.contains("sorry") && lowered.contains("bdsmlr") && lowered.contains("not found")
    }

    private static func isLikelyMedia(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        let path = url.path.lowercased()
        guard ext != "svg",
              !path.contains("avatar"),
              !path.contains("placeholder"),
              !path.contains("loading"),
              !path.contains("logo") else {
            return false
        }
        return ["jpg", "jpeg", "png", "webp", "gif", "mp4", "webm", "m4v"].contains(ext) ||
            (url.host?.lowercased().contains("bdsmlr") ?? false)
    }

    private static func tags(named tag: String, html: String) -> [String] {
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

    private static func metaContent(from html: String, names: Set<String>) -> String? {
        metaContents(from: html, names: names).first
    }

    private static func metaContents(from html: String, names: Set<String>) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"<meta\b([^>]*)>"#, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        var results: [String] = []
        for match in regex.matches(in: html, range: range) {
            guard let attributesRange = Range(match.range(at: 1), in: html) else { continue }
            let values = attributeValues(from: String(html[attributesRange]))
            let key = (values["property"] ?? values["name"] ?? values["itemprop"])?.lowercased()
            guard let key, names.contains(key),
                  let content = values["content"]?.trimmed,
                  !content.isEmpty else {
                continue
            }
            results.append(content)
        }
        return results
    }

    private static func titleTag(fromHTML html: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"<title\b[^>]*>(.*?)</title>"#, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
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
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { continue }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            guard let match = regex.firstMatch(in: text, range: range),
                  let capture = Range(match.range(at: 1), in: text) else {
                continue
            }
            return String(text[capture])
        }
        return nil
    }

    private static func captureMatches(patterns: [String], in text: String) -> [String] {
        var values: [String] = []
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { continue }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            values.append(contentsOf: regex.matches(in: text, range: range).compactMap { match in
                guard match.numberOfRanges > 1,
                      let capture = Range(match.range(at: 1), in: text) else {
                    return nil
                }
                return String(text[capture])
            })
        }
        return values
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

    private static func pathParts(from url: URL) -> [String] {
        url.path.split(separator: "/").map { String($0).removingPercentEncoding ?? String($0) }
    }

    private static func cleanBlogName(_ raw: String) -> String {
        raw.trimmed
            .trimmingCharacters(in: CharacterSet(charactersIn: "/@ "))
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
    }

    private static func cleanTitle(_ raw: String, fallback: String) -> String {
        var title = decodeHTML(stripTags(raw))
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmed
        for suffix in [" - BDSMlr", " | BDSMlr", " - bdsmlr.com", " | bdsmlr.com"] {
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
        host == "bdsmlr.com" ||
            host == "www.bdsmlr.com" ||
            host.hasSuffix(".bdsmlr.com") ||
            host == "bdsmlr.test" ||
            host == "www.bdsmlr.test" ||
            host.hasSuffix(".bdsmlr.test")
    }
}
