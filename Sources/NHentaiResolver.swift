import Foundation

struct NHentaiGallery: Decodable {
    let id: Int?
    let mediaID: String
    let title: NHentaiTitle?
    let images: NHentaiImages
    let tags: [NHentaiTag]?

    enum CodingKeys: String, CodingKey {
        case id
        case mediaID = "media_id"
        case title
        case images
        case tags
    }
}

struct NHentaiTitle: Decodable {
    let english: String?
    let japanese: String?
    let pretty: String?
}

struct NHentaiImages: Decodable {
    let pages: [NHentaiImage]
}

struct NHentaiImage: Decodable {
    let t: String
    let w: Int?
    let h: Int?
}

struct NHentaiTag: Decodable {
    let type: String?
    let name: String?
}

final class NHentaiResolver {
    func canResolve(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "nhentai.net" || host == "nhentai.test"
    }

    func resolve(_ url: URL, headers: HTTPRequestOptions = HTTPRequestOptions()) async throws -> ResolvedDownload {
        let id = try galleryID(from: url)
        guard let galleryURL = Self.canonicalGalleryURL(for: id, sourceURL: url),
              let firstPageURL = Self.galleryPageURL(for: id, page: 1, sourceURL: url) else {
            throw NativeDownloadError.invalidURL(url.absoluteString)
        }
        let referer = headers.referer ?? galleryURL.absoluteString
        var imageCDNBaseURL: URL?

        do {
            let html = try await HTTPClient.shared.string(
                from: firstPageURL,
                referer: referer,
                userAgent: headers.userAgent
            )
            imageCDNBaseURL = Self.imageCDNBaseURL(fromHTML: html, sourceURL: galleryURL)
            if let data = Self.embeddedGalleryData(fromHTML: html) {
                return try Self.resolvedDownload(
                    from: data,
                    sourceURL: galleryURL,
                    userAgent: headers.userAgent,
                    imageCDNBaseURL: imageCDNBaseURL
                )
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // The legacy extractor's HTML path is primary; the API remains a compatibility fallback.
        }

        let data = try await HTTPClient.shared.data(
            from: try apiURL(for: url),
            referer: referer,
            userAgent: headers.userAgent
        )
        return try Self.resolvedDownload(
            from: data,
            sourceURL: galleryURL,
            userAgent: headers.userAgent,
            imageCDNBaseURL: imageCDNBaseURL
        )
    }

    func apiURL(for url: URL) throws -> URL {
        let id = try galleryID(from: url)
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw NativeDownloadError.invalidURL(url.absoluteString)
        }
        components.path = "/api/gallery/\(id)"
        components.queryItems = nil
        guard let apiURL = components.url else {
            throw NativeDownloadError.invalidURL(url.absoluteString)
        }
        return apiURL
    }

    static func canonicalGalleryURL(for id: String, sourceURL: URL? = nil) -> URL? {
        let cleaned = id.trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard cleaned.range(of: #"^[0-9]+$"#, options: .regularExpression) != nil else {
            return nil
        }
        let sourceHost = sourceURL?.host?.lowercased()
        let host = sourceHost == "nhentai.test" ? "nhentai.test" : "nhentai.net"
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/g/\(cleaned)/"
        return components.url
    }

    static func canonicalURL(for url: URL) -> URL? {
        guard let host = url.host?.lowercased(),
              host == "nhentai.net" || host == "nhentai.test",
              let id = galleryIDValue(from: url) else {
            return nil
        }
        return canonicalGalleryURL(for: id, sourceURL: url)
    }

