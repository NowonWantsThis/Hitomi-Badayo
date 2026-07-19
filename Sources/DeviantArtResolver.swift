import Foundation

final class DeviantArtResolver {
    func canResolve(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(),
              Self.isDeviantArtHost(host),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return false
        }

        return Self.isArtworkURL(url) || Self.username(from: url) != nil
    }

    func resolve(
        _ url: URL,
        headers: HTTPRequestOptions = HTTPRequestOptions(),
        rangeExpression: String = ""
    ) async throws -> ResolvedDownload {
        let sourceURL = Self.canonicalInputURL(for: url) ?? url
        if Self.isArtworkURL(sourceURL) {
            let html = try await HTTPClient.shared.string(from: sourceURL, referer: headers.referer, userAgent: headers.userAgent)
            return try Self.resolvedArtworkDownload(fromHTML: html, pageURL: sourceURL)
        }

        guard let username = Self.username(from: sourceURL) else {
            throw NativeDownloadError.invalidURL(url.absoluteString)
        }

        let firstURL = try Self.galleryURL(for: username, sourceURL: sourceURL, page: 1)
        let firstHTML = try await HTTPClient.shared.string(from: firstURL, referer: headers.referer ?? sourceURL.absoluteString, userAgent: headers.userAgent)
        let title = Self.galleryTitle(fromHTML: firstHTML, username: username)
        let itemRange = rangeExpression.trimmed
        let discoveryLimit = try Self.maximumRequestedItem(in: itemRange)
        var artworkURLs: [URL] = []
        var seenArtworkURLs = Set<String>()
        var galleryPageCount = 1

        func appendNewArtworkURLs(_ candidates: [URL]) -> Int {
            var appended = 0
            for candidate in candidates {
                let identity = URLIdentity.normalize(candidate.absoluteString)
                guard seenArtworkURLs.insert(identity).inserted else { continue }
                artworkURLs.append(candidate)
                appended += 1
                if let discoveryLimit, artworkURLs.count >= discoveryLimit {
                    break
                }
            }
            return appended
        }

        _ = appendNewArtworkURLs(Self.artworkURLs(fromHTML: firstHTML, baseURL: firstURL))
        var page = 2
        while discoveryLimit.map({ artworkURLs.count < $0 }) ?? true {
            try Task.checkCancellation()
            let pageURL = try Self.galleryURL(for: username, sourceURL: sourceURL, page: page)
            let html = try await HTTPClient.shared.string(
                from: pageURL,
                referer: firstURL.absoluteString,
                userAgent: headers.userAgent
            )
            galleryPageCount += 1
            let appended = appendNewArtworkURLs(Self.artworkURLs(fromHTML: html, baseURL: pageURL))
            guard appended > 0 else { break }
            page += 1
        }

        guard !artworkURLs.isEmpty else { throw NativeDownloadError.noFiles }
        var selectedArtworks = Array(artworkURLs.enumerated())
        var selectedPositions: [Int]?
        if !itemRange.isEmpty {
            let indexes = try Self.itemIndexes(for: itemRange, total: artworkURLs.count)
            selectedArtworks = indexes.map { (offset: $0, element: artworkURLs[$0]) }
            selectedPositions = indexes.map { $0 + 1 }
        }

        var assets: [ResolvedAsset] = []
        var seen = Set<String>()
        var resolvedArtworkCount = 0
        var skippedArtworkCount = 0

        for selectedArtwork in selectedArtworks {
            try Task.checkCancellation()
            let artworkURL = selectedArtwork.element
            do {
                let html = try await HTTPClient.shared.string(
                    from: artworkURL,
                    referer: firstURL.absoluteString,
                    userAgent: headers.userAgent
                )
                let resolved = try Self.resolvedArtworkDownload(fromHTML: html, pageURL: artworkURL)
                resolvedArtworkCount += 1

                for asset in resolved.assets {
                    let normalized = URLIdentity.normalize(asset.remoteURL.absoluteString)
                    guard !seen.contains(normalized) else { continue }
                    seen.insert(normalized)
                    var metadata = asset.metadata
                    metadata["collection_position"] = String(selectedArtwork.offset + 1)
                    metadata["artwork_position"] = String(selectedArtwork.offset + 1)
                    assets.append(ResolvedAsset(
                        remoteURL: asset.remoteURL,
                        filename: asset.filename,
                        metadata: metadata,
                        referer: asset.referer,
                        userAgent: asset.userAgent,
                        additionalHeaders: asset.additionalHeaders,
                        decryption: asset.decryption,
                        xorKey: asset.xorKey,
                        pixivGridShuffle: asset.pixivGridShuffle,
                        pixivUgoiraPackage: asset.pixivUgoiraPackage,
                        lezhinImageShuffle: asset.lezhinImageShuffle,
                        pythonSegmentDecorator: asset.pythonSegmentDecorator
                    ))
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                skippedArtworkCount += 1
            }
        }

        guard !assets.isEmpty else {
            throw NativeDownloadError.noFiles
        }

        var metadata = Self.deviantArtMetadata(
            username: username,
            title: title,
            pageURL: sourceURL,
            artworkID: "",
            assets: assets
        )
        metadata["listed_artwork_count"] = String(artworkURLs.count)
        metadata["resolved_artwork_count"] = String(resolvedArtworkCount)
        metadata["resolved_media_count"] = String(assets.count)
        metadata["gallery_page_count"] = String(galleryPageCount)
        if skippedArtworkCount > 0 {
            metadata["skipped_count"] = String(skippedArtworkCount)
        }
        if let selectedPositions {
            metadata["range"] = itemRange
            metadata["range_scope"] = "collection_items"
            metadata["range_total"] = String(artworkURLs.count)
            metadata["range_selected"] = String(selectedPositions.count)
            metadata["range_indexes"] = selectedPositions.map(String.init).joined(separator: ",")
        }

        return ResolvedDownload(
            title: title,
            folderName: "DeviantArt \(title)".sanitizedFilename(maxLength: 120),
            assets: assets,
            metadata: metadata
        )
    }

    static func resolvedArtworkDownload(fromHTML html: String, pageURL: URL) throws -> ResolvedDownload {
        let title = artworkTitle(fromHTML: html, pageURL: pageURL).sanitizedFilename(maxLength: 120)
        let urls = mediaURLs(fromHTML: html, pageURL: pageURL)

        if urls.isEmpty, html.range(of: "joinpoint=mature", options: .caseInsensitive) != nil {
            throw NativeDownloadError.unsupported("DeviantArt mature content requires a logged-in cookie.")
        }

        guard !urls.isEmpty else {
            throw NativeDownloadError.noFiles
        }

        let artworkID = artworkID(from: pageURL) ?? urls.first?.deletingPathExtension().lastPathComponent ?? "deviation"
        let assets = urls.enumerated().map { offset, remote in
            ResolvedAsset(
                remoteURL: remote,
                filename: filename(for: remote, title: title, artworkID: artworkID, index: offset + 1),
                metadata: assetMetadata(
                    for: remote,
                    artworkID: artworkID,
                    title: title,
                    username: username(from: pageURL),
                    pageURL: pageURL,
                    index: offset + 1
                ),
                referer: pageURL.absoluteString
            )
        }

        return ResolvedDownload(
            title: title,
            folderName: "DeviantArt \(title)".sanitizedFilename(maxLength: 120),
            assets: assets,
            metadata: deviantArtMetadata(
                username: username(from: pageURL),
                title: title,
                pageURL: pageURL,
                artworkID: artworkID,
                assets: assets
            )
        )
    }

    private static func deviantArtMetadata(username: String?, title: String = "", pageURL: URL? = nil, artworkID: String = "", assets: [ResolvedAsset] = []) -> [String: String] {
        let imageCount = assets.filter { $0.metadata["media_type"] == "image" }.count
        let videoCount = assets.filter { $0.metadata["media_type"] == "video" }.count
        let contentID = artworkID.isEmpty ? username ?? "" : artworkID
        return DownloadMetadata.clean([
            "site": "DeviantArt",
            "title": title,
            "series": title,
            "category": assets.contains(where: { $0.metadata["type"] == "video" }) ? "video" : "image",
            "type": artworkID.isEmpty ? "gallery" : "artwork",
            "media_type": artworkID.isEmpty ? "gallery" : "artwork",
            "host": pageURL?.host ?? "",
            "id": contentID,
            "artwork_id": artworkID,
            "gallery_id": contentID,
            "media_count": assets.isEmpty ? "" : String(assets.count),
            "image_count": imageCount > 0 ? String(imageCount) : "",
            "video_count": videoCount > 0 ? String(videoCount) : "",
            "artist": username ?? "",
            "author": username ?? "",
            "creator": username ?? "",
            "user": username ?? "",
            "username": username ?? "",
            "uploader": username ?? "",
            "channel": username ?? "",
            "url": pageURL?.absoluteString ?? "",
            "source_url": pageURL?.absoluteString ?? "",
            "page_url": pageURL?.absoluteString ?? ""
        ])
    }

    static func mediaURLs(fromHTML html: String, pageURL: URL) -> [URL] {
        let normalizedHTML = normalizeEscapes(decodeHTML(html))
        var candidates: [String] = []
        candidates.append(contentsOf: metaURLCandidates(from: html))
        candidates.append(contentsOf: noscriptImageCandidates(from: normalizedHTML))
        candidates.append(contentsOf: attributeMediaCandidates(from: normalizedHTML))
        candidates.append(contentsOf: jsonMediaCandidates(from: normalizedHTML))

        var output: [URL] = []
        var seen = Set<String>()
        for candidate in candidates {
            guard let remote = absoluteURL(candidate, baseURL: pageURL),
                  shouldDownload(remote) else {
                continue
            }

            let normalized = URLIdentity.normalize(remote.absoluteString)
            guard normalized != URLIdentity.normalize(pageURL.absoluteString),
                  !seen.contains(normalized) else {
                continue
            }
            seen.insert(normalized)
            output.append(remote)
        }
        return output
    }

    static func artworkURLs(fromHTML html: String, baseURL: URL) -> [URL] {
        let hrefs = anchorHREFs(fromHTML: html)
        var output: [URL] = []
        for href in hrefs {
            guard let url = absoluteURL(href, baseURL: baseURL),
                  isArtworkURL(url),
                  let host = url.host?.lowercased(),
                  isDeviantArtHost(host) else {
                continue
            }
            output.append(canonicalArtworkURL(url) ?? url)
        }
        return uniqueURLs(output)
    }

    static func maxGalleryPage(fromHTML html: String) -> Int {
        let pattern = #"(?:[?&]|&amp;)page=([0-9]+)"#
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
            throw NativeDownloadError.unsupported("Range did not match any DeviantArt artworks.")
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

    static func galleryURL(for username: String, sourceURL: URL, page: Int = 1) throws -> URL {
        guard var components = URLComponents(url: sourceURL, resolvingAgainstBaseURL: false) else {
            throw NativeDownloadError.invalidURL(sourceURL.absoluteString)
        }

        components.host = canonicalHost(for: sourceURL.host)
        components.path = downloadCollectionPath(username: username, sourceURL: sourceURL)
        components.fragment = nil
        components.queryItems = page > 1 ? [URLQueryItem(name: "page", value: String(page))] : nil

        guard let url = components.url else {
            throw NativeDownloadError.invalidURL(sourceURL.absoluteString)
        }
        return url
    }

    static func canonicalProfileURL(username rawUsername: String, sourceURL: URL? = nil) -> URL? {
        guard let username = normalizedUsername(rawUsername) else {
            return nil
        }
        var components = URLComponents()
        components.scheme = sourceURL?.scheme ?? "https"
        components.host = canonicalHost(for: sourceURL?.host)
        components.path = "/\(username)"
        return components.url
    }

    static func canonicalInputURL(for url: URL) -> URL? {
        guard let host = url.host?.lowercased(),
              isDeviantArtHost(host),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }

        if isArtworkURL(url) {
            return canonicalArtworkURL(url)
        }

        return canonicalCollectionURL(for: url)
    }

    static func canonicalCollectionURL(for url: URL) -> URL? {
        guard let host = url.host?.lowercased(),
              isDeviantArtHost(host),
              !isArtworkURL(url),
              let username = username(from: url),
              let path = collectionPath(username: username, sourceURL: url, defaultPlainGalleryToAll: true) else {
            return nil
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = canonicalHost(for: host)
        components.path = path
        return components.url
    }

    static func canonicalProfileOrCollectionURL(path rawPath: String, sourceURL: URL? = nil) -> URL? {
        let parts = rawPath
            .trimmed
            .trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        guard let first = parts.first,
              let username = normalizedUsername(first),
              let path = collectionPath(
                username: username,
                tailParts: Array(parts.dropFirst()),
                defaultPlainGalleryToAll: true
              ) else {
            return nil
        }

        var components = URLComponents()
        components.scheme = sourceURL?.scheme ?? "https"
        components.host = canonicalHost(for: sourceURL?.host)
        components.path = path
        return components.url
    }

    static func isArtworkURL(_ url: URL) -> Bool {
        let parts = url.path.split(separator: "/").map(String.init)
        if parts.count >= 2, parts[0].lowercased() == "art" {
            return true
        }
        if parts.count >= 3, parts[1].lowercased() == "art" {
            return true
        }
        return false
    }

    static func username(from url: URL) -> String? {
        guard let host = url.host?.lowercased(), isDeviantArtHost(host) else { return nil }

        if let subdomain = legacySubdomainUsername(from: host) {
            return normalizedUsername(subdomain)
        }

        let parts = url.path.split(separator: "/").map(String.init)
        guard let first = parts.first?.trimmed,
              !first.isEmpty,
              let username = normalizedUsername(first) else {
            return nil
        }
        return username
    }

    private static func canonicalArtworkURL(_ url: URL) -> URL? {
        guard let user = username(from: url),
              let artIndex = url.path.split(separator: "/").map(String.init).firstIndex(where: { $0.lowercased() == "art" }) else {
            return nil
        }
        let parts = url.path.split(separator: "/").map(String.init)
        guard artIndex + 1 < parts.count else { return nil }
        let slug = parts[(artIndex + 1)...].joined(separator: "/")
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        components.host = canonicalHost(for: url.host)
        components.path = "/\(user)/art/\(slug)"
        components.queryItems = nil
        components.fragment = nil
        return components.url
    }

    private static func downloadCollectionPath(username: String, sourceURL: URL) -> String {
        let profilePath = "/\(username)"
        guard let path = collectionPath(username: username, sourceURL: sourceURL, defaultPlainGalleryToAll: true),
              path != profilePath else {
            return "\(profilePath)/gallery/all"
        }
        return path
    }

    private static func collectionPath(username: String, sourceURL: URL, defaultPlainGalleryToAll: Bool) -> String? {
        guard let host = sourceURL.host?.lowercased() else { return nil }
        let parts = sourceURL.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        let tailParts = legacySubdomainUsername(from: host) != nil ? parts : Array(parts.dropFirst())
        return collectionPath(
            username: username,
            tailParts: tailParts,
            defaultPlainGalleryToAll: defaultPlainGalleryToAll
        )
    }

    private static func collectionPath(username: String, tailParts: [String], defaultPlainGalleryToAll: Bool) -> String? {
        guard normalizedUsername(username) != nil else { return nil }
        guard !tailParts.isEmpty else { return "/\(username)" }
        guard tailParts.allSatisfy(isSafeCollectionPathComponent) else { return nil }

        let lowered = tailParts.map { $0.lowercased() }
        switch lowered.first {
        case "gallery":
            if tailParts.count == 1 {
                return defaultPlainGalleryToAll ? "/\(username)/gallery/all" : nil
            }
            guard tailParts.count <= 3 else { return nil }
            return "/\(username)/\(tailParts.joined(separator: "/"))"
        case "favourites", "favorites":
            guard tailParts.count <= 3 else { return nil }
            return "/\(username)/\(tailParts.joined(separator: "/"))"
        default:
            return nil
        }
    }

    private static func isSafeCollectionPathComponent(_ value: String) -> Bool {
        guard !value.isEmpty, value != ".", value != ".." else { return false }
        return value.range(of: #"^[A-Za-z0-9._~%-]+$"#, options: .regularExpression) != nil
    }

    private static func normalizedUsername(_ rawUsername: String) -> String? {
        let username = rawUsername.trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "@/ "))
        guard username.range(of: #"^[A-Za-z0-9_-]{1,80}$"#, options: .regularExpression) != nil,
              !reservedPathComponents.contains(username.lowercased()) else {
            return nil
        }
        return username
    }

    private static func artworkID(from url: URL) -> String? {
        let last = url.lastPathComponent
        if let value = captureMatches(pattern: #"-([0-9]+)$"#, in: last).first {
            return value
        }
        return last.isEmpty ? nil : last
    }

    private static func filename(for url: URL, title: String, artworkID: String, index: Int) -> String {
        let ext = url.pathExtension.trimmed.isEmpty ? "jpg" : url.pathExtension
        let suffix = index == 1 ? "" : " \(index)"
        return "\(artworkID) - \(title)\(suffix).\(ext)".sanitizedFilename(maxLength: 180)
    }

    private static func assetMetadata(for url: URL, artworkID: String, title: String, username: String?, pageURL: URL, index: Int) -> [String: String] {
        let type = mediaType(for: url)
        let format = mediaFormat(for: url)
        let mediaID = "\(artworkID)-\(index)"
        return DownloadMetadata.clean([
            "site": "DeviantArt",
            "title": title,
            "series": title,
            "type": type,
            "media_type": type,
            "category": type == "video" ? "video" : "image",
            "id": artworkID,
            "artwork_id": artworkID,
            "gallery_id": artworkID,
            "media_id": mediaID,
            "page": String(index),
            "position": String(index),
            "artist": username ?? "",
            "author": username ?? "",
            "creator": username ?? "",
            "user": username ?? "",
            "username": username ?? "",
            "uploader": username ?? "",
            "channel": username ?? "",
            "format": format,
            "media_format": format,
            "image_url": type == "image" ? url.absoluteString : "",
            "video_url": type == "video" ? url.absoluteString : "",
            "media_url": url.absoluteString,
            "source_url": url.absoluteString,
            "page_url": pageURL.absoluteString
        ])
    }

    private static func mediaType(for url: URL) -> String {
        ["mp4", "webm", "mov", "m4v"].contains(mediaFormat(for: url)) ? "video" : "image"
    }

    private static func mediaFormat(for url: URL) -> String {
        let pathExtension = url.pathExtension.lowercased()
        if !pathExtension.isEmpty {
            return pathExtension
        }
        let lower = url.absoluteString.lowercased()
        for value in ["jpg", "jpeg", "png", "gif", "webp", "avif", "mp4", "webm", "mov", "m4v"] where lower.contains(".\(value)") {
            return value
        }
        return ""
    }

    private static func artworkTitle(fromHTML html: String, pageURL: URL) -> String {
        let title = metaContent(from: html, names: ["og:title", "twitter:title"]) ??
            titleTag(fromHTML: html) ??
            pageURL.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "-", with: " ")
        return cleanTitle(title)
    }

    private static func galleryTitle(fromHTML html: String, username: String) -> String {
        let title = metaContent(from: html, names: ["og:title", "twitter:title"]) ??
            titleTag(fromHTML: html) ??
            username
        return cleanTitle(title)
    }

    private static func metaURLCandidates(from html: String) -> [String] {
        let names: Set<String> = [
            "og:image", "og:image:url", "og:image:secure_url",
            "og:video", "og:video:url", "og:video:secure_url",
            "twitter:image", "twitter:image:src", "twitter:player:stream"
        ]

        guard let regex = try? NSRegularExpression(pattern: #"<meta\b([^>]*)>"#, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        var candidates: [String] = []
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
            candidates.append(content)
        }
        return candidates
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

    private static func noscriptImageCandidates(from html: String) -> [String] {
        let blocks = captureMatches(pattern: #"<noscript\b[^>]*>(.*?)</noscript>"#, in: html)
        return blocks.flatMap { block in
            attributeMediaCandidates(from: block)
        }
    }

    private static func attributeMediaCandidates(from html: String) -> [String] {
        guard let tagRegex = try? NSRegularExpression(
            pattern: #"<(img|video|source|a)\b([^>]*)>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return []
        }

        var candidates: [String] = []
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        for match in tagRegex.matches(in: html, range: range) {
            guard let attributesRange = Range(match.range(at: 2), in: html) else { continue }
            let values = attributeValues(from: String(html[attributesRange]))
            for key in ["data-super-full-img", "data-fullview-src", "data-download-url", "data-src", "src", "href"] {
                if let value = values[key]?.trimmed, !value.isEmpty {
                    candidates.append(value)
                }
            }
            if let srcset = values["srcset"] {
                candidates.append(contentsOf: srcsetCandidates(srcset))
            }
        }
        return candidates
    }

    private static func jsonMediaCandidates(from html: String) -> [String] {
        let keys = [
            "prettyName",
            "src",
            "url",
            "fullview",
            "fullView",
            "downloadUrl",
            "download_url"
        ]

        var candidates: [String] = []
        for key in keys {
            let pattern = #""\#(NSRegularExpression.escapedPattern(for: key))"\s*:\s*"([^"]+)""#
            candidates.append(contentsOf: captureMatches(pattern: pattern, in: html))
        }
        return candidates
    }

    private static func srcsetCandidates(_ srcset: String) -> [String] {
        srcset
            .split(separator: ",")
            .compactMap { part in
                part
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .split(separator: " ")
                    .first
                    .map(String.init)
            }
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

    private static func shouldDownload(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        if isDeviantArtHost(host), url.path.lowercased().contains("/join/") {
            return false
        }

        let ext = url.pathExtension.lowercased()
        if ["jpg", "jpeg", "png", "gif", "webp", "avif", "mp4", "webm", "mov", "m4v"].contains(ext) {
            return true
        }

        return host.contains("wixmp") || host.contains("deviantart.net")
    }

    private static func cleanTitle(_ raw: String) -> String {
        var title = decodeHTML(stripTags(raw))
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmed

        for pattern in [
            #"(?i)\s+by\s+[^|]+?\s+on\s+deviantart$"#,
            #"(?i)\s+on\s+deviantart$"#,
            #"(?i)\s+\|\s+deviantart$"#,
            #"(?i)\s+-\s+deviantart$"#
        ] {
            title = title.replacingOccurrences(of: pattern, with: "", options: .regularExpression).trimmed
        }

        return title.isEmpty ? "DeviantArt Artwork" : title
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
            return normalizeEscapes(String(text[capture]))
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
        let value = normalizeEscapes(decodeHTML(raw)).trimmed
        if value.hasPrefix("//") {
            return URL(string: "\(baseURL.scheme ?? "https"):\(value)")
        }
        return URL(string: value, relativeTo: baseURL)?.absoluteURL
    }

    private static func normalizeEscapes(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"\\u002F"#, with: "/", options: .caseInsensitive)
            .replacingOccurrences(of: #"\/"#, with: "/")
            .replacingOccurrences(of: #"\\/"#, with: "/")
            .replacingOccurrences(of: #"\\u0026"#, with: "&", options: .caseInsensitive)
    }

    private static func canonicalHost(for host: String?) -> String {
        host?.lowercased().hasSuffix(".test") == true ? "www.deviantart.test" : "www.deviantart.com"
    }

    private static func legacySubdomainUsername(from host: String) -> String? {
        let lowered = host.lowercased()
        guard lowered.hasSuffix(".deviantart.com") || lowered.hasSuffix(".deviantart.test") else {
            return nil
        }
        let first = lowered.split(separator: ".").first.map(String.init)
        guard let first,
              !["www", "m", "deviantart"].contains(first) else {
            return nil
        }
        return first
    }

    private static func isDeviantArtHost(_ host: String) -> Bool {
        host == "deviantart.com" ||
            host == "www.deviantart.com" ||
            host == "m.deviantart.com" ||
            host.hasSuffix(".deviantart.com") ||
            host == "deviantart.test" ||
            host == "www.deviantart.test" ||
            host.hasSuffix(".deviantart.test")
    }

    private static let reservedPathComponents: Set<String> = [
        "about",
        "account",
        "art",
        "browse",
        "chat",
        "collections",
        "daily-deviations",
        "deviations",
        "developers",
        "groups",
        "help",
        "join",
        "login",
        "messages",
        "notifications",
        "popular",
        "privacy",
        "search",
        "settings",
        "shop",
        "signup",
        "submit",
        "tag",
        "terms",
        "users"
    ]

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
