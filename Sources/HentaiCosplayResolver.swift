import Foundation

final class HentaiCosplayResolver {
    private struct ImageSource {
        var url: URL
        var referer: URL
        var isDetailPage: Bool
    }

    func canResolve(_ url: URL) -> Bool {
        guard let canonical = Self.canonicalURL(for: url) else {
            return false
        }
        let path = canonical.path.lowercased()
        return path.contains("/story/") || path.contains("/image/") || path.contains("/video/")
    }

    func resolve(
        _ url: URL,
        headers: HTTPRequestOptions = HTTPRequestOptions(),
        assetLimit: Int? = nil
    ) async throws -> ResolvedDownload {
        let pageURL = Self.canonicalURL(for: url) ?? url
        let html = try await HTTPClient.shared.string(from: pageURL, referer: headers.referer, userAgent: headers.userAgent)
        let title = Self.title(fromHTML: html, pageURL: pageURL)

        if Self.isVideoPage(pageURL) {
            let videos = Self.videoURLs(fromHTML: html, baseURL: pageURL)
            let mp4s = videos.filter { Self.mediaKind(for: $0) == "mp4" }
            if !mp4s.isEmpty {
                return try Self.resolvedVideoDownload(title: title, videos: mp4s, pageURL: pageURL, pageHTML: html)
            }
            if let hls = videos.first(where: { Self.mediaKind(for: $0) == "m3u8" }) {
                let hlsDownload = try await M3U8Resolver().resolve(
                    hls,
                    headers: HTTPRequestOptions(referer: headers.referer ?? pageURL.absoluteString, userAgent: headers.userAgent)
                )
                return ResolvedDownload(
                    title: title,
                    folderName: "HentaiCosplay \(title)".sanitizedFilename(maxLength: 120),
                    assets: hlsDownload.assets,
                    packageMode: hlsDownload.packageMode,
                    metadata: Self.downloadMetadata(
                        fromHTML: html,
                        pageURL: pageURL,
                        title: title,
                        mediaType: "video",
                        mediaCount: 1,
                        mediaURL: hls
                    )
                )
            }
            throw NativeDownloadError.noFiles
        }

        return try await resolveImages(
            fromHTML: html,
            title: title,
            pageURL: pageURL,
            headers: headers,
            assetLimit: assetLimit
        )
    }

