import Foundation

final class NHentaiComResolver {
    func canResolve(_ url: URL) -> Bool {
        Self.slug(from: url) != nil
    }

    func resolve(_ url: URL, headers: HTTPRequestOptions = HTTPRequestOptions()) async throws -> ResolvedDownload {
        guard let slug = Self.slug(from: url) else {
            throw NativeDownloadError.invalidURL(url.absoluteString)
        }
        let infoData = try await HTTPClient.shared.data(
            from: Self.infoAPIURL(slug: slug, sourceURL: url),
            referer: headers.referer ?? url.absoluteString,
            userAgent: headers.userAgent
        )
        let imagesData = try await HTTPClient.shared.data(
            from: Self.imagesAPIURL(slug: slug, sourceURL: url),
            referer: headers.referer ?? url.absoluteString,
            userAgent: headers.userAgent
        )
        return try Self.resolvedDownload(
            infoData: infoData,
            imagesData: imagesData,
            sourceURL: url,
            userAgent: headers.userAgent
        )
    }

    static func slug(from url: URL) -> String? {
        guard let host = url.host?.lowercased(),
              isNHentaiComHost(host),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }
        let parts = url.path.split(separator: "/").map(String.init)
        guard let index = parts.firstIndex(where: { $0.lowercased() == "comic" }),
              index + 1 < parts.count else {
            return nil
        }
        let slug = parts[index + 1].removingPercentEncoding ?? parts[index + 1]
        return isValidSlug(slug) ? slug : nil
    }

    static func canonicalURL(for url: URL) -> URL? {
        guard let slug = slug(from: url),
              let host = url.host?.lowercased() else {
            return nil
        }
        var components = URLComponents()
        components.scheme = url.scheme ?? "https"
        components.host = host.hasSuffix(".test") ? "nhentai.com.test" : "nhentai.com"
        components.path = "/comic/\(slug)"
        return components.url
    }

    static func infoAPIURL(slug: String, sourceURL: URL) -> URL {
        var components = URLComponents()
        components.scheme = sourceURL.scheme ?? "https"
        components.host = sourceURL.host?.lowercased().hasSuffix(".test") == true ? "nhentai.com.test" : "nhentai.com"
        components.path = "/api/comics/\(slug)"
        return components.url!
    }

    static func imagesAPIURL(slug: String, sourceURL: URL) -> URL {
        var components = URLComponents()
        components.scheme = sourceURL.scheme ?? "https"
        components.host = sourceURL.host?.lowercased().hasSuffix(".test") == true ? "nhentai.com.test" : "nhentai.com"
        components.path = "/api/comics/\(slug)/images"
        return components.url!
    }

    static func resolvedDownload(
        infoData: Data,
        imagesData: Data,
        sourceURL: URL,
        userAgent: String? = nil
    ) throws -> ResolvedDownload {
        let info = try jsonObject(from: infoData)
        let imagesObject = try jsonObject(from: imagesData)
        let slug = slug(from: sourceURL) ?? stringValue(info["id"]) ?? sourceURL.lastPathComponent
        let comicID = stringValue(info["id"]) ?? slug
        let title = cleanTitle(stringValue(info["title"]) ?? stringValue(info["name"]) ?? "nhentai.com \(slug)", fallback: slug)
        let imageURLs = imageSourceURLs(from: imagesObject, sourceURL: sourceURL)
        guard !imageURLs.isEmpty else {
            throw NativeDownloadError.noFiles
        }

        let pageURL = canonicalURL(for: sourceURL) ?? sourceURL
        let metadata = metadata(
            info: info,
            slug: slug,
            comicID: comicID,
            title: title,
            imageCount: imageURLs.count,
            pageURL: pageURL
        )
        let assets = imageURLs.enumerated().map { offset, remote in
            ResolvedAsset(
                remoteURL: remote,
                filename: filename(for: remote, index: offset + 1),
                metadata: assetMetadata(for: remote, index: offset + 1, comicMetadata: metadata, pageURL: pageURL),
                referer: pageURL.absoluteString,
                userAgent: userAgent
            )
        }

        return ResolvedDownload(
            title: title,
            folderName: "\(title) (\(comicID))".sanitizedFilename(maxLength: 120),
            assets: assets,
            metadata: metadata
        )
    }

    private static func imageSourceURLs(from object: [String: Any], sourceURL: URL) -> [URL] {
        let rawItems = (object["images"] as? [[String: Any]]) ??
            (object["data"] as? [[String: Any]]) ??
            []
        var urls: [URL] = []
        var seen = Set<String>()
        for item in rawItems {
            guard let raw = stringValue(item["source_url"]) ??
                stringValue(item["sourceUrl"]) ??
                stringValue(item["url"]) else {
                continue
            }
            guard let remote = absoluteURL(raw, baseURL: sourceURL) else { continue }
            let normalized = URLIdentity.normalize(remote.absoluteString)
            guard !seen.contains(normalized) else { continue }
            seen.insert(normalized)
            urls.append(remote)
        }
        return urls
    }

    private static func metadata(info: [String: Any], slug: String, comicID: String, title: String, imageCount: Int, pageURL: URL) -> [String: String] {
        let artists = joinedNames(info["artists"])
        let groups = joinedNames(info["groups"])
        let creators = [artists, groups].filter { !$0.isEmpty }.joined(separator: ", ")
        return DownloadMetadata.clean([
            "artist": creators,
            "author": creators,
            "creator": creators,
            "uploader": creators,
            "channel": creators,
            "language": joinedNames(info["language"]),
            "parody": joinedNames(info["parodies"]),
            "series": joinedNames(info["seriess"]).isEmpty ? title : joinedNames(info["seriess"]),
            "category": joinedNames(info["category"]),
            "type": stringValue(info["type"]) ?? joinedNames(info["category"]),
            "tag": joinedNames(info["tags"]),
            "tags": joinedNames(info["tags"]),
            "gallery_id": comicID,
            "comic_id": comicID,
            "id": comicID,
            "slug": slug,
            "site": "nhentai.com",
            "title": title,
            "media_type": "image",
            "media_count": String(imageCount),
            "image_count": String(imageCount),
            "url": pageURL.absoluteString,
            "source_url": pageURL.absoluteString,
            "page_url": pageURL.absoluteString
        ])
    }

    private static func assetMetadata(for url: URL, index: Int, comicMetadata: [String: String], pageURL: URL) -> [String: String] {
        let format = mediaFormat(for: url)
        return DownloadMetadata.clean([
            "artist": comicMetadata["artist"] ?? "",
            "author": comicMetadata["author"] ?? "",
            "creator": comicMetadata["creator"] ?? "",
            "uploader": comicMetadata["uploader"] ?? "",
            "channel": comicMetadata["channel"] ?? "",
            "language": comicMetadata["language"] ?? "",
            "parody": comicMetadata["parody"] ?? "",
            "series": comicMetadata["series"] ?? "",
            "category": comicMetadata["category"] ?? "",
            "tag": comicMetadata["tag"] ?? "",
            "tags": comicMetadata["tags"] ?? "",
            "gallery_id": comicMetadata["gallery_id"] ?? "",
            "comic_id": comicMetadata["comic_id"] ?? "",
            "site": "nhentai.com",
            "title": comicMetadata["title"] ?? "",
            "type": "image",
            "media_type": "image",
            "page": String(index),
            "position": String(index),
            "format": format,
            "media_format": format,
            "image_url": url.absoluteString,
            "source_url": url.absoluteString,
            "media_url": url.absoluteString,
            "page_url": pageURL.absoluteString
        ])
    }

    private static func joinedNames(_ value: Any?) -> String {
        if let string = stringValue(value) {
            return string.trimmed
        }
        if let dict = value as? [String: Any] {
            return stringValue(dict["name"]) ?? stringValue(dict["title"]) ?? ""
        }
        if let list = value as? [[String: Any]] {
            return list.compactMap { stringValue($0["name"]) ?? stringValue($0["title"]) }
                .map { $0.trimmed }
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
        }
        if let array = value as? [Any] {
            return array.compactMap(joinedNames).filter { !$0.isEmpty }.joined(separator: ", ")
        }
        return ""
    }

    private static func filename(for url: URL, index: Int) -> String {
        let ext = mediaFormat(for: url)
        return String(format: "%04d.%@", index, ext).sanitizedFilename(maxLength: 120)
    }

    private static func mediaFormat(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        if ext == "jpeg" {
            return "jpg"
        }
        return ext.isEmpty ? "jpg" : ext
    }

    private static func cleanTitle(_ raw: String, fallback: String) -> String {
        let title = raw
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmed
            .sanitizedFilename(maxLength: 120)
        return title.isEmpty ? fallback : title
    }

    private static func jsonObject(from data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NativeDownloadError.invalidGalleryData
        }
        return object
    }

    private static func absoluteURL(_ raw: String, baseURL: URL) -> URL? {
        let value = raw.trimmed
        if value.hasPrefix("//") {
            return URL(string: "\(baseURL.scheme ?? "https"):\(value)")
        }
        return URL(string: value, relativeTo: baseURL)?.absoluteURL
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    private static func isValidSlug(_ value: String) -> Bool {
        !value.isEmpty &&
            value.count <= 180 &&
            value.range(of: #"^[A-Za-z0-9][A-Za-z0-9_-]*$"#, options: .regularExpression) != nil
    }

    private static func isNHentaiComHost(_ host: String) -> Bool {
        host == "nhentai.com" ||
            host == "www.nhentai.com" ||
            host == "nhentai.com.test" ||
            host == "www.nhentai.com.test"
    }
}