    static func galleryPageURL(for id: String, page: Int, sourceURL: URL? = nil) -> URL? {
        guard page > 0,
              let galleryURL = canonicalGalleryURL(for: id, sourceURL: sourceURL),
              var components = URLComponents(url: galleryURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.path = "/g/\(id)/\(page)/"
        return components.url
    }

    static func embeddedGalleryData(fromHTML html: String) -> Data? {
        var searchStart = html.startIndex
        while searchStart < html.endIndex,
              let parseRange = html.range(
                of: "JSON.parse(",
                range: searchStart..<html.endIndex
              ) {
            if let literal = jsonStringLiteral(in: html, startingAt: parseRange.upperBound),
               let literalData = literal.data(using: .utf8),
               let jsonText = try? JSONDecoder().decode(String.self, from: literalData),
               let data = jsonText.data(using: .utf8),
               (try? JSONDecoder().decode(NHentaiGallery.self, from: data)) != nil {
                return data
            }
            searchStart = parseRange.upperBound
        }
        return nil
    }

    static func imageCDNBaseURL(fromHTML html: String, sourceURL: URL) -> URL? {
        guard let regex = try? NSRegularExpression(
            pattern: #"["']?image_cdn_urls["']?\s*:\s*(\[.*?\])"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return nil
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, range: range),
              let capture = Range(match.range(at: 1), in: html),
              let data = String(html[capture]).data(using: .utf8),
              let values = try? JSONSerialization.jsonObject(with: data) as? [Any],
              let raw = values.compactMap({ $0 as? String }).map(\.trimmed).last(where: { !$0.isEmpty }) else {
            return nil
        }

        let candidate: String
        if raw.hasPrefix("//") {
            candidate = "\(sourceURL.scheme ?? "https"):\(raw)"
        } else if raw.contains("://") {
            candidate = raw
        } else {
            candidate = "https://\(raw)"
        }
        guard let url = URL(string: candidate),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil else {
            return nil
        }
        return url
    }

    static func resolvedDownload(
        from data: Data,
        sourceURL: URL,
        userAgent: String? = nil,
        imageCDNBaseURL: URL? = nil
    ) throws -> ResolvedDownload {
        let gallery = try JSONDecoder().decode(NHentaiGallery.self, from: data)
        var assets: [ResolvedAsset] = []
        let imageHost = sourceURL.host?.lowercased() == "nhentai.test"
            ? "i.nhentai.test"
            : "i.nhentai.net"
        let resolvedImageCDNBaseURL = imageCDNBaseURL ?? URL(string: "https://\(imageHost)")!
        let metadata = metadata(
            for: gallery,
            sourceURL: sourceURL,
            imageCDNBaseURL: resolvedImageCDNBaseURL
        )
        let galleryID = gallery.id.map(String.init) ?? Self.galleryIDValue(from: sourceURL)

        for (offset, image) in gallery.images.pages.enumerated() {
            let ext = extensionForImageType(image.t)
            let index = offset + 1
            guard var components = URLComponents(url: resolvedImageCDNBaseURL, resolvingAgainstBaseURL: false) else {
                continue
            }
            components.path = "/galleries/\(gallery.mediaID)/\(index).\(ext)"
            components.query = nil
            components.fragment = nil
            guard let remote = components.url else { continue }
            let pageURL = galleryID.flatMap {
                galleryPageURL(for: $0, page: index, sourceURL: sourceURL)
            } ?? sourceURL
            assets.append(ResolvedAsset(
                remoteURL: remote,
                filename: String(format: "%04d.%@", index, ext),
                metadata: assetMetadata(
                    for: image,
                    remote: remote,
                    index: index,
                    galleryMetadata: metadata,
                    pageURL: pageURL
                ),
                referer: pageURL.absoluteString,
                userAgent: userAgent
            ))
        }

        guard !assets.isEmpty else {
            throw NativeDownloadError.noFiles
        }

        let title = (gallery.title?.pretty ?? gallery.title?.english ?? gallery.title?.japanese ?? "nHentai \(gallery.id.map(String.init) ?? gallery.mediaID)")
            .sanitizedFilename(maxLength: 120)
        let id = gallery.id.map(String.init) ?? gallery.mediaID
        return ResolvedDownload(
            title: title,
            folderName: "\(title) (\(id))".sanitizedFilename(maxLength: 120),
            assets: assets,
            metadata: downloadMetadata(from: metadata, imageCount: assets.count)
        )
    }

    private func galleryID(from url: URL) throws -> String {
        if let id = Self.galleryIDValue(from: url) {
            return id
        }
        throw NativeDownloadError.missingGalleryID(url.absoluteString)
    }

    private static func galleryIDValue(from url: URL) -> String? {
        let path = url.path
        let patterns = [
            #"/g/([0-9]+)"#,
            #"/gallery/([0-9]+)"#,
            #"/api/gallery/([0-9]+)"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(path.startIndex..<path.endIndex, in: path)
            guard let match = regex.firstMatch(in: path, range: range),
                  match.numberOfRanges > 1,
                  let capture = Range(match.range(at: 1), in: path) else {
                continue
            }
            return String(path[capture])
        }
        return nil
    }

    private static func jsonStringLiteral(in text: String, startingAt start: String.Index) -> String? {
        var index = start
        while index < text.endIndex, text[index].isWhitespace {
            index = text.index(after: index)
        }
        guard index < text.endIndex, text[index] == "\"" else { return nil }

        let literalStart = index
        var escaped = false
        index = text.index(after: index)
        while index < text.endIndex {
            let character = text[index]
            if escaped {
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "\"" {
                return String(text[literalStart...index])
            }
            index = text.index(after: index)
        }
        return nil
    }

    private static func extensionForImageType(_ type: String) -> String {
        switch type.lowercased() {
        case "j":
            return "jpg"
        case "p":
            return "png"
        case "g":
            return "gif"
        case "w":
            return "webp"
        default:
            return "jpg"
        }
    }

    private static func metadata(for gallery: NHentaiGallery, sourceURL: URL, imageCDNBaseURL: URL) -> [String: String] {
        let grouped = Dictionary(grouping: gallery.tags ?? []) { ($0.type ?? "").lowercased() }
            .mapValues { values in
                values.compactMap { $0.name?.trimmed }.filter { !$0.isEmpty }.joined(separator: ", ")
            }
        let artists = grouped["artist"] ?? grouped["group"] ?? ""
        return DownloadMetadata.clean([
            "artist": artists,
            "author": artists,
            "creator": artists,
            "uploader": artists,
            "channel": artists,
            "language": grouped["language"] ?? "",
            "parody": grouped["parody"] ?? "",
            "category": grouped["category"] ?? "",
            "character": grouped["character"] ?? "",
            "tag": grouped["tag"] ?? "",
            "tags": grouped["tag"] ?? "",
            "media_id": gallery.mediaID,
            "gallery_id": gallery.id.map(String.init) ?? "",
            "id": gallery.id.map(String.init) ?? gallery.mediaID,
            "site": "nHentai",
            "type": "gallery",
            "media_type": "image",
            "image_cdn": imageCDNBaseURL.host ?? "",
            "image_cdn_url": imageCDNBaseURL.absoluteString,
            "source_url": sourceURL.absoluteString,
            "page_url": sourceURL.absoluteString
        ])
    }

    private static func downloadMetadata(from metadata: [String: String], imageCount: Int) -> [String: String] {
        var result = metadata
        result["media_count"] = String(imageCount)
        result["image_count"] = String(imageCount)
        return DownloadMetadata.clean(result)
    }

    private static func assetMetadata(for image: NHentaiImage, remote: URL, index: Int, galleryMetadata: [String: String], pageURL: URL) -> [String: String] {
        let format = extensionForImageType(image.t)
        let galleryMediaID = galleryMetadata["media_id"] ?? ""
        return DownloadMetadata.clean([
            "artist": galleryMetadata["artist"] ?? "",
            "author": galleryMetadata["author"] ?? "",
            "creator": galleryMetadata["creator"] ?? "",
            "uploader": galleryMetadata["uploader"] ?? "",
            "channel": galleryMetadata["channel"] ?? "",
            "language": galleryMetadata["language"] ?? "",
            "parody": galleryMetadata["parody"] ?? "",
            "series": galleryMetadata["parody"] ?? "",
            "category": galleryMetadata["category"] ?? "",
            "character": galleryMetadata["character"] ?? "",
            "tag": galleryMetadata["tag"] ?? "",
            "tags": galleryMetadata["tags"] ?? "",
            "media_id": galleryMediaID.isEmpty ? String(index) : "\(galleryMediaID)-\(index)",
            "gallery_media_id": galleryMediaID,
            "gallery_id": galleryMetadata["gallery_id"] ?? "",
            "id": galleryMetadata["id"] ?? "",
            "image_cdn": galleryMetadata["image_cdn"] ?? "",
            "image_cdn_url": galleryMetadata["image_cdn_url"] ?? "",
            "site": "nHentai",
            "type": "image",
            "media_type": "image",
            "page": String(index),
            "position": String(index),
            "width": image.w.map(String.init) ?? "",
            "height": image.h.map(String.init) ?? "",
            "resolution": (image.w != nil && image.h != nil) ? "\(image.w ?? 0)x\(image.h ?? 0)" : "",
            "format": format,
            "media_format": format,
            "image_url": remote.absoluteString,
            "media_url": remote.absoluteString,
            "source_url": remote.absoluteString,
            "page_url": pageURL.absoluteString
        ])
    }
}