    private func resolveImages(
        fromHTML html: String,
        title: String,
        pageURL: URL,
        headers: HTTPRequestOptions,
        assetLimit: Int?
    ) async throws -> ResolvedDownload {
        var assets: [ResolvedAsset] = []
        var seen = Set<String>()
        var sources: [ImageSource] = []
        var seenSources = Set<String>()
        let pageMetadata = Self.pageMetadata(fromHTML: html, pageURL: pageURL, title: title)

        func append(_ remote: URL, referer: URL) {
            let normalized = URLIdentity.normalize(remote.absoluteString)
            guard !seen.contains(normalized) else { return }
            seen.insert(normalized)
            let index = assets.count + 1
            assets.append(Self.asset(
                forImage: remote,
                index: index,
                referer: referer.absoluteString,
                metadata: Self.assetMetadata(for: remote, pageMetadata: pageMetadata, pageURL: referer, index: index)
            ))
        }

        func appendSource(_ url: URL, referer: URL, isDetailPage: Bool) {
            let normalized = URLIdentity.normalize(url.absoluteString)
            guard seenSources.insert(normalized).inserted else { return }
            sources.append(ImageSource(url: url, referer: referer, isDetailPage: isDetailPage))
        }

        let firstPages = Self.storyPageURLs(fromHTML: html, baseURL: pageURL)
        var pages = firstPages
        let normalizedCurrent = URLIdentity.normalize(pageURL.absoluteString)
        if !pages.contains(where: { URLIdentity.normalize($0.absoluteString) == normalizedCurrent }) {
            pages.insert(pageURL, at: 0)
        }

        for page in pages {
            try Task.checkCancellation()
            let pageHTML = URLIdentity.normalize(page.absoluteString) == normalizedCurrent
                ? html
                : try await HTTPClient.shared.string(from: page, referer: pageURL.absoluteString, userAgent: headers.userAgent)

            let imagePages = Self.imagePageURLs(fromHTML: pageHTML, baseURL: page)
            if imagePages.isEmpty {
                for image in Self.imageURLs(fromHTML: pageHTML, baseURL: page) {
                    appendSource(image, referer: page, isDetailPage: false)
                }
            } else {
                for imagePage in imagePages {
                    appendSource(imagePage, referer: page, isDetailPage: true)
                }
            }
        }

        let finiteAssetLimit = assetLimit.flatMap { $0 > 0 ? $0 : nil }
        for source in sources {
            try Task.checkCancellation()
            if let finiteAssetLimit, assets.count >= finiteAssetLimit { break }

            if source.isDetailPage {
                let imageHTML = try await HTTPClient.shared.string(
                    from: source.url,
                    referer: source.referer.absoluteString,
                    userAgent: headers.userAgent
                )
                guard let image = Self.linkedDetailImageURL(fromHTML: imageHTML, baseURL: source.url) ??
                    Self.imageURLs(fromHTML: imageHTML, baseURL: source.url).first else {
                    continue
                }
                append(image, referer: source.url)
            } else {
                append(source.url, referer: source.referer)
            }
        }

        guard !assets.isEmpty else {
            throw NativeDownloadError.noFiles
        }

        var metadata = Self.downloadMetadata(
            fromHTML: html,
            pageURL: pageURL,
            title: title,
            mediaType: "image",
            mediaCount: assets.count,
            mediaURL: assets.count == 1 ? assets[0].remoteURL : nil
        )
        metadata["listed_media_count"] = String(sources.count)
        metadata["resolved_media_count"] = String(assets.count)

        return ResolvedDownload(
            title: title,
            folderName: "HentaiCosplay \(title)".sanitizedFilename(maxLength: 120),
            assets: assets,
            metadata: metadata
        )
    }

    static func resolvedImageDownload(fromHTML html: String, pageURL: URL) throws -> ResolvedDownload {
        let title = title(fromHTML: html, pageURL: pageURL)
        let images = imageURLs(fromHTML: html, baseURL: pageURL)
        guard !images.isEmpty else {
            throw NativeDownloadError.noFiles
        }
        return ResolvedDownload(
            title: title,
            folderName: "HentaiCosplay \(title)".sanitizedFilename(maxLength: 120),
            assets: images.enumerated().map {
                let metadata = pageMetadata(fromHTML: html, pageURL: pageURL, title: title)
                return asset(
                    forImage: $0.element,
                    index: $0.offset + 1,
                    referer: pageURL.absoluteString,
                    metadata: assetMetadata(for: $0.element, pageMetadata: metadata, pageURL: pageURL, index: $0.offset + 1)
                )
            },
            metadata: downloadMetadata(
                fromHTML: html,
                pageURL: pageURL,
                title: title,
                mediaType: "image",
                mediaCount: images.count,
                mediaURL: images.count == 1 ? images[0] : nil
            )
        )
    }

    static func resolvedVideoDownload(title: String, videos: [URL], pageURL: URL, pageHTML: String? = nil) throws -> ResolvedDownload {
        guard !videos.isEmpty else {
            throw NativeDownloadError.noFiles
        }
        return ResolvedDownload(
            title: title,
            folderName: "HentaiCosplay \(title)".sanitizedFilename(maxLength: 120),
            assets: videos.enumerated().map { offset, video in
                let metadata = pageMetadata(fromHTML: pageHTML ?? "", pageURL: pageURL, title: title)
                return asset(
                    forVideo: video,
                    title: title,
                    index: offset + 1,
                    referer: pageURL.absoluteString,
                    metadata: assetMetadata(for: video, pageMetadata: metadata, pageURL: pageURL, index: offset + 1)
                )
            },
            metadata: downloadMetadata(
                fromHTML: pageHTML ?? "",
                pageURL: pageURL,
                title: title,
                mediaType: "video",
                mediaCount: videos.count,
                mediaURL: videos.count == 1 ? videos[0] : nil
            )
        )
    }

