import Foundation

final class FlickrResolver {
    func canResolve(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(),
              Self.isSupportedHost(host),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return false
        }

        return Self.photoID(from: url) != nil || Self.userID(from: url) != nil
    }

    func resolve(
        _ url: URL,
        headers: HTTPRequestOptions = HTTPRequestOptions(),
        rangeExpression: String = ""
    ) async throws -> ResolvedDownload {
        let sourceURL = Self.canonicalContentURL(for: url) ?? url
        if Self.photoID(from: sourceURL) != nil {
            let pageURL = Self.canonicalPhotoURL(for: sourceURL) ?? Self.canonicalShortPhotoURL(for: sourceURL) ?? sourceURL
            let html = try await HTTPClient.shared.string(from: pageURL, referer: headers.referer, userAgent: headers.userAgent)
            return try Self.resolvedPhotoDownload(fromHTML: html, pageURL: pageURL)
        }

        guard let userID = Self.userID(from: sourceURL) else {
            throw NativeDownloadError.invalidURL(url.absoluteString)
        }

        let firstURL = try Self.userPhotosPageURL(for: userID, sourceURL: sourceURL, page: 1)
        let firstHTML = try await HTTPClient.shared.string(from: firstURL, referer: headers.referer ?? sourceURL.absoluteString, userAgent: headers.userAgent)
        let title = Self.collectionTitle(fromHTML: firstHTML, userID: userID)
        let itemRange = rangeExpression.trimmed
        let discoveryLimit = try Self.maximumRequestedItem(in: itemRange)
        var photoURLs: [URL] = []
        var seenPhotoURLs = Set<String>()
        var collectionPageCount = 1

        func appendNewPhotoURLs(_ candidates: [URL]) {
            for candidate in candidates {
                let identity = URLIdentity.normalize(candidate.absoluteString)
                guard seenPhotoURLs.insert(identity).inserted else { continue }
                photoURLs.append(candidate)
                if let discoveryLimit, photoURLs.count >= discoveryLimit {
                    break
                }
            }
        }

        appendNewPhotoURLs(Self.photoPageURLs(fromHTML: firstHTML, userID: userID, baseURL: firstURL))
        var maximumPage = Self.maxPageNumber(fromHTML: firstHTML, userID: userID)
        var page = 2
        while page <= maximumPage && (discoveryLimit.map { photoURLs.count < $0 } ?? true) {
            try Task.checkCancellation()
            let pageURL = try Self.userPhotosPageURL(for: userID, sourceURL: sourceURL, page: page)
            let html = try await HTTPClient.shared.string(
                from: pageURL,
                referer: firstURL.absoluteString,
                userAgent: headers.userAgent
            )
            collectionPageCount += 1
            maximumPage = max(maximumPage, Self.maxPageNumber(fromHTML: html, userID: userID))
            appendNewPhotoURLs(Self.photoPageURLs(fromHTML: html, userID: userID, baseURL: pageURL))
            page += 1
        }

        guard !photoURLs.isEmpty else { throw NativeDownloadError.noFiles }
        var selectedPhotos = Array(photoURLs.enumerated())
        var selectedPositions: [Int]?
        if !itemRange.isEmpty {
            let indexes = try Self.itemIndexes(for: itemRange, total: photoURLs.count)
            selectedPhotos = indexes.map { (offset: $0, element: photoURLs[$0]) }
            selectedPositions = indexes.map { $0 + 1 }
        }

        var assets: [ResolvedAsset] = []
        var seen = Set<String>()
        var resolvedPhotoCount = 0
        var skippedPhotoCount = 0

        for selectedPhoto in selectedPhotos {
            try Task.checkCancellation()
            let photoURL = selectedPhoto.element
            do {
                let html = try await HTTPClient.shared.string(
                    from: photoURL,
                    referer: firstURL.absoluteString,
                    userAgent: headers.userAgent
                )
                var asset = try Self.photoAsset(fromHTML: html, pageURL: photoURL)
                resolvedPhotoCount += 1
                let normalized = URLIdentity.normalize(asset.remoteURL.absoluteString)
                guard !seen.contains(normalized) else { continue }
                seen.insert(normalized)
                let position = String(selectedPhoto.offset + 1)
                asset.metadata["page"] = position
                asset.metadata["position"] = position
                asset.metadata["collection_position"] = position
                asset.metadata["photo_position"] = position
                assets.append(asset)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                skippedPhotoCount += 1
            }
        }

        guard !assets.isEmpty else {
            throw NativeDownloadError.noFiles
        }

        var metadata = Self.flickrMetadata(
            userID: userID,
            title: title,
            pageURL: sourceURL,
            assets: assets,
            type: "photostream"
        )
        metadata["listed_photo_count"] = String(photoURLs.count)
        metadata["resolved_photo_count"] = String(resolvedPhotoCount)
        metadata["resolved_media_count"] = String(assets.count)
        metadata["collection_page_count"] = String(collectionPageCount)
        if skippedPhotoCount > 0 {
            metadata["skipped_count"] = String(skippedPhotoCount)
        }
        if let selectedPositions {
            metadata["range"] = itemRange
            metadata["range_scope"] = "collection_items"
            metadata["range_total"] = String(photoURLs.count)
            metadata["range_selected"] = String(selectedPositions.count)
            metadata["range_indexes"] = selectedPositions.map(String.init).joined(separator: ",")
        }

        return ResolvedDownload(
            title: title,
            folderName: title.sanitizedFilename(maxLength: 120),
            assets: assets,
            metadata: metadata
        )
    }

    static func resolvedPhotoDownload(fromHTML html: String, pageURL: URL) throws -> ResolvedDownload {
        let effectivePageURL = canonicalPhotoPageURL(fromHTML: html, baseURL: pageURL) ?? pageURL
        let title = photoTitle(fromHTML: html, pageURL: effectivePageURL)
        let asset = try photoAsset(fromHTML: html, pageURL: effectivePageURL, title: title)
        return ResolvedDownload(
            title: title,
            folderName: title.sanitizedFilename(maxLength: 120),
            assets: [asset],
            metadata: flickrMetadata(userID: userID(from: effectivePageURL), title: title, pageURL: effectivePageURL, assets: [asset], type: "photo")
        )
    }

    private static func flickrMetadata(userID: String?, title: String = "", pageURL: URL? = nil, assets: [ResolvedAsset] = [], type: String = "") -> [String: String] {
        let firstAsset = assets.first
        let firstPhotoID = firstAsset?.metadata["photo_id"] ?? ""
        let firstImageURL = firstAsset?.metadata["image_url"] ?? ""
        return DownloadMetadata.clean([
            "site": "Flickr",
            "title": title,
            "series": title,
            "category": "image",
            "type": type,
            "media_type": type,
            "host": pageURL?.host ?? "",
            "id": type == "photo" ? firstPhotoID : userID ?? "",
            "photo_id": firstPhotoID,
            "gallery_id": type == "photo" ? firstPhotoID : userID ?? "",
            "media_count": assets.isEmpty ? "" : String(assets.count),
            "image_count": assets.isEmpty ? "" : String(assets.count),
            "artist": userID ?? "",
            "author": userID ?? "",
            "creator": userID ?? "",
            "user": userID ?? "",
            "username": userID ?? "",
            "uploader": userID ?? "",
            "channel": userID ?? "",
            "thumbnail": firstImageURL,
            "url": pageURL?.absoluteString ?? "",
            "source_url": pageURL?.absoluteString ?? "",
            "page_url": pageURL?.absoluteString ?? ""
        ])
    }

    static func photoAsset(fromHTML html: String, pageURL: URL, title: String? = nil) throws -> ResolvedAsset {
        let image = metaContent(from: html, names: ["og:image", "og:image:url", "og:image:secure_url", "twitter:image", "twitter:image:src"])
            .flatMap { absoluteURL($0, baseURL: pageURL) }
        guard let remote = image else {
            throw NativeDownloadError.noFiles
        }

        let photoID = photoID(from: pageURL) ?? numericPhotoID(fromHTML: html) ?? remote.deletingPathExtension().lastPathComponent
        let date = dateCreated(fromHTML: html)
        let title = title ?? photoTitle(fromHTML: html, pageURL: pageURL)
        return ResolvedAsset(
            remoteURL: remote,
            filename: photoFilename(remoteURL: remote, photoID: photoID, date: date),
            metadata: assetMetadata(for: remote, photoID: photoID, title: title, userID: userID(from: pageURL), pageURL: pageURL, date: date, index: 1),
            referer: pageURL.absoluteString
        )
    }

    static func photoPageURLs(fromHTML html: String, userID: String, baseURL: URL) -> [URL] {
        let attributes = anchorHREFs(fromHTML: html)
        let patterns = [
            #"/photos/\#(NSRegularExpression.escapedPattern(for: userID))/([0-9]+)"#,
            #"flickr\.(?:com|test)/photos/\#(NSRegularExpression.escapedPattern(for: userID))/([0-9]+)"#
        ]

        var urls: [URL] = []
        for href in attributes {
            guard let url = absoluteURL(href, baseURL: baseURL),
                  let id = firstCapture(patterns: patterns, in: url.absoluteString) else {
                continue
            }
            urls.append(photoURL(for: userID, photoID: id, sourceURL: baseURL) ?? url)
        }
        return uniqueURLs(urls)
    }

    static func maxPageNumber(fromHTML html: String, userID: String) -> Int {
        let escaped = NSRegularExpression.escapedPattern(for: userID)
        let pattern = #"/photos/\#(escaped)/page([0-9]+)"#
        let values = captureMatches(pattern: pattern, in: html).compactMap(Int.init)
        return max(values.max() ?? 1, 1)
    }

    private struct ItemRangeSegment {
        var start: Int?
        var end: Int?
    }

    private static func maximumRequestedItem(in expression: String) throws -> Int? {
        let segments = try itemRangeSegments(from: expression)
        guard !segments.isEmpty else { return nil }
        if segments.contains(where: { $0.end == nil }) { return nil }
        return segments.compactMap(\.end).max()
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
            for position in start...end where seen.insert(position - 1).inserted {
                indexes.append(position - 1)
            }
        }
        guard !indexes.isEmpty else {
            throw NativeDownloadError.unsupported("Range did not match any Flickr photos.")
        }
        return indexes
    }

    private static func itemRangeSegments(from expression: String) throws -> [ItemRangeSegment] {
        guard !expression.isEmpty else { return [] }
        let compact = expression.filter { !$0.isWhitespace }
        let pieces = compact.components(separatedBy: CharacterSet(charactersIn: ",;"))
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

    static func photoID(from url: URL) -> String? {
        if let shortID = shortPhotoID(from: url) {
            return shortID
        }

        let parts = url.path.split(separator: "/").map(String.init)
        guard parts.count >= 3,
              parts[0].lowercased() == "photos",
              parts[2].range(of: #"^[0-9]+$"#, options: .regularExpression) != nil else {
            return nil
        }
        return parts[2]
    }

    static func userID(from url: URL) -> String? {
        let parts = url.path.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return nil }
        let tab = parts[0].lowercased()
        guard tab == "photos" || tab == "people" else { return nil }
        let user = parts[1].trimmed
        guard !user.isEmpty,
              !["tags", "groups", "explore", "search"].contains(user.lowercased()) else {
            return nil
        }
        return user
    }

    static func canonicalPhotoURL(for url: URL) -> URL? {
        guard let host = url.host?.lowercased(),
              isFlickrHost(host),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let userID = userID(from: url),
              let photoID = photoID(from: url) else {
            return nil
        }
        return photoURL(for: userID, photoID: photoID, sourceURL: url)
    }

    static func canonicalUserPhotosURL(for url: URL) -> URL? {
        guard let host = url.host?.lowercased(),
              isFlickrHost(host),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              photoID(from: url) == nil,
              let userID = userID(from: url) else {
            return nil
        }
        return try? userPhotosURL(for: userID, sourceURL: url)
    }

    static func canonicalContentURL(for url: URL) -> URL? {
        if let short = canonicalShortPhotoURL(for: url) {
            return short
        }
        if let host = url.host?.lowercased(),
           isFlickrHost(host),
           let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https",
           let userID = userID(from: url) {
            return try? userPhotosURL(for: userID, sourceURL: url)
        }
        return canonicalUserPhotosURL(for: url)
    }

    static func canonicalShortPhotoURL(for url: URL) -> URL? {
        guard let host = url.host?.lowercased(),
              isFlickrShortHost(host),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let code = shortPhotoCode(from: url),
              shortPhotoID(from: url) != nil,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        components.scheme = scheme
        components.host = host.hasSuffix(".test") ? "flic.kr.test" : "flic.kr"
        components.path = "/p/\(code)"
        components.queryItems = nil
        components.fragment = nil
        return components.url
    }

    static func userPhotosURL(for userID: String, sourceURL: URL, page: Int = 1) throws -> URL {
        guard var components = URLComponents(url: sourceURL, resolvingAgainstBaseURL: false) else {
            throw NativeDownloadError.invalidURL(sourceURL.absoluteString)
        }

        components.host = apiHost(for: sourceURL.host)
        components.path = page <= 1 ? "/photos/\(userID)" : "/photos/\(userID)/page\(page)"
        components.queryItems = nil
        components.fragment = nil

        guard let url = components.url else {
            throw NativeDownloadError.invalidURL(sourceURL.absoluteString)
        }
        return url
    }

    static func userPhotosPageURL(for userID: String, sourceURL: URL, page: Int) throws -> URL {
        guard var components = URLComponents(url: sourceURL, resolvingAgainstBaseURL: false) else {
            throw NativeDownloadError.invalidURL(sourceURL.absoluteString)
        }

        components.host = apiHost(for: sourceURL.host)
        components.path = "/photos/\(userID)/page\(max(page, 1))"
        components.queryItems = nil
        components.fragment = nil

        guard let url = components.url else {
            throw NativeDownloadError.invalidURL(sourceURL.absoluteString)
        }
        return url
    }

    private static func photoURL(for userID: String, photoID: String, sourceURL: URL) -> URL? {
        guard var components = URLComponents(url: sourceURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.host = apiHost(for: sourceURL.host)
        components.path = "/photos/\(userID)/\(photoID)"
        components.queryItems = nil
        components.fragment = nil
        return components.url
    }

    private static func photoFilename(remoteURL: URL, photoID: String, date: String?) -> String {
        let ext = remoteURL.pathExtension.trimmed.isEmpty ? "jpg" : remoteURL.pathExtension
        let dateToken = date.flatMap(originalDateTokenForFilename) ?? date
        let base = [dateToken, photoID]
            .compactMap { $0?.trimmed }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return "\(base.isEmpty ? photoID : base).\(ext)".sanitizedFilename(maxLength: 180)
    }

    private static func assetMetadata(for remoteURL: URL, photoID: String, title: String, userID: String?, pageURL: URL, date: String?, index: Int) -> [String: String] {
        let format = mediaFormat(for: remoteURL)
        return DownloadMetadata.clean([
            "site": "Flickr",
            "title": title,
            "series": title,
            "type": "image",
            "media_type": "image",
            "category": "image",
            "id": photoID,
            "photo_id": photoID,
            "gallery_id": photoID,
            "media_id": photoID,
            "page": String(index),
            "position": String(index),
            "artist": userID ?? "",
            "author": userID ?? "",
            "creator": userID ?? "",
            "user": userID ?? "",
            "username": userID ?? "",
            "uploader": userID ?? "",
            "channel": userID ?? "",
            "date": date ?? "",
            "published_date": date ?? "",
            "format": format,
            "media_format": format,
            "image_url": remoteURL.absoluteString,
            "media_url": remoteURL.absoluteString,
            "source_url": remoteURL.absoluteString,
            "page_url": pageURL.absoluteString
        ])
    }

    private static func mediaFormat(for url: URL) -> String {
        let pathExtension = url.pathExtension.lowercased()
        if !pathExtension.isEmpty {
            return pathExtension
        }
        let lower = url.absoluteString.lowercased()
        for value in ["jpg", "jpeg", "png", "gif", "webp", "avif"] where lower.contains(".\(value)") {
            return value
        }
        return ""
    }

    private static func photoTitle(fromHTML html: String, pageURL: URL) -> String {
        let title = metaContent(from: html, names: ["og:title", "twitter:title"]) ??
            titleTag(fromHTML: html) ??
            photoID(from: pageURL) ??
            "Flickr Photo"
        return cleanTitle(title)
    }

    private static func collectionTitle(fromHTML html: String, userID: String) -> String {
        let title = h1Text(fromHTML: html) ??
            metaContent(from: html, names: ["og:title", "twitter:title"]) ??
            titleTag(fromHTML: html) ??
            userID
        return "\(cleanTitle(title)) (flickr_\(userID))".sanitizedFilename(maxLength: 120)
    }

    private static func dateCreated(fromHTML html: String) -> String? {
        if let digits = firstCapture(patterns: [#""dateCreated"\s*:\s*\{\s*"data"\s*:\s*"([0-9]+)""#], in: html) {
            return digits
        }

        if let published = metaContent(from: html, names: ["article:published_time", "datepublished", "date"])?.trimmed,
           !published.isEmpty {
            if published.count >= 10 {
                let prefix = String(published.prefix(10))
                if prefix.range(of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2}$"#, options: .regularExpression) != nil {
                    return prefix
                }
            }
            return published.sanitizedFilename(maxLength: 24)
        }
        return nil
    }

    private static func numericPhotoID(fromHTML html: String) -> String? {
        firstCapture(patterns: [
            #""photoId"\s*:\s*"?([0-9]+)"?"#,
            #""id"\s*:\s*"?([0-9]{5,})"?"#
        ], in: html)
    }

    private static func cleanTitle(_ raw: String) -> String {
        var title = decodeHTML(stripTags(raw))
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmed
        for suffix in [" | Flickr", " - Flickr", " | Flickr - Photo Sharing!", " - a photo on Flickriver"] {
            if title.lowercased().hasSuffix(suffix.lowercased()) {
                title.removeLast(suffix.count)
                title = title.trimmed
            }
        }
        return title.isEmpty ? "Flickr Photo" : title
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
              let capture = Range(match.range(at: 1), in: html) else {
            return nil
        }
        return String(html[capture])
    }

    private static func h1Text(fromHTML html: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: #"<h1\b[^>]*>(.*?)</h1>"#,
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

    private static func canonicalPhotoPageURL(fromHTML html: String, baseURL: URL) -> URL? {
        var candidates: [String] = []
        candidates.append(contentsOf: metaContents(from: html, names: ["og:url", "twitter:url"]))
        candidates.append(contentsOf: canonicalLinkHREFs(fromHTML: html))

        for candidate in candidates {
            guard let absolute = absoluteURL(candidate, baseURL: baseURL) else { continue }
            if let photo = canonicalPhotoURL(for: absolute) {
                return photo
            }
            if let short = canonicalShortPhotoURL(for: absolute) {
                return short
            }
        }

        return nil
    }

    private static func metaContents(from html: String, names: Set<String>) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"<meta\b([^>]*)>"#, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        return regex.matches(in: html, range: range).compactMap { match in
            guard let attributesRange = Range(match.range(at: 1), in: html) else { return nil }
            let values = attributeValues(from: String(html[attributesRange]))
            let key = (values["property"] ?? values["name"] ?? values["itemprop"])?.lowercased()
            guard let key, names.contains(key),
                  let content = values["content"]?.trimmed,
                  !content.isEmpty else {
                return nil
            }
            return content
        }
    }

    private static func canonicalLinkHREFs(fromHTML html: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"<link\b([^>]*)>"#, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        return regex.matches(in: html, range: range).compactMap { match in
            guard let attributesRange = Range(match.range(at: 1), in: html) else { return nil }
            let values = attributeValues(from: String(html[attributesRange]))
            let rels = (values["rel"] ?? "").lowercased().components(separatedBy: .whitespacesAndNewlines)
            guard rels.contains("canonical"),
                  let href = values["href"]?.trimmed,
                  !href.isEmpty else {
                return nil
            }
            return href
        }
    }

    private static func originalDateTokenForFilename(_ raw: String) -> String? {
        guard let seconds = TimeInterval(raw.trimmed) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yy-MM-dd"
        return formatter.string(from: Date(timeIntervalSince1970: seconds))
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
            if let value = captureMatches(pattern: pattern, in: text).first {
                return value
            }
        }
        return nil
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

    private static func absoluteURL(_ raw: String, baseURL: URL) -> URL? {
        let value = raw.trimmed
        if value.hasPrefix("//") {
            return URL(string: "\(baseURL.scheme ?? "https"):\(value)")
        }
        return URL(string: value, relativeTo: baseURL)?.absoluteURL
    }

    private static func apiHost(for host: String?) -> String {
        host?.lowercased().hasSuffix(".test") == true ? "www.flickr.test" : "www.flickr.com"
    }

    private static func shortPhotoID(from url: URL) -> String? {
        guard let code = shortPhotoCode(from: url) else { return nil }
        return decodeShortPhotoID(code)
    }

    private static func shortPhotoCode(from url: URL) -> String? {
        guard let host = url.host?.lowercased(),
              isFlickrShortHost(host) else {
            return nil
        }

        let parts = url.path.split(separator: "/").map(String.init)
        guard parts.count >= 2,
              parts[0].lowercased() == "p" else {
            return nil
        }

        let code = parts[1].trimmed
        return code.isEmpty ? nil : code
    }

    private static func decodeShortPhotoID(_ code: String) -> String? {
        var value = 0
        for character in code {
            guard let digit = flickrShortDigitValues[character],
                  value <= (Int.max - digit) / 58 else {
                return nil
            }
            value = value * 58 + digit
        }
        return value > 0 ? String(value) : nil
    }

    private static func isSupportedHost(_ host: String) -> Bool {
        isFlickrHost(host) || isFlickrShortHost(host)
    }

    private static func isFlickrHost(_ host: String) -> Bool {
        host == "flickr.com" ||
            host == "www.flickr.com" ||
            host == "m.flickr.com" ||
            host.hasSuffix(".flickr.com") ||
            host == "flickr.test" ||
            host == "www.flickr.test" ||
            host.hasSuffix(".flickr.test")
    }

    private static func isFlickrShortHost(_ host: String) -> Bool {
        host == "flic.kr" ||
            host == "www.flic.kr" ||
            host == "flic.kr.test" ||
            host == "www.flic.kr.test"
    }

    private static let flickrShortAlphabet = "123456789abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ"
    private static let flickrShortDigitValues = Dictionary(uniqueKeysWithValues: flickrShortAlphabet.enumerated().map { index, character in
        (character, index)
    })

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
