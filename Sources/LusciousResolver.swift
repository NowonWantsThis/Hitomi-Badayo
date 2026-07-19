import Foundation

struct LusciousMediaAsset {
    var remoteURL: URL
    var id: String? = nil
    var title: String?
    var position: Int?
    var kind: String
    var referer: String
}

final class LusciousResolver {
    private let itemsPerPage = 50

    func canResolve(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(),
              Self.isSupportedHost(host),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return false
        }
        let path = url.path.lowercased()
        return path.contains("/albums/") || path.contains("/videos/")
    }

    func resolve(
        _ url: URL,
        headers: HTTPRequestOptions = HTTPRequestOptions(),
        assetLimit: Int? = nil
    ) async throws -> ResolvedDownload {
        let pageURL = Self.canonicalURL(for: url) ?? url
        let html = try await HTTPClient.shared.string(from: pageURL, referer: headers.referer, userAgent: headers.userAgent)
        if Self.isLoginRequiredHTML(html) {
            throw NativeDownloadError.unsupported("Luscious login is required for this page.")
        }

        let title = Self.title(fromHTML: html, pageURL: pageURL)
        if Self.isVideoPage(pageURL) {
            let videos = Self.videoURLs(fromHTML: html, baseURL: pageURL)
            let directVideos = videos.filter { ["mp4", "webm", "mov"].contains(Self.mediaKind(for: $0)) }
            if !directVideos.isEmpty {
                return try Self.resolvedVideoDownload(title: title, videos: directVideos, pageURL: pageURL, pageHTML: html)
            }
            if let hls = videos.first(where: { Self.mediaKind(for: $0) == "m3u8" }) {
                let hlsDownload = try await M3U8Resolver().resolve(
                    hls,
                    headers: HTTPRequestOptions(referer: headers.referer ?? pageURL.absoluteString, userAgent: headers.userAgent)
                )
                return ResolvedDownload(
                    title: title,
                    folderName: "Luscious \(title)".sanitizedFilename(maxLength: 120),
                    assets: hlsDownload.assets,
                    packageMode: hlsDownload.packageMode,
                    metadata: Self.downloadMetadata(
                        from: Self.lusciousMetadata(title: title, albumID: nil, pageURL: pageURL, html: html),
                        type: "video",
                        media: [(kind: "video", url: hls)]
                    )
                )
            }
            throw NativeDownloadError.noFiles
        }

        let albumID = Self.albumID(from: pageURL) ?? Self.albumID(fromHTML: html)
        guard let albumID else {
            throw NativeDownloadError.missingGalleryID(pageURL.absoluteString)
        }

        let finiteAssetLimit = assetLimit.flatMap { $0 > 0 ? $0 : nil }
        var media: [LusciousMediaAsset] = []
        var seen = Set<String>()
        var page = 1
        var hasNextPage = true
        var resolvedPageCount = 0

        while hasNextPage {
            try Task.checkCancellation()
            let apiURL = try Self.albumAPIURL(albumID: albumID, page: page, sourceURL: pageURL, itemsPerPage: itemsPerPage)
            let data = try await HTTPClient.shared.data(
                from: apiURL,
                referer: pageURL.absoluteString,
                userAgent: headers.userAgent,
                additionalHeaders: ["Accept": "application/json, text/plain, */*"]
            )
            let parsed = try Self.mediaAssets(fromAPIData: data, sourceURL: pageURL)
            guard !parsed.items.isEmpty else { break }

            resolvedPageCount += 1
            var appendedOnPage = 0
            for item in parsed.items {
                try Task.checkCancellation()
                let normalized = URLIdentity.normalize(item.remoteURL.absoluteString)
                guard !seen.contains(normalized) else { continue }
                seen.insert(normalized)
                media.append(item)
                appendedOnPage += 1
                if let finiteAssetLimit, media.count >= finiteAssetLimit { break }
            }
            if appendedOnPage == 0 { break }
            if let finiteAssetLimit, media.count >= finiteAssetLimit { break }

            hasNextPage = parsed.hasNextPage
            page += 1
        }

        var resolved = try Self.resolvedAlbumDownload(title: title, albumID: albumID, media: media, sourceURL: pageURL, pageHTML: html)
        resolved.metadata["resolved_page_count"] = String(resolvedPageCount)
        resolved.metadata["resolved_media_count"] = String(media.count)
        return resolved
    }

    static func resolvedAlbumDownload(title: String, albumID: String, media: [LusciousMediaAsset], sourceURL: URL, pageHTML: String? = nil) throws -> ResolvedDownload {
        guard !media.isEmpty else {
            throw NativeDownloadError.noFiles
        }
        let metadata = downloadMetadata(
            from: lusciousMetadata(title: title, albumID: albumID, pageURL: sourceURL, html: pageHTML),
            type: "album",
            media: media.map { (kind: $0.kind, url: $0.remoteURL) }
        )
        return ResolvedDownload(
            title: title,
            folderName: "Luscious \(title)".sanitizedFilename(maxLength: 120),
            assets: media.enumerated().map { offset, item in
                asset(for: item, index: offset + 1, metadata: assetMetadata(for: item, baseMetadata: metadata, index: offset + 1))
            },
            metadata: metadata
        )
    }

    static func resolvedVideoDownload(title: String, videos: [URL], pageURL: URL, pageHTML: String? = nil) throws -> ResolvedDownload {
        guard !videos.isEmpty else {
            throw NativeDownloadError.noFiles
        }
        let metadata = downloadMetadata(
            from: lusciousMetadata(title: title, albumID: albumID(from: pageURL) ?? albumID(fromHTML: pageHTML ?? ""), pageURL: pageURL, html: pageHTML),
            type: "video",
            media: videos.map { (kind: "video", url: $0) }
        )
        return ResolvedDownload(
            title: title,
            folderName: "Luscious \(title)".sanitizedFilename(maxLength: 120),
            assets: videos.enumerated().map { offset, video in
                let kind = mediaKind(for: video)
                let ext = kind.isEmpty ? "mp4" : kind
                let suffix = offset == 0 ? "" : " \(offset + 1)"
                return ResolvedAsset(
                    remoteURL: video,
                    filename: "\(title)\(suffix).\(ext)".sanitizedFilename(maxLength: 180),
                    metadata: assetMetadata(for: video, kind: "video", baseMetadata: metadata, pageURL: pageURL, index: offset + 1),
                    referer: pageURL.absoluteString
                )
            },
            metadata: metadata
        )
    }

    static func albumID(from url: URL) -> String? {
        let parts = pathParts(from: url)
        guard let index = parts.firstIndex(where: { $0.lowercased() == "albums" }),
              index + 1 < parts.count else {
            return nil
        }

        for part in parts[(index + 1)...].reversed() {
            if let match = firstCapture(patterns: [#"([0-9]{2,})$"#], in: part) {
                return match
            }
        }
        return nil
    }

    static func albumID(fromHTML html: String) -> String? {
        firstCapture(patterns: [
            #"/moderation/flag/album/[0-9]+/[^"']*[\?&]id=([0-9]+)"#,
            #""album_id"\s*[:,]\s*"([0-9]+)""#,
            #"\balbum_id\s*[:=]\s*["']?([0-9]+)"#,
            #"/albums/[^"']*?([0-9]{2,})(?:[/?#"']|$)"#
        ], in: html)
    }

    static func albumAPIURL(albumID: String, page: Int, sourceURL: URL, itemsPerPage: Int = 50) throws -> URL {
        var components = URLComponents()
        components.scheme = sourceURL.scheme ?? "https"
        components.host = apiHost(for: sourceURL)
        components.path = "/graphql/nobatch/"

        let variables: [String: Any] = [
            "input": [
                "filters": [
                    ["name": "album_id", "value": albumID]
                ],
                "display": "rating_all_time",
                "items_per_page": itemsPerPage,
                "page": page
            ]
        ]
        let variableData = try JSONSerialization.data(withJSONObject: variables, options: [.sortedKeys])
        let variableString = String(decoding: variableData, as: UTF8.self)

        components.queryItems = [
            URLQueryItem(name: "operationName", value: "AlbumListOwnPictures"),
            URLQueryItem(name: "query", value: albumListQuery),
            URLQueryItem(name: "variables", value: variableString)
        ]
        guard let url = components.url else {
            throw NativeDownloadError.invalidURL("Luscious album API URL")
        }
        return url
    }

    static func mediaAssets(fromAPIData data: Data, sourceURL: URL) throws -> (items: [LusciousMediaAsset], hasNextPage: Bool) {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NativeDownloadError.invalidGalleryData
        }
        if let errors = root["errors"] as? [[String: Any]],
           let message = errors.compactMap({ $0["message"] as? String }).first {
            throw NativeDownloadError.unsupported("Luscious API error: \(message)")
        }
        guard let list = (((root["data"] as? [String: Any])?["picture"] as? [String: Any])?["list"] as? [String: Any]) else {
            throw NativeDownloadError.invalidGalleryData
        }

        let info = list["info"] as? [String: Any]
        let hasNext = flexibleBool(info?["has_next_page"]) ?? flexibleBool(info?["hasNextPage"]) ?? false
        let rawItems = list["items"] as? [[String: Any]] ?? []

        var items: [LusciousMediaAsset] = []
        var seen = Set<String>()
        for raw in rawItems {
            guard let asset = mediaAsset(fromItem: raw, sourceURL: sourceURL) else { continue }
            let normalized = URLIdentity.normalize(asset.remoteURL.absoluteString)
            guard !seen.contains(normalized) else { continue }
            seen.insert(normalized)
            items.append(asset)
        }
        return (items, hasNext)
    }

    static func videoURLs(fromHTML html: String, baseURL: URL) -> [URL] {
        var results: [URL] = []
        var seen = Set<String>()

        func append(_ raw: String?) {
            guard let raw else { return }
            let cleaned = decodeURLString(raw)
            guard let remote = absoluteURL(cleaned, baseURL: baseURL),
                  ["mp4", "webm", "mov", "m3u8"].contains(mediaKind(for: remote)) else {
                return
            }
            let normalized = URLIdentity.normalize(remote.absoluteString)
            guard !seen.contains(normalized) else { return }
            seen.insert(normalized)
            results.append(remote)
        }

        for tag in ["source", "video"] {
            for attrs in tagAttributes(tag: tag, html: html) {
                let values = attributeValues(from: attrs)
                append(values["src"] ?? values["data-src"])
            }
        }

        for name in ["og:video", "og:video:url", "og:video:secure_url", "twitter:player:stream"] {
            append(metaContent(from: html, names: [name]))
        }

        for raw in firstCaptures(patterns: [
            #""(?:url_to_video|source|src|file)"\s*:\s*"([^"]+\.(?:mp4|webm|mov|m3u8)(?:\?[^"]*)?)""#,
            #"'(?:url_to_video|source|src|file)'\s*:\s*'([^']+\.(?:mp4|webm|mov|m3u8)(?:\?[^']*)?)'"#,
            #"\b(?:src|source)\s*=\s*["']([^"']+\.(?:mp4|webm|mov|m3u8)(?:\?[^"']*)?)["']"#
        ], in: html) {
            append(raw)
        }

        return results
    }

    static func title(fromHTML html: String, pageURL: URL) -> String {
        let candidates = [
            elementText(pattern: #"<h1\b[^>]*>(.*?)</h1>"#, in: html),
            elementText(pattern: #"<[^>]+\bclass\s*=\s*["'][^"']*(?:album[-_ ]?title|gallery[-_ ]?title|video[-_ ]?title|title)[^"']*["'][^>]*>(.*?)</[^>]+>"#, in: html),
            metaContent(from: html, names: ["og:title", "twitter:title", "title", "name"]),
            attributeContent(fromHTML: html, attributeNames: ["data-album-title", "data-gallery-title", "data-video-title", "data-title"]),
            scriptTitle(fromHTML: html),
            titleTag(fromHTML: html),
            titleFromURLSlug(pageURL),
            albumID(from: pageURL),
            pageURL.lastPathComponent
        ]

        for candidate in candidates {
            guard let candidate else { continue }
            let title = cleanTitle(candidate, fallback: "")
            if isUsefulTitle(title) {
                return title
            }
        }
        return "Luscious \(albumID(from: pageURL) ?? "media")".sanitizedFilename(maxLength: 120)
    }

    static func isVideoPage(_ url: URL) -> Bool {
        url.path.lowercased().contains("/videos/")
    }

    static func canonicalURL(for url: URL) -> URL? {
        guard let host = url.host?.lowercased(),
              isSupportedHost(host),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        if host == "members.luscious.net" {
            components.host = "www.luscious.net"
        } else if host == "members.luscious.test" {
            components.host = "www.luscious.test"
        }
        components.queryItems = nil
        components.fragment = nil
        return components.url
    }

    static func mediaKind(for url: URL) -> String {
        let absolute = url.absoluteString.lowercased()
        for ext in ["m3u8", "mp4", "webm", "mov", "jpg", "jpeg", "png", "webp", "gif", "avif"] {
            if absolute.range(of: #"\.\#(ext)(?:[?#]|$)"#, options: .regularExpression) != nil {
                return ext == "jpeg" ? "jpg" : ext
            }
        }
        let ext = url.pathExtension.lowercased()
        return ext == "jpeg" ? "jpg" : ext
    }

    static func isLoginRequiredHTML(_ html: String) -> Bool {
        let lowered = html.lowercased()
        return lowered.contains("loginrequired") ||
            lowered.contains("members.luscious.net/login") ||
            lowered.contains("/login") && lowered.contains("password") && lowered.contains("luscious")
    }

    static func asset(for item: LusciousMediaAsset, index: Int, metadata: [String: String] = [:]) -> ResolvedAsset {
        let ext = mediaKind(for: item.remoteURL)
        let fallback = item.kind == "video" ? "mp4" : "jpg"
        return ResolvedAsset(
            remoteURL: item.remoteURL,
            filename: originalStyleAlbumFilename(for: item, index: index, extensionName: ext.isEmpty ? fallback : ext),
            metadata: metadata,
            referer: item.referer
        )
    }

    private static func originalStyleAlbumFilename(for item: LusciousMediaAsset, index: Int, extensionName: String) -> String {
        let base = item.id?.trimmed.isEmpty == false ? item.id!.trimmed : String(format: "%04d", index)
        return "\(base).\(extensionName)".sanitizedFilename(maxLength: 180)
    }

    static func lusciousMetadata(title: String, albumID: String?, pageURL: URL, html: String?) -> [String: String] {
        let links = html.map { anchorTexts(fromHTML: $0) } ?? []
        let tags = linkTexts(links, markers: ["tag", "tags"])
        let categories = linkTexts(links, markers: ["category", "categories", "genre", "genres"])
        let uploader = firstLinkText(links, markers: ["user", "users", "member", "members", "models", "model"])
        let effectiveAlbumID = albumID ?? html.flatMap { Self.albumID(fromHTML: $0) } ?? Self.albumID(from: pageURL)

        return DownloadMetadata.clean([
            "artist": uploader,
            "author": uploader,
            "creator": uploader,
            "uploader": uploader,
            "channel": uploader,
            "series": title,
            "category": categories.joined(separator: ", "),
            "tag": tags.joined(separator: ", "),
            "tags": tags.joined(separator: ", "),
            "album_id": effectiveAlbumID ?? "",
            "gallery_id": effectiveAlbumID ?? "",
            "slug": pageURL.deletingPathExtension().lastPathComponent,
            "site": "Luscious",
            "title": title,
            "url": pageURL.absoluteString,
            "source_url": pageURL.absoluteString,
            "page_url": pageURL.absoluteString
        ])
    }

    static func downloadMetadata(from metadata: [String: String], type: String, media: [(kind: String, url: URL)]) -> [String: String] {
        var result = metadata
        let normalizedKinds = Set(media.map { normalizedMediaType(kind: $0.kind, url: $0.url) })
        let mediaType: String
        if normalizedKinds.count == 1 {
            mediaType = normalizedKinds.first ?? ""
        } else if normalizedKinds.isEmpty {
            mediaType = ""
        } else {
            mediaType = "mixed"
        }
        result["type"] = type
        result["media_type"] = mediaType
        result["media_count"] = String(media.count)
        let imageCount = media.filter { normalizedMediaType(kind: $0.kind, url: $0.url) == "image" }.count
        let videoCount = media.filter { normalizedMediaType(kind: $0.kind, url: $0.url) == "video" }.count
        result["image_count"] = imageCount > 0 ? String(imageCount) : ""
        result["video_count"] = videoCount > 0 ? String(videoCount) : ""
        if media.count == 1, let first = media.first {
            let firstType = normalizedMediaType(kind: first.kind, url: first.url)
            let format = mediaFormat(for: first.url)
            result["format"] = format
            result["media_format"] = format
            result["media_url"] = first.url.absoluteString
            if firstType == "image" {
                result["image_url"] = first.url.absoluteString
            } else if firstType == "video" {
                result["video_url"] = first.url.absoluteString
            }
        }
        return DownloadMetadata.clean(result)
    }

    static func assetMetadata(for item: LusciousMediaAsset, baseMetadata: [String: String], index: Int) -> [String: String] {
        var metadata = assetMetadata(for: item.remoteURL, kind: item.kind, baseMetadata: baseMetadata, pageURL: URL(string: item.referer), index: index)
        if let id = item.id, !id.trimmed.isEmpty {
            metadata["media_id"] = id
        }
        metadata["item_title"] = item.title ?? ""
        metadata["item_position"] = item.position.map(String.init) ?? ""
        metadata["position"] = item.position.map(String.init) ?? metadata["position"] ?? ""
        metadata["page"] = item.position.map(String.init) ?? metadata["page"] ?? ""
        metadata["page_url"] = item.referer
        return DownloadMetadata.clean(metadata)
    }

    static func assetMetadata(for url: URL, kind: String, baseMetadata: [String: String], pageURL: URL? = nil, index: Int) -> [String: String] {
        let mediaType = normalizedMediaType(kind: kind, url: url)
        let format = mediaFormat(for: url)
        let albumID = baseMetadata["album_id"] ?? baseMetadata["gallery_id"] ?? ""
        let mediaID = albumID.isEmpty ? String(index) : "\(albumID)-\(index)"
        let sourcePage = pageURL?.absoluteString ?? baseMetadata["page_url"] ?? baseMetadata["url"] ?? ""
        return DownloadMetadata.clean([
            "artist": baseMetadata["artist"] ?? "",
            "author": baseMetadata["author"] ?? "",
            "creator": baseMetadata["creator"] ?? "",
            "uploader": baseMetadata["uploader"] ?? "",
            "channel": baseMetadata["channel"] ?? "",
            "series": baseMetadata["series"] ?? baseMetadata["title"] ?? "",
            "category": baseMetadata["category"] ?? "",
            "tag": baseMetadata["tag"] ?? "",
            "tags": baseMetadata["tags"] ?? "",
            "album_id": baseMetadata["album_id"] ?? "",
            "gallery_id": baseMetadata["gallery_id"] ?? "",
            "id": albumID,
            "media_id": mediaID,
            "page": String(index),
            "position": String(index),
            "slug": baseMetadata["slug"] ?? "",
            "site": "Luscious",
            "title": baseMetadata["title"] ?? "",
            "type": mediaType,
            "media_type": mediaType,
            "format": format,
            "media_format": format,
            "image_url": mediaType == "image" ? url.absoluteString : "",
            "video_url": mediaType == "video" ? url.absoluteString : "",
            "media_url": url.absoluteString,
            "source_url": url.absoluteString,
            "page_url": sourcePage
        ])
    }

    static func mediaFormat(for url: URL) -> String {
        let kind = mediaKind(for: url)
        return kind.isEmpty ? "jpg" : kind
    }

    private static func normalizedMediaType(kind: String, url: URL) -> String {
        if kind == "video" {
            return "video"
        }
        if ["mp4", "webm", "mov", "m3u8"].contains(mediaKind(for: url)) {
            return "video"
        }
        return "image"
    }

    private static func mediaAsset(fromItem item: [String: Any], sourceURL: URL) -> LusciousMediaAsset? {
        let id = flexibleString(item["id"])
        let title = item["title"] as? String
        let position = flexibleInt(item["position"])
        let fields: [(String, String)] = [
            ("url_to_original", "image"),
            ("url_to_video", "video"),
            ("url", "media")
        ]

        for (field, kind) in fields {
            guard let raw = item[field] as? String,
                  let remote = absoluteURL(decodeURLString(raw), baseURL: sourceURL) else {
                continue
            }
            if kind != "media" || ["jpg", "png", "webp", "gif", "avif", "mp4", "webm", "mov", "m3u8"].contains(mediaKind(for: remote)) {
                return LusciousMediaAsset(remoteURL: remote, id: id, title: title, position: position, kind: kind == "video" ? "video" : "image", referer: sourceURL.absoluteString)
            }
        }

        if let thumbnail = bestThumbnail(from: item["thumbnails"], sourceURL: sourceURL) {
            return LusciousMediaAsset(remoteURL: thumbnail, id: id, title: title, position: position, kind: "image", referer: sourceURL.absoluteString)
        }
        return nil
    }

    private static func bestThumbnail(from value: Any?, sourceURL: URL) -> URL? {
        guard let thumbnails = value as? [[String: Any]] else { return nil }
        let sorted = thumbnails.sorted { lhs, rhs in
            (flexibleInt(lhs["width"]) ?? 0) * (flexibleInt(lhs["height"]) ?? 0) >
                (flexibleInt(rhs["width"]) ?? 0) * (flexibleInt(rhs["height"]) ?? 0)
        }
        for thumbnail in sorted {
            guard let raw = thumbnail["url"] as? String,
                  let remote = absoluteURL(decodeURLString(raw), baseURL: sourceURL),
                  ["jpg", "png", "webp", "gif", "avif"].contains(mediaKind(for: remote)) else {
                continue
            }
            return remote
        }
        return nil
    }

    private static func apiHost(for sourceURL: URL) -> String {
        let host = sourceURL.host?.lowercased() ?? ""
        return host.hasSuffix(".test") || host == "luscious.test" ? "apicdn.luscious.test" : "apicdn.luscious.net"
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

    private static func attributeContent(fromHTML html: String, attributeNames: Set<String>) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"<[A-Za-z][A-Za-z0-9:-]*\b([^>]*)>"#, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        for match in regex.matches(in: html, range: range) {
            guard let attributesRange = Range(match.range(at: 1), in: html) else { continue }
            let values = attributeValues(from: String(html[attributesRange]))
            for name in attributeNames {
                if let value = values[name]?.trimmed, !value.isEmpty {
                    return value
                }
            }
        }
        return nil
    }

    private static func scriptTitle(fromHTML html: String) -> String? {
        for raw in firstCaptures(patterns: [
            #""(?:album_title|albumTitle|gallery_title|galleryTitle|video_title|videoTitle|display_title|displayTitle|name)"\s*:\s*"((?:\\.|[^"\\])+)""#,
            #""(?:album|gallery|video)"\s*:\s*\{[^{}]*"title"\s*:\s*"((?:\\.|[^"\\])+)""#,
            #""title"\s*:\s*"((?:\\.|[^"\\])+)""#
        ], in: html) {
            let title = decodeScriptString(raw)
            if isUsefulTitle(cleanTitle(title, fallback: "")) {
                return title
            }
        }
        return nil
    }

    private static func titleFromURLSlug(_ url: URL) -> String? {
        let parts = pathParts(from: url)
        guard let index = parts.firstIndex(where: { $0.lowercased() == "albums" || $0.lowercased() == "videos" }),
              index + 1 < parts.count else {
            return nil
        }

        let afterType = Array(parts.dropFirst(index + 1))
        let slug = afterType.first(where: { part in
            part.range(of: #"[A-Za-z가-힣ぁ-ゖァ-ヺ一-龯]"#, options: .regularExpression) != nil
        }) ?? afterType.first
        guard var slug = slug?.trimmed, !slug.isEmpty else { return nil }
        slug = slug
            .replacingOccurrences(of: #"[_-]?[0-9]{2,}$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[_-]+"#, with: " ", options: .regularExpression)
            .trimmed
        return slug.isEmpty ? nil : slug
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
        var results: [String] = []
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
                results.append(value)
            }
        }
        return results
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

    private static func decodeURLString(_ text: String) -> String {
        decodeHTML(text)
            .replacingOccurrences(of: "\\/", with: "/")
            .replacingOccurrences(of: "\\u002F", with: "/")
            .replacingOccurrences(of: "\\u0026", with: "&")
    }

    private static func decodeScriptString(_ text: String) -> String {
        decodeURLString(text)
            .replacingOccurrences(of: #"\""#, with: "\"")
            .replacingOccurrences(of: #"\'"#, with: "'")
            .replacingOccurrences(of: #"\\n"#, with: " ")
            .replacingOccurrences(of: #"\\t"#, with: " ")
    }

    private static func pathParts(from url: URL) -> [String] {
        url.path.split(separator: "/").map { String($0).removingPercentEncoding ?? String($0) }
    }

    private static func flexibleBool(_ value: Any?) -> Bool? {
        if let bool = value as? Bool { return bool }
        if let int = value as? Int { return int != 0 }
        if let number = value as? NSNumber { return number.boolValue }
        if let string = value as? String {
            let lowered = string.trimmed.lowercased()
            if ["1", "true", "yes", "y"].contains(lowered) { return true }
            if ["0", "false", "no", "n"].contains(lowered) { return false }
        }
        return nil
    }

    private static func flexibleInt(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string.trimmed) }
        return nil
    }

    private static func flexibleString(_ value: Any?) -> String? {
        if let string = value as? String {
            let trimmed = string.trimmed
            return trimmed.isEmpty ? nil : trimmed
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        if let int = value as? Int {
            return String(int)
        }
        return nil
    }

    private static func cleanTitle(_ raw: String, fallback: String) -> String {
        var title = decodeHTML(stripTags(raw))
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmed
        for suffix in [
            " - Luscious",
            " | Luscious",
            " - Luscious.net",
            " | Luscious.net",
            " - members.luscious.net",
            " | members.luscious.net"
        ] {
            if title.lowercased().hasSuffix(suffix.lowercased()) {
                title.removeLast(suffix.count)
                title = title.trimmed
            }
        }
        return title.isEmpty ? fallback : title.sanitizedFilename(maxLength: 120)
    }

    private static func isUsefulTitle(_ title: String) -> Bool {
        let lowered = title.trimmed.lowercased()
        guard !lowered.isEmpty else { return false }
        if [
            "luscious",
            "luscious.net",
            "members.luscious.net",
            "www.luscious.net",
            "login",
            "member login",
            "luscious login",
            "login required",
            "download"
        ].contains(lowered) {
            return false
        }
        if lowered.contains("login") && lowered.contains("luscious") {
            return false
        }
        return true
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

    private static let supportedDomains = [
        "luscious.net",
        "luscious.test"
    ]

    private static let albumListQuery = """
    query AlbumListOwnPictures($input: PictureListInput!) {
      picture {
        list(input: $input) {
          info {
            page
            has_next_page
            has_previous_page
            total_items
            total_pages
            items_per_page
          }
          items {
            id
            title
            description
            width
            height
            url_to_original
            url_to_video
            url
            position
            thumbnails {
              width
              height
              size
              url
            }
          }
        }
      }
    }
    """
}
