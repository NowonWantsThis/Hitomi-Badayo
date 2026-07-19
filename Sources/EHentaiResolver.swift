import Foundation

private actor EHentaiImagePageRateLimiter {
    private let minimumInterval: TimeInterval
    private var nextRequestTime: TimeInterval = 0

    init(minimumInterval: TimeInterval) {
        self.minimumInterval = max(0, minimumInterval)
    }

    func wait() async throws {
        let now = ProcessInfo.processInfo.systemUptime
        let scheduled = max(now, nextRequestTime)
        nextRequestTime = scheduled + minimumInterval
        let delay = scheduled - now
        guard delay > 0 else { return }
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
    }
}

private struct EHentaiImagePageEntry {
    var pageURL: URL
    var thumbnailURL: URL?
}

final class EHentaiResolver {
    private let maxGalleryPages = 1_000
    private let maxImagePages = 40_000
#if TESTING
    private static let galleryPageDelayNanoseconds: UInt64 = 0
    private static let imagePageRateLimiter = EHentaiImagePageRateLimiter(minimumInterval: 0)
#else
    private static let galleryPageDelayNanoseconds: UInt64 = 2_000_000_000
    private static let imagePageRateLimiter = EHentaiImagePageRateLimiter(minimumInterval: 2)
#endif

    func canResolve(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(),
              Self.isSupportedHost(host),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return false
        }

