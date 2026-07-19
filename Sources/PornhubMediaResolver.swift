import Foundation

enum PornhubResolverError: LocalizedError {
    case authenticationRequired

    var errorDescription: String? {
        switch self {
        case .authenticationRequired:
            return "Pornhub Premium login is required."
        }
    }
}

struct PornhubMediaRequest: Equatable {
    enum Kind: String {
        case video
        case gif
        case photo
        case album
    }

    var kind: Kind
    var id: String
}

struct PornhubVideoCandidate: Equatable {
    var url: URL
    var quality: Int
    var label: String
}

final class PornhubMediaResolver {
    func canResolve(_ url: URL) -> Bool {
        Self.request(from: url) != nil
    }

    func resolve(
        _ url: URL,
        headers: HTTPRequestOptions = HTTPRequestOptions(),
        preferredResolution: String = "",
        verifyPremiumLogin: Bool = true
    ) async throws -> ResolvedDownload {
        guard let request = Self.request(from: url) else {
            throw NativeDownloadError.invalidURL(url.absoluteString)
        }
        if verifyPremiumLogin {
            try await Self.requirePremiumLoginIfNeeded(for: url, headers: headers)
        }

        let pageHeaders = await PornhubCollectionResolver.pageHeaders(for: url, ajax: false)
        let html = try await HTTPClient.shared.string(
            from: url,
            referer: headers.referer,
            userAgent: headers.userAgent,
            additionalHeaders: pageHeaders
        )
        switch request.kind {
        case .video:
            return try await Self.videoDownload(
                fromHTML: html,
                pageURL: url,
                videoID: request.id,
                userAgent: headers.userAgent,
                preferredResolution: preferredResolution
            )
        case .gif:
            return try Self.gifDownload(fromHTML: html, pageURL: url, gifID: request.id)
        case .photo:
            return try Self.photoDownload(fromHTML: html, pageURL: url, photoID: request.id)
        case .album:
            let photoURLs = Self.albumPhotoURLs(fromHTML: html, pageURL: url)
            guard !photoURLs.isEmpty else {
                throw NativeDownloadError.noFiles
            }

            var assets: [ResolvedAsset] = []
            for photoURL in photoURLs {
                guard let photoID = Self.request(from: photoURL)?.id,
                      let photoHTML = try? await HTTPClient.shared.string(
                        from: photoURL,
                        referer: headers.referer ?? url.absoluteString,
                        userAgent: headers.userAgent,
                        additionalHeaders: await PornhubCollectionResolver.pageHeaders(
                            for: photoURL,
                            ajax: false
                        )
                      ),
                      let resolved = try? Self.photoDownload(fromHTML: photoHTML, pageURL: photoURL, photoID: photoID) else {
                    continue
                }
                for asset in resolved.assets {
                    assets.append(asset)
                }
            }

            guard !assets.isEmpty else {
                throw NativeDownloadError.noFiles
            }
            let rawTitle = Self.title(fromHTML: html, fallback: "Pornhub album \(request.id)")
            let title = Self.titleWithIdentifier(rawTitle, id: "album_\(request.id)")
            return ResolvedDownload(
                title: title,
                folderName: "Pornhub \(title)".sanitizedFilename(maxLength: 120),
                assets: assets,
                metadata: Self.metadata(kind: .album, id: request.id, title: title, pageURL: url, mediaURL: nil, html: html)
                    .merging([
                        "item_count": String(assets.count),
                        "media_count": String(assets.count),
                        "image_count": String(assets.count)
                    ]) { current, _ in current }
            )
        }
    }

