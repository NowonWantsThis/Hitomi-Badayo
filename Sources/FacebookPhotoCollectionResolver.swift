import Foundation

struct FacebookPhotoCollectionRequest: Equatable {
    var identifier: String
    var sourceURL: URL
    var photosURL: URL
}

struct FacebookPhotoCollectionEntry: Equatable {
    var photoID: String
    var pageURL: URL
    var thumbnailURL: URL?
}

struct FacebookPhotoCollectionPage: Equatable {
    var title: String
    var thumbnailURL: URL?
    var entries: [FacebookPhotoCollectionEntry]
    var nextURL: URL?
    var requiresLogin: Bool
}

final class FacebookPhotoCollectionResolver {
    static let defaultCollectionItemLimit = 2_000

    func canResolve(_ url: URL) -> Bool {
        Self.request(from: url) != nil
    }

    func resolve(
        _ url: URL,
        headers: HTTPRequestOptions = HTTPRequestOptions(),
        rangeExpression: String = ""
    ) async throws -> ResolvedDownload {
        guard let request = Self.request(from: url) else {
            throw NativeDownloadError.invalidURL(url.absoluteString)
        }
        let itemRange = rangeExpression.trimmed
        let itemLimit = try Self.collectionItemLimit(for: itemRange)

        var title = ""
        var thumbnailURL: URL?
        var entries: [FacebookPhotoCollectionEntry] = []
        var seenPhotoIDs = Set<String>()
        var visitedPageURLs = Set<String>()
        var currentURL: URL? = request.photosURL
        var sawLoginPage = false
        var fetchedPageCount = 0

        while entries.count < itemLimit {
            try Task.checkCancellation()
            guard let pageURL = currentURL else { break }
            let pageIdentity = URLIdentity.normalize(pageURL.absoluteString)
            guard visitedPageURLs.insert(pageIdentity).inserted else { break }

            let html = try await HTTPClient.shared.string(
                from: pageURL,
                referer: headers.referer ?? request.sourceURL.absoluteString,
                userAgent: headers.userAgent
            )
            fetchedPageCount += 1
            let page = Self.collectionPage(fromHTML: html, request: request, pageURL: pageURL)
            if title.isEmpty, !page.title.isEmpty { title = page.title }
            if thumbnailURL == nil { thumbnailURL = page.thumbnailURL }
            sawLoginPage = sawLoginPage || page.requiresLogin
            Self.appendUnique(
                page.entries,
                to: &entries,
                seen: &seenPhotoIDs,
                limit: itemLimit
            )
            currentURL = page.nextURL
        }

        if entries.count < itemLimit,
           !sawLoginPage,
           Self.shouldUseBrowserRenderer(for: request.photosURL) {
            let cookieHeader = await CookieStore.shared.cookieHeader(for: request.photosURL)
            do {
                let rendered = try await FacebookPhotoCollectionWebRenderer.render(
                    url: request.photosURL,
                    referer: headers.referer ?? request.sourceURL.absoluteString,
                    userAgent: headers.userAgent,
                    cookieHeader: cookieHeader,
                    itemLimit: itemLimit
                )
                let page = Self.collectionPage(
                    fromHTML: rendered.html,
                    request: request,
                    pageURL: rendered.finalURL,
                    additionalLinks: rendered.photoLinks
                )
                if !page.title.isEmpty { title = page.title }
                if thumbnailURL == nil { thumbnailURL = page.thumbnailURL }
                sawLoginPage = sawLoginPage || page.requiresLogin
                Self.appendUnique(
                    page.entries,
                    to: &entries,
                    seen: &seenPhotoIDs,
                    limit: itemLimit
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Static HTML remains useful when WebKit is unavailable or Facebook blocks rendering.
            }
        }

        guard !entries.isEmpty else {
            if sawLoginPage {
                throw NativeDownloadError.unsupported(
                    "Facebook photos require a signed-in session. Save Facebook cookies from the login browser and retry."
                )
            }
            throw NativeDownloadError.unsupported(
                "No Facebook profile photos were exposed. The profile may require signed-in cookies or may not have public photos."
            )
        }

        let listedItemCount = entries.count
        var selectedPositions: [Int]?
        if !itemRange.isEmpty {
            let indexes = try Self.itemIndexes(for: itemRange, total: entries.count)
            entries = indexes.map { entries[$0] }
            selectedPositions = indexes.map { $0 + 1 }
        }

        let photoResolver = FacebookPhotoResolver()
        var resolved: [(entry: FacebookPhotoCollectionEntry, download: ResolvedDownload)] = []
        var failures: [Error] = []
        for entry in entries {
            try Task.checkCancellation()
            do {
                let download = try await photoResolver.resolve(entry.pageURL, headers: headers)
                resolved.append((entry, download))
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                failures.append(error)
            }
        }
        guard !resolved.isEmpty else {
            throw failures.first ?? NativeDownloadError.noFiles
        }

        var download = Self.combinedDownload(
            request: request,
            profileTitle: title,
            profileThumbnailURL: thumbnailURL,
            photos: resolved
        )
        download.metadata["discovered_item_count"] = String(listedItemCount)
        download.metadata["listed_item_count"] = String(listedItemCount)
        download.metadata["collection_pages"] = String(fetchedPageCount)
        download.metadata["resolved_item_count"] = String(resolved.count)
        if let selectedPositions {
            download.metadata["range"] = itemRange
            download.metadata["range_scope"] = "collection_items"
            download.metadata["range_total"] = String(listedItemCount)
            download.metadata["range_selected"] = String(selectedPositions.count)
            download.metadata["range_indexes"] = selectedPositions.map(String.init).joined(separator: ",")
        }
        if !failures.isEmpty {
            download.metadata["skipped_count"] = String(failures.count)
        }
        return download
    }

    static func request(from url: URL) -> FacebookPhotoCollectionRequest? {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host?.lowercased(),
              isSupportedHost(host),
              FacebookPhotoResolver.photoID(from: url) == nil,
              FacebookVideoResolver.videoID(from: url) == nil else {
            return nil
        }

        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        let lower = parts.map { $0.lowercased() }
        let identifier: String

        if url.path.lowercased().hasSuffix("/profile.php") || lower.first == "profile.php" {
            guard let id = queryValue(names: ["id"], in: url), isValidIdentifier(id) else {
                return nil
            }
            identifier = id
        } else if lower.first == "people" {
            guard parts.count >= 2, isValidIdentifier(parts[1]) else { return nil }
            identifier = parts[1]
        } else if lower.first == "pg" {
            guard parts.count >= 2, isValidIdentifier(parts[1]) else { return nil }
            identifier = parts[1]
        } else {
            guard let first = parts.first,
                  isValidIdentifier(first),
                  !reservedProfilePaths.contains(first.lowercased()) else {
                return nil
            }
            if parts.count > 1 {
                guard ["photos", "photos_by", "photos_albums"].contains(lower[1]) else {
                    return nil
                }
            }
            identifier = first
        }

        var sourceComponents = URLComponents()
        sourceComponents.scheme = "https"
        sourceComponents.host = canonicalHost(from: host)
        sourceComponents.path = "/\(identifier)"
        guard let sourceURL = sourceComponents.url else { return nil }

        var photosComponents = sourceComponents
        photosComponents.path = "/\(identifier)/photos"
        guard let photosURL = photosComponents.url else { return nil }
        return FacebookPhotoCollectionRequest(
            identifier: identifier,
            sourceURL: sourceURL,
            photosURL: photosURL
        )
    }

    static func collectionPage(
        fromHTML html: String,
        request: FacebookPhotoCollectionRequest,
        pageURL: URL? = nil,
        additionalLinks: [String] = []
    ) -> FacebookPhotoCollectionPage {
        let baseURL = pageURL ?? request.photosURL
        let normalizedHTML = normalizeEscapes(decodeHTML(html))
        var entries: [FacebookPhotoCollectionEntry] = []
        var seen = Set<String>()

        for anchor in captures(
            pattern: #"<a\b[^>]*\bhref\s*=\s*(?:\"[^\"]*\"|'[^']*')[^>]*>.*?</a>"#,
            in: normalizedHTML,
            group: 0
        ) {
            guard anchor.range(of: #"<img\b"#, options: [.caseInsensitive, .regularExpression]) != nil,
                  let href = attributeValue("href", in: anchor) else {
                continue
            }
            let thumbnail = firstImageURL(in: anchor, baseURL: baseURL)
            if let entry = entry(from: href, thumbnailURL: thumbnail, request: request, baseURL: baseURL),
               seen.insert(entry.photoID).inserted {
                entries.append(entry)
            }
        }

        for href in captures(
            pattern: #"\bhref\s*=\s*(?:\"([^\"]+)\"|'([^']+)')"#,
            in: normalizedHTML,
            groups: [1, 2]
        ) + additionalLinks {
            if let entry = entry(from: href, thumbnailURL: nil, request: request, baseURL: baseURL),
               seen.insert(entry.photoID).inserted {
                entries.append(entry)
            }
        }

        return FacebookPhotoCollectionPage(
            title: profileTitle(fromHTML: normalizedHTML, fallback: request.identifier),
            thumbnailURL: metaContent(named: "og:image", in: normalizedHTML)
                .flatMap { absoluteURL($0, baseURL: baseURL) },
            entries: entries,
            nextURL: nextPageURL(fromHTML: normalizedHTML, baseURL: baseURL),
            requiresLogin: requiresLogin(normalizedHTML)
        )
    }

    static func combinedDownload(
        request: FacebookPhotoCollectionRequest,
        profileTitle: String,
        profileThumbnailURL: URL?,
        photos: [(entry: FacebookPhotoCollectionEntry, download: ResolvedDownload)]
    ) -> ResolvedDownload {
        let cleanProfileTitle = cleanText(profileTitle, fallback: request.identifier)
        let collectionTitle = "\(cleanProfileTitle) (facebook_\(request.identifier))"
            .sanitizedFilename(maxLength: 160)
        var assets: [ResolvedAsset] = []

        for (photoIndex, photo) in photos.enumerated() {
            for (assetIndex, original) in photo.download.assets.enumerated() {
                var asset = original
                let prefix = String(format: "%04d-%@", photoIndex + 1, photo.entry.photoID)
                asset.filename = "\(prefix)-\(original.filename)".sanitizedFilename(maxLength: 180)
                let collectionValues = collectionMetadata(
                    request: request,
                    entry: photo.entry,
                    index: photoIndex,
                    assetIndex: assetIndex
                )
                for (key, value) in collectionValues { asset.metadata[key] = value }
                assets.append(asset)
            }
        }

        let firstThumbnail = profileThumbnailURL?.absoluteString ??
            photos.lazy.compactMap { $0.entry.thumbnailURL?.absoluteString }.first ??
            photos.lazy.compactMap { $0.download.metadata["thumbnail"] }.first ?? ""
        return ResolvedDownload(
            title: collectionTitle,
            folderName: collectionTitle.sanitizedFilename(maxLength: 120),
            assets: assets,
            metadata: DownloadMetadata.clean([
                "site": "Facebook",
                "title": collectionTitle,
                "series": cleanProfileTitle,
                "artist": cleanProfileTitle,
                "author": cleanProfileTitle,
                "creator": cleanProfileTitle,
                "uploader": cleanProfileTitle,
                "channel": cleanProfileTitle,
                "category": "image",
                "type": "collection",
                "media_type": "image",
                "collection": "true",
                "profile_id": request.identifier,
                "collection_id": request.identifier,
                "gallery_id": request.identifier,
                "item_count": String(photos.count),
                "media_count": String(assets.count),
                "image_count": String(assets.count),
                "thumbnail": firstThumbnail,
                "url": request.sourceURL.absoluteString,
                "source_url": request.sourceURL.absoluteString,
                "page_url": request.photosURL.absoluteString,
                "profile_url": request.sourceURL.absoluteString,
                "collection_url": request.photosURL.absoluteString
            ])
        )
    }

    private static func appendUnique(
        _ values: [FacebookPhotoCollectionEntry],
        to entries: inout [FacebookPhotoCollectionEntry],
        seen: inout Set<String>,
        limit: Int = Int.max
    ) {
        for entry in values where seen.insert(entry.photoID).inserted {
            entries.append(entry)
            if entries.count >= limit { break }
        }
    }

    private struct ItemRangeSegment {
        var start: Int?
        var end: Int?
    }

    static func collectionItemLimit(for expression: String) throws -> Int {
        let segments = try itemRangeSegments(from: expression.trimmed)
        guard !segments.isEmpty else { return defaultCollectionItemLimit }
        if segments.contains(where: { $0.end == nil }) { return Int.max }
        return max(1, segments.compactMap(\.end).max() ?? defaultCollectionItemLimit)
    }

    private static func itemIndexes(for expression: String, total: Int) throws -> [Int] {
        let segments = try itemRangeSegments(from: expression)
        guard !segments.isEmpty else { return Array(0..<max(0, total)) }
        guard total > 0 else { return [] }
        var indexes: [Int] = []
        var seen = Set<Int>()
        for segment in segments {
            let start = max(1, segment.start ?? 1)
            let end = min(total, segment.end ?? total)
            guard start <= end else { continue }
            for position in start...end {
                let index = position - 1
                if seen.insert(index).inserted { indexes.append(index) }
            }
        }
        guard !indexes.isEmpty else {
            throw NativeDownloadError.unsupported("Range did not match any Facebook photos.")
        }
        return indexes
    }

    private static func itemRangeSegments(from expression: String) throws -> [ItemRangeSegment] {
        guard !expression.isEmpty else { return [] }
        let compact = expression
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\t", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
        let pieces = compact
            .components(separatedBy: CharacterSet(charactersIn: ",;"))
            .filter { !$0.isEmpty }
        guard !pieces.isEmpty else {
            throw NativeDownloadError.unsupported("Invalid range.")
        }
        return try pieces.map { piece in
            if let split = itemRangeSplit(piece) {
                let start = try positiveItemRangeBound(split.0)
                let end = try positiveItemRangeBound(split.1)
                guard start != nil || end != nil else {
                    throw NativeDownloadError.unsupported("Invalid range.")
                }
                if let start, let end, start > end {
                    throw NativeDownloadError.unsupported("Invalid range.")
                }
                return ItemRangeSegment(start: start, end: end)
            }
            guard let position = Int(piece), position > 0 else {
                throw NativeDownloadError.unsupported("Invalid range.")
            }
            return ItemRangeSegment(start: position, end: position)
        }
    }

    private static func itemRangeSplit(_ value: String) -> (String, String)? {
        for separator in ["...", "..", "~", "-"] {
            if let range = value.range(of: separator) {
                return (String(value[..<range.lowerBound]), String(value[range.upperBound...]))
            }
        }
        return nil
    }

    private static func positiveItemRangeBound(_ value: String) throws -> Int? {
        guard !value.isEmpty else { return nil }
        guard let bound = Int(value), bound > 0 else {
            throw NativeDownloadError.unsupported("Invalid range.")
        }
        return bound
    }

    private static func entry(
        from rawLink: String,
        thumbnailURL: URL?,
        request: FacebookPhotoCollectionRequest,
        baseURL: URL
    ) -> FacebookPhotoCollectionEntry? {
        guard let rawURL = absoluteURL(rawLink, baseURL: baseURL),
              let photoID = FacebookPhotoResolver.photoID(from: rawURL) else {
            return nil
        }
        return FacebookPhotoCollectionEntry(
            photoID: photoID,
            pageURL: FacebookPhotoResolver.canonicalURL(
                photoID: photoID,
                sourceURL: request.sourceURL
            ),
            thumbnailURL: thumbnailURL
        )
    }

    private static func collectionMetadata(
        request: FacebookPhotoCollectionRequest,
        entry: FacebookPhotoCollectionEntry,
        index: Int,
        assetIndex: Int
    ) -> [String: String] {
        DownloadMetadata.clean([
            "collection": "true",
            "collection_id": request.identifier,
            "collection_index": String(index + 1),
            "collection_item_id": entry.photoID,
            "collection_url": request.photosURL.absoluteString,
            "profile_id": request.identifier,
            "profile_url": request.sourceURL.absoluteString,
            "photo_id": entry.photoID,
            "media_id": entry.photoID,
            "page": String(index + 1),
            "position": String(index + 1),
            "asset_index": String(assetIndex + 1),
            "item_page_url": entry.pageURL.absoluteString,
            "item_thumbnail": entry.thumbnailURL?.absoluteString ?? ""
        ])
    }

    private static func firstImageURL(in html: String, baseURL: URL) -> URL? {
        for attribute in ["data-full-size-href", "data-src", "data-lazy-src", "src"] {
            if let raw = attributeValue(attribute, in: html),
               let url = absoluteURL(raw, baseURL: baseURL) {
                return url
            }
        }
        return nil
    }

    private static func nextPageURL(fromHTML html: String, baseURL: URL) -> URL? {
        for tag in captures(pattern: #"<a\b[^>]*>"#, in: html, group: 0) {
            let rel = attributeValue("rel", in: tag)?.lowercased() ?? ""
            let cssClass = attributeValue("class", in: tag)?.lowercased() ?? ""
            guard rel.split(separator: " ").contains("next") ||
                    cssClass.contains("next") ||
                    attributeValue("data-next-page", in: tag) != nil else {
                continue
            }
            if let raw = attributeValue("href", in: tag) ?? attributeValue("data-next-page", in: tag),
               let url = absoluteURL(raw, baseURL: baseURL),
               isSupportedHost(url.host?.lowercased() ?? "") {
                return url
            }
        }

        for pattern in [
            #"\"next(?:_page|Page)?\"\s*:\s*\"([^\"]+)\""#,
            #"\"next_page_url\"\s*:\s*\"([^\"]+)\""#
        ] {
            if let raw = captures(pattern: pattern, in: html).first,
               let url = absoluteURL(raw, baseURL: baseURL),
               isSupportedHost(url.host?.lowercased() ?? "") {
                return url
            }
        }
        return nil
    }

    private static func profileTitle(fromHTML html: String, fallback: String) -> String {
        for tag in ["h1", "h2"] {
            if let raw = captures(
                pattern: #"<\#(tag)\b[^>]*>(.*?)</\#(tag)>"#,
                in: html
            ).first {
                let value = cleanText(raw, fallback: "")
                if !value.isEmpty, value.lowercased() != "photos" { return value }
            }
        }
        if let value = metaContent(named: "og:title", in: html), !value.trimmed.isEmpty {
            return cleanText(value, fallback: fallback)
        }
        if let raw = captures(pattern: #"<title\b[^>]*>(.*?)</title>"#, in: html).first {
            return cleanText(raw, fallback: fallback)
        }
        return fallback
    }

    private static func requiresLogin(_ html: String) -> Bool {
        let lower = html.lowercased()
        return lower.contains("id=\"loginbutton\"") ||
            lower.contains("id='loginbutton'") ||
            lower.contains("/login/?next=") ||
            lower.contains("log into facebook") ||
            lower.contains("facebook에 로그인") ||
            lower.contains("fb_loggedout") ||
            lower.contains("comet_loggedout_pkg")
    }

    private static func shouldUseBrowserRenderer(for url: URL) -> Bool {
        guard ProcessInfo.processInfo.environment["HITOMI_NATIVE_FACEBOOK_DISABLE_WEB_RENDERER"] != "1",
              let host = url.host?.lowercased() else {
            return false
        }
        return !host.hasSuffix(".test")
    }

    private static func queryValue(names: [String], in url: URL) -> String? {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        for name in names {
            if let value = items.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame })?.value?.trimmed,
               !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func attributeValue(_ name: String, in tag: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        return captures(
            pattern: #"\b\#(escaped)\s*=\s*(?:\"([^\"]*)\"|'([^']*)'|([^\s>\"']+))"#,
            in: tag,
            groups: [1, 2, 3]
        ).first
    }

    private static func metaContent(named name: String, in html: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        for pattern in [
            #"<meta\b[^>]*(?:property|name)\s*=\s*[\"']\#(escaped)[\"'][^>]*content\s*=\s*[\"']([^\"']+)[\"'][^>]*>"#,
            #"<meta\b[^>]*content\s*=\s*[\"']([^\"']+)[\"'][^>]*(?:property|name)\s*=\s*[\"']\#(escaped)[\"'][^>]*>"#
        ] {
            if let value = captures(pattern: pattern, in: html).first {
                return decodeHTML(value).trimmed
            }
        }
        return nil
    }

    private static func captures(
        pattern: String,
        in text: String,
        group: Int = 1
    ) -> [String] {
        captures(pattern: pattern, in: text, groups: [group])
    }

    private static func captures(
        pattern: String,
        in text: String,
        groups: [Int]
    ) -> [String] {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            for group in groups where match.numberOfRanges > group {
                if let capture = Range(match.range(at: group), in: text) {
                    return String(text[capture])
                }
            }
            return nil
        }
    }

    private static func absoluteURL(_ raw: String, baseURL: URL) -> URL? {
        var value = normalizeEscapes(decodeHTML(raw)).trimmed
        value = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        guard !value.isEmpty, !value.lowercased().hasPrefix("javascript:") else { return nil }
        if value.hasPrefix("//") { value = "\(baseURL.scheme ?? "https"):\(value)" }
        return URL(string: value, relativeTo: baseURL)?.absoluteURL
    }

    private static func normalizeEscapes(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: #"\/"#, with: "/")
            .replacingOccurrences(of: #"\\/"#, with: "/")
            .replacingOccurrences(of: #"\u002F"#, with: "/", options: .caseInsensitive)
            .replacingOccurrences(of: #"\u003A"#, with: ":", options: .caseInsensitive)
            .replacingOccurrences(of: #"\u003F"#, with: "?", options: .caseInsensitive)
            .replacingOccurrences(of: #"\u0026"#, with: "&", options: .caseInsensitive)
            .replacingOccurrences(of: #"\u003D"#, with: "=", options: .caseInsensitive)
    }

    private static func cleanText(_ raw: String, fallback: String) -> String {
        var text = decodeHTML(
            raw.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        )
        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        .trimmed
        text = text.replacingOccurrences(
            of: #"(?i)\s*(?:\||-|·)\s*(?:photos\s*)?\|?\s*facebook.*$"#,
            with: "",
            options: .regularExpression
        ).trimmed
        return (text.isEmpty ? fallback : text).sanitizedFilename(maxLength: 120)
    }

    private static func decodeHTML(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#34;", with: "\"")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
    }

    private static func canonicalHost(from host: String) -> String {
        host.hasSuffix(".test") ? "www.facebook.test" : "www.facebook.com"
    }

    private static func isSupportedHost(_ host: String) -> Bool {
        if ["facebook.test", "www.facebook.test", "m.facebook.test", "mbasic.facebook.test"].contains(host) {
            return true
        }
        let labels = host.split(separator: ".").map(String.init)
        guard labels.count >= 2, labels[labels.count - 2] == "facebook" else { return false }
        return labels.last?.range(of: #"^[a-z]{2,12}$"#, options: .regularExpression) != nil
    }

    private static func isValidIdentifier(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z0-9][A-Za-z0-9._-]*$"#, options: .regularExpression) != nil
    }

    private static let reservedProfilePaths: Set<String> = [
        "about", "ads", "business", "events", "friends", "gaming", "groups", "help",
        "home.php", "login", "marketplace", "messages", "notifications", "pages",
        "permalink.php", "photo", "photo.php", "policies", "posts", "privacy", "reel",
        "reels", "search", "settings", "share", "sharer", "stories", "story.php",
        "video.php", "videos", "watch"
    ]
}
