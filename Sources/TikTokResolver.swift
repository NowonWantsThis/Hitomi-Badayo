import Foundation

struct TikTokMediaCandidate {
    var url: URL
    var score: Int
    var keyPath: [String] = []
    var mediaType: String = "video"
    var metadata: [String: String] = [:]
}

private struct TikTokVideoInfo {
    var id: String
    var title: String
    var folderTitle: String
    var authorName: String
    var authorID: String
}

final class TikTokResolver {
    func canResolve(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(),
              Self.isSupportedHost(host),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return false
        }
        return Self.videoID(from: url) != nil ||
            Self.profileUsername(from: url) != nil ||
            Self.shortLinkCode(from: url) != nil
    }

    func resolve(_ url: URL, headers: HTTPRequestOptions = HTTPRequestOptions()) async throws -> ResolvedDownload {
        if let shortCode = Self.shortLinkCode(from: url) {
            let target = try await Self.expandedShortURL(url, headers: headers)
            var resolved = try await resolve(target, headers: headers)
            resolved.metadata["short_url"] = url.absoluteString
            resolved.metadata["short_code"] = shortCode
            resolved.metadata["redirect_url"] = target.absoluteString
            return resolved
        }

        let pageURL = Self.canonicalContentURL(from: url) ?? url
        let html = try await HTTPClient.shared.string(from: pageURL, referer: headers.referer, userAgent: headers.userAgent)
        return try Self.resolvedDownload(fromHTML: html, pageURL: pageURL)
    }

    static func resolvedDownload(fromHTML html: String, pageURL: URL) throws -> ResolvedDownload {
        if let id = videoID(from: pageURL) {
            return try resolvedSingleDownload(fromHTML: html, pageURL: pageURL, videoID: id)
        }
        if profileUsername(from: pageURL) != nil {
            return try resolvedProfileDownload(fromHTML: html, pageURL: pageURL)
        }
        throw NativeDownloadError.invalidURL(pageURL.absoluteString)
    }

    static func videoID(from url: URL) -> String? {
        let parts = url.path.split(separator: "/").map { String($0).removingPercentEncoding ?? String($0) }
        let markers = ["video", "photo", "v"]
        for marker in markers {
            guard let index = parts.firstIndex(where: { $0.lowercased() == marker }),
                  index + 1 < parts.count else {
                continue
            }
            let candidate = parts[index + 1]
            if isNumericID(candidate) {
                return candidate
            }
        }

        if let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems {
            for name in ["item_id", "itemId", "video_id", "videoId", "modal_id", "modalId"] {
                guard let value = items.first(where: { $0.name == name })?.value,
                      isNumericID(value) else {
                    continue
                }
                return value
            }
        }
        return nil
    }

    static func profileUsername(from url: URL) -> String? {
        guard let host = url.host?.lowercased(),
              isSupportedHost(host),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              videoID(from: url) == nil else {
            return nil
        }

        let parts = url.path.split(separator: "/").map { String($0).removingPercentEncoding ?? String($0) }
        if parts.count == 1, parts[0].hasPrefix("@") {
            let username = String(parts[0].dropFirst()).trimmed
            return isValidProfileIdentifier(username) ? username : nil
        }

        if parts.count == 2,
           host.contains("douyin"),
           parts[0].lowercased() == "user" {
            let username = parts[1].trimmed
            return isValidProfileIdentifier(username) ? username : nil
        }
        return nil
    }

    static func shortLinkCode(from url: URL) -> String? {
        guard let host = url.host?.lowercased(),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }

        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        let code: String
        if isDedicatedShortLinkHost(host) {
            guard parts.count == 1 else { return nil }
            code = parts[0]
        } else if isTikTokMainHost(host),
                  parts.count == 2,
                  parts[0].lowercased() == "t" {
            code = parts[1]
        } else {
            return nil
        }

        let trimmed = code.trimmed
        guard trimmed.range(of: #"^[0-9A-Za-z_-]{4,128}$"#, options: .regularExpression) != nil else {
            return nil
        }
        return trimmed
    }

    static func canonicalContentURL(from url: URL) -> URL? {
        guard let host = url.host?.lowercased(),
              isSupportedHost(host),
              videoID(from: url) != nil || profileUsername(from: url) != nil,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        components.scheme = "https"
        components.query = nil
        components.fragment = nil

        if let username = profileUsername(from: url), videoID(from: url) == nil {
            components.path = host.contains("douyin") ? "/user/\(username)" : "/@\(username)"
        }
        return components.url
    }

    static func canonicalProfileURL(username rawUsername: String, sourceURL: URL? = nil) -> URL? {
        let username = rawUsername.trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "@/ "))
        guard isValidProfileIdentifier(username) else { return nil }

        let sourceHost = sourceURL?.host?.lowercased() ?? ""
        var components = URLComponents()
        components.scheme = sourceURL?.scheme ?? "https"
        if sourceHost.contains("douyin") {
            components.host = sourceHost.hasSuffix(".test") ? "douyin.test" : "www.douyin.com"
            components.path = "/user/\(username)"
        } else {
            components.host = sourceHost.hasSuffix(".test") ? "tiktok.test" : "www.tiktok.com"
            components.path = "/@\(username)"
        }
        return components.url
    }

    private static func expandedShortURL(_ url: URL, headers: HTTPRequestOptions) async throws -> URL {
        guard let response = try await HTTPClient.shared.head(
            from: url,
            referer: headers.referer,
            userAgent: headers.userAgent
        ),
              let finalURL = response.url,
              finalURL.absoluteString != url.absoluteString,
              videoID(from: finalURL) != nil || profileUsername(from: finalURL) != nil,
              let canonical = canonicalContentURL(from: finalURL) else {
            throw NativeDownloadError.unsupported("TikTok short link did not resolve to a supported video, photo, or profile URL.")
        }
        return canonical
    }

    static func itemObject(fromHTML html: String, videoID: String) -> [String: Any]? {
        let objects = jsonPayloads(fromHTML: html).compactMap { payload -> Any? in
            try? JSONSerialization.jsonObject(with: payload)
        }

        var collected: [[String: Any]] = []
        for object in objects {
            collected.append(contentsOf: itemObjects(in: object, expectedID: videoID))
        }

        if let exact = collected.first(where: { itemID(from: $0) == videoID }) {
            return exact
        }
        return collected.first
    }

    static func itemObjects(fromHTML html: String) -> [[String: Any]] {
        let objects = jsonPayloads(fromHTML: html).compactMap { payload -> Any? in
            try? JSONSerialization.jsonObject(with: payload)
        }

        var output: [[String: Any]] = []
        var seen = Set<String>()
        for object in objects {
            for item in itemObjects(in: object) {
                guard let id = itemID(from: item),
                      !seen.contains(id) else {
                    continue
                }
                seen.insert(id)
                output.append(item)
            }
        }
        return output
    }

    static func mediaURLs(fromItem item: [String: Any], pageURL: URL) -> [URL] {
        mediaCandidates(fromItem: item, pageURL: pageURL).map(\.url)
    }

    static func mediaCandidates(fromItem item: [String: Any], pageURL: URL) -> [TikTokMediaCandidate] {
        let videoCandidates = videoContainer(from: item).map { collectMediaCandidates(in: $0, pageURL: pageURL) } ?? []
        let shouldSort = !videoCandidates.isEmpty
        let candidates = shouldSort ? videoCandidates : imageMediaCandidates(fromItem: item, pageURL: pageURL)
        var seen = Set<String>()
        let ordered = shouldSort ? candidates.sorted { $0.score > $1.score } : candidates
        return ordered
            .compactMap { candidate in
                let normalized = URLIdentity.normalize(candidate.url.absoluteString)
                guard !seen.contains(normalized) else { return nil }
                seen.insert(normalized)
                return candidate
            }
    }

    static func jsonPayloads(fromHTML html: String) -> [Data] {
        let scriptIDs = ["SIGI_STATE", "__UNIVERSAL_DATA_FOR_REHYDRATION__", "__NEXT_DATA__", "RENDER_DATA"]
        var payloads: [Data] = []
        var seen = Set<String>()
        func appendPayloads(from contents: [String]) {
            for data in contents.compactMap(jsonData(fromScriptContent:)) {
                let key = String(data: data, encoding: .utf8) ?? data.base64EncodedString()
                guard !seen.contains(key) else { continue }
                seen.insert(key)
                payloads.append(data)
            }
        }

        for scriptID in scriptIDs {
            appendPayloads(from: scriptContents(id: scriptID, fromHTML: html))
        }
        appendPayloads(from: jsonScriptContents(fromHTML: html))
        appendPayloads(from: assignmentPayloads(fromHTML: html))
        return payloads
    }

    private static func resolvedSingleDownload(fromHTML html: String, pageURL: URL, videoID id: String) throws -> ResolvedDownload {
        guard let item = itemObject(fromHTML: html, videoID: id) else {
            throw NativeDownloadError.invalidGalleryData
        }
        let allMediaItems = mediaCandidates(fromItem: item, pageURL: pageURL)
        guard !allMediaItems.isEmpty else {
            throw NativeDownloadError.noFiles
        }
        let mediaItems = allMediaItems.first?.mediaType == "video" ? [allMediaItems[0]] : allMediaItems

        let info = videoInfo(fromItem: item, fallbackID: id)
        let assets = mediaItems.enumerated().map { offset, media in
            ResolvedAsset(
                remoteURL: media.url,
                filename: filename(for: media, info: info, position: offset + 1, total: mediaItems.count),
                metadata: assetMetadata(for: media, item: item, info: info, pageURL: pageURL, position: offset + 1),
                referer: pageURL.absoluteString
            )
        }
        let site = siteName(from: pageURL)
        let packageMode: DownloadPackageMode
        let packageModeName: String
        if mediaItems.count == 1, mediaItems[0].mediaType == "video" {
            packageMode = .concatenate(outputFilename: assets[0].filename)
            packageModeName = "concatenate"
        } else {
            packageMode = .files
            packageModeName = "files"
        }
        return ResolvedDownload(
            title: info.title,
            folderName: "\(site) \(info.folderTitle)".sanitizedFilename(maxLength: 120),
            assets: assets,
            packageMode: packageMode,
            metadata: itemMetadata(info: info, assets: assets, pageURL: pageURL, packageMode: packageModeName)
        )
    }

    private static func resolvedProfileDownload(fromHTML html: String, pageURL: URL) throws -> ResolvedDownload {
        let username = profileUsername(from: pageURL) ?? "profile"
        let items = itemObjects(fromHTML: html)
        var assets: [ResolvedAsset] = []
        var seen = Set<String>()
        var displayName = ""

        for item in items {
            let allItemMedia = mediaCandidates(fromItem: item, pageURL: pageURL)
            guard !allItemMedia.isEmpty else { continue }
            let itemMedia = allItemMedia.first?.mediaType == "video" ? [allItemMedia[0]] : allItemMedia

            let info = videoInfo(fromItem: item, fallbackID: itemID(from: item) ?? "video-\(assets.count + 1)")
            if displayName.isEmpty {
                displayName = [info.authorName, info.authorID, username].first(where: { !$0.trimmed.isEmpty }) ?? ""
            }

            let itemPageURL = webpageURL(fromItem: item, pageURL: pageURL)
            for media in itemMedia {
                let mediaURL = media.url
                let normalized = URLIdentity.normalize(mediaURL.absoluteString)
                guard !seen.contains(normalized) else { continue }
                seen.insert(normalized)

                let ext = mediaExtension(for: media)
                let baseName = "\(info.title)-\(info.id).\(ext)".sanitizedFilename(maxLength: 150)
                assets.append(ResolvedAsset(
                    remoteURL: mediaURL,
                    filename: String(format: "%04d-%@", assets.count + 1, baseName).sanitizedFilename(maxLength: 180),
                    metadata: assetMetadata(for: media, item: item, info: info, pageURL: itemPageURL, position: assets.count + 1),
                    referer: itemPageURL.absoluteString
                ))
            }
        }

        guard !assets.isEmpty else {
            throw NativeDownloadError.noFiles
        }

        let titleBase = displayName.trimmed.isEmpty ? username : displayName
        let title = "\(titleBase) (tiktok_\(username))".sanitizedFilename(maxLength: 120)
        return ResolvedDownload(
            title: title,
            folderName: "\(siteName(from: pageURL)) \(title)".sanitizedFilename(maxLength: 120),
            assets: assets,
            metadata: profileMetadata(titleBase: titleBase, username: username, assets: assets, pageURL: pageURL)
        )
    }

    private static func webpageURL(fromItem item: [String: Any], pageURL: URL) -> URL {
        for key in ["permalink_url", "permalinkUrl", "shareUrl", "share_url", "url"] {
            if let raw = stringValue(item[key]),
               let url = absoluteURL(raw, baseURL: pageURL) {
                return url
            }
        }
        return pageURL
    }

    private static func videoInfo(fromItem item: [String: Any], fallbackID: String) -> TikTokVideoInfo {
        let id = itemID(from: item) ?? fallbackID
        let rawTitle = stringValue(item["desc"]) ??
            stringValue(item["description"]) ??
            stringValue(item["title"]) ??
            stringValue(dictionary(at: ["shareMeta"], in: item)?["title"]) ??
            stringValue(dictionary(at: ["seoProps", "metaParams"], in: item)?["title"]) ??
            "TikTok \(id)"
        let title = cleanTitle(rawTitle)

        let author = item["author"] as? [String: Any] ??
            item["authorInfo"] as? [String: Any] ??
            item["author_info"] as? [String: Any]
        let authorID = cleanTitle(
            stringValue(author?["uniqueId"]) ??
                stringValue(author?["unique_id"]) ??
                stringValue(author?["id"]) ??
                ""
        )
        let authorName = cleanTitle(
            stringValue(author?["nickname"]) ??
                stringValue(author?["uniqueId"]) ??
                stringValue(author?["unique_id"]) ??
                ""
        )
        let folderTitle = authorName.isEmpty ? title : "\(authorName) - \(title)"
        return TikTokVideoInfo(id: id, title: title, folderTitle: folderTitle, authorName: authorName, authorID: authorID)
    }

    private static func itemMetadata(info: TikTokVideoInfo, assets: [ResolvedAsset], pageURL: URL, packageMode: String) -> [String: String] {
        let firstAsset = assets.first
        let firstVideo = assets.first { $0.metadata["media_type"] == "video" }
        let firstImage = assets.first { $0.metadata["media_type"] == "image" }
        let videoCount = assets.filter { $0.metadata["media_type"] == "video" }.count
        let imageCount = assets.filter { $0.metadata["media_type"] == "image" }.count
        let type = imageCount > 0 && videoCount > 0 ? "mixed" : imageCount > 0 ? "image" : "video"
        return DownloadMetadata.clean([
            "site": siteName(from: pageURL),
            "title": info.title,
            "type": type,
            "media_type": type,
            "package_mode": packageMode,
            "media_count": String(assets.count),
            "video_count": videoCount > 0 ? String(videoCount) : "",
            "image_count": imageCount > 0 ? String(imageCount) : "",
            "id": info.id,
            "video_id": info.id,
            "media_id": info.id,
            "video_url": firstVideo?.remoteURL.absoluteString ?? "",
            "image_url": firstImage?.remoteURL.absoluteString ?? "",
            "media_url": firstAsset?.remoteURL.absoluteString ?? "",
            "source_url": pageURL.absoluteString,
            "page_url": pageURL.absoluteString,
            "format": firstAsset?.metadata["format"] ?? "",
            "media_format": firstAsset?.metadata["media_format"] ?? "",
            "width": firstAsset?.metadata["width"] ?? "",
            "height": firstAsset?.metadata["height"] ?? "",
            "resolution": firstAsset?.metadata["resolution"] ?? "",
            "quality": firstAsset?.metadata["quality"] ?? "",
            "artist": info.authorName,
            "author": info.authorName,
            "creator": info.authorName,
            "uploader": info.authorName,
            "channel": info.authorName,
            "user": info.authorID,
            "username": info.authorID,
            "uploader_id": info.authorID,
            "channel_id": info.authorID
        ])
    }

    private static func profileMetadata(titleBase: String, username: String, assets: [ResolvedAsset], pageURL: URL) -> [String: String] {
        let videoCount = assets.filter { $0.metadata["media_type"] == "video" }.count
        let imageCount = assets.filter { $0.metadata["media_type"] == "image" }.count
        let mediaType = imageCount > 0 && videoCount > 0 ? "mixed" : imageCount > 0 ? "image" : "video"
        return DownloadMetadata.clean([
            "site": siteName(from: pageURL),
            "title": titleBase,
            "type": "profile",
            "media_type": mediaType,
            "package_mode": "files",
            "media_count": String(assets.count),
            "video_count": videoCount > 0 ? String(videoCount) : "",
            "image_count": imageCount > 0 ? String(imageCount) : "",
            "post_count": String(assets.count),
            "id": username,
            "user": username,
            "username": username,
            "uploader_id": username,
            "channel_id": username,
            "profile_url": pageURL.absoluteString,
            "source_url": pageURL.absoluteString,
            "page_url": pageURL.absoluteString,
            "artist": titleBase,
            "author": titleBase,
            "creator": titleBase,
            "uploader": titleBase,
            "channel": titleBase
        ])
    }

    private static func assetMetadata(for candidate: TikTokMediaCandidate, item: [String: Any], info: TikTokVideoInfo, pageURL: URL, position: Int) -> [String: String] {
        let video = videoContainer(from: item) ?? item
        let values = [video, item]
        let format = mediaFormat(for: candidate.url, video: video)
        let width = candidate.metadata["width"] ?? firstMetadataValue(in: values, keys: ["width", "Width", "displayWidth", "display_width"])
        let height = candidate.metadata["height"] ?? firstMetadataValue(in: values, keys: ["height", "Height", "displayHeight", "display_height"])
        let resolution = height.isEmpty ? "" : "\(height)p"
        let rawQuality = firstMetadataValue(in: values, keys: ["quality", "ratio", "definition", "format", "formatType", "format_type"])
        let mediaType = candidate.mediaType

        return DownloadMetadata.clean([
            "site": siteName(from: pageURL),
            "title": info.title,
            "type": mediaType,
            "media_type": mediaType,
            "id": info.id,
            "video_id": info.id,
            "media_id": info.id,
            "page": String(position),
            "position": String(position),
            "stream_id": candidate.keyPath.joined(separator: "."),
            "format": format,
            "media_format": format,
            "width": width,
            "height": height,
            "resolution": resolution,
            "quality": resolution.isEmpty ? rawQuality : resolution,
            "duration": firstMetadataValue(in: values, keys: ["duration", "durationMs", "duration_ms"]),
            "bitrate": firstMetadataValue(in: values, keys: ["bitrate", "bitRate", "bit_rate"]),
            "video_url": mediaType == "video" ? candidate.url.absoluteString : "",
            "image_url": mediaType == "image" ? candidate.url.absoluteString : "",
            "media_url": candidate.url.absoluteString,
            "source_url": pageURL.absoluteString,
            "page_url": pageURL.absoluteString,
            "artist": info.authorName,
            "author": info.authorName,
            "creator": info.authorName,
            "uploader": info.authorName,
            "channel": info.authorName,
            "user": info.authorID,
            "username": info.authorID,
            "uploader_id": info.authorID,
            "channel_id": info.authorID
        ])
    }

    private static func itemObjects(in value: Any) -> [[String: Any]] {
        if let dictionary = value as? [String: Any] {
            var results: [[String: Any]] = []
            if isVideoItem(dictionary) {
                results.append(dictionary)
            }
            for key in dictionary.keys.sorted() {
                guard let child = dictionary[key] else { continue }
                results.append(contentsOf: itemObjects(in: child))
            }
            return results
        }

        if let array = value as? [Any] {
            return array.flatMap { itemObjects(in: $0) }
        }
        return []
    }

    private static func itemObjects(in value: Any, expectedID: String) -> [[String: Any]] {
        if let dictionary = value as? [String: Any] {
            var results: [[String: Any]] = []
            if isVideoItem(dictionary, expectedID: expectedID) {
                results.append(dictionary)
            }
            for key in dictionary.keys.sorted() {
                guard let child = dictionary[key] else { continue }
                results.append(contentsOf: itemObjects(in: child, expectedID: expectedID))
            }
            return results
        }

        if let array = value as? [Any] {
            return array.flatMap { itemObjects(in: $0, expectedID: expectedID) }
        }
        return []
    }

    private static func isVideoItem(_ object: [String: Any], expectedID: String) -> Bool {
        guard hasMediaContainer(object) else { return false }
        guard let id = itemID(from: object) else { return true }
        return id == expectedID
    }

    private static func isVideoItem(_ object: [String: Any]) -> Bool {
        hasMediaContainer(object) && itemID(from: object) != nil
    }

    private static func itemID(from item: [String: Any]) -> String? {
        for key in ["id", "itemId", "item_id", "awemeId", "aweme_id", "groupId", "group_id"] {
            if let value = stringValue(item[key]), isNumericID(value) {
                return value
            }
        }
        if let video = item["video"] as? [String: Any] {
            for key in ["id", "vid", "videoId", "video_id"] {
                if let value = stringValue(video[key]), isNumericID(value) {
                    return value
                }
            }
        }
        return nil
    }

    private static func hasMediaContainer(_ object: [String: Any]) -> Bool {
        videoContainer(from: object) != nil || imagePostContainer(from: object) != nil
    }

    private static func videoContainer(from item: [String: Any]) -> [String: Any]? {
        item["video"] as? [String: Any] ?? item["videoData"] as? [String: Any]
    }

    private static func imagePostContainer(from item: [String: Any]) -> Any? {
        for key in ["imagePost", "image_post", "imagePostData", "image_post_info", "imagePostInfo", "photoModeImageInfo"] {
            if let value = item[key] {
                return value
            }
        }
        if videoContainer(from: item) == nil,
           let images = item["images"] {
            return images
        }
        return nil
    }

    private static func collectMediaCandidates(in value: Any, pageURL: URL, keyPath: [String] = []) -> [TikTokMediaCandidate] {
        if let string = stringValue(value),
           let url = absoluteURL(string, baseURL: pageURL),
           isLikelyVideoURL(url, raw: string, keyPath: keyPath) {
            return [TikTokMediaCandidate(url: url, score: mediaScore(raw: string, keyPath: keyPath), keyPath: keyPath)]
        }

        if let dictionary = value as? [String: Any] {
            var candidates: [TikTokMediaCandidate] = []
            for (key, child) in dictionary {
                let path = keyPath + [key]
                guard !isExcludedMediaPath(path) else { continue }
                candidates.append(contentsOf: collectMediaCandidates(in: child, pageURL: pageURL, keyPath: path))
            }
            return candidates
        }

        if let array = value as? [Any] {
            return array.flatMap { collectMediaCandidates(in: $0, pageURL: pageURL, keyPath: keyPath) }
        }
        return []
    }

    private static func imageMediaCandidates(fromItem item: [String: Any], pageURL: URL) -> [TikTokMediaCandidate] {
        guard let container = imagePostContainer(from: item) else { return [] }
        if let images = imagePostImages(from: container) {
            return images.enumerated().compactMap { offset, image in
                collectImageCandidates(in: image, pageURL: pageURL, keyPath: ["imagePost", "images", String(offset)])
                    .max { $0.score < $1.score }
            }
        }
        return collectImageCandidates(in: container, pageURL: pageURL, keyPath: ["imagePost"])
    }

    private static func imagePostImages(from value: Any) -> [Any]? {
        if let array = value as? [Any] {
            return array
        }
        guard let dictionary = value as? [String: Any] else {
            return nil
        }
        for key in ["images", "imageList", "image_list"] {
            if let array = dictionary[key] as? [Any], !array.isEmpty {
                return array
            }
        }
        return nil
    }

    private static func collectImageCandidates(
        in value: Any,
        pageURL: URL,
        keyPath: [String],
        inheritedMetadata: [String: String] = [:]
    ) -> [TikTokMediaCandidate] {
        if let string = stringValue(value),
           let url = absoluteURL(string, baseURL: pageURL),
           isLikelyImageURL(url, raw: string, keyPath: keyPath) {
            return [
                TikTokMediaCandidate(
                    url: url,
                    score: imageScore(raw: string, keyPath: keyPath, metadata: inheritedMetadata),
                    keyPath: keyPath,
                    mediaType: "image",
                    metadata: inheritedMetadata
                )
            ]
        }

        if let dictionary = value as? [String: Any] {
            var candidates: [TikTokMediaCandidate] = []
            let metadata = inheritedMetadata.merging(imageMetadata(from: dictionary)) { _, new in new }
            for (key, child) in dictionary {
                let path = keyPath + [key]
                if let raw = stringValue(child),
                   let url = absoluteURL(raw, baseURL: pageURL),
                   isLikelyImageURL(url, raw: raw, keyPath: path) {
                    candidates.append(TikTokMediaCandidate(
                        url: url,
                        score: imageScore(raw: raw, keyPath: path, metadata: metadata),
                        keyPath: path,
                        mediaType: "image",
                        metadata: metadata
                    ))
                } else {
                    candidates.append(contentsOf: collectImageCandidates(in: child, pageURL: pageURL, keyPath: path, inheritedMetadata: metadata))
                }
            }
            return candidates
        }

        if let array = value as? [Any] {
            return array.flatMap { collectImageCandidates(in: $0, pageURL: pageURL, keyPath: keyPath, inheritedMetadata: inheritedMetadata) }
        }
        return []
    }

    private static func mediaScore(raw: String, keyPath: [String]) -> Int {
        let path = keyPath.map { $0.lowercased() }.joined(separator: ".")
        let value = raw.lowercased()
        var score = 0
        if path.contains("download") { score += 2_000_000 }
        if path.contains("playaddrh264") || path.contains("play_addr_h264") { score += 900_000 }
        if path.contains("playaddr") || path.contains("play_addr") { score += 800_000 }
        if path.contains("url_list") || path.contains("urllist") { score += 400_000 }
        if value.contains(".mp4") || value.contains("mime_type=video_mp4") { score += 50_000 }
        if value.contains("watermark=0") || value.contains("wm=0") { score += 2_000 }
        if value.contains("h264") { score += 1_000 }
        return score
    }

    private static func imageScore(raw: String, keyPath: [String], metadata: [String: String]) -> Int {
        let path = keyPath.map { $0.lowercased() }.joined(separator: ".")
        let value = raw.lowercased()
        var score = 0
        if path.contains("origin") || path.contains("original") { score += 2_000_000 }
        if path.contains("display") || path.contains("imageurl") || path.contains("image_url") { score += 1_000_000 }
        if path.contains("urllist") || path.contains("url_list") { score += 500_000 }
        if value.contains("/origin") || value.contains("/obj/") { score += 50_000 }
        if value.contains(".webp") || value.contains(".jpg") || value.contains(".jpeg") || value.contains(".png") { score += 10_000 }
        if let width = Int(metadata["width"] ?? ""), let height = Int(metadata["height"] ?? "") {
            score += min(width * height, 10_000_000) / 100
        }
        return score
    }

    private static func isLikelyVideoURL(_ url: URL, raw: String, keyPath: [String]) -> Bool {
        let value = raw.lowercased()
        let host = url.host?.lowercased() ?? ""
        let path = keyPath.map { $0.lowercased() }.joined(separator: ".")
        if isExcludedMediaPath(keyPath) { return false }
        if path.contains("download") || path.contains("playaddr") || path.contains("play_addr") || path.contains("url_list") || path.contains("urllist") {
            return true
        }
        return value.contains(".mp4") ||
            value.contains("mime_type=video") ||
            value.contains("/video/") ||
            host.contains("tiktokcdn") ||
            host.contains("douyinvod") ||
            host.contains("byteoversea") ||
            host.contains("muscdn")
    }

    private static func isLikelyImageURL(_ url: URL, raw: String, keyPath: [String]) -> Bool {
        let value = raw.lowercased()
        let host = url.host?.lowercased() ?? ""
        let ext = url.pathExtension.lowercased()
        if ["jpg", "jpeg", "png", "webp", "avif"].contains(ext) {
            return true
        }
        return value.contains("image") ||
            value.contains("mime_type=image") ||
            host.contains("tiktokcdn") ||
            host.contains("douyinpic") ||
            host.contains("byteimg")
    }

    private static func imageMetadata(from dictionary: [String: Any]) -> [String: String] {
        var metadata: [String: String] = [:]
        let width = firstMetadataValue(in: [dictionary], keys: ["width", "Width", "imageWidth", "image_width", "displayWidth", "display_width"])
        let height = firstMetadataValue(in: [dictionary], keys: ["height", "Height", "imageHeight", "image_height", "displayHeight", "display_height"])
        if !width.isEmpty { metadata["width"] = width }
        if !height.isEmpty { metadata["height"] = height }
        return metadata
    }

    private static func isExcludedMediaPath(_ path: [String]) -> Bool {
        let joined = path.map { $0.lowercased() }.joined(separator: ".")
        return joined.contains("cover") ||
            joined.contains("avatar") ||
            joined.contains("image") ||
            joined.contains("thumbnail") ||
            joined.contains("thumb") ||
            joined.contains("poster")
    }

    private static func scriptContents(id: String, fromHTML html: String) -> [String] {
        let escapedID = NSRegularExpression.escapedPattern(for: id)
        let pattern = #"<script\b(?=[^>]*\bid\s*=\s*["']"# + escapedID + #"["'])[^>]*>(.*?)</script>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        return regex.matches(in: html, range: range).compactMap { match in
            guard let capture = Range(match.range(at: 1), in: html) else { return nil }
            return String(html[capture])
        }
    }

    private static func jsonScriptContents(fromHTML html: String) -> [String] {
        let pattern = #"<script\b(?=[^>]*\btype\s*=\s*["'][^"']*(?:application/json|application/ld\+json)[^"']*["'])[^>]*>(.*?)</script>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        return regex.matches(in: html, range: range).compactMap { match in
            guard let capture = Range(match.range(at: 1), in: html) else { return nil }
            return String(html[capture])
        }
    }

    private static func assignmentPayloads(fromHTML html: String) -> [String] {
        let patterns = [
            #"window\.__INIT_PROPS__\s*=\s*(\{.*?\})\s*;"#,
            #"window\.__UNIVERSAL_DATA_FOR_REHYDRATION__\s*=\s*(\{.*?\})\s*;"#
        ]
        return patterns.flatMap { pattern -> [String] in
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
                return []
            }
            let range = NSRange(html.startIndex..<html.endIndex, in: html)
            return regex.matches(in: html, range: range).compactMap { match in
                guard let capture = Range(match.range(at: 1), in: html) else { return nil }
                return String(html[capture])
            }
        }
    }

    private static func jsonData(fromScriptContent raw: String) -> Data? {
        let decoded = decodeHTML(normalizeEscapes(raw)).trimmed
        return jsonDataCandidate(from: decoded)
    }

    private static func jsonDataCandidate(from text: String, depth: Int = 0) -> Data? {
        guard depth < 3 else { return nil }

        var candidates = [text]
        if let percentDecoded = text.removingPercentEncoding,
           percentDecoded != text {
            candidates.append(percentDecoded)
        }

        for candidate in candidates {
            let normalized = decodeHTML(normalizeEscapes(candidate)).trimmed
            if normalized.hasPrefix("{") || normalized.hasPrefix("[") {
                return normalized.data(using: .utf8)
            }

            guard normalized.hasPrefix("\""),
                  let data = normalized.data(using: .utf8),
                  let nested = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? String,
                  let nestedData = jsonDataCandidate(from: nested, depth: depth + 1) else {
                continue
            }
            return nestedData
        }
        return nil
    }

    private static func absoluteURL(_ raw: String, baseURL: URL) -> URL? {
        let cleaned = decodeHTML(normalizeEscapes(raw))
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'").union(.whitespacesAndNewlines))
        let values = [cleaned, cleaned.removingPercentEncoding ?? cleaned]
        for value in values where !value.isEmpty {
            if value.hasPrefix("//") {
                return URL(string: "\(baseURL.scheme ?? "https"):\(value)")
            }
            if let url = URL(string: value, relativeTo: baseURL)?.absoluteURL,
               ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                return url
            }
        }
        return nil
    }

    private static func isSupportedHost(_ host: String) -> Bool {
        host == "tiktok.com" ||
            host == "www.tiktok.com" ||
            host == "m.tiktok.com" ||
            host.hasSuffix(".tiktok.com") ||
            host == "douyin.com" ||
            host == "www.douyin.com" ||
            host.hasSuffix(".douyin.com") ||
            host == "tiktok.test" ||
            host == "www.tiktok.test" ||
            host.hasSuffix(".tiktok.test") ||
            host == "douyin.test" ||
            host == "www.douyin.test" ||
            host.hasSuffix(".douyin.test")
    }

    private static func isDedicatedShortLinkHost(_ host: String) -> Bool {
        [
            "vm.tiktok.com",
            "vt.tiktok.com",
            "v.douyin.com",
            "vm.tiktok.test",
            "vt.tiktok.test",
            "v.douyin.test"
        ].contains(host)
    }

    private static func isTikTokMainHost(_ host: String) -> Bool {
        [
            "tiktok.com",
            "www.tiktok.com",
            "m.tiktok.com",
            "tiktok.test",
            "www.tiktok.test",
            "m.tiktok.test"
        ].contains(host)
    }

    private static func siteName(from url: URL) -> String {
        (url.host?.lowercased().contains("douyin") ?? false) ? "Douyin" : "TikTok"
    }

    private static func mediaFormat(for url: URL, video: [String: Any]) -> String {
        let ext = url.pathExtension.trimmed.lowercased()
        if !ext.isEmpty { return ext }

        let raw = url.absoluteString.lowercased()
        if raw.contains("video_mp4") || raw.contains(".mp4") { return "mp4" }
        if raw.contains(".m3u8") { return "m3u8" }
        return firstMetadataValue(in: [video], keys: ["format", "formatType", "format_type"]).lowercased()
    }

    private static func mediaExtension(for candidate: TikTokMediaCandidate) -> String {
        let ext = candidate.url.pathExtension.trimmed.lowercased()
        if !ext.isEmpty {
            return ext
        }
        let raw = candidate.url.absoluteString.lowercased()
        if candidate.mediaType == "image" {
            for value in ["jpg", "jpeg", "png", "webp", "avif"] where raw.contains(".\(value)") {
                return value
            }
            return "jpg"
        }
        if raw.contains("video_mp4") || raw.contains(".mp4") {
            return "mp4"
        }
        if raw.contains(".m3u8") {
            return "m3u8"
        }
        return "mp4"
    }

    private static func filename(for media: TikTokMediaCandidate, info: TikTokVideoInfo, position: Int, total: Int) -> String {
        let ext = mediaExtension(for: media)
        if total == 1, media.mediaType == "video" {
            return "\(info.title)-\(info.id).\(ext)".sanitizedFilename(maxLength: 180)
        }
        let suffix = total > 1 ? "-\(String(format: "%02d", position))" : ""
        return "\(String(format: "%04d", position))-\(info.title)-\(info.id)\(suffix).\(ext)"
            .sanitizedFilename(maxLength: 180)
    }

    private static func firstMetadataValue(in dictionaries: [[String: Any]], keys: [String]) -> String {
        for dictionary in dictionaries {
            for key in keys {
                if let value = stringValue(dictionary[key])?.trimmed, !value.isEmpty {
                    return value
                }
            }
        }
        return ""
    }

    private static func dictionary(at path: [String], in object: [String: Any]) -> [String: Any]? {
        var current: Any? = object
        for key in path {
            current = (current as? [String: Any])?[key]
        }
        return current as? [String: Any]
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    private static func cleanTitle(_ raw: String) -> String {
        var value = raw
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmed
        value = value.replacingOccurrences(of: #"(?i)\s+\|\s+TikTok.*$"#, with: "", options: .regularExpression)
        return value.sanitizedFilename(maxLength: 120)
    }

    private static func normalizeEscapes(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\/", with: "/")
            .replacingOccurrences(of: "\\u0026", with: "&", options: .caseInsensitive)
            .replacingOccurrences(of: "\\u003d", with: "=", options: .caseInsensitive)
            .replacingOccurrences(of: "\\u003f", with: "?", options: .caseInsensitive)
            .replacingOccurrences(of: "\\u002F", with: "/", options: .caseInsensitive)
            .replacingOccurrences(of: "\\u003A", with: ":", options: .caseInsensitive)
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

    private static func isNumericID(_ value: String) -> Bool {
        value.range(of: #"^[0-9]{4,}$"#, options: .regularExpression) != nil
    }

    private static func isValidProfileIdentifier(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z0-9._-]{1,80}$"#, options: .regularExpression) != nil
    }
}
