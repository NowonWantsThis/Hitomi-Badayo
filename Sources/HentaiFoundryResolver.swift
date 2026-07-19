import Foundation

final class HentaiFoundryResolver {
    private let maxGalleryPages = 100

    func canResolve(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(),
              Self.isSupportedHost(host),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return false
        }

        return Self.picturePageInfo(from: url) != nil || Self.galleryUsername(from: url) != nil
    }

    func resolve(
        _ url: URL,
        headers: HTTPRequestOptions = HTTPRequestOptions(),
        postLimit: Int? = nil
    ) async throws -> ResolvedDownload {
        let sourceURL = Self.canonicalContentURL(from: url) ?? url
        if Self.picturePageInfo(from: sourceURL) != nil {
            let html = try await HTTPClient.shared.string(from: sourceURL, referer: headers.referer, userAgent: headers.userAgent)
            return try Self.resolvedDownload(fromHTML: html, pageURL: sourceURL)
        }

        guard let username = Self.galleryUsername(from: sourceURL) else {
            throw NativeDownloadError.unsupported("Unsupported Hentai Foundry URL.")
        }
        return try await resolveGallery(
            username: username,
            sourceURL: sourceURL,
            headers: headers,
            postLimit: postLimit
        )
    }

    private func resolveGallery(
        username: String,
        sourceURL: URL,
        headers: HTTPRequestOptions,
        postLimit: Int?
    ) async throws -> ResolvedDownload {
        if let enterURL = Self.enterAgreementURL(sourceURL: sourceURL) {
            if let enterHTML = try? await HTTPClient.shared.string(from: enterURL, referer: headers.referer, userAgent: headers.userAgent) {
                try? await Self.applyGalleryFilters(
                    fromHTML: enterHTML,
                    enterURL: enterURL,
                    sourceURL: sourceURL,
                    userAgent: headers.userAgent
                )
            }
        }

        let galleryURL = Self.galleryURL(username: username, sourceURL: sourceURL)
        var pageURL: URL? = galleryURL
        var seenPages = Set<String>()
        var postURLs: [URL] = []
        var seenPosts = Set<String>()
        var firstHTML = ""
        var pageIndex = 0

        while let currentPageURL = pageURL, pageIndex < maxGalleryPages {
            try Task.checkCancellation()
            let pageIdentity = URLIdentity.normalize(currentPageURL.absoluteString)
            guard seenPages.insert(pageIdentity).inserted else { break }

            let html = try await HTTPClient.shared.string(
                from: currentPageURL,
                referer: pageIndex == 0 ? (headers.referer ?? sourceURL.absoluteString) : galleryURL.absoluteString,
                userAgent: headers.userAgent
            )
            if pageIndex == 0 {
                firstHTML = html
            }

            for postURL in Self.picturePageURLs(fromHTML: html, baseURL: currentPageURL, username: username) {
                let normalized = URLIdentity.normalize(postURL.absoluteString)
                guard !seenPosts.contains(normalized) else { continue }
                seenPosts.insert(normalized)
                postURLs.append(postURL)
            }

            if let nextURL = Self.nextGalleryPageURL(fromHTML: html, baseURL: currentPageURL, username: username),
               !seenPages.contains(URLIdentity.normalize(nextURL.absoluteString)) {
                pageURL = nextURL
            } else {
                pageURL = nil
            }

            pageIndex += 1
        }

        let finitePostLimit = postLimit.flatMap { $0 > 0 ? $0 : nil }
        let detailURLs = finitePostLimit.map { Array(postURLs.prefix($0)) } ?? postURLs
        var downloads: [(url: URL, resolved: ResolvedDownload)] = []
        for postURL in detailURLs {
            try Task.checkCancellation()
            let html = try await HTTPClient.shared.string(from: postURL, referer: galleryURL.absoluteString, userAgent: headers.userAgent)
            if let resolved = try? Self.resolvedDownload(fromHTML: html, pageURL: postURL) {
                downloads.append((postURL, resolved))
            }
        }

        return try Self.resolvedCollectionDownload(
            username: username,
            sourceURL: galleryURL,
            galleryHTML: firstHTML,
            postDownloads: downloads,
            listedPostCount: postURLs.count
        )
    }

    static func resolvedDownload(fromHTML html: String, pageURL: URL) throws -> ResolvedDownload {
        let sourceURL = canonicalPictureURL(from: pageURL) ?? pageURL
        let title = title(fromHTML: html, pageURL: sourceURL)
        let artist = artistName(fromHTML: html, pageURL: sourceURL) ?? picturePageInfo(from: sourceURL)?.username ?? ""
        let pictureID = picturePageInfo(from: sourceURL)?.id ?? ""
        let urls = mediaURLs(fromHTML: html, baseURL: sourceURL)
        guard !urls.isEmpty else {
            throw NativeDownloadError.noFiles
        }

        let assets = urls.enumerated().map { offset, remote in
            ResolvedAsset(
                remoteURL: remote,
                filename: filename(for: remote, index: offset + 1),
                metadata: assetMetadata(for: remote, pictureID: pictureID, artist: artist, title: title, pageURL: sourceURL, index: offset + 1),
                referer: sourceURL.absoluteString
            )
        }

        let folderBits = [artist, title].filter { !$0.trimmed.isEmpty }.joined(separator: " - ")
        return ResolvedDownload(
            title: title.sanitizedFilename(maxLength: 120),
            folderName: "HentaiFoundry \(folderBits.isEmpty ? title : folderBits)".sanitizedFilename(maxLength: 120),
            assets: assets,
            metadata: DownloadMetadata.clean([
                "artist": artist,
                "author": artist,
                "creator": artist,
                "user": artist,
                "username": artist,
                "uploader": artist,
                "channel": artist,
                "picture_id": pictureID,
                "gallery_id": artist,
                "slug": pageURL.lastPathComponent,
                "site": "Hentai Foundry",
                "title": title,
                "series": title,
                "type": "picture",
                "media_type": "image",
                "category": "image",
                "media_count": String(urls.count),
                "image_count": String(urls.count),
                "url": sourceURL.absoluteString,
                "source_url": sourceURL.absoluteString,
                "page_url": sourceURL.absoluteString
            ])
        )
    }

    static func resolvedCollectionDownload(
        username: String,
        sourceURL: URL,
        galleryHTML: String,
        postDownloads: [(url: URL, resolved: ResolvedDownload)],
        listedPostCount: Int? = nil
    ) throws -> ResolvedDownload {
        var assets: [ResolvedAsset] = []
        var seenFiles = Set<String>()

        for (postIndex, item) in postDownloads.enumerated() {
            for asset in item.resolved.assets {
                var filename = String(format: "%04d-%@", postIndex + 1, asset.filename).sanitizedFilename(maxLength: 180)
                if seenFiles.contains(filename.lowercased()) {
                    let ext = (filename as NSString).pathExtension
                    let base = (filename as NSString).deletingPathExtension
                    filename = ext.isEmpty
                        ? "\(base)-\(assets.count + 1)"
                        : "\(base)-\(assets.count + 1).\(ext)"
                }
                seenFiles.insert(filename.lowercased())
                var metadata = asset.metadata
                metadata["post_index"] = String(postIndex + 1)
                metadata["page"] = String(assets.count + 1)
                metadata["position"] = String(assets.count + 1)
                metadata["collection_position"] = String(assets.count + 1)
                assets.append(ResolvedAsset(
                    remoteURL: asset.remoteURL,
                    filename: filename,
                    metadata: metadata,
                    referer: asset.referer ?? item.url.absoluteString
                ))
            }
        }

        guard !assets.isEmpty else {
            throw NativeDownloadError.noFiles
        }

        let title = galleryTitle(fromHTML: galleryHTML, username: username)
        return ResolvedDownload(
            title: "\(title) (hentai-foundry_\(username))".sanitizedFilename(maxLength: 120),
            folderName: "HentaiFoundry \(username) - \(title)".sanitizedFilename(maxLength: 120),
            assets: assets,
            metadata: DownloadMetadata.clean([
                "artist": username,
                "author": username,
                "creator": username,
                "user": username,
                "username": username,
                "uploader": username,
                "channel": username,
                "type": "artist",
                "media_type": "image",
                "category": "image",
                "media_count": String(assets.count),
                "image_count": String(assets.count),
                "post_count": String(postDownloads.count),
                "listed_post_count": String(listedPostCount ?? postDownloads.count),
                "gallery_id": username,
                "slug": username,
                "site": "Hentai Foundry",
                "title": title,
                "url": sourceURL.absoluteString,
                "source_url": sourceURL.absoluteString,
                "page_url": sourceURL.absoluteString
            ])
        )
    }

    static func mediaURLs(fromHTML html: String, baseURL: URL) -> [URL] {
        let normalizedHTML = decodeHTML(html).replacingOccurrences(of: #"\/"#, with: "/")
        let blocks = classBlocks(in: normalizedHTML, className: "picBox")
        let searchSpace = blocks.isEmpty ? normalizedHTML : blocks.joined(separator: "\n")
        var candidates: [String] = []
        let originalSrcCandidates = captureGroupMatches(pattern: #"\.src\s*=\s*['"]([^'"]+)['"]"#, in: searchSpace)

        if originalSrcCandidates.isEmpty {
            candidates.append(contentsOf: imageCandidates(fromHTML: searchSpace))
            candidates.append(contentsOf: linkCandidates(fromHTML: searchSpace))
            candidates.append(contentsOf: mediaURLStrings(in: searchSpace))
        } else {
            candidates.append(contentsOf: originalSrcCandidates)
        }

        var urls: [URL] = []
        var seen = Set<String>()
        for candidate in candidates {
            guard let remote = absoluteURL(candidate, baseURL: baseURL),
                  isDownloadableMedia(remote) else {
                continue
            }
            let normalized = URLIdentity.normalize(remote.absoluteString)
            guard !seen.contains(normalized) else { continue }
            seen.insert(normalized)
            urls.append(remote)
        }
        return urls
    }

    static func picturePageURLs(fromHTML html: String, baseURL: URL, username: String? = nil) -> [URL] {
        let galleryBlocks = classBlocks(in: decodeHTML(html), className: "galleryViewTable")
        let galleryHTML = galleryBlocks.first ?? html
        return anchorEntries(fromHTML: galleryHTML).compactMap { anchor in
            guard let href = anchor.attributes["href"],
                  anchorHasClass(anchor, className: "thumbLink"),
                  let url = absoluteURL(href, baseURL: baseURL),
                  let canonical = canonicalPictureURL(from: url),
                  let info = picturePageInfo(from: canonical),
                  username == nil || info.username.caseInsensitiveCompare(username ?? "") == .orderedSame else {
                return nil
            }
            return canonical
        }.uniqueByNormalizedURL()
    }

    static func galleryPageURLs(fromHTML html: String, baseURL: URL, username: String) -> [URL] {
        nextGalleryPageURL(fromHTML: html, baseURL: baseURL, username: username).map { [$0] } ?? []
    }

    static func nextGalleryPageURL(fromHTML html: String, baseURL: URL, username: String) -> URL? {
        for listItem in tagBlocks(tag: "li", html: decodeHTML(html)) {
            let attributes = attributeValues(from: listItem.attributes)
            let classes = classTokens(attributes["class"])
            guard classes.contains("next") else { continue }

            for anchor in anchorEntries(fromHTML: listItem.body) {
                guard let href = anchor.attributes["href"],
                      let url = absoluteURL(href, baseURL: baseURL),
                      let galleryUser = galleryUsername(from: url),
                      galleryUser.caseInsensitiveCompare(username) == .orderedSame,
                      picturePageInfo(from: url) == nil else {
                    continue
                }
                return cleanedNavigationURL(url)
            }
        }
        return nil
    }

    static func canonicalContentURL(from url: URL) -> URL? {
        if let picture = canonicalPictureURL(from: url) {
            return picture
        }
        if let username = galleryUsername(from: url) {
            return galleryURL(username: username, sourceURL: url)
        }
        return nil
    }

    private static func canonicalPictureURL(from url: URL) -> URL? {
        guard picturePageInfo(from: url) != nil else { return nil }
        return cleanedContentURL(url)
    }

    static func picturePageInfo(from url: URL) -> (username: String, id: String)? {
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 4,
              parts[0].lowercased() == "pictures",
              parts[1].lowercased() == "user",
              !parts[2].isEmpty,
              Int(parts[3]) != nil else {
            return nil
        }
        return (parts[2], parts[3])
    }

    static func galleryUsername(from url: URL) -> String? {
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        if parts.count >= 2,
           parts[0].lowercased() == "user",
           !parts[1].isEmpty {
            return parts[1]
        }
        if parts.count == 3,
           parts[0].lowercased() == "pictures",
           parts[1].lowercased() == "user",
           !parts[2].isEmpty {
            return parts[2]
        }
        return nil
    }

    static func galleryURL(username: String, sourceURL: URL) -> URL {
        var components = URLComponents()
        components.scheme = sourceURL.scheme ?? "https"
        components.host = canonicalHost(for: sourceURL)
        components.path = "/pictures/user/\(username)"
        return components.url!
    }

    private static func enterAgreementURL(sourceURL: URL) -> URL? {
        var components = URLComponents()
        components.scheme = sourceURL.scheme ?? "https"
        components.host = canonicalHost(for: sourceURL)
        components.path = "/site/index"
        components.queryItems = [
            URLQueryItem(name: "enterAgree", value: "1"),
            URLQueryItem(name: "size", value: "1550")
        ]
        return components.url
    }

    private static func filterURL(sourceURL: URL) -> URL? {
        var components = URLComponents()
        components.scheme = sourceURL.scheme ?? "https"
        components.host = canonicalHost(for: sourceURL)
        components.path = "/site/filters"
        return components.url
    }

    private static func applyGalleryFilters(fromHTML html: String, enterURL: URL, sourceURL: URL, userAgent: String?) async throws {
        guard let filterURL = filterURL(sourceURL: sourceURL) else { return }
        let fields = filterFields(fromHTML: html)
        guard !fields.isEmpty else { return }
        _ = try await HTTPClient.shared.postForm(
            to: filterURL,
            fields: fields,
            referer: enterURL.absoluteString,
            userAgent: userAgent
        )
    }

    static func filterFields(fromHTML html: String) -> [String: String] {
        let normalizedHTML = decodeHTML(html)
        let filterBox = elementBlock(
            in: normalizedHTML,
            tag: "aside",
            attribute: "id",
            value: "FilterBox"
        ) ?? elementBlock(
            in: normalizedHTML,
            tag: "div",
            attribute: "id",
            value: "FilterBox"
        ) ?? normalizedHTML

        var fields: [String: String] = [:]

        for select in tagBlocks(tag: "select", html: filterBox) {
            let attributes = attributeValues(from: select.attributes)
            guard let name = attributes["name"], !name.isEmpty else { continue }
            let optionValues = tagAttributeCandidates(tag: "option", fromHTML: select.body, keys: ["value"])
            if let value = optionValues.last {
                fields[name] = value
            }
        }

        for attrs in tagAttributes(tag: "input", html: filterBox) {
            let values = attributeValues(from: attrs)
            guard let name = values["name"],
                  name.hasPrefix("rating_") || name == "CSRF_TOKEN",
                  let value = values["value"] else {
                continue
            }
            fields[name] = value
        }

        if !fields.isEmpty {
            fields["filter_media"] = "A"
            fields["filter_order"] = "date_new"
            fields["filter_type"] = "0"
        }
        return fields
    }

    private static func canonicalHost(for sourceURL: URL) -> String {
        let host = sourceURL.host?.lowercased() ?? "www.hentai-foundry.com"
        return host.hasSuffix(".test") || host == "hentai-foundry.test"
            ? "www.hentai-foundry.test"
            : "www.hentai-foundry.com"
    }

    private static func anchorHasClass(
        _ anchor: (attributes: [String: String], text: String),
        className: String
    ) -> Bool {
        classTokens(anchor.attributes["class"]).contains(className.lowercased())
    }

    private static func classTokens(_ value: String?) -> Set<String> {
        Set((value ?? "")
            .split(whereSeparator: { $0.isWhitespace })
            .map { $0.lowercased() })
    }

    private static func imageCandidates(fromHTML html: String) -> [String] {
        tagAttributeCandidates(tag: "img", fromHTML: html, keys: [
            "data-fullview-src",
            "data-original",
            "data-src",
            "data-lazy-src",
            "src"
        ])
    }

    private static func linkCandidates(fromHTML html: String) -> [String] {
        tagAttributeCandidates(tag: "a", fromHTML: html, keys: ["href"])
    }

    private static func tagAttributeCandidates(tag: String, fromHTML html: String, keys: [String]) -> [String] {
        guard let regex = try? NSRegularExpression(
            pattern: #"<\#(tag)\b([^>]*)>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return []
        }

        var values: [String] = []
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        for match in regex.matches(in: html, range: range) {
            guard let attrsRange = Range(match.range(at: 1), in: html) else { continue }
            let attributes = attributeValues(from: String(html[attrsRange]))
            for key in keys {
                if let value = attributes[key]?.trimmed, !value.isEmpty {
                    values.append(value)
                }
            }
        }
        return values
    }

    private static func tagAttributes(tag: String, html: String) -> [String] {
        guard let regex = try? NSRegularExpression(
            pattern: #"<\#(tag)\b([^>]*)>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return []
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        return regex.matches(in: html, range: range).compactMap { match in
            Range(match.range(at: 1), in: html).map { String(html[$0]) }
        }
    }

    private static func tagBlocks(tag: String, html: String) -> [(attributes: String, body: String)] {
        guard let regex = try? NSRegularExpression(
            pattern: #"<\#(tag)\b([^>]*)>(.*?)</\#(tag)>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return []
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        return regex.matches(in: html, range: range).compactMap { match in
            guard let attrsRange = Range(match.range(at: 1), in: html),
                  let bodyRange = Range(match.range(at: 2), in: html) else {
                return nil
            }
            return (String(html[attrsRange]), String(html[bodyRange]))
        }
    }

    private static func elementBlock(in html: String, tag: String, attribute: String, value: String) -> String? {
        let pattern = #"<\#(tag)\b[^>]*\b\#(attribute)\s*=\s*["']\#(value)["'][^>]*>(.*?)</\#(tag)>"#
        return captureGroupMatches(pattern: pattern, in: html).first
    }

    private static func mediaURLStrings(in html: String) -> [String] {
        let pattern = #"(?i)(?:https?:)?//[^\s"'<>\\]+?\.(?:jpe?g|png|gif|webp|bmp|webm|avi|mp4|mkv|wmv)(?:\?[^\s"'<>\\]*)?|/[^\s"'<>\\]+?\.(?:jpe?g|png|gif|webp|bmp|webm|avi|mp4|mkv|wmv)(?:\?[^\s"'<>\\]*)?"#
        return captureWholeMatches(pattern: pattern, in: html)
    }

    private static func title(fromHTML html: String, pageURL: URL) -> String {
        let title = elementText(pattern: #"<h1\b[^>]*>(.*?)</h1>"#, in: html) ??
            metaContent(from: html, names: ["og:title", "twitter:title"]) ??
            titleTag(fromHTML: html) ??
            pageURL.lastPathComponent.replacingOccurrences(of: "-", with: " ")
        return cleanTitle(title, fallback: "Hentai Foundry \(picturePageInfo(from: pageURL)?.id ?? "picture")")
    }

    private static func galleryTitle(fromHTML html: String, username: String) -> String {
        let title = elementText(pattern: #"<h1\b[^>]*>(.*?)</h1>"#, in: html) ??
            titleTag(fromHTML: html) ??
            "\(username) gallery"
        return cleanTitle(title, fallback: "\(username) gallery")
    }

    private static func artistName(fromHTML html: String, pageURL: URL) -> String? {
        if let username = picturePageInfo(from: pageURL)?.username {
            return username
        }
        for anchor in anchorEntries(fromHTML: html) {
            guard let href = anchor.attributes["href"],
                  let url = absoluteURL(href, baseURL: pageURL),
                  let username = galleryUsername(from: url),
                  !username.isEmpty else {
                continue
            }
            return cleanTitle(anchor.text.isEmpty ? username : anchor.text, fallback: username)
        }
        return nil
    }

    private static func classBlocks(in html: String, className: String) -> [String] {
        let pattern = #"<(?:section|div)\b[^>]*\bclass\s*=\s*["'][^"']*\#(className)[^"']*["'][^>]*>(.*?)</(?:section|div)>"#
        return captureGroupMatches(pattern: pattern, in: html, group: 1)
    }

    private static func elementText(pattern: String, in html: String) -> String? {
        guard let raw = captureGroupMatches(pattern: pattern, in: html).first else { return nil }
        let text = cleanTitle(stripTags(raw), fallback: "")
        return text.isEmpty ? nil : text
    }

    private static func metaContent(from html: String, names: [String]) -> String? {
        for name in names {
            let patterns = [
                #"<meta\b[^>]*(?:property|name)\s*=\s*["']\#(name)["'][^>]*content\s*=\s*["']([^"']+)["'][^>]*>"#,
                #"<meta\b[^>]*content\s*=\s*["']([^"']+)["'][^>]*(?:property|name)\s*=\s*["']\#(name)["'][^>]*>"#
            ]
            for pattern in patterns {
                if let value = captureGroupMatches(pattern: pattern, in: html).first {
                    let text = cleanTitle(value, fallback: "")
                    if !text.isEmpty {
                        return text
                    }
                }
            }
        }
        return nil
    }

    private static func titleTag(fromHTML html: String) -> String? {
        guard let title = captureGroupMatches(pattern: #"<title\b[^>]*>(.*?)</title>"#, in: html).first else {
            return nil
        }
        let text = cleanTitle(title, fallback: "")
        return text.isEmpty ? nil : text
    }

    private static func attributeValues(from raw: String) -> [String: String] {
        var values: [String: String] = [:]
        guard let regex = try? NSRegularExpression(
            pattern: #"([A-Za-z_:][-A-Za-z0-9_:.]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+))"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return values
        }
        let range = NSRange(raw.startIndex..<raw.endIndex, in: raw)
        for match in regex.matches(in: raw, range: range) {
            guard let keyRange = Range(match.range(at: 1), in: raw) else { continue }
            let key = String(raw[keyRange]).lowercased()
            let value: String
            if let range = Range(match.range(at: 2), in: raw) {
                value = String(raw[range])
            } else if let range = Range(match.range(at: 3), in: raw) {
                value = String(raw[range])
            } else if let range = Range(match.range(at: 4), in: raw) {
                value = String(raw[range])
            } else {
                value = ""
            }
            values[key] = decodeHTML(value)
        }
        return values
    }

    private static func anchorEntries(fromHTML html: String) -> [(attributes: [String: String], text: String)] {
        guard let regex = try? NSRegularExpression(
            pattern: #"<a\b([^>]*)>(.*?)</a>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return []
        }
        var entries: [(attributes: [String: String], text: String)] = []
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        for match in regex.matches(in: html, range: range) {
            guard let attrsRange = Range(match.range(at: 1), in: html),
                  let textRange = Range(match.range(at: 2), in: html) else {
                continue
            }
            entries.append((
                attributes: attributeValues(from: String(html[attrsRange])),
                text: cleanTitle(stripTags(String(html[textRange])), fallback: "")
            ))
        }
        return entries
    }

    private static func captureGroupMatches(pattern: String, in text: String, group: Int = 1) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > group,
                  let resultRange = Range(match.range(at: group), in: text) else {
                return nil
            }
            return String(text[resultRange])
        }
    }

    private static func captureWholeMatches(pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            Range(match.range(at: 0), in: text).map { String(text[$0]) }
        }
    }

    private static func absoluteURL(_ raw: String, baseURL: URL) -> URL? {
        var value = decodeHTML(raw)
            .replacingOccurrences(of: #"\/"#, with: "/")
            .trimmed
        guard !value.isEmpty,
              !value.lowercased().hasPrefix("javascript:"),
              !value.lowercased().hasPrefix("mailto:") else {
            return nil
        }
        if value.hasPrefix("//") {
            value = (baseURL.scheme ?? "https") + ":" + value
        }
        if let url = URL(string: value, relativeTo: baseURL)?.absoluteURL,
           let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            return url
        }
        return nil
    }

    private static func cleanedContentURL(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        components.queryItems = nil
        components.fragment = nil
        return components.url ?? url
    }

    private static func cleanedNavigationURL(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        components.fragment = nil
        return components.url ?? url
    }

    private static func isDownloadableMedia(_ url: URL) -> Bool {
        allowedExtensions.contains(url.pathExtension.lowercased())
    }

    private static func filename(for url: URL, index: Int) -> String {
        let rawExt = url.pathExtension.lowercased()
        let ext = rawExt == "bmp" || rawExt.isEmpty ? "jpg" : rawExt
        return String(format: "%04d.%@", index, ext).sanitizedFilename(maxLength: 180)
    }

    private static func assetMetadata(for url: URL, pictureID: String, artist: String, title: String, pageURL: URL, index: Int) -> [String: String] {
        let format = mediaFormat(for: url)
        return DownloadMetadata.clean([
            "artist": artist,
            "author": artist,
            "creator": artist,
            "user": artist,
            "username": artist,
            "uploader": artist,
            "channel": artist,
            "picture_id": pictureID,
            "gallery_id": artist,
            "id": pictureID,
            "media_id": pictureID.isEmpty ? String(index) : "\(pictureID)-\(index)",
            "page": String(index),
            "position": String(index),
            "slug": pageURL.lastPathComponent,
            "site": "Hentai Foundry",
            "title": title,
            "series": title,
            "type": "image",
            "media_type": "image",
            "category": "image",
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

    private static func stripTags(_ raw: String) -> String {
        raw.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
    }

    private static func decodeHTML(_ raw: String) -> String {
        var text = raw
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#34;", with: "\"")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")

        guard let regex = try? NSRegularExpression(pattern: #"&#(?:x([0-9A-Fa-f]+)|([0-9]+));"#) else {
            return text
        }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)).reversed()
        for match in matches {
            guard let whole = Range(match.range(at: 0), in: text) else { continue }
            let value: UInt32?
            if let hexRange = Range(match.range(at: 1), in: text) {
                value = UInt32(String(text[hexRange]), radix: 16)
            } else if let decimalRange = Range(match.range(at: 2), in: text) {
                value = UInt32(String(text[decimalRange]), radix: 10)
            } else {
                value = nil
            }
            if let value, let scalar = UnicodeScalar(value) {
                text.replaceSubrange(whole, with: String(Character(scalar)))
            }
        }
        return text
    }

    private static func cleanTitle(_ raw: String, fallback: String) -> String {
        var text = decodeHTML(stripTags(raw))
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmed
        for suffix in [
            " - Hentai Foundry",
            " | Hentai Foundry",
            " - hentai-foundry.com",
            " | hentai-foundry.com"
        ] {
            if text.lowercased().hasSuffix(suffix.lowercased()) {
                text = String(text.dropLast(suffix.count)).trimmed
            }
        }
        return text.isEmpty ? fallback : text
    }

    private static func isSupportedHost(_ host: String) -> Bool {
        supportedDomains.contains { domain in
            host == domain || host.hasSuffix("." + domain)
        }
    }

    private static let supportedDomains = [
        "hentai-foundry.com",
        "hentai-foundry.test"
    ]

    private static let allowedExtensions: Set<String> = [
        "jpg",
        "jpeg",
        "png",
        "gif",
        "webp",
        "bmp",
        "webm",
        "avi",
        "mp4",
        "mkv",
        "wmv"
    ]
}

private extension Array where Element == URL {
    func uniqueByNormalizedURL() -> [URL] {
        var seen = Set<String>()
        var output: [URL] = []
        for url in self {
            let normalized = URLIdentity.normalize(url.absoluteString)
            guard !seen.contains(normalized) else { continue }
            seen.insert(normalized)
            output.append(url)
        }
        return output
    }
}