        return Self.galleryID(from: url) != nil || Self.imagePageID(from: url) != nil
    }

    func resolve(
        _ url: URL,
        headers: HTTPRequestOptions = HTTPRequestOptions(),
        preferOriginal: Bool = false,
        preferJapaneseTitle: Bool = false
    ) async throws -> ResolvedDownload {
        if Self.imagePageID(from: url) != nil {
            let referer = headers.referer ?? Self.siteRootURL(for: url)?.absoluteString
            try await Self.imagePageRateLimiter.wait()
            let html = try await HTTPClient.shared.string(from: url, referer: referer, userAgent: headers.userAgent)
            let imagePage = await Self.refreshedImagePageIfNeeded(html: html, pageURL: url, referer: referer, userAgent: headers.userAgent)
            let title = Self.imageTitle(fromHTML: imagePage.html, pageURL: imagePage.pageURL)
            let metadata = Self.imageMetadata(pageURL: imagePage.pageURL, title: title)
            let asset = try Self.imageAsset(
                fromHTML: imagePage.html,
                pageURL: imagePage.pageURL,
                galleryMetadata: metadata,
                userAgent: headers.userAgent,
                preferOriginal: preferOriginal
            )
            return ResolvedDownload(
                title: title,
                folderName: "\(Self.siteName(for: url)) \(title)".sanitizedFilename(maxLength: 120),
                assets: [asset],
                metadata: metadata
            )
        }

        guard let gallery = Self.galleryID(from: url),
              let firstURL = Self.galleryPageURL(for: gallery, sourceURL: url, page: 0) else {
            throw NativeDownloadError.invalidURL(url.absoluteString)
        }

        let firstHTML = try await HTTPClient.shared.string(
            from: firstURL,
            referer: headers.referer ?? Self.siteRootURL(for: firstURL)?.absoluteString,
            userAgent: headers.userAgent
        )
        let title = Self.galleryTitle(
            fromHTML: firstHTML,
            pageURL: firstURL,
            preferJapanese: preferJapaneseTitle
        )
        var baseMetadata = Self.galleryMetadata(fromHTML: firstHTML, pageURL: firstURL, title: title, gallery: gallery)
        var imagePages = Self.imagePageEntries(fromHTML: firstHTML, galleryID: gallery.id, baseURL: firstURL)
        let maxPage = min(Self.maxGalleryPageNumber(fromHTML: firstHTML, gallery: gallery, baseURL: firstURL), maxGalleryPages - 1)

        if maxPage > 0 {
            for page in 1...maxPage {
                guard let pageURL = Self.galleryPageURL(for: gallery, sourceURL: url, page: page) else { continue }
                if Self.galleryPageDelayNanoseconds > 0 {
                    try await Task.sleep(nanoseconds: Self.galleryPageDelayNanoseconds)
                }
                let html = try await HTTPClient.shared.string(from: pageURL, referer: firstURL.absoluteString, userAgent: headers.userAgent)
                imagePages.append(contentsOf: Self.imagePageEntries(fromHTML: html, galleryID: gallery.id, baseURL: pageURL))
            }
        }

        imagePages = Self.uniqueImagePageEntries(imagePages).prefix(maxImagePages).map { $0 }
        if let thumbnail = imagePages.compactMap(\.thumbnailURL).first {
            baseMetadata["thumbnail"] = thumbnail.absoluteString
            baseMetadata["thumbnail_url"] = thumbnail.absoluteString
            baseMetadata["thumbnail_referer"] = firstURL.absoluteString
        }
        let assets = Self.lazyImageAssets(
            imagePages,
            galleryMetadata: baseMetadata,
            galleryURL: firstURL,
            headers: headers,
            preferOriginal: preferOriginal
        )

        guard !assets.isEmpty else {
            throw NativeDownloadError.noFiles
        }

        baseMetadata["media_count"] = String(assets.count)
        baseMetadata["image_count"] = String(assets.count)
        baseMetadata["asset_resolution"] = "lazy"

        return ResolvedDownload(
            title: title,
            folderName: "\(Self.siteName(for: url)) \(title)".sanitizedFilename(maxLength: 120),
            assets: assets,
            metadata: DownloadMetadata.clean(baseMetadata)
        )
    }

    private static func lazyImageAssets(
        _ entries: [EHentaiImagePageEntry],
        galleryMetadata: [String: String],
        galleryURL: URL,
        headers: HTTPRequestOptions,
        preferOriginal: Bool
    ) -> [ResolvedAsset] {
        entries.enumerated().map { offset, entry in
            let page = imagePageID(from: entry.pageURL)?.page ?? offset + 1
            var metadata = galleryMetadata
            metadata["page"] = String(page)
            metadata["position"] = String(page)
            metadata["format"] = "jpg"
            metadata["media_format"] = "jpg"
            metadata["type"] = "image"
            metadata["media_type"] = "image"
            metadata["page_url"] = entry.pageURL.absoluteString
            metadata["source_url"] = entry.pageURL.absoluteString
            metadata["ehentai_image_page_url"] = entry.pageURL.absoluteString
            metadata["ehentai_gallery_url"] = galleryURL.absoluteString
            metadata["ehentai_lazy_asset"] = "true"
            metadata["ehentai_prefer_original"] = preferOriginal ? "true" : "false"
            metadata["asset_concurrency_override"] = "1"
            metadata["continue_asset_failures"] = "true"
            if let thumbnailURL = entry.thumbnailURL {
                metadata["thumbnail"] = thumbnailURL.absoluteString
                metadata["thumbnail_url"] = thumbnailURL.absoluteString
                metadata["thumbnail_referer"] = galleryURL.absoluteString
            }
            return ResolvedAsset(
                remoteURL: entry.pageURL,
                filename: String(format: "%04d.jpg", page),
                metadata: DownloadMetadata.clean(metadata),
                referer: galleryURL.absoluteString,
                userAgent: headers.userAgent
            )
        }
    }

    static func galleryID(from url: URL) -> (id: String, token: String)? {
        let parts = normalizedPathParts(from: url)
        guard parts.count >= 3,
              ["g", "mpv"].contains(parts[0].lowercased()),
              parts[1].range(of: #"^[0-9]+$"#, options: .regularExpression) != nil else {
            return nil
        }

        let token = parts[2].trimmed
        guard !token.isEmpty else { return nil }
        return (parts[1], token)
    }

    static func imagePageID(from url: URL) -> (galleryID: String, page: Int?)? {
        let parts = normalizedPathParts(from: url)
        guard parts.count >= 3,
              parts[0].lowercased() == "s" else {
            return nil
        }

        let marker = parts[2]
        let pieces = marker.split(separator: "-", maxSplits: 1).map(String.init)
        guard let galleryID = pieces.first,
              galleryID.range(of: #"^[0-9]+$"#, options: .regularExpression) != nil else {
            return nil
        }

        let page = pieces.count > 1 ? Int(pieces[1].filter { $0.isNumber }) : nil
        return (galleryID, page)
    }

    static func galleryPageURL(for gallery: (id: String, token: String), sourceURL: URL, page: Int) -> URL? {
        guard var components = URLComponents(url: sourceURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.path = usesLoFiPath(sourceURL) ? "/lofi/g/\(gallery.id)/\(gallery.token)/" : "/g/\(gallery.id)/\(gallery.token)/"
        components.fragment = nil
        components.queryItems = page > 0 ? [URLQueryItem(name: "p", value: String(page))] : nil
        return components.url
    }

    static func imagePageURLs(fromHTML html: String, galleryID: String, baseURL: URL) -> [URL] {
        imagePageEntries(fromHTML: html, galleryID: galleryID, baseURL: baseURL).map(\.pageURL)
    }

    private static func imagePageEntries(
        fromHTML html: String,
        galleryID: String,
        baseURL: URL
    ) -> [EHentaiImagePageEntry] {
        var thumbnailsByPage: [String: URL] = [:]
        if let regex = try? NSRegularExpression(
            pattern: #"<a\b([^>]*)>(.*?)</a>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) {
            let range = NSRange(html.startIndex..<html.endIndex, in: html)
            for match in regex.matches(in: html, range: range) {
                guard let attributesRange = Range(match.range(at: 1), in: html),
                      let bodyRange = Range(match.range(at: 2), in: html) else {
                    continue
                }
                let anchorValues = attributeValues(from: String(html[attributesRange]))
                guard let href = anchorValues["href"],
                      let pageURL = absoluteURL(href, baseURL: baseURL),
                      isSupportedHost(pageURL.host?.lowercased() ?? ""),
                      imagePageID(from: pageURL)?.galleryID == galleryID else {
                    continue
                }
                let body = String(html[bodyRange])
                guard let imageRegex = try? NSRegularExpression(
                    pattern: #"<img\b([^>]*)>"#,
                    options: [.caseInsensitive, .dotMatchesLineSeparators]
                ),
                      let imageMatch = imageRegex.firstMatch(
                        in: body,
                        range: NSRange(body.startIndex..<body.endIndex, in: body)
                      ),
                      let imageAttributesRange = Range(imageMatch.range(at: 1), in: body) else {
                    continue
                }
                let imageValues = attributeValues(from: String(body[imageAttributesRange]))
                if let source = imageSource(from: imageValues, baseURL: baseURL),
                   let thumbnailURL = absoluteURL(source, baseURL: baseURL) {
                    thumbnailsByPage[URLIdentity.normalize(pageURL.absoluteString)] = thumbnailURL
                }
            }
        }

        var entries: [EHentaiImagePageEntry] = []
        for href in candidateURLStrings(fromHTML: html) {
            guard let url = absoluteURL(href, baseURL: baseURL),
                  isSupportedHost(url.host?.lowercased() ?? ""),
                  imagePageID(from: url)?.galleryID == galleryID else {
                continue
            }
            entries.append(EHentaiImagePageEntry(
                pageURL: url,
                thumbnailURL: thumbnailsByPage[URLIdentity.normalize(url.absoluteString)]
            ))
        }
        return uniqueImagePageEntries(entries)
    }

    private static func uniqueImagePageEntries(
        _ values: [EHentaiImagePageEntry]
    ) -> [EHentaiImagePageEntry] {
        var seen = Set<String>()
        return values.filter { entry in
            seen.insert(URLIdentity.normalize(entry.pageURL.absoluteString)).inserted
        }
    }

    static func maxGalleryPageNumber(fromHTML html: String, gallery: (id: String, token: String), baseURL: URL) -> Int {
        let galleryPrefixes = Set([
            "/g/\(gallery.id)/\(gallery.token)/",
            "/mpv/\(gallery.id)/\(gallery.token)/",
            "/lofi/g/\(gallery.id)/\(gallery.token)/",
            "/lofi/mpv/\(gallery.id)/\(gallery.token)/"
        ])
        var pages = Set<Int>()

        for href in candidateURLStrings(fromHTML: html) {
            guard let url = absoluteURL(href, baseURL: baseURL),
                  isSupportedHost(url.host?.lowercased() ?? ""),
                  galleryPrefixes.contains(url.path),
                  let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else {
                continue
            }

            for item in queryItems where item.name == "p" {
                if let value = item.value, let page = Int(value), page >= 0 {
                    pages.insert(page)
                }
            }
        }

        let normalizedHTML = html.replacingOccurrences(of: "\\/", with: "/")
        for prefix in galleryPrefixes {
            let escapedPrefix = NSRegularExpression.escapedPattern(for: prefix)
            if let regex = try? NSRegularExpression(pattern: escapedPrefix + #"\?[^"'<>\s]*?p=([0-9]+)"#, options: [.caseInsensitive]) {
                let range = NSRange(normalizedHTML.startIndex..<normalizedHTML.endIndex, in: normalizedHTML)
                for match in regex.matches(in: normalizedHTML, range: range) {
                    guard let capture = Range(match.range(at: 1), in: normalizedHTML),
                          let page = Int(normalizedHTML[capture]),
                          page >= 0 else {
                        continue
                    }
                    pages.insert(page)
                }
            }
        }

        if let count = galleryImageCount(fromHTML: html), count > 0 {
            pages.insert(max((count - 1) / 40, 0))
        }

        return pages.max() ?? 0
    }

    static func imageAsset(
        fromHTML html: String,
        pageURL: URL,
        galleryMetadata: [String: String] = [:],
        userAgent: String? = nil,
        preferOriginal: Bool = false
    ) throws -> ResolvedAsset {
        guard let remote = imageURL(
            fromHTML: html,
            pageURL: pageURL,
            preferOriginal: preferOriginal
        ) else {
            throw NativeDownloadError.noFiles
        }

        let page = imagePageID(from: pageURL)?.page
        return ResolvedAsset(
            remoteURL: remote,
            filename: imageFilename(for: remote, page: page),
            metadata: assetMetadata(for: remote, pageURL: pageURL, galleryMetadata: galleryMetadata),
            referer: pageURL.absoluteString,
            userAgent: userAgent
        )
    }

    static func isLazyImageAsset(_ asset: ResolvedAsset) -> Bool {
        asset.metadata["ehentai_lazy_asset"] == "true" &&
            asset.metadata["ehentai_image_page_url"]?.isEmpty == false
    }

    static func resolveLazyImageAsset(_ asset: ResolvedAsset) async throws -> ResolvedAsset {
        guard isLazyImageAsset(asset),
              let rawPageURL = asset.metadata["ehentai_image_page_url"],
              let pageURL = URL(string: rawPageURL) else {
            return asset
        }
        let galleryURL = asset.metadata["ehentai_gallery_url"]
            .flatMap(URL.init(string:))
        let referer = galleryURL?.absoluteString ?? asset.referer ?? pageURL.absoluteString
        try await imagePageRateLimiter.wait()
        let html = try await HTTPClient.shared.string(
            from: pageURL,
            referer: referer,
            userAgent: asset.userAgent,
            retryLimitOverride: 0
        )
        let imagePage = await refreshedImagePageIfNeeded(
            html: html,
            pageURL: pageURL,
            referer: pageURL.absoluteString,
            userAgent: asset.userAgent
        )
        var resolved = try imageAsset(
            fromHTML: imagePage.html,
            pageURL: imagePage.pageURL,
            galleryMetadata: asset.metadata,
            userAgent: asset.userAgent,
            preferOriginal: asset.metadata["ehentai_prefer_original"] == "true"
        )
        resolved.metadata = DownloadMetadata.clean(
            asset.metadata.merging(resolved.metadata) { _, resolvedValue in resolvedValue }
        )
        resolved.metadata["ehentai_lazy_asset"] = "false"
        resolved.metadata["asset_concurrency_override"] = "1"
        resolved.metadata["continue_asset_failures"] = "true"
        return resolved
    }

    static func imageLimitRefreshURL(fromHTML html: String, pageURL: URL) -> URL? {
        guard isImageLimitPage(fromHTML: html),
              let token = imageLimitToken(fromHTML: html),
              var components = URLComponents(url: pageURL, resolvingAgainstBaseURL: false) else {
            return nil
        }

        var queryItems = components.queryItems?.filter { $0.name.lowercased() != "nl" } ?? []
        queryItems.append(URLQueryItem(name: "nl", value: token))
        components.queryItems = queryItems
        return components.url
    }

    static func galleryTitle(fromHTML html: String, pageURL: URL, preferJapanese: Bool = false) -> String {
        let preferredTitle = elementText(id: preferJapanese ? "gj" : "gn", fromHTML: html)
        let fallbackTitle = elementText(id: preferJapanese ? "gn" : "gj", fromHTML: html)
        let title = preferredTitle ??
            fallbackTitle ??
            metaContent(from: html, names: ["og:title", "twitter:title"]) ??
            titleTag(fromHTML: html) ??
            galleryID(from: pageURL)?.id ??
            "Gallery"
        return cleanTitle(title)
    }

    static func imageTitle(fromHTML html: String, pageURL: URL) -> String {
        let title = metaContent(from: html, names: ["og:title", "twitter:title"]) ??
            titleTag(fromHTML: html) ??
            imagePageID(from: pageURL).map { "Image \($0.galleryID)-\($0.page.map(String.init) ?? "1")" } ??
            "Image"
        return cleanTitle(title)
    }

    static func galleryMetadata(
        fromHTML html: String,
        pageURL: URL,
        title: String? = nil,
        gallery: (id: String, token: String)? = nil,
        assetCount: Int? = nil
    ) -> [String: String] {
        let grouped = tagMetadataGroups(fromHTML: html)
        let galleryInfo = gallery ?? galleryID(from: pageURL)
        let artist = grouped["artist"] ?? grouped["group"] ?? ""
        let category = grouped["category"] ?? categoryText(fromHTML: html) ?? ""
        let imageCount = galleryImageCount(fromHTML: html) ?? assetCount
        let pageCount = galleryInfo.map { maxGalleryPageNumber(fromHTML: html, gallery: $0, baseURL: pageURL) + 1 }
        let tagText = joinMetadata([
            grouped["female"],
            grouped["male"],
            grouped["mixed"],
            grouped["misc"],
            grouped["other"]
        ])
        return DownloadMetadata.clean([
            "artist": artist,
            "author": artist,
            "creator": artist,
            "uploader": artist,
            "channel": artist,
            "language": grouped["language"] ?? "",
            "parody": grouped["parody"] ?? "",
            "series": grouped["parody"] ?? "",
            "category": category,
            "character": grouped["character"] ?? "",
            "tag": tagText,
            "tags": tagText.isEmpty ? joinMetadata(grouped.values.map { Optional($0) }) : tagText,
            "gallery_id": galleryInfo?.id ?? "",
            "gallery_token": galleryInfo?.token ?? "",
            "id": galleryInfo?.id ?? "",
            "site": siteName(for: pageURL),
            "title": title ?? galleryTitle(fromHTML: html, pageURL: pageURL),
            "type": "gallery",
            "media_type": "image",
            "media_count": imageCount.map(String.init) ?? "",
            "image_count": imageCount.map(String.init) ?? "",
            "page_count": pageCount.map(String.init) ?? ""
        ])
    }

    private static func imageMetadata(pageURL: URL, title: String? = nil) -> [String: String] {
        let pageInfo = imagePageID(from: pageURL)
        return DownloadMetadata.clean([
            "gallery_id": pageInfo?.galleryID ?? "",
            "id": pageInfo?.galleryID ?? "",
            "page": pageInfo?.page.map(String.init) ?? "",
            "site": siteName(for: pageURL),
            "title": title ?? "",
            "type": "image",
            "media_type": "image",
            "media_count": "1",
            "image_count": "1"
        ])
    }

    private static func assetMetadata(for remote: URL, pageURL: URL, galleryMetadata: [String: String]) -> [String: String] {
        let pageInfo = imagePageID(from: pageURL)
        let galleryID = galleryMetadata["gallery_id"] ?? pageInfo?.galleryID ?? ""
        let page = pageInfo?.page.map(String.init) ?? galleryMetadata["page"] ?? ""
        let format = mediaFormat(for: remote)
        return DownloadMetadata.clean([
            "artist": galleryMetadata["artist"] ?? "",
            "author": galleryMetadata["author"] ?? "",
            "creator": galleryMetadata["creator"] ?? "",
            "uploader": galleryMetadata["uploader"] ?? "",
            "channel": galleryMetadata["channel"] ?? "",
            "language": galleryMetadata["language"] ?? "",
            "parody": galleryMetadata["parody"] ?? "",
            "series": galleryMetadata["series"] ?? galleryMetadata["parody"] ?? "",
            "category": galleryMetadata["category"] ?? "",
            "character": galleryMetadata["character"] ?? "",
            "tag": galleryMetadata["tag"] ?? "",
            "tags": galleryMetadata["tags"] ?? "",
            "gallery_id": galleryID,
            "gallery_token": galleryMetadata["gallery_token"] ?? "",
            "id": galleryMetadata["id"] ?? galleryID,
            "site": galleryMetadata["site"] ?? siteName(for: pageURL),
            "title": galleryMetadata["title"] ?? "",
            "type": "image",
            "media_type": "image",
            "page": page,
            "position": page,
            "format": format,
            "media_format": format,
            "image_url": remote.absoluteString,
            "media_url": remote.absoluteString,
            "source_url": remote.absoluteString,
            "page_url": pageURL.absoluteString
        ])
    }

    private static func imageURL(fromHTML html: String, pageURL: URL, preferOriginal: Bool) -> URL? {
        let original = originalImageURL(fromHTML: html, pageURL: pageURL)
        if preferOriginal, let original {
            return original
        }

        guard let regex = try? NSRegularExpression(
            pattern: #"<img\b([^>]*)>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return nil
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        var fallback: URL?
        for match in regex.matches(in: html, range: range) {
            guard let attributesRange = Range(match.range(at: 1), in: html) else { continue }
            let values = attributeValues(from: String(html[attributesRange]))
            let id = values["id"]?.lowercased()
            let src = imageSource(from: values, baseURL: pageURL)
            guard let src, let remote = absoluteURL(src, baseURL: pageURL) else { continue }

            guard !isBandwidthLimitImageURL(remote) else {
                continue
            }
            if id == "img" {
                return remote
            }
            if fallback == nil, isLikelyImageURL(remote) {
                fallback = remote
            }
        }

        if let meta = metaContent(from: html, names: ["og:image", "og:image:url", "twitter:image", "twitter:image:src"]),
           let remote = absoluteURL(meta, baseURL: pageURL),
           isLikelyImageURL(remote) {
            return remote
        }

        return fallback ?? original
    }

    private static func refreshedImagePageIfNeeded(html: String, pageURL: URL, referer: String?, userAgent: String?) async -> (html: String, pageURL: URL) {
        var currentHTML = html
        var currentURL = pageURL
        for _ in 0..<3 {
            guard let refreshURL = imageLimitRefreshURL(fromHTML: currentHTML, pageURL: currentURL) else {
                return (currentHTML, currentURL)
            }
            do {
                try await imagePageRateLimiter.wait()
                currentHTML = try await HTTPClient.shared.string(
                    from: refreshURL,
                    referer: referer ?? currentURL.absoluteString,
                    userAgent: userAgent,
                    retryLimitOverride: 0
                )
                currentURL = refreshURL
            } catch {
                return (currentHTML, currentURL)
            }
        }
        return (currentHTML, currentURL)
    }

    private static func isImageLimitPage(fromHTML html: String) -> Bool {
        let lowered = html.lowercased()
        return lowered.contains("509.gif") ||
            lowered.contains("509 bandwidth exceeded") ||
            lowered.contains("bandwidth exceeded")
    }

    private static func imageLimitToken(fromHTML html: String) -> String? {
        firstCapture(patterns: [
            #"\bnl\s*\(\s*['"]([^'"]+)['"]\s*\)"#,
            #"\bnl\s*=\s*['"]([^'"]+)['"]"#,
            #"\bnl\s*[.=]\s*['"]([^'"]+)['"]"#,
            #"[?&]nl=([A-Za-z0-9_-]+)"#
        ], in: html).map { decodeHTML($0).trimmed }.flatMap { $0.isEmpty ? nil : $0 }
    }

    private static func originalImageURL(fromHTML html: String, pageURL: URL) -> URL? {
        guard let regex = try? NSRegularExpression(
            pattern: #"<a\b([^>]*)>(.*?)</a>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return nil
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        for match in regex.matches(in: html, range: range) {
            guard let attributesRange = Range(match.range(at: 1), in: html),
                  let textRange = Range(match.range(at: 2), in: html) else {
                continue
            }
            let values = attributeValues(from: String(html[attributesRange]))
            let text = decodeHTML(stripTags(String(html[textRange]))).lowercased()
            guard let href = values["href"],
                  text.contains("download original") || href.lowercased().contains("fullimg.php") else {
                continue
            }
            if let remote = absoluteURL(href, baseURL: pageURL),
               isLikelyImageURL(remote) {
                return remote
            }
        }
        return nil
    }

    private static func imageSource(from attributes: [String: String], baseURL: URL) -> String? {
        for key in ["data-original", "data-full", "data-src", "data-lazy-src", "data-url"] {
            guard let raw = attributes[key],
                  let url = absoluteURL(raw, baseURL: baseURL),
                  isLikelyImageURL(url) else {
                continue
            }
            return raw
        }

        for key in ["srcset", "data-srcset"] {
            guard let raw = attributes[key],
                  let candidate = srcsetImageSource(raw, baseURL: baseURL) else {
                continue
            }
            return candidate
        }

        if let raw = attributes["src"],
           let url = absoluteURL(raw, baseURL: baseURL),
           isLikelyImageURL(url) {
            return raw
        }
        return nil
    }

    private static func srcsetImageSource(_ raw: String, baseURL: URL) -> String? {
        var best: (source: String, score: Double)?
        for part in raw.split(separator: ",") {
            let tokens = part.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            guard let source = tokens.first,
                  let url = absoluteURL(source, baseURL: baseURL),
                  isLikelyImageURL(url) else {
                continue
            }
            var score = 1.0
            for token in tokens.dropFirst() {
                let lowered = token.lowercased()
                if lowered.hasSuffix("w"),
                   let width = Double(lowered.dropLast()) {
                    score = max(score, width)
                } else if lowered.hasSuffix("x"),
                          let density = Double(lowered.dropLast()) {
                    score = max(score, density * 1_000)
                }
            }
            if best == nil || score > best!.score {
                best = (source, score)
            }
        }
        return best?.source
    }

    private static func imageFilename(for url: URL, page: Int?) -> String {
        let ext = mediaFormat(for: url)
        let index = page ?? 1
        return String(format: "%04d.%@", index, ext).sanitizedFilename(maxLength: 180)
    }

    private static func mediaFormat(for url: URL) -> String {
        let ext = url.lastPathComponent.lowercased() == "fullimg.php" ? "" : url.pathExtension.lowercased()
        if ext == "jpeg" {
            return "jpg"
        }
        return ext.isEmpty ? "jpg" : ext
    }

    private static func galleryImageCount(fromHTML html: String) -> Int? {
        let text = decodeHTML(stripTags(html))
        guard let textValue = firstCapture(patterns: [
            #"\bof\s+([0-9,]+)\s+images\b"#,
            #"\b(?:showing\s+)?[0-9,]+\s*[-–]\s*[0-9,]+\s+of\s+([0-9,]+)\b"#
        ], in: text) else {
            return nil
        }
        return Int(textValue.replacingOccurrences(of: ",", with: ""))
    }

    private static func tagMetadataGroups(fromHTML html: String) -> [String: String] {
        guard let regex = try? NSRegularExpression(
            pattern: #"<a\b([^>]*)>(.*?)</a>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return [:]
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        var grouped: [String: [String]] = [:]
        for match in regex.matches(in: html, range: range) {
            guard let attributesRange = Range(match.range(at: 1), in: html),
                  let textRange = Range(match.range(at: 2), in: html) else {
                continue
            }
            let values = attributeValues(from: String(html[attributesRange]))
            guard let namespace = tagNamespace(from: values) else { continue }
            var text = cleanTitle(String(html[textRange]))
            if text.lowercased().hasPrefix("\(namespace):") {
                text = String(text.dropFirst(namespace.count + 1)).trimmed
            }
            guard !text.isEmpty else { continue }
            if grouped[namespace]?.contains(text) != true {
                grouped[namespace, default: []].append(text)
            }
        }

        return grouped.mapValues { $0.joined(separator: ", ") }
    }

    private static func tagNamespace(from attributes: [String: String]) -> String? {
        let known = Set(["artist", "group", "language", "parody", "character", "female", "male", "mixed", "misc", "other", "category"])
        let candidates = [
            attributes["id"] ?? "",
            attributes["href"]?.removingPercentEncoding ?? attributes["href"] ?? ""
        ]

        for candidate in candidates {
            let lowered = candidate.lowercased()
            let namespace = firstCapture(
                patterns: [
                    #"ta_([a-z0-9_]+):"#,
                    #"(?:/tag/|[?&]f_search=)([a-z0-9_]+):"#
                ],
                in: lowered
            )?
            .replacingOccurrences(of: "_", with: " ")
            .trimmed

            if let namespace, known.contains(namespace) {
                return namespace
            }
        }
        return nil
    }

    private static func categoryText(fromHTML html: String) -> String? {
        elementText(id: "gdc", fromHTML: html)
    }

    private static func joinMetadata(_ values: [String?]) -> String {
        var seen = Set<String>()
        var result: [String] = []
        for value in values {
            for part in (value ?? "").split(separator: ",") {
                let cleaned = String(part).trimmed
                guard !cleaned.isEmpty, !seen.contains(cleaned.lowercased()) else { continue }
                seen.insert(cleaned.lowercased())
                result.append(cleaned)
            }
        }
        return result.joined(separator: ", ")
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

    private static func candidateURLStrings(fromHTML html: String) -> [String] {
        var values = anchorHREFs(fromHTML: html)
        let attributePattern = #"\b(?:href|data-href|data-url|data-page-url|data-link)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>"']+))"#
        if let regex = try? NSRegularExpression(pattern: attributePattern, options: [.caseInsensitive]) {
            let range = NSRange(html.startIndex..<html.endIndex, in: html)
            for match in regex.matches(in: html, range: range) {
                for group in 1...3 {
                    guard let capture = Range(match.range(at: group), in: html) else { continue }
                    values.append(String(html[capture]))
                    break
                }
            }
        }

        let normalizedHTML = html.replacingOccurrences(of: "\\/", with: "/")
        let urlPattern = #"https?://(?:www\.)?(?:e-hentai|exhentai)\.org/(?:lofi/)?(?:s|g|mpv)/[^"'<>\s]+"#
        if let regex = try? NSRegularExpression(pattern: urlPattern, options: [.caseInsensitive]) {
            let range = NSRange(normalizedHTML.startIndex..<normalizedHTML.endIndex, in: normalizedHTML)
            for match in regex.matches(in: normalizedHTML, range: range) {
                guard let capture = Range(match.range(at: 0), in: normalizedHTML) else { continue }
                values.append(String(normalizedHTML[capture]))
            }
        }

        var seen = Set<String>()
        var output: [String] = []
        for raw in values {
            let cleaned = decodeHTML(raw)
                .replacingOccurrences(of: "\\/", with: "/")
                .trimmed
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'(),;"))
            guard !cleaned.isEmpty,
                  !seen.contains(cleaned) else {
                continue
            }
            seen.insert(cleaned)
            output.append(cleaned)
        }
        return output
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

    private static func elementText(id: String, fromHTML html: String) -> String? {
        let pattern = #"<([A-Za-z0-9]+)\b[^>]*\bid\s*=\s*["']\#(NSRegularExpression.escapedPattern(for: id))["'][^>]*>(.*?)</\1>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, range: range),
              let capture = Range(match.range(at: 2), in: html) else {
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
        guard let regex = try? NSRegularExpression(
            pattern: #"<title\b[^>]*>(.*?)</title>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return nil
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, range: range),
              let titleRange = Range(match.range(at: 1), in: html) else {
            return nil
        }
        return decodeHTML(stripTags(String(html[titleRange]))).trimmed
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

    private static func absoluteURL(_ raw: String, baseURL: URL) -> URL? {
        let value = raw.trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "\"'(),;"))
        guard !value.isEmpty,
              !value.lowercased().hasPrefix("javascript:"),
              !value.lowercased().hasPrefix("data:"),
              !value.lowercased().hasPrefix("blob:") else {
            return nil
        }

        if value.hasPrefix("//") {
            return URL(string: "\(baseURL.scheme ?? "https"):\(value)")
        }
        return URL(string: value, relativeTo: baseURL)?.absoluteURL
    }

    private static func siteRootURL(for url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.path = "/"
        components.query = nil
        components.fragment = nil
        return components.url
    }

    private static func uniqueURLs(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        var result: [URL] = []
        for url in urls {
            let normalized = URLIdentity.normalize(url.absoluteString)
            guard !seen.contains(normalized) else { continue }
            seen.insert(normalized)
            result.append(url)
        }
        return result
    }

    private static func pathParts(from url: URL) -> [String] {
        url.path.split(separator: "/").map { String($0).removingPercentEncoding ?? String($0) }
    }

    private static func normalizedPathParts(from url: URL) -> [String] {
        let parts = pathParts(from: url)
        if parts.first?.lowercased() == "lofi" {
            return Array(parts.dropFirst())
        }
        return parts
    }

    private static func usesLoFiPath(_ url: URL) -> Bool {
        pathParts(from: url).first?.lowercased() == "lofi"
    }

    private static func cleanTitle(_ raw: String) -> String {
        var title = decodeHTML(stripTags(raw))
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmed
        for suffix in [" - E-Hentai Galleries", " - ExHentai.org", " | E-Hentai Galleries"] {
            if title.lowercased().hasSuffix(suffix.lowercased()) {
                title.removeLast(suffix.count)
                title = title.trimmed
            }
        }
        return title.isEmpty ? "E-Hentai Gallery" : title.sanitizedFilename(maxLength: 120)
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
            let numberText = radix == 16 ? String(digits.dropFirst()) : digits
            if let scalarValue = UInt32(numberText, radix: radix),
               let scalar = UnicodeScalar(scalarValue) {
                output.replaceSubrange(whole, with: String(Character(scalar)))
            }
        }
        return output
    }

    private static func isLikelyImageURL(_ url: URL) -> Bool {
        guard !isBandwidthLimitImageURL(url) else {
            return false
        }
        let ext = url.pathExtension.lowercased()
        let path = url.path.lowercased()
        return ext.isEmpty ||
            path.contains("fullimg.php") ||
            ["jpg", "jpeg", "png", "gif", "webp", "avif"].contains(ext)
    }

    private static func isBandwidthLimitImageURL(_ url: URL) -> Bool {
        url.lastPathComponent.lowercased() == "509.gif"
    }

    private static func isSupportedHost(_ host: String) -> Bool {
        host == "e-hentai.org" ||
            host == "www.e-hentai.org" ||
            host == "exhentai.org" ||
            host == "www.exhentai.org" ||
            host == "e-hentai.test" ||
            host == "exhentai.test" ||
            host.hasSuffix(".e-hentai.test") ||
            host.hasSuffix(".exhentai.test")
    }

    private static func siteName(for url: URL) -> String {
        let host = url.host?.lowercased() ?? ""
        return host.contains("exhentai") ? "ExHentai" : "E-Hentai"
    }
}