    static func request(from url: URL) -> PornhubMediaRequest? {
        guard let host = url.host?.lowercased(),
              isSupportedHost(host),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }

        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let path = url.path.lowercased()
        if path == "/view_video.php" || path.hasSuffix("/view_video.php") {
            for name in ["viewkey", "view_key", "id"] {
                if let value = queryItems.first(where: { $0.name.lowercased() == name })?.value,
                   isValidID(value) {
                    return PornhubMediaRequest(kind: .video, id: value)
                }
            }
        }

        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true).map { String($0).removingPercentEncoding ?? String($0) }
        guard parts.count >= 2 else { return nil }
        let marker = parts[0].lowercased()
        let id = parts[1].trimmed
        guard isValidID(id) else { return nil }

        switch marker {
        case "embed":
            return PornhubMediaRequest(kind: .video, id: id)
        case "gif":
            return PornhubMediaRequest(kind: .gif, id: id)
        case "photo":
            return PornhubMediaRequest(kind: .photo, id: id)
        case "album":
            return PornhubMediaRequest(kind: .album, id: id)
        default:
            return nil
        }
    }

    static func canonicalURL(kind: PornhubMediaRequest.Kind, id: String, sourceURL: URL? = nil) -> URL? {
        let mediaID = id.trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard isValidID(mediaID) else { return nil }

        var components = URLComponents()
        components.scheme = "https"
        components.host = canonicalHost(from: sourceURL)
        switch kind {
        case .video:
            components.path = "/view_video.php"
            components.queryItems = [URLQueryItem(name: "viewkey", value: mediaID)]
        case .gif:
            components.path = "/gif/\(mediaID)"
        case .photo:
            components.path = "/photo/\(mediaID)"
        case .album:
            components.path = "/album/\(mediaID)"
        }
        return components.url
    }

    static func requiresPremiumLogin(for url: URL) -> Bool {
        url.host?.lowercased().contains("pornhubpremium") == true
    }

    static func isLoggedInPremiumHTML(_ html: String) -> Bool {
        html.range(
            of: #"<[^>]+\bid\s*=\s*[\"']profileMenuDropdown[\"'][^>]*>"#,
            options: [.caseInsensitive, .regularExpression]
        ) != nil
    }

    static func premiumSessionIsAuthenticated(headers: HTTPRequestOptions = HTTPRequestOptions()) async throws -> Bool {
        let statusURL = URL(string: "https://www.pornhubpremium.com/")!
        let html = try await HTTPClient.shared.string(
            from: statusURL,
            referer: headers.referer,
            userAgent: headers.userAgent,
            additionalHeaders: await PornhubCollectionResolver.pageHeaders(for: statusURL, ajax: false)
        )
        return isLoggedInPremiumHTML(html)
    }

    static func requirePremiumLoginIfNeeded(
        for url: URL,
        headers: HTTPRequestOptions = HTTPRequestOptions()
    ) async throws {
        guard requiresPremiumLogin(for: url) else { return }
        guard try await premiumSessionIsAuthenticated(headers: headers) else {
            throw PornhubResolverError.authenticationRequired
        }
    }

    static func videoDownload(
        fromHTML html: String,
        pageURL: URL,
        videoID: String,
        userAgent: String? = nil,
        preferredResolution: String = ""
    ) async throws -> ResolvedDownload {
        guard let candidate = selectedVideoCandidate(
            videoCandidates(fromHTML: html, pageURL: pageURL),
            preferredResolution: preferredResolution
        ) else {
            throw NativeDownloadError.noFiles
        }
        let title = videoTitle(fromHTML: html, fallback: "Pornhub video \(videoID)")
        let artist = videoArtist(fromHTML: html)

        if isM3U8(candidate.url) {
            let hls = try await M3U8Resolver().resolve(
                candidate.url,
                headers: HTTPRequestOptions(referer: pageURL.absoluteString, userAgent: userAgent),
                preferredResolution: preferredResolution
            )
            let filename = originalVideoFilename(
                title: title,
                id: videoID,
                artist: artist,
                mediaURL: candidate.url,
                forcedExtension: "mp4"
            )
            return ResolvedDownload(
                title: title,
                folderName: "Pornhub \(title)".sanitizedFilename(maxLength: 120),
                assets: hlsAssetsWithPageMetadata(
                    hls.assets,
                    id: videoID,
                    title: title,
                    pageURL: pageURL,
                    candidate: candidate,
                    html: html
                ),
                packageMode: .concatenate(outputFilename: filename),
                metadata: metadata(kind: .video, id: videoID, title: title, pageURL: pageURL, mediaURL: candidate.url, html: html, artist: artist)
                    .merging(videoMetadata(candidate: candidate)) { current, _ in current }
                    .merging(hls.metadata) { current, _ in current }
            )
        }

        let filename = originalVideoFilename(title: title, id: videoID, artist: artist, mediaURL: candidate.url)
        let pageMetadata = metadata(kind: .video, id: videoID, title: title, pageURL: pageURL, mediaURL: candidate.url, html: html, artist: artist)
            .merging(videoMetadata(candidate: candidate)) { current, _ in current }
        return ResolvedDownload(
            title: title,
            folderName: "Pornhub \(title)".sanitizedFilename(maxLength: 120),
            assets: [
                ResolvedAsset(
                    remoteURL: candidate.url,
                    filename: filename,
                    metadata: mediaMetadata(kind: .video, mediaURL: candidate.url, candidate: candidate, pageMetadata: pageMetadata, pageURL: pageURL, index: 1),
                    referer: pageURL.absoluteString
                )
            ],
            packageMode: .concatenate(outputFilename: filename),
            metadata: pageMetadata
        )
    }

    static func gifDownload(fromHTML html: String, pageURL: URL, gifID: String) throws -> ResolvedDownload {
        guard let raw = firstCapture(pattern: #"\bdata-mp4\s*=\s*["']([^"']+)["']"#, in: html),
              let mediaURL = absoluteURL(raw, baseURL: pageURL) else {
            throw NativeDownloadError.noFiles
        }
        let title = title(
            fromHTML: html,
            preferred: firstCapture(pattern: #"\bdata-gif-title\s*=\s*["']([^"']+)["']"#, in: html),
            fallback: "Pornhub gif \(gifID)"
        )
        let filename = originalVideoFilename(title: title, id: "gif_\(gifID)", artist: "", mediaURL: mediaURL)
        let pageMetadata = metadata(kind: .gif, id: gifID, title: title, pageURL: pageURL, mediaURL: mediaURL, html: html)
        return ResolvedDownload(
            title: title,
            folderName: "Pornhub \(title)".sanitizedFilename(maxLength: 120),
            assets: [
                ResolvedAsset(
                    remoteURL: mediaURL,
                    filename: filename,
                    metadata: mediaMetadata(kind: .gif, mediaURL: mediaURL, pageMetadata: pageMetadata, pageURL: pageURL, index: 1),
                    referer: pageURL.absoluteString
                )
            ],
            packageMode: .concatenate(outputFilename: filename),
            metadata: pageMetadata
        )
    }

    static func photoDownload(fromHTML html: String, pageURL: URL, photoID: String) throws -> ResolvedDownload {
        guard let mediaURL = photoImageURL(fromHTML: html, pageURL: pageURL) else {
            throw NativeDownloadError.noFiles
        }
        let rawTitle = title(fromHTML: html, fallback: "Pornhub photo \(photoID)")
        let title = titleWithIdentifier(rawTitle, id: "photo_\(photoID)")
        let filename = originalPhotoFilename(id: photoID, mediaURL: mediaURL)
        let pageMetadata = metadata(kind: .photo, id: photoID, title: title, pageURL: pageURL, mediaURL: mediaURL, html: html)
        return ResolvedDownload(
            title: title,
            folderName: "Pornhub \(title)".sanitizedFilename(maxLength: 120),
            assets: [
                ResolvedAsset(
                    remoteURL: mediaURL,
                    filename: filename,
                    metadata: mediaMetadata(kind: .photo, mediaURL: mediaURL, pageMetadata: pageMetadata, pageURL: pageURL, index: 1),
                    referer: pageURL.absoluteString
                )
            ],
            metadata: pageMetadata
        )
    }

    static func albumPhotoURLs(fromHTML html: String, pageURL: URL) -> [URL] {
        let blocks = allCaptures(
            pattern: #"<[^>]*\bclass\s*=\s*["'][^"']*photoAlbumListBlock[^"']*["'][^>]*>.*?</(?:li|div|section)>"#,
            in: html,
            group: 0
        )
        let scope = blocks.isEmpty ? html : blocks.joined(separator: "\n")
        let hrefs = allCaptures(pattern: #"\bhref\s*=\s*["']([^"']*/photo/[0-9A-Za-z_-]+[^"']*)["']"#, in: scope)
        var seen = Set<String>()
        return hrefs.compactMap { raw in
            guard let url = absoluteURL(raw, baseURL: pageURL),
                  request(from: url)?.kind == .photo else {
                return nil
            }
            let key = url.absoluteString
            guard !seen.contains(key) else { return nil }
            seen.insert(key)
            return url
        }
    }

    static func videoCandidates(fromHTML html: String, pageURL: URL) -> [PornhubVideoCandidate] {
        let normalized = normalizeEscapes(decodeHTML(html))
        var candidates: [PornhubVideoCandidate] = []

        for tag in allCaptures(pattern: #"<(?:video|source)\b[^>]*>"#, in: normalized, group: 0) {
            let label = attributeValue("label", in: tag) ??
                attributeValue("data-quality", in: tag) ??
                attributeValue("title", in: tag) ??
                ""
            for attribute in ["src", "data-src", "data-video", "data-url", "data-file"] {
                if let raw = attributeValue(attribute, in: tag) {
                    appendVideoCandidate(rawURL: raw, label: label, pageURL: pageURL, candidates: &candidates)
                }
            }
        }

        for meta in allCaptures(pattern: #"<meta\b[^>]*>"#, in: normalized, group: 0) {
            let name = (attributeValue("property", in: meta) ?? attributeValue("name", in: meta) ?? "").lowercased()
            guard ["og:video", "og:video:url", "og:video:secure_url", "twitter:player:stream"].contains(name),
                  let content = attributeValue("content", in: meta) else {
                continue
            }
            appendVideoCandidate(rawURL: content, label: name, pageURL: pageURL, candidates: &candidates)
        }

        for object in mediaDefinitionJSONObjects(in: normalized) {
            collectVideoCandidates(in: object, pageURL: pageURL, inheritedLabel: "", candidates: &candidates)
        }

        for pattern in [
            #""(?:videoUrl|videoURL|video_url|url|src|file)"\s*:\s*"([^"]+)""#,
            #"'(?:videoUrl|videoURL|video_url|url|src|file)'\s*:\s*'([^']+)'"#
        ] {
            for raw in allCaptures(pattern: pattern, in: normalized) {
                appendVideoCandidate(rawURL: raw, label: "", pageURL: pageURL, candidates: &candidates)
            }
        }

        for raw in allCaptures(pattern: #"(?:https?:)?//[^"'\s<>]+?\.(?:mp4|m3u8)(?:\?[^"'\s<>]*)?"#, in: normalized, group: 0) {
            appendVideoCandidate(rawURL: raw, label: "", pageURL: pageURL, candidates: &candidates)
        }

        return uniqueVideoCandidates(candidates)
    }

    private static func photoImageURL(fromHTML html: String, pageURL: URL) -> URL? {
        let scope = firstCapture(
            pattern: #"<[^>]*(?:\bid\s*=\s*["']photoImageSection["']|\bclass\s*=\s*["'][^"']*photoImageSection[^"']*["'])[^>]*>(.*?)</(?:div|section)>"#,
            in: html
        ) ?? html
        let patterns = [
            #"\b(?:data-original|data-src|src)\s*=\s*["']([^"']+\.(?:jpg|jpeg|png|webp)(?:\?[^"']*)?)["']"#,
            #"<a\b[^>]*\bhref\s*=\s*["']([^"']+\.(?:jpg|jpeg|png|webp)(?:\?[^"']*)?)["']"#
        ]
        for pattern in patterns {
            for raw in allCaptures(pattern: pattern, in: scope) {
                guard let url = absoluteURL(raw, baseURL: pageURL),
                      isImage(url) else {
                    continue
                }
                return url
            }
        }
        return nil
    }

    private static func videoTitle(fromHTML html: String, fallback: String) -> String {
        if let raw = firstCapture(
            pattern: #"<h1\b[^>]*\bclass\s*=\s*["'][^"']*\btitle\b[^"']*["'][^>]*>(.*?)</h1>"#,
            in: html
        ) {
            let withoutFreeLabel = raw.replacingOccurrences(
                of: #"(?is)<[^>]*\bclass\s*=\s*["'][^"']*phpFree[^"']*["'][^>]*>.*?</[^>]+>"#,
                with: "",
                options: .regularExpression
            )
            return cleanTitle(withoutFreeLabel, fallback: fallback)
        }
        return title(fromHTML: html, fallback: fallback)
    }

    private static func videoArtist(fromHTML html: String) -> String {
        guard let raw = firstCapture(
            pattern: #"<div\b[^>]*\bclass\s*=\s*["'][^"']*usernameWrap[^"']*["'][^>]*>(.*?)</div>"#,
            in: html
        ) else {
            return ""
        }
        return cleanTitle(raw, fallback: "")
    }

    private static func title(fromHTML html: String, preferred: String? = nil, fallback: String) -> String {
        let raw = preferred ??
            metaContent(from: html, names: ["og:title", "twitter:title"]) ??
            elementText(pattern: #"<h1\b[^>]*>(.*?)</h1>"#, in: html) ??
            elementText(pattern: #"<title\b[^>]*>(.*?)</title>"#, in: html) ??
            fallback
        return cleanTitle(raw, fallback: fallback)
    }

    private static func metadata(
        kind: PornhubMediaRequest.Kind,
        id: String,
        title: String,
        pageURL: URL,
        mediaURL: URL?,
        html: String,
        artist: String = ""
    ) -> [String: String] {
        return DownloadMetadata.clean([
            "site": "Pornhub",
            "title": title,
            "series": title,
            "artist": artist,
            "author": artist,
            "creator": artist,
            "uploader": artist,
            "category": kind == .photo || kind == .album ? "image" : "video",
            "type": kind.rawValue,
            "media_type": kind.rawValue,
            "format": mediaURL.map(mediaFormat(for:)) ?? "",
            "media_format": mediaURL.map(mediaFormat(for:)) ?? "",
            "host": pageURL.host ?? "",
            "id": id,
            "media_id": id,
            "gallery_id": id,
            "video_id": kind == .gif || kind == .video ? id : "",
            "album_id": kind == .album ? id : "",
            "photo_id": kind == .photo ? id : "",
            "media_count": kind == .album ? "" : "1",
            "video_count": kind == .video || kind == .gif ? "1" : "",
            "image_count": kind == .photo ? "1" : "",
            "video_url": kind == .gif || kind == .video ? mediaURL?.absoluteString ?? "" : "",
            "image_url": kind == .photo ? mediaURL?.absoluteString ?? "" : "",
            "media_url": mediaURL?.absoluteString ?? "",
            "thumbnail": thumbnailURL(fromHTML: html, pageURL: pageURL)?.absoluteString ?? "",
            "url": pageURL.absoluteString,
            "source_url": pageURL.absoluteString,
            "page_url": pageURL.absoluteString
        ])
    }

    private static func thumbnailURL(fromHTML html: String, pageURL: URL) -> URL? {
        if let raw = metaContent(from: html, names: ["og:image", "twitter:image"]),
           let url = absoluteURL(raw, baseURL: pageURL) {
            return url
        }
        if let raw = firstCapture(pattern: #"https?://[^"'\s<>]+\.phncdn\.com/pics/gifs/[^"'\s<>]+\.jpg"#, in: html) {
            return absoluteURL(raw, baseURL: pageURL)
        }
        return nil
    }

    private static func videoMetadata(candidate: PornhubVideoCandidate) -> [String: String] {
        let height = candidate.quality > 0 && candidate.quality < 10_000 ? String(candidate.quality) : ""
        let resolution = height.isEmpty ? "" : "\(height)p"
        return DownloadMetadata.clean([
            "type": isM3U8(candidate.url) ? "hls" : "video",
            "media_type": isM3U8(candidate.url) ? "hls" : "video",
            "format": mediaFormat(for: candidate.url),
            "media_format": mediaFormat(for: candidate.url),
            "quality": candidate.quality > 0 ? String(candidate.quality) : "",
            "height": height,
            "resolution": resolution,
            "video_url": candidate.url.absoluteString,
            "media_url": candidate.url.absoluteString,
            "playlist_url": isM3U8(candidate.url) ? candidate.url.absoluteString : ""
        ])
    }

    private static func mediaMetadata(kind: PornhubMediaRequest.Kind, mediaURL: URL, candidate: PornhubVideoCandidate? = nil, pageMetadata: [String: String], pageURL: URL, index: Int) -> [String: String] {
        let format = mediaFormat(for: mediaURL)
        let height = candidate.flatMap { candidate in
            candidate.quality > 0 && candidate.quality < 10_000 ? String(candidate.quality) : nil
        } ?? ""
        let resolution = height.isEmpty ? "" : "\(height)p"
        return DownloadMetadata.clean([
            "site": "Pornhub",
            "title": pageMetadata["title"] ?? "",
            "series": pageMetadata["series"] ?? "",
            "artist": pageMetadata["artist"] ?? "",
            "author": pageMetadata["author"] ?? "",
            "creator": pageMetadata["creator"] ?? "",
            "uploader": pageMetadata["uploader"] ?? "",
            "id": pageMetadata["id"] ?? "",
            "media_id": pageMetadata["media_id"] ?? "",
            "gallery_id": pageMetadata["gallery_id"] ?? "",
            "video_id": pageMetadata["video_id"] ?? "",
            "photo_id": pageMetadata["photo_id"] ?? "",
            "album_id": pageMetadata["album_id"] ?? "",
            "type": kind.rawValue,
            "media_type": kind.rawValue,
            "category": kind == .photo || kind == .album ? "image" : "video",
            "page": String(index),
            "position": String(index),
            "format": format,
            "media_format": format,
            "height": height,
            "resolution": resolution,
            "quality": candidate.map { $0.quality > 0 ? String($0.quality) : "" } ?? "",
            "video_url": kind == .video || kind == .gif ? mediaURL.absoluteString : "",
            "image_url": kind == .photo ? mediaURL.absoluteString : "",
            "media_url": mediaURL.absoluteString,
            "source_url": mediaURL.absoluteString,
            "page_url": pageURL.absoluteString,
            "playlist_url": isM3U8(mediaURL) ? mediaURL.absoluteString : ""
        ])
    }

    static func hlsAssetsWithPageMetadata(_ assets: [ResolvedAsset], id: String, title: String, pageURL: URL, candidate: PornhubVideoCandidate, html: String) -> [ResolvedAsset] {
        let thumbnail = thumbnailURL(fromHTML: html, pageURL: pageURL)
        return assets.enumerated().map { offset, asset in
            var enriched = asset
            enriched.metadata = asset.metadata.merging(segmentMetadata(
                id: id,
                title: title,
                pageURL: pageURL,
                candidate: candidate,
                asset: asset,
                index: offset + 1,
                thumbnail: thumbnail
            )) { _, new in new }
            return enriched
        }
    }

    private static func segmentMetadata(id: String, title: String, pageURL: URL, candidate: PornhubVideoCandidate, asset: ResolvedAsset, index: Int, thumbnail: URL?) -> [String: String] {
        let type = asset.metadata["type"] ?? "hls_segment"
        let format = mediaFormat(for: asset.remoteURL, fallback: mediaFormat(forFilename: asset.filename, fallback: "ts"))
        let height = candidate.quality > 0 && candidate.quality < 10_000 ? String(candidate.quality) : ""
        let resolution = height.isEmpty ? "" : "\(height)p"
        return DownloadMetadata.clean([
            "site": "Pornhub",
            "title": title,
            "series": title,
            "id": id,
            "media_id": "\(id)-segment-\(index)",
            "gallery_id": id,
            "video_id": id,
            "type": type,
            "media_type": type == "hls_segment" ? "segment" : type,
            "category": "video",
            "page": String(index),
            "position": String(index),
            "format": format,
            "media_format": format,
            "height": height,
            "resolution": resolution,
            "quality": candidate.quality > 0 ? String(candidate.quality) : "",
            "thumbnail": thumbnail?.absoluteString ?? "",
            "playlist_url": asset.metadata["playlist_url"] ?? candidate.url.absoluteString,
            "video_url": asset.remoteURL.absoluteString,
            "media_url": asset.remoteURL.absoluteString,
            "source_url": pageURL.absoluteString,
            "page_url": pageURL.absoluteString
        ])
    }

    private static func mediaFormat(for url: URL) -> String {
        let pathExtension = url.pathExtension.lowercased()
        if !pathExtension.isEmpty {
            return pathExtension
        }
        let lower = url.absoluteString.lowercased()
        for value in ["m3u8", "mp4", "m4v", "mov", "webm", "jpg", "jpeg", "png", "webp"] where lower.contains(".\(value)") {
            return value
        }
        return ""
    }

    private static func mediaFormat(for url: URL, fallback: String) -> String {
        let format = mediaFormat(for: url)
        return format.isEmpty ? fallback : format
    }

    private static func mediaFormat(forFilename filename: String, fallback: String) -> String {
        let ext = (filename as NSString).pathExtension.lowercased()
        return ext.isEmpty ? fallback : ext
    }

    private static func originalVideoFilename(
        title: String,
        id: String,
        artist: String,
        mediaURL: URL,
        forcedExtension: String? = nil
    ) -> String {
        let ext = forcedExtension ?? (mediaURL.pathExtension.trimmed.isEmpty ? "mp4" : mediaURL.pathExtension)
        let prefix = artist.trimmed.isEmpty ? "" : "[\(artist)] "
        return "\(prefix)\(title) (\(id)).\(ext)".sanitizedFilename(maxLength: 180)
    }

    private static func originalPhotoFilename(id: String, mediaURL: URL) -> String {
        let ext = mediaURL.pathExtension.trimmed.isEmpty ? "jpg" : mediaURL.pathExtension
        return "\(id).\(ext)".sanitizedFilename(maxLength: 180)
    }

    private static func titleWithIdentifier(_ title: String, id: String) -> String {
        "\(title) (\(id))".sanitizedFilename(maxLength: 120)
    }

    private static func metaContent(from html: String, names: [String]) -> String? {
        for name in names {
            let patterns = [
                #"<meta\b[^>]*(?:property|name)\s*=\s*["']\#(name)["'][^>]*content\s*=\s*["']([^"']+)["'][^>]*>"#,
                #"<meta\b[^>]*content\s*=\s*["']([^"']+)["'][^>]*(?:property|name)\s*=\s*["']\#(name)["'][^>]*>"#
            ]
            for pattern in patterns {
                if let value = capture(pattern: pattern, in: html, group: 2) ?? capture(pattern: pattern, in: html, group: 1) {
                    return decodeHTML(value).trimmed
                }
            }
        }
        return nil
    }

    private static func elementText(pattern: String, in html: String) -> String? {
        guard let raw = firstCapture(pattern: pattern, in: html) else { return nil }
        let text = cleanTitle(raw, fallback: "")
        return text.isEmpty ? nil : text
    }

    private static func attributeValue(_ name: String, in tag: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        return firstCapture(pattern: #"\b\#(escaped)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>"']+))"#, in: tag, groups: [1, 2, 3])
    }

    private static func firstCapture(pattern: String, in text: String) -> String? {
        firstCapture(pattern: pattern, in: text, groups: [1])
    }

    private static func firstCapture(pattern: String, in text: String, groups: [Int]) -> String? {
        for group in groups {
            if let value = capture(pattern: pattern, in: text, group: group) {
                return value
            }
        }
        return nil
    }

    private static func capture(pattern: String, in text: String, group: Int) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > group,
              let capture = Range(match.range(at: group), in: text) else {
            return nil
        }
        return String(text[capture])
    }

    private static func allCaptures(pattern: String, in text: String) -> [String] {
        allCaptures(pattern: pattern, in: text, group: 1)
    }

    private static func allCaptures(pattern: String, in text: String, group: Int) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > group,
                  let capture = Range(match.range(at: group), in: text) else {
                return nil
            }
            return String(text[capture])
        }
    }

    private static func mediaDefinitionJSONObjects(in text: String) -> [Any] {
        var objects: [Any] = []
        var searchStart = text.startIndex
        while searchStart < text.endIndex,
              let marker = text.range(of: "mediaDefinitions", options: [.caseInsensitive], range: searchStart..<text.endIndex) {
            guard let bracket = text[marker.upperBound...].firstIndex(of: "["),
                  let payload = balancedPayload(in: text, start: bracket, opening: "[", closing: "]") else {
                searchStart = marker.upperBound
                continue
            }
            objects.append(contentsOf: jsonObjects(fromPayload: payload))
            searchStart = marker.upperBound
        }
        return objects
    }

    private static func jsonObjects(fromPayload payload: String) -> [Any] {
        var objects: [Any] = []
        var seen = Set<String>()
        for raw in jsonPayloadVariants(payload) {
            let value = raw.trimmed
            guard !value.isEmpty, seen.insert(value).inserted, let data = value.data(using: .utf8) else {
                continue
            }
            if let object = try? JSONSerialization.jsonObject(with: data) {
                objects.append(object)
            }
        }
        return objects
    }

    private static func jsonPayloadVariants(_ payload: String) -> [String] {
        let decoded = normalizeEscapes(decodeHTML(payload))
        return [
            payload,
            decoded,
            decoded
                .replacingOccurrences(of: #"\""#, with: #"""#)
                .replacingOccurrences(of: #"\'"#, with: "'")
        ]
    }

    private static func balancedPayload(in text: String, start: String.Index, opening: Character, closing: Character) -> String? {
        var depth = 0
        var quote: Character?
        var escaped = false
        var index = start

        while index < text.endIndex {
            let char = text[index]
            if let quoteChar = quote {
                if escaped {
                    escaped = false
                } else if char == "\\" {
                    escaped = true
                } else if char == quoteChar {
                    quote = nil
                }
            } else if char == "\"" || char == "'" {
                quote = char
            } else if char == opening {
                depth += 1
            } else if char == closing {
                depth -= 1
                if depth == 0 {
                    return String(text[start...index])
                }
            }
            index = text.index(after: index)
        }
        return nil
    }

    private static func collectVideoCandidates(in object: Any, pageURL: URL, inheritedLabel: String, candidates: inout [PornhubVideoCandidate]) {
        if let dict = object as? [String: Any] {
            let label = stringValue(dict["quality"]) ??
                stringValue(dict["qualityText"]) ??
                stringValue(dict["height"]) ??
                stringValue(dict["format"]) ??
                stringValue(dict["label"]) ??
                inheritedLabel

            for key in ["videoUrl", "videoURL", "video_url", "url", "src", "file", "hls", "m3u8", "mp4"] {
                if let raw = stringValue(dict[key]) {
                    appendVideoCandidate(rawURL: raw, label: label, pageURL: pageURL, candidates: &candidates)
                }
            }

            for (key, value) in dict {
                collectVideoCandidates(in: value, pageURL: pageURL, inheritedLabel: label.isEmpty ? key : label, candidates: &candidates)
            }
        } else if let array = object as? [Any] {
            for item in array {
                collectVideoCandidates(in: item, pageURL: pageURL, inheritedLabel: inheritedLabel, candidates: &candidates)
            }
        }
    }

    private static func appendVideoCandidate(rawURL: String, label: String, pageURL: URL, candidates: inout [PornhubVideoCandidate]) {
        for raw in expandedRawVideoURLs(rawURL) {
            guard let url = absoluteURL(raw, baseURL: pageURL),
                  isPlayableVideo(url) else {
                continue
            }
            candidates.append(PornhubVideoCandidate(url: url, quality: qualityFrom(label: label, url: url), label: label))
            return
        }
    }

    private static func expandedRawVideoURLs(_ raw: String) -> [String] {
        let cleaned = normalizeEscapes(decodeHTML(raw)).trimmed
        var values = [cleaned]
        if let decoded = cleaned.removingPercentEncoding, decoded != cleaned {
            values.append(decoded)
        }
        return values
    }

    static func selectedVideoCandidate(
        _ candidates: [PornhubVideoCandidate],
        preferredResolution: String = ""
    ) -> PornhubVideoCandidate? {
        let ordered = candidates.enumerated()
            .filter { !isDASH($0.element) }
            .sorted { lhs, rhs in
                let leftQuality = effectiveQuality(lhs.element)
                let rightQuality = effectiveQuality(rhs.element)
                if leftQuality != rightQuality {
                    return leftQuality < rightQuality
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
        guard let lowest = ordered.first else { return nil }

        guard let ceiling = preferredHeight(from: preferredResolution) else {
            return ordered.last
        }
        return ordered.last(where: { effectiveQuality($0) <= ceiling }) ?? lowest
    }

    static func preferredHeight(from raw: String) -> Int? {
        var value = raw.trimmed.uppercased()
        guard !value.isEmpty else { return nil }
        if value.hasSuffix("P") {
            value.removeLast()
            return Int(value)
        }
        switch value {
        case "2K": return 1_440
        case "4K": return 2_160
        case "8K": return 4_320
        default: return Int(value)
        }
    }

    private static func effectiveQuality(_ candidate: PornhubVideoCandidate) -> Int {
        candidate.quality - (isM3U8(candidate.url) ? 1 : 0)
    }

    private static func isDASH(_ candidate: PornhubVideoCandidate) -> Bool {
        let text = "\(candidate.label) \(candidate.url.absoluteString)".lowercased()
        return text.contains("dash") || candidate.url.pathExtension.lowercased() == "mpd"
    }

    private static func uniqueVideoCandidates(_ candidates: [PornhubVideoCandidate]) -> [PornhubVideoCandidate] {
        var seen = Set<String>()
        return candidates.filter { candidate in
            let key = URLIdentity.normalize(candidate.url.absoluteString)
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }

    private static func absoluteURL(_ raw: String, baseURL: URL) -> URL? {
        var value = normalizeEscapes(decodeHTML(raw))
            .trimmed
        guard !value.isEmpty,
              !value.lowercased().hasPrefix("javascript:"),
              !value.lowercased().hasPrefix("data:") else {
            return nil
        }
        if value.hasPrefix("//") {
            value = (baseURL.scheme ?? "https") + ":" + value
        }
        guard let url = URL(string: value, relativeTo: baseURL)?.absoluteURL,
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }
        return url
    }

    private static func isPlayableVideo(_ url: URL) -> Bool {
        let lower = url.absoluteString.lowercased()
        return ["mp4", "m4v", "mov", "webm", "m3u8"].contains(url.pathExtension.lowercased()) ||
            lower.contains(".mp4") ||
            lower.contains(".m3u8") ||
            lower.contains(".webm")
    }

    private static func isM3U8(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "m3u8" || url.absoluteString.lowercased().contains(".m3u8")
    }

    private static func isSupportedHost(_ host: String) -> Bool {
        host == "pornhub.com" || host.hasSuffix(".pornhub.com") ||
            host == "pornhub.net" || host.hasSuffix(".pornhub.net") ||
            host == "pornhub.org" || host.hasSuffix(".pornhub.org") ||
            host == "pornhubthbh7ap3u.onion" ||
            host == "www.pornhubthbh7ap3u.onion" ||
            host == "pornhubvybmsymdol4iibwgwtkpwmeyd6luq2gxajgjzfjvotyt5zhyd.onion" ||
            host == "pornhubpremium.com" || host.hasSuffix(".pornhubpremium.com") ||
            host == "pornhubpremium.net" || host.hasSuffix(".pornhubpremium.net") ||
            host == "pornhubpremium.org" || host.hasSuffix(".pornhubpremium.org") ||
            host == "pornhub.test" ||
            host == "www.pornhub.test"
    }

    private static func canonicalHost(from sourceURL: URL?) -> String {
        guard let host = sourceURL?.host?.lowercased() else {
            return "www.pornhub.com"
        }
        if host.hasSuffix(".test") {
            return "www.pornhub.test"
        }
        return host.contains("pornhubpremium") ? "www.pornhubpremium.com" : "www.pornhub.com"
    }

    private static func isValidID(_ id: String) -> Bool {
        !id.isEmpty && id.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil
    }

    private static func isImage(_ url: URL) -> Bool {
        ["jpg", "jpeg", "png", "webp"].contains(url.pathExtension.lowercased())
    }

    private static func normalizeEscapes(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: #"\/"#, with: "/")
            .replacingOccurrences(of: #"\\/"#, with: "/")
            .replacingOccurrences(of: #"\u002F"#, with: "/")
            .replacingOccurrences(of: #"\u002f"#, with: "/")
    }

    private static func qualityFrom(label: String, url: URL) -> Int {
        let labelText = label.lowercased()
        if labelText.contains("source") || labelText.contains("original") {
            return 10_000
        }
        for source in [label, url.absoluteString] {
            let values = allCaptures(pattern: #"([0-9]{3,4})\s*p?"#, in: source)
                .compactMap(Int.init)
                .filter { (240...8640).contains($0) }
            if let best = values.max() {
                return best
            }
        }
        return 0
    }

    private static func stringValue(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            return string.trimmed.isEmpty ? nil : string
        case let number as NSNumber:
            return number.stringValue
        default:
            return nil
        }
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
            let scalarValue: UInt32?
            if let hexRange = Range(match.range(at: 1), in: text) {
                scalarValue = UInt32(String(text[hexRange]), radix: 16)
            } else if let decimalRange = Range(match.range(at: 2), in: text) {
                scalarValue = UInt32(String(text[decimalRange]), radix: 10)
            } else {
                scalarValue = nil
            }
            if let scalarValue, let scalar = UnicodeScalar(scalarValue) {
                text.replaceSubrange(whole, with: String(Character(scalar)))
            }
        }
        return text
    }

    private static func cleanTitle(_ raw: String, fallback: String) -> String {
        var text = decodeHTML(stripTags(raw))
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmed
        for suffix in [" - Pornhub.com", " | Pornhub.com", " - Pornhub", " | Pornhub"] {
            if text.lowercased().hasSuffix(suffix.lowercased()) {
                text = String(text.dropLast(suffix.count)).trimmed
            }
        }
        return (text.isEmpty ? fallback : text).sanitizedFilename(maxLength: 120)
    }
}
