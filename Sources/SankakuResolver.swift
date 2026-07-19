import Foundation

enum SankakuSection: String {
    case chan
    case idol
    case www
    case app

    var displayName: String {
        switch self {
        case .chan: return "chan"
        case .idol: return "idol"
        case .www: return "www"
        case .app: return "app"
        }
    }
}

struct SankakuResolvedMedia {
    var remoteURL: URL
    var postID: String
    var mediaIndex: Int = 0
    var title: String?
    var referer: String
}

final class SankakuResolver {
    func canResolve(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(),
              Self.section(for: host) != nil,
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return false
        }
        let path = url.path.lowercased()
        guard !path.contains("/login") else {
            return false
        }
        return true
    }

    func resolve(
        _ url: URL,
        headers: HTTPRequestOptions = HTTPRequestOptions(),
        assetLimit: Int? = nil
    ) async throws -> ResolvedDownload {
        let html = try await HTTPClient.shared.string(from: url, referer: headers.referer, userAgent: headers.userAgent)
        let isListing = Self.postID(from: url) == nil && !Self.isWWWPage(url)
        let parsedHTML = isListing ? Self.listingHTMLByRemovingImprovedBanners(html) : html
        if Self.isLoginRequiredHTML(parsedHTML) {
            throw NativeDownloadError.unsupported("Sankaku login is required for this page.")
        }

        if Self.isWWWPage(url), Self.postID(from: url) == nil {
            if let resolved = try? Self.resolvedWWWDownload(fromHTML: html, pageURL: url),
               !resolved.assets.isEmpty {
                return resolved
            }
        }

        if Self.postID(from: url) != nil {
            return try Self.resolvedPostDownload(fromHTML: html, pageURL: url)
        }

        return try await resolveListing(
            firstHTML: parsedHTML,
            sourceURL: url,
            headers: headers,
            assetLimit: assetLimit
        )
    }

    private func resolveListing(
        firstHTML: String,
        sourceURL: URL,
        headers: HTTPRequestOptions,
        assetLimit: Int?
    ) async throws -> ResolvedDownload {
        let section = Self.section(for: sourceURL.host?.lowercased() ?? "") ?? .chan
        let title = Self.listTitle(fromHTML: firstHTML, pageURL: sourceURL, section: section)
        let normalizedSource = URLIdentity.normalize(sourceURL.absoluteString)
        let limit = assetLimit.flatMap { $0 > 0 ? $0 : nil }

        var pageURL: URL? = sourceURL
        var seenPages = Set<String>()
        var seenPosts = Set<String>()
        var seenPostIDs = Set<String>()
        var media: [SankakuResolvedMedia] = []
        var seenMedia = Set<String>()

        while let currentPageURL = pageURL {
            try Task.checkCancellation()
            let normalizedPage = URLIdentity.normalize(currentPageURL.absoluteString)
            guard seenPages.insert(normalizedPage).inserted else { break }

            let rawHTML = normalizedPage == normalizedSource
                ? firstHTML
                : try await HTTPClient.shared.string(
                    from: currentPageURL,
                    referer: sourceURL.absoluteString,
                    userAgent: headers.userAgent
                )
            let html = Self.listingHTMLByRemovingImprovedBanners(rawHTML)
            if Self.isLoginRequiredHTML(html) {
                throw NativeDownloadError.unsupported("Sankaku login is required for this page.")
            }

            let pagePostURLs = Self.postURLs(fromHTML: html, baseURL: currentPageURL)
            for postURL in pagePostURLs {
                try Task.checkCancellation()
                let normalizedPost = URLIdentity.normalize(postURL.absoluteString)
                guard seenPosts.insert(normalizedPost).inserted else { continue }
                if let postID = Self.postID(from: postURL) {
                    seenPostIDs.insert(postID)
                }

                let postHTML = try await HTTPClient.shared.string(
                    from: postURL,
                    referer: sourceURL.absoluteString,
                    userAgent: headers.userAgent
                )
                guard let postMedia = try? Self.media(fromPostHTML: postHTML, pageURL: postURL) else {
                    continue
                }
                for item in postMedia {
                    let normalized = URLIdentity.normalize(item.remoteURL.absoluteString)
                    guard seenMedia.insert(normalized).inserted else { continue }
                    media.append(item)
                    if let limit, media.count >= limit { break }
                }
                if let limit, media.count >= limit { break }
            }

            if let limit, media.count >= limit { break }

            let nextPage = Self.paginationURLs(fromHTML: html, baseURL: currentPageURL)
                .first { !seenPages.contains(URLIdentity.normalize($0.absoluteString)) }
            if let nextPage {
                pageURL = nextPage
                continue
            }

            if pagePostURLs.isEmpty, Self.isPremiumListingErrorHTML(html) {
                guard !seenPostIDs.isEmpty else {
                    throw NativeDownloadError.unsupported("Sankaku login is required for this page.")
                }
                pageURL = Self.premiumRangeBypassURL(
                    baseURL: currentPageURL,
                    postIDs: Array(seenPostIDs)
                )
                continue
            }

            pageURL = nil
        }

        if media.isEmpty {
            media = Self.mediaCandidates(fromHTML: firstHTML, pageURL: sourceURL).enumerated().map { offset, remote in
                SankakuResolvedMedia(
                    remoteURL: remote,
                    postID: Self.postID(from: sourceURL) ?? "post",
                    mediaIndex: offset,
                    title: title,
                    referer: sourceURL.absoluteString
                )
            }
        }

        return try Self.resolvedListDownload(title: title, section: section, media: media, pageURL: sourceURL)
    }

    static func resolvedPostDownload(fromHTML html: String, pageURL: URL) throws -> ResolvedDownload {
        let media = try media(fromPostHTML: html, pageURL: pageURL)
        guard !media.isEmpty else {
            throw NativeDownloadError.noFiles
        }
        let title = postTitle(fromHTML: html, pageURL: pageURL)
        let section = section(for: pageURL.host?.lowercased() ?? "") ?? .chan
        return ResolvedDownload(
            title: title,
            folderName: "Sankaku \(section.displayName) \(title)".sanitizedFilename(maxLength: 120),
            assets: media.enumerated().map { offset, item in asset(for: item, offset: offset) },
            metadata: sankakuMetadata(
                title: title,
                section: section,
                type: "post",
                postID: postID(from: pageURL) ?? postID(fromHTML: html) ?? media.first?.postID ?? "",
                tags: tagNames(fromHTML: html, pageURL: pageURL),
                media: media,
                pageURL: pageURL
            )
        )
    }

    static func resolvedListDownload(title: String, section: SankakuSection, media: [SankakuResolvedMedia], pageURL: URL? = nil) throws -> ResolvedDownload {
        guard !media.isEmpty else {
            throw NativeDownloadError.noFiles
        }
        return ResolvedDownload(
            title: title,
            folderName: "Sankaku \(section.displayName) \(title)".sanitizedFilename(maxLength: 120),
            assets: media.enumerated().map { offset, item in asset(for: item, offset: offset) },
            metadata: sankakuMetadata(
                title: title,
                section: section,
                type: "list",
                postID: "",
                tags: pageURL.map { tagNames(fromHTML: "", pageURL: $0) } ?? [],
                media: media,
                pageURL: pageURL
            )
        )
    }

    static func resolvedWWWDownload(fromHTML html: String, pageURL: URL) throws -> ResolvedDownload {
        let title = postTitle(fromHTML: html, pageURL: pageURL)
        let urls = wwwImageURLs(fromHTML: html, pageURL: pageURL)
        guard !urls.isEmpty else {
            throw NativeDownloadError.noFiles
        }
        let media = urls.enumerated().map { offset, remote in
            SankakuResolvedMedia(
                remoteURL: remote,
                postID: postID(from: pageURL) ?? "post",
                mediaIndex: offset,
                title: title,
                referer: pageURL.absoluteString
            )
        }
        return ResolvedDownload(
            title: title,
            folderName: "Sankaku www \(title)".sanitizedFilename(maxLength: 120),
            assets: media.enumerated().map { offset, item in asset(for: item, offset: offset) },
            metadata: sankakuMetadata(
                title: title,
                section: .www,
                type: "article",
                postID: slug(from: pageURL),
                tags: tagNames(fromHTML: html, pageURL: pageURL),
                media: media,
                pageURL: pageURL
            )
        )
    }

    static func media(fromPostHTML html: String, pageURL: URL) throws -> [SankakuResolvedMedia] {
        if isPremiumHTML(html), mediaCandidates(fromHTML: html, pageURL: pageURL).isEmpty {
            throw NativeDownloadError.unsupported("Sankaku Plus content requires a logged-in cookie.")
        }
        if isLoginRequiredHTML(html) {
            throw NativeDownloadError.unsupported("Sankaku login is required for this post.")
        }

        let postID = postID(from: pageURL) ?? postID(fromHTML: html) ?? "post"
        let title = postTitle(fromHTML: html, pageURL: pageURL)
        let urls = mediaCandidates(fromHTML: html, pageURL: pageURL)
        return urls.enumerated().map { offset, remote in
            SankakuResolvedMedia(
                remoteURL: remote,
                postID: postID,
                mediaIndex: offset,
                title: offset == 0 ? title : nil,
                referer: pageURL.absoluteString
            )
        }
    }

    static func postID(from url: URL) -> String? {
        let patterns = [
            #"/post/show/([0-9]+)"#,
            #"/posts/([0-9]+)"#
        ]
        for pattern in patterns {
            if let id = firstCapture(patterns: [pattern], in: url.path) {
                return id
            }
        }
        return queryValue("id", in: url) ?? queryValue("post_id", in: url)
    }

    static func postID(fromHTML html: String) -> String? {
        firstCapture(patterns: [
            #"hidden_post_id["']?\s+value\s*=\s*["']?([0-9]+)"#,
            #"\bpost_id\s*[:=]\s*["']?([0-9]+)"#,
            #"/post/show/([0-9]+)"#,
            #"/posts/([0-9]+)"#
        ], in: html)
    }

    static func postURL(id: String, sourceURL: URL) -> URL {
        let section = section(for: sourceURL.host?.lowercased() ?? "") ?? .chan
        var components = URLComponents()
        components.scheme = sourceURL.scheme ?? "https"
        components.host = canonicalHost(for: sourceURL, section: section)
        components.path = section == .app || section == .www || sourceURL.path.contains("/posts/") ? "/posts/\(id)" : "/post/show/\(id)"
        return components.url!
    }

    static func tagSearchURLString(section: SankakuSection, tags: String, testHost: Bool = false) -> String? {
        let encodedTags = encodedTagQuery(tags)
        guard !encodedTags.isEmpty else { return nil }
        let host: String
        switch section {
        case .chan:
            host = testHost ? "chan.sankakucomplex.test" : "chan.sankakucomplex.com"
        case .idol:
            host = testHost ? "idol.sankakucomplex.test" : "idol.sankakucomplex.com"
        case .www:
            host = testHost ? "www.sankakucomplex.test" : "www.sankakucomplex.com"
        case .app:
            host = testHost ? "sankaku.test" : "sankaku.app"
        }
        return "https://\(host)/?tags=\(encodedTags)"
    }

    static func postURLs(fromHTML html: String, baseURL: URL) -> [URL] {
        var urls: [URL] = []
        var seen = Set<String>()

        func append(id: String) {
            let url = postURL(id: id, sourceURL: baseURL)
            let normalized = URLIdentity.normalize(url.absoluteString)
            guard !seen.contains(normalized) else { return }
            seen.insert(normalized)
            urls.append(url)
        }

        for href in anchorHREFs(fromHTML: html) {
            guard let url = absoluteURL(href, baseURL: baseURL),
                  let id = postID(from: url) else {
                continue
            }
            append(id: id)
        }

        for id in firstCaptures(patterns: [
            #"/post/show/([0-9]+)"#,
            #"/posts/([0-9]+)"#,
            #"\bpost_id\s*[:=]\s*["']?([0-9]+)"#,
            #"\bdata-(?:post-)?id\s*=\s*["']?([0-9]+)"#
        ], in: html) {
            append(id: id)
        }

        return urls
    }

    static func listingHTMLByRemovingImprovedBanners(_ html: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: #"<div\b[^>]*>|</div\s*>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return html
        }

        let fullRange = NSRange(html.startIndex..<html.endIndex, in: html)
        var output = ""
        var cursor = html.startIndex
        var suppressedDepth = 0

        for match in regex.matches(in: html, range: fullRange) {
            guard let tokenRange = Range(match.range, in: html) else { continue }
            let token = String(html[tokenRange])
            let isClosing = token.range(of: #"^</div"#, options: [.regularExpression, .caseInsensitive]) != nil

            if suppressedDepth > 0 {
                suppressedDepth += isClosing ? -1 : 1
                if suppressedDepth == 0 {
                    cursor = tokenRange.upperBound
                }
                continue
            }

            guard !isClosing else { continue }
            let classes = Set(
                (attributeValues(from: token)["class"] ?? "")
                    .lowercased()
                    .split(whereSeparator: \Character.isWhitespace)
                    .map(String.init)
            )
            guard classes.contains("carousel-data-ai") else { continue }
            output.append(contentsOf: html[cursor..<tokenRange.lowerBound])
            if token.hasSuffix("/>") {
                cursor = tokenRange.upperBound
            } else {
                suppressedDepth = 1
            }
        }

        if suppressedDepth == 0 {
            output.append(contentsOf: html[cursor...])
        }
        return output
    }

    static func paginationURLs(fromHTML html: String, baseURL: URL) -> [URL] {
        var urls: [URL] = []
        var seen = Set<String>()

        func append(_ url: URL) {
            guard let host = url.host?.lowercased(),
                  section(for: host) != nil,
                  URLIdentity.normalize(url.absoluteString) != URLIdentity.normalize(baseURL.absoluteString) else {
                return
            }
            let normalized = URLIdentity.normalize(url.absoluteString)
            guard !seen.contains(normalized) else { return }
            seen.insert(normalized)
            urls.append(url)
        }

        for href in anchorHREFs(fromHTML: html) {
            guard let url = absoluteURL(href, baseURL: baseURL),
                  hasPaginationMarker(url) else {
                continue
            }
            append(url)
        }

        for attrs in tagAttributes(tag: "a", html: html) + tagAttributes(tag: "link", html: html) {
            let values = attributeValues(from: attrs)
            let className = values["class"]?.lowercased() ?? ""
            let rel = values["rel"]?.lowercased() ?? ""
            if className.contains("next-page-url") || rel.contains("next") {
                if let href = values["href"], let url = absoluteURL(href, baseURL: baseURL) {
                    append(url)
                }
            }
        }

        for attrs in tagAttributes(tag: "div", html: html) {
            let values = attributeValues(from: attrs)
            let className = values["class"]?.lowercased() ?? ""
            guard className.contains("pagination"),
                  let href = values["next-page-url"],
                  let url = absoluteURL(href, baseURL: baseURL) else {
                continue
            }
            append(url)
        }

        return urls.sorted { lhs, rhs in
            pageSortValue(lhs) < pageSortValue(rhs)
        }
    }

    static func premiumRangeBypassURL(baseURL: URL, postIDs: [String]) -> URL? {
        guard let minimumPostID = postIDs.filter({ !$0.isEmpty }).min() else {
            return nil
        }
        let tags = queryValue("tags", in: baseURL) ?? ""
        let strippedTags = tags
            .replacingOccurrences(
                of: #"(?:^|\s+)id_range:<[0-9A-Za-z]+"#,
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmed
        let updatedTags = [strippedTags, "id_range:<\(minimumPostID)"]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return urlByRemovingQueryItems(
            ["tags", "page", "next"],
            appending: [("tags", updatedTags)],
            in: baseURL
        )
    }

    static func mediaCandidates(fromHTML html: String, pageURL: URL) -> [URL] {
        let normalizedHTML = decodeURLString(decodeHTML(html))
        var strong: [String] = []
        var fallback: [String] = []

        for tag in ["source", "video"] {
            for attrs in tagAttributes(tag: tag, html: normalizedHTML) {
                let values = attributeValues(from: attrs)
                strong.appendIfPresent(values["src"] ?? values["data-src"])
            }
        }

        for attrs in tagAttributes(tag: "a", html: normalizedHTML) {
            let values = attributeValues(from: attrs)
            let marker = [values["id"], values["class"], values["href"]].compactMap { $0?.lowercased() }.joined(separator: " ")
            if marker.contains("highres") || marker.contains("original") || marker.contains("download") {
                strong.appendIfPresent(values["href"])
            }
        }

        for attrs in tagAttributes(tag: "img", html: normalizedHTML) {
            let values = attributeValues(from: attrs)
            let idClass = [values["id"], values["class"]].compactMap { $0?.lowercased() }.joined(separator: " ")
            for key in ["data-file-url", "data-large-file-url", "data-original", "data-src"] {
                strong.appendIfPresent(values[key])
            }
            let raw = values["src"]
            if idClass.contains("image") || idClass.contains("post-content") || idClass.contains("post_content") {
                fallback.appendIfPresent(raw)
            }
        }

        strong.append(contentsOf: firstCaptures(patterns: [
            #""(?:file_url|fileUrl|large_file_url|largeFileUrl|video_url|videoUrl|contentUrl|highres)"\s*:\s*"([^"]+)""#,
            #"'(?:file_url|fileUrl|large_file_url|largeFileUrl|video_url|videoUrl|contentUrl|highres)'\s*:\s*'([^']+)'"#,
            #"\b(?:file_url|large_file_url|video_url)\s*=\s*["']([^"']+)["']"#
        ], in: normalizedHTML))

        fallback.append(contentsOf: metaMediaURLs(fromHTML: normalizedHTML))
        fallback.append(contentsOf: firstCaptures(patterns: [
            #""(?:sample_url|sampleUrl|preview_url|previewUrl)"\s*:\s*"([^"]+)""#,
            #"'(?:sample_url|sampleUrl|preview_url|previewUrl)'\s*:\s*'([^']+)'"#
        ], in: normalizedHTML))

        let rawCandidates = strong.isEmpty ? fallback : strong
        return uniqueMediaURLs(rawCandidates, baseURL: pageURL)
    }

    static func wwwImageURLs(fromHTML html: String, pageURL: URL) -> [URL] {
        let normalizedHTML = decodeURLString(decodeHTML(html))
        let scopes = firstCaptures(patterns: [
            #"<(?:div|section|article)\b[^>]*\bclass\s*=\s*["'][^"']*entry-content[^"']*["'][^>]*>(.*?)</(?:div|section|article)>"#
        ], in: normalizedHTML)
        let searchHTML = scopes.isEmpty ? [normalizedHTML] : scopes
        var raw: [String] = []

        for scope in searchHTML {
            for attrs in tagAttributes(tag: "img", html: scope) {
                let values = attributeValues(from: attrs)
                raw.appendIfPresent(values["data-lazy-src"] ?? values["data-src"] ?? values["data-original"] ?? values["src"])
            }
            for href in anchorHREFs(fromHTML: scope) {
                raw.append(href)
            }
        }

        return uniqueMediaURLs(raw, baseURL: pageURL).filter { isImage($0) }
    }

    static func postTitle(fromHTML html: String, pageURL: URL) -> String {
        let title = elementText(pattern: #"<[^>]+\bclass\s*=\s*["'][^"']*(?:entry-title|post-title|title)[^"']*["'][^>]*>(.*?)</[^>]+>"#, in: html) ??
            metaContent(from: html, names: ["og:title", "twitter:title"]) ??
            titleTag(fromHTML: html) ??
            postID(from: pageURL) ??
            "Sankaku Post"
        return cleanTitle(title, fallback: "Sankaku \(postID(from: pageURL) ?? "post")")
    }

    static func listTitle(fromHTML html: String, pageURL: URL, section: SankakuSection) -> String {
        let tags = queryValue("tags", in: pageURL)?.replacingOccurrences(of: "+", with: " ").trimmed
        if let tags, !tags.isEmpty {
            return "[\(section.displayName)] \(tags)".sanitizedFilename(maxLength: 120)
        }
        let title = metaContent(from: html, names: ["og:title", "twitter:title"]) ??
            titleTag(fromHTML: html) ??
            "Sankaku \(section.displayName)"
        return cleanTitle(title, fallback: "Sankaku \(section.displayName)")
    }

    static func sankakuMetadata(title: String, section: SankakuSection, type: String, postID: String, tags: [String], media: [SankakuResolvedMedia], pageURL: URL?) -> [String: String] {
        let postIDs = uniqueValues(media.map(\.postID).filter { $0 != "post" })
        let effectivePostID = postID.isEmpty ? postIDs.first ?? "" : postID
        let tagText = joinMetadata(tags)
        let imageCount = media.filter { isImage($0.remoteURL) }.count
        let videoCount = media.filter { isVideo($0.remoteURL) }.count
        return DownloadMetadata.clean([
            "series": section.displayName,
            "category": section == .www ? "article" : "booru",
            "section": section.displayName,
            "type": type,
            "media_type": mediaType(imageCount: imageCount, videoCount: videoCount),
            "post_id": effectivePostID,
            "gallery_id": effectivePostID.isEmpty ? slug(from: pageURL) : effectivePostID,
            "media_id": effectivePostID,
            "post_count": postIDs.isEmpty ? "" : String(postIDs.count),
            "media_count": String(media.count),
            "image_count": imageCount > 0 ? String(imageCount) : "",
            "video_count": videoCount > 0 ? String(videoCount) : "",
            "tag": tagText,
            "tags": tagText,
            "search": tagText,
            "slug": slug(from: pageURL),
            "site": "Sankaku",
            "title": title
        ])
    }

    static func tagNames(fromHTML html: String, pageURL: URL?) -> [String] {
        var tags = pageURL.map { queryTags(from: $0) } ?? []
        let normalizedHTML = decodeHTML(html)

        for attrs in tagAttributes(tag: "a", html: normalizedHTML) {
            let values = attributeValues(from: attrs)
            let href = values["href"] ?? ""
            if let baseURL = pageURL ?? URL(string: "https://sankaku.app/"),
               let hrefURL = absoluteURL(href, baseURL: baseURL) {
                tags.append(contentsOf: queryTags(from: hrefURL))
            }
            if let tag = firstCapture(patterns: [#"/tags/([^/?#]+)"#, #"/tag/([^/?#]+)"#], in: href) {
                tags.append(tag)
            }
        }

        tags.append(contentsOf: firstCaptures(patterns: [
            #""tag_string"\s*:\s*"([^"]+)""#,
            #"'tag_string'\s*:\s*'([^']+)'"#,
            #"\btags\s*[:=]\s*["']([^"']+)["']"#
        ], in: normalizedHTML).flatMap(splitTags))
        return uniqueValues(tags)
    }

    static func isLoginRequiredHTML(_ html: String) -> Bool {
        let lowered = html.lowercased()
        return lowered.contains("login.sankakucomplex.com/login") ||
            lowered.contains("/login") && lowered.contains("password") && lowered.contains("sankaku")
    }

    static func isPremiumHTML(_ html: String) -> Bool {
        let lowered = html.lowercased()
        return lowered.contains("post-content-notification") ||
            lowered.contains("sankaku plus") ||
            lowered.contains("post-premium-browsing_error")
    }

    static func isPremiumListingErrorHTML(_ html: String) -> Bool {
        html.lowercased().contains("post-premium-browsing_error")
    }

    static func isWWWPage(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return section(for: host) == .www
    }

    static func section(for host: String) -> SankakuSection? {
        let lowered = host.lowercased()
        if lowered == "chan.sankakucomplex.com" || lowered == "chan.sankakucomplex.test" {
            return .chan
        }
        if lowered == "idol.sankakucomplex.com" || lowered == "idol.sankakucomplex.test" {
            return .idol
        }
        if lowered == "www.sankakucomplex.com" || lowered == "sankakucomplex.com" || lowered == "www.sankakucomplex.test" || lowered == "sankakucomplex.test" {
            return .www
        }
        if lowered == "sankaku.app" || lowered.hasSuffix(".sankaku.app") || lowered == "sankaku.test" || lowered.hasSuffix(".sankaku.test") {
            return .app
        }
        return nil
    }

    private static func asset(for item: SankakuResolvedMedia, offset: Int) -> ResolvedAsset {
        let ext = mediaExtension(for: item.remoteURL)
        let suffix: String
        if item.postID == "post" {
            suffix = String(format: "%04d", offset + 1)
        } else if item.mediaIndex == 0 {
            suffix = item.postID
        } else {
            suffix = String(format: "%@_p%02d", item.postID, item.mediaIndex)
        }
        return ResolvedAsset(
            remoteURL: item.remoteURL,
            filename: "\(suffix).\(ext)".sanitizedFilename(maxLength: 180),
            metadata: assetMetadata(for: item, offset: offset, mediaID: suffix, format: ext),
            referer: item.referer
        )
    }

    private static func assetMetadata(for item: SankakuResolvedMedia, offset: Int, mediaID: String, format: String) -> [String: String] {
        let page = item.postID == "post" ? offset + 1 : item.mediaIndex + 1
        let pageText = String(page)
        let section = URL(string: item.referer)
            .flatMap { $0.host }
            .flatMap { section(for: $0.lowercased()) } ?? .chan
        let type = isVideo(item.remoteURL) ? "video" : "image"
        return DownloadMetadata.clean([
            "series": section.displayName,
            "category": section == .www ? "article" : "booru",
            "section": section.displayName,
            "episode": item.title ?? item.postID,
            "chapter": item.title ?? item.postID,
            "type": type,
            "media_type": type,
            "post_id": item.postID == "post" ? "" : item.postID,
            "gallery_id": item.postID == "post" ? mediaID : item.postID,
            "media_id": mediaID,
            "id": mediaID,
            "page": pageText,
            "position": String(offset + 1),
            "format": format,
            "media_format": format,
            "image_url": type == "image" ? item.remoteURL.absoluteString : "",
            "video_url": type == "video" ? item.remoteURL.absoluteString : "",
            "media_url": item.remoteURL.absoluteString,
            "source_url": item.remoteURL.absoluteString,
            "page_url": item.referer,
            "site": "Sankaku",
            "title": item.title ?? item.postID
        ])
    }

    private static func canonicalHost(for sourceURL: URL, section: SankakuSection) -> String {
        let host = sourceURL.host?.lowercased() ?? ""
        if host.hasSuffix(".test") || host == "sankaku.test" {
            switch section {
            case .chan: return "chan.sankakucomplex.test"
            case .idol: return "idol.sankakucomplex.test"
            case .www: return "www.sankakucomplex.test"
            case .app: return "sankaku.test"
            }
        }
        switch section {
        case .chan: return "chan.sankakucomplex.com"
        case .idol: return "idol.sankakucomplex.com"
        case .www: return "www.sankakucomplex.com"
        case .app: return "sankaku.app"
        }
    }

    private static func uniqueMediaURLs(_ rawValues: [String], baseURL: URL) -> [URL] {
        var urls: [URL] = []
        var seen = Set<String>()
        for raw in rawValues {
            guard let remote = absoluteURL(decodeURLString(raw), baseURL: baseURL),
                  isLikelyMedia(remote) else {
                continue
            }
            let normalized = URLIdentity.normalize(remote.absoluteString)
            guard !seen.contains(normalized) else { continue }
            seen.insert(normalized)
            urls.append(remote)
        }
        return urls
    }

    private static func isLikelyMedia(_ url: URL) -> Bool {
        let lowered = url.absoluteString.lowercased()
        guard !lowered.contains("redirect.png"),
              !lowered.contains("/banner"),
              !lowered.contains("/avatar"),
              !lowered.contains("/logo"),
              !lowered.contains("blank.gif") else {
            return false
        }
        return ["jpg", "jpeg", "png", "gif", "webp", "mp4", "webm"].contains(mediaExtension(for: url)) ||
            lowered.contains("get.sankaku.plus")
    }

    private static func isImage(_ url: URL) -> Bool {
        ["jpg", "jpeg", "png", "gif", "webp"].contains(mediaExtension(for: url))
    }

    private static func isVideo(_ url: URL) -> Bool {
        ["mp4", "webm"].contains(mediaExtension(for: url))
    }

    private static func mediaType(imageCount: Int, videoCount: Int) -> String {
        if imageCount > 0, videoCount > 0 {
            return "mixed"
        }
        if videoCount > 0 {
            return "video"
        }
        return "image"
    }

    private static func queryTags(from url: URL) -> [String] {
        guard let raw = queryValue("tags", in: url), !raw.trimmed.isEmpty else {
            return []
        }
        return splitTags(raw)
    }

    private static func splitTags(_ raw: String) -> [String] {
        let decoded = (raw.removingPercentEncoding ?? raw)
            .replacingOccurrences(of: "+", with: " ")
            .replacingOccurrences(of: "%20", with: " ")
        return decoded
            .split(whereSeparator: { $0 == "," || $0 == " " || $0 == "\n" || $0 == "\t" })
            .map(String.init)
    }

    private static func encodedTagQuery(_ raw: String) -> String {
        let normalized = (raw.removingPercentEncoding ?? raw)
            .replacingOccurrences(of: "%20", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmed
        guard !normalized.isEmpty else { return "" }

        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~:")
        var encoded = ""
        for scalar in normalized.unicodeScalars {
            if scalar == " " || scalar == "\t" || scalar == "\n" || scalar == "," || scalar == ";" {
                if !encoded.hasSuffix("+") {
                    encoded.append("+")
                }
            } else if scalar == "+" {
                encoded.append("%2B")
            } else if allowed.contains(scalar) {
                encoded.append(String(scalar))
            } else {
                for byte in String(scalar).utf8 {
                    encoded.append(String(format: "%%%02X", byte))
                }
            }
        }
        return encoded.trimmingCharacters(in: CharacterSet(charactersIn: "+"))
    }

    private static func joinMetadata(_ values: [String]) -> String {
        uniqueValues(values).joined(separator: ", ")
    }

    private static func uniqueValues(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values {
            let cleaned = decodeHTML(value)
                .replacingOccurrences(of: "_", with: " ")
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

    private static func slug(from url: URL?) -> String {
        guard let url else { return "" }
        let parts = url.path.split(separator: "/").map { String($0).removingPercentEncoding ?? String($0) }
        return parts.last(where: { !$0.trimmed.isEmpty }) ?? ""
    }

    private static func mediaExtension(for url: URL) -> String {
        let absolute = url.absoluteString.lowercased()
        for ext in ["jpg", "jpeg", "png", "gif", "webp", "mp4", "webm"] {
            if absolute.range(of: #"\.\#(ext)(?:[?#]|$)"#, options: .regularExpression) != nil {
                return ext == "jpeg" ? "jpg" : ext
            }
        }
        let ext = url.pathExtension.lowercased()
        return ext == "jpeg" ? "jpg" : (ext.isEmpty ? "jpg" : ext)
    }

    private static func hasPaginationMarker(_ url: URL) -> Bool {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return items.contains { ["page", "next"].contains($0.name.lowercased()) }
    }

    private static func pageSortValue(_ url: URL) -> Int {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let page = components?.queryItems?.first { $0.name.lowercased() == "page" }?.value.flatMap(Int.init)
        let next = components?.queryItems?.first { $0.name.lowercased() == "next" }?.value.flatMap(Int.init)
        return page ?? next ?? Int.max
    }

    private static func urlByRemovingQueryItems(_ removedNames: Set<String>, appending additions: [(String, String)], in url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        let removed = Set(removedNames.map { $0.lowercased() })
        let pieces = (components.percentEncodedQuery ?? "")
            .split(separator: "&", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { piece in
                let rawName = piece.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? piece
                let name = rawName.removingPercentEncoding ?? rawName
                return !removed.contains(name.lowercased())
            }
        let appended = additions.map { "\($0.0)=\(percentEncodedQueryValue($0.1))" }
        let query = (pieces + appended).filter { !$0.isEmpty }.joined(separator: "&")
        components.percentEncodedQuery = query.isEmpty ? nil : query
        return components.url ?? url
    }

    private static func percentEncodedQueryValue(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        var encoded = ""
        for scalar in value.unicodeScalars {
            if allowed.contains(scalar) {
                encoded.append(String(scalar))
            } else {
                for byte in String(scalar).utf8 {
                    encoded.append(String(format: "%%%02X", byte))
                }
            }
        }
        return encoded
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

    private static func metaMediaURLs(fromHTML html: String) -> [String] {
        var urls: [String] = []
        let names: Set<String> = [
            "og:image", "og:image:url", "og:image:secure_url",
            "og:video", "og:video:url", "og:video:secure_url",
            "twitter:image", "twitter:image:src", "twitter:player:stream"
        ]
        guard let regex = try? NSRegularExpression(pattern: #"<meta\b([^>]*)>"#, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        for match in regex.matches(in: html, range: range) {
            guard let attributesRange = Range(match.range(at: 1), in: html) else { continue }
            let values = attributeValues(from: String(html[attributesRange]))
            let key = (values["property"] ?? values["name"] ?? values["itemprop"])?.lowercased()
            guard let key, names.contains(key),
                  let content = values["content"],
                  !content.trimmed.isEmpty else {
                continue
            }
            urls.append(content)
        }
        return urls
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

    private static func titleTag(fromHTML html: String) -> String? {
        elementText(pattern: #"<title\b[^>]*>(.*?)</title>"#, in: html)
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

    private static func firstCaptures(patterns: [String], in text: String) -> [String] {
        var values: [String] = []
        var seen = Set<String>()
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
                continue
            }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            for match in regex.matches(in: text, range: range) {
                guard let capture = Range(match.range(at: 1), in: text) else { continue }
                let value = String(text[capture])
                guard !seen.contains(value) else { continue }
                seen.insert(value)
                values.append(value)
            }
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

    private static func queryValue(_ name: String, in url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name.lowercased() == name.lowercased() }?
            .value
    }

    private static func decodeURLString(_ text: String) -> String {
        decodeHTML(text)
            .replacingOccurrences(of: "\\/", with: "/")
            .replacingOccurrences(of: "\\u002F", with: "/")
            .replacingOccurrences(of: "\\u0026", with: "&")
    }

    private static func cleanTitle(_ raw: String, fallback: String) -> String {
        var title = decodeHTML(stripTags(raw))
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmed
        for suffix in [
            " - Sankaku Complex",
            " | Sankaku Complex",
            " - Sankaku",
            " | Sankaku",
            " - chan.sankakucomplex.com",
            " | chan.sankakucomplex.com",
            " - idol.sankakucomplex.com",
            " | idol.sankakucomplex.com"
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
}

private extension Array where Element == String {
    mutating func appendIfPresent(_ value: String?) {
        guard let value, !value.trimmed.isEmpty else { return }
        append(value)
    }
}