    static func title(fromHTML html: String, pageURL: URL) -> String {
        let title = elementText(pattern: #"<(?:h1|h2|div|span)\b[^>]*\bclass\s*=\s*["'][^"']*(?:post_title|post-title|entry-title)[^"']*["'][^>]*>(.*?)</(?:h1|h2|div|span)>"#, in: html) ??
            elementText(pattern: #"<h1\b[^>]*>(.*?)</h1>"#, in: html) ??
            metaContent(from: html, names: ["og:title", "twitter:title"]) ??
            titleTag(fromHTML: html) ??
            pageURL.lastPathComponent
        return cleanTitle(title, fallback: "HentaiCosplay")
    }

    static func storyPageURLs(fromHTML html: String, baseURL: URL) -> [URL] {
        let baseStory = storySlug(from: baseURL)
        var results: [URL] = []
        var seen = Set<String>()

        if let root = storyRootURL(from: baseURL) {
            results.append(root)
            seen.insert(URLIdentity.normalize(root.absoluteString))
        }

        for href in anchorHREFs(fromHTML: html) {
            guard let url = absoluteURL(href, baseURL: baseURL),
                  storySlug(from: url) == baseStory,
                  url.path.lowercased().contains("/page/") else {
                continue
            }
            let normalized = URLIdentity.normalize(url.absoluteString)
            guard !seen.contains(normalized) else { continue }
            seen.insert(normalized)
            results.append(url)
        }

        return results
    }

    static func imagePageURLs(fromHTML html: String, baseURL: URL) -> [URL] {
        var results: [URL] = []
        var seen = Set<String>()

        for href in anchorHREFs(fromHTML: html) {
            guard let url = absoluteURL(href, baseURL: baseURL),
                  isImagePage(url) else {
                continue
            }
            let normalized = URLIdentity.normalize(url.absoluteString)
            guard !seen.contains(normalized) else { continue }
            seen.insert(normalized)
            results.append(url)
        }
        return results
    }

    static func linkedDetailImageURL(fromHTML html: String, baseURL: URL) -> URL? {
        let scope = firstCapture(patterns: [
            #"<(?:div|ul)\b[^>]*(?:id|class)\s*=\s*[\"'][^\"']*(?:display_image_detail|detail_list)[^\"']*[\"'][^>]*>(.*?)</(?:div|ul)>"#
        ], in: html) ?? html
        let raw = firstCapture(patterns: [
            #"<a\b[^>]*\bhref\s*=\s*\"([^\"]+)\"[^>]*>.*?<img\b"#,
            #"<a\b[^>]*\bhref\s*=\s*'([^']+)'[^>]*>.*?<img\b"#
        ], in: scope)
        guard let raw,
              let remote = absoluteURL(raw, baseURL: baseURL),
              isLikelyImage(remote) else {
            return nil
        }
        return remote
    }

    static func imageURLs(fromHTML html: String, baseURL: URL) -> [URL] {
        let imageScope = imageScope(fromHTML: html)
        let scoped = imageScope.html

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

        for attrs in tagAttributes(tag: "img", html: scoped) {
            let values = attributeValues(from: attrs)
            let className = values["class"]?.lowercased() ?? ""
            guard className.contains("display_image_detail") ||
                    className.contains("wp-image") ||
                    imageScope.allowsPlainImageSources ||
                    hasDedicatedImageAttribute(values) ||
                    isImagePage(baseURL) else {
                continue
            }
            for candidate in imageCandidateValues(from: values) {
                append(candidate)
            }
        }

        for attrs in tagAttributes(tag: "source", html: scoped) {
            let values = attributeValues(from: attrs)
            guard imageScope.allowsPlainImageSources ||
                    hasDedicatedImageAttribute(values) ||
                    isImagePage(baseURL) else {
                continue
            }
            for candidate in imageCandidateValues(from: values) {
                append(candidate)
            }
        }

        for href in anchorHREFs(fromHTML: scoped) {
            append(href)
        }

        return results
    }

    private static func imageCandidateValues(from values: [String: String]) -> [String] {
        var candidates: [String] = []

        for key in preferredImageAttributeNames {
            if let value = values[key]?.trimmed, !value.isEmpty {
                candidates.append(value)
            }
        }

        for key in srcsetImageAttributeNames {
            if let srcset = values[key]?.trimmed,
               let best = bestSrcsetCandidate(srcset) {
                candidates.append(best)
            }
        }

        if let value = values["src"]?.trimmed, !value.isEmpty {
            candidates.append(value)
        }

        return candidates
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

    private struct HentaiCosplayImageScope {
        var html: String
        var allowsPlainImageSources: Bool
    }

    private static func imageScope(fromHTML html: String) -> HentaiCosplayImageScope {
        if let dedicated = firstCapture(patterns: [
            #"<(?:div|section|article|ul)\b[^>]*\bclass\s*=\s*["'][^"']*(?:display_image_detail|detail_list)[^"']*["'][^>]*>(.*?)</(?:div|section|article|ul)>"#
        ], in: html) {
            return HentaiCosplayImageScope(html: dedicated, allowsPlainImageSources: true)
        }

        if let broad = firstCapture(patterns: [
            #"<(?:div|section|article)\b[^>]*\bclass\s*=\s*["'][^"']*(?:post|entry-content)[^"']*["'][^>]*>(.*?)</(?:div|section|article)>"#
        ], in: html) {
            return HentaiCosplayImageScope(html: broad, allowsPlainImageSources: false)
        }

        return HentaiCosplayImageScope(html: html, allowsPlainImageSources: false)
    }

    static func videoURLs(fromHTML html: String, baseURL: URL) -> [URL] {
        let scoped = firstCapture(patterns: [
            #"<(?:div|section)\b[^>]*\bclass\s*=\s*["'][^"']*video-container[^"']*["'][^>]*>(.*?)</(?:div|section)>"#
        ], in: html) ?? html

        var results: [URL] = []
        var seen = Set<String>()
        for tag in ["source", "video"] {
            for attrs in tagAttributes(tag: tag, html: scoped) {
                let values = attributeValues(from: attrs)
                let raw = values["src"] ?? values["data-src"]
                guard let raw,
                      let remote = absoluteURL(raw, baseURL: baseURL),
                      ["mp4", "m3u8"].contains(mediaKind(for: remote)) else {
                    continue
                }
                let normalized = URLIdentity.normalize(remote.absoluteString)
                guard !seen.contains(normalized) else { continue }
                seen.insert(normalized)
                results.append(remote)
            }
        }
        return results
    }

    static func isImagePage(_ url: URL) -> Bool {
        url.path.lowercased().contains("/image/")
    }

    static func isVideoPage(_ url: URL) -> Bool {
        url.path.lowercased().contains("/video/")
    }

    static func mediaKind(for url: URL) -> String {
        let absolute = url.absoluteString.lowercased()
        if absolute.contains(".m3u8") || url.pathExtension.lowercased() == "m3u8" {
            return "m3u8"
        }
        if absolute.contains(".mp4") || url.pathExtension.lowercased() == "mp4" {
            return "mp4"
        }
        return url.pathExtension.lowercased()
    }

    static func mediaFormat(for url: URL) -> String {
        let kind = mediaKind(for: url)
        if kind == "jpeg" {
            return "jpg"
        }
        return kind.isEmpty ? "jpg" : kind
    }

    static func canonicalURL(for url: URL) -> URL? {
        guard let host = url.host?.lowercased(),
              isSupportedHost(host),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        components.host = canonicalHost(for: host)
        components.path = canonicalPath(url.path)
        components.queryItems = nil
        components.fragment = nil
        return components.url
    }

    static func asset(forImage url: URL, index: Int, referer: String, metadata: [String: String] = [:]) -> ResolvedAsset {
        let ext = url.pathExtension.trimmed.isEmpty ? "jpg" : url.pathExtension.lowercased()
        return ResolvedAsset(
            remoteURL: url,
            filename: String(format: "%04d.%@", index, ext).sanitizedFilename(maxLength: 180),
            metadata: metadata,
            referer: referer
        )
    }

    static func asset(forVideo url: URL, title: String, index: Int, referer: String, metadata: [String: String] = [:]) -> ResolvedAsset {
        let ext = mediaKind(for: url) == "m3u8" ? "m3u8" : (url.pathExtension.trimmed.isEmpty ? "mp4" : url.pathExtension.lowercased())
        let suffix = index == 1 ? "" : " \(index)"
        return ResolvedAsset(
            remoteURL: url,
            filename: "\(title)\(suffix).\(ext)".sanitizedFilename(maxLength: 180),
            metadata: metadata,
            referer: referer
        )
    }

    static func pageMetadata(fromHTML html: String, pageURL: URL, title: String? = nil) -> [String: String] {
        let links = anchorTexts(fromHTML: html)
        let tags = linkTexts(links, markers: ["tag", "tags"])
        let categories = linkTexts(links, markers: ["category", "categories"])
        let author = firstLinkText(links, markers: ["author", "model", "models", "cosplayer", "cosplayers"])
        let slug = storySlug(from: pageURL) ?? contentSlug(from: pageURL) ?? pageURL.deletingPathExtension().lastPathComponent
        let contentType = contentType(from: pageURL)
        let resolvedTitle = title ?? Self.title(fromHTML: html, pageURL: pageURL)

        return DownloadMetadata.clean([
            "artist": author,
            "author": author,
            "creator": author,
            "uploader": author,
            "channel": author,
            "series": resolvedTitle,
            "category": categories.isEmpty ? contentType : categories.joined(separator: ", "),
            "tag": tags.joined(separator: ", "),
            "tags": tags.joined(separator: ", "),
            "slug": slug,
            "content_id": slug,
            "type": contentType,
            "site": "HentaiCosplay",
            "title": resolvedTitle
        ])
    }

    static func downloadMetadata(fromHTML html: String, pageURL: URL, title: String, mediaType: String, mediaCount: Int, mediaURL: URL?) -> [String: String] {
        var metadata = pageMetadata(fromHTML: html, pageURL: pageURL, title: title)
        metadata["media_type"] = mediaType
        metadata["media_count"] = String(mediaCount)
        if mediaType == "image" {
            metadata["image_count"] = String(mediaCount)
        } else if mediaType == "video" {
            metadata["video_count"] = String(mediaCount)
        }
        metadata["url"] = pageURL.absoluteString
        metadata["source_url"] = pageURL.absoluteString
        metadata["page_url"] = pageURL.absoluteString
        if let mediaURL {
            let format = mediaFormat(for: mediaURL)
            metadata["format"] = format
            metadata["media_format"] = format
            metadata["media_url"] = mediaURL.absoluteString
            if mediaType == "image" {
                metadata["image_url"] = mediaURL.absoluteString
            } else if mediaType == "video" {
                metadata["video_url"] = mediaURL.absoluteString
            }
        }
        return DownloadMetadata.clean(metadata)
    }

    static func assetMetadata(for url: URL, pageMetadata: [String: String], pageURL: URL, index: Int) -> [String: String] {
        let format = mediaFormat(for: url)
        let mediaType = ["mp4", "m3u8", "webm", "mov", "m4v"].contains(format) ? "video" : "image"
        let contentID = pageMetadata["content_id"] ?? ""
        return DownloadMetadata.clean([
            "artist": pageMetadata["artist"] ?? "",
            "author": pageMetadata["author"] ?? "",
            "creator": pageMetadata["creator"] ?? "",
            "uploader": pageMetadata["uploader"] ?? "",
            "channel": pageMetadata["channel"] ?? "",
            "series": pageMetadata["series"] ?? pageMetadata["title"] ?? "",
            "category": pageMetadata["category"] ?? mediaType,
            "tag": pageMetadata["tag"] ?? "",
            "tags": pageMetadata["tags"] ?? "",
            "slug": pageMetadata["slug"] ?? "",
            "content_id": contentID,
            "id": contentID,
            "media_id": contentID.isEmpty ? String(index) : "\(contentID)-\(index)",
            "page": String(index),
            "position": String(index),
            "content_type": pageMetadata["type"] ?? "",
            "type": mediaType,
            "media_type": mediaType,
            "site": "HentaiCosplay",
            "title": pageMetadata["title"] ?? "",
            "format": format,
            "media_format": format,
            "image_url": mediaType == "image" ? url.absoluteString : "",
            "video_url": mediaType == "video" ? url.absoluteString : "",
            "media_url": url.absoluteString,
            "source_url": url.absoluteString,
            "page_url": pageURL.absoluteString
        ])
    }

    private static func storySlug(from url: URL) -> String? {
        let parts = pathParts(from: url)
        guard let index = parts.firstIndex(where: { $0.lowercased() == "story" }),
              index + 1 < parts.count else {
            return nil
        }
        return parts[index + 1]
    }

    private static func storyRootURL(from url: URL) -> URL? {
        guard let slug = storySlug(from: url) else { return nil }
        var components = URLComponents()
        components.scheme = url.scheme ?? "https"
        components.host = url.host
        components.path = "/story/\(slug)/"
        return components.url
    }

    private static func contentSlug(from url: URL) -> String? {
        let parts = pathParts(from: url)
        for marker in ["image", "video"] {
            guard let index = parts.firstIndex(where: { $0.lowercased() == marker }),
                  index + 1 < parts.count else {
                continue
            }
            return parts[index + 1]
        }
        return nil
    }

    private static func contentType(from url: URL) -> String {
        let path = url.path.lowercased()
        if path.contains("/video/") { return "video" }
        if path.contains("/image/") { return "image" }
        if path.contains("/story/") { return "story" }
        return ""
    }

    private static func pageNumber(from url: URL) -> Int {
        let parts = pathParts(from: url)
        guard let index = parts.firstIndex(where: { $0.lowercased() == "page" }),
              index + 1 < parts.count,
              let number = Int(parts[index + 1]) else {
            return 1
        }
        return number
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

    private static func anchorTexts(fromHTML html: String) -> [(href: String, text: String)] {
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
            (url.host?.lowercased().contains("hentai") ?? false) ||
            (url.host?.lowercased().contains("porn-images") ?? false)
    }

    private static func pathParts(from url: URL) -> [String] {
        url.path.split(separator: "/").map { String($0).removingPercentEncoding ?? String($0) }
    }

    private static func cleanTitle(_ raw: String, fallback: String) -> String {
        var title = decodeHTML(stripTags(raw))
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmed
        for suffix in [
            " - Hentai Cosplay",
            " | Hentai Cosplay",
            " - hentai-cosplays.com",
            " | hentai-cosplays.com",
            " - porn-images-xxx.com",
            " | porn-images-xxx.com"
        ] {
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
        supportedDomains.contains { domain in
            host == domain || host.hasSuffix("." + domain)
        }
    }

    private static func canonicalHost(for host: String) -> String {
        if host == "hentai-cosplays.com" || host.hasSuffix(".hentai-cosplays.com") {
            return "hentai-cosplays.com"
        }
        if host == "hentai-cosplays.test" || host.hasSuffix(".hentai-cosplays.test") {
            return "hentai-cosplays.test"
        }
        return host
    }

    private static func canonicalPath(_ path: String) -> String {
        let parts = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        var output: [String] = []
        var index = 0
        while index < parts.count {
            let part = parts[index]
            let next = index + 1 < parts.count ? parts[index + 1] : ""
            if ["page", "attachment"].contains(part.lowercased()),
               !next.isEmpty,
               next.allSatisfy(\.isNumber) {
                index += 2
                continue
            }
            output.append(part)
            index += 1
        }

        guard !output.isEmpty else { return "/" }
        return "/" + output.joined(separator: "/") + "/"
    }

    private static let supportedDomains = [
        "hentai-cosplays.com",
        "porn-images-xxx.com",
        "hentai-img.com",
        "porn-video-xxx.com",
        "hentai-cosplays.test",
        "porn-images-xxx.test",
        "hentai-img.test",
        "porn-video-xxx.test"
    ]
}
