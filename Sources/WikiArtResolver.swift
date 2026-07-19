import Foundation

struct WikiArtAPIRequest {
    var url: URL
    var artistSlug: String
    var page: Int
}

final class WikiArtResolver {
    private let maxAPIPages = 99

    func canResolve(_ url: URL) -> Bool {
        artistSlug(from: url) != nil
    }

    func resolve(_ url: URL, headers: HTTPRequestOptions = HTTPRequestOptions()) async throws -> ResolvedDownload {
        let firstRequest = try apiRequest(for: url, page: 1)
        let artistURL = Self.canonicalArtistURL(for: firstRequest.artistSlug, sourceURL: url) ?? url
        let artistHTML = try await HTTPClient.shared.string(
            from: artistURL,
            referer: headers.referer,
            userAgent: headers.userAgent
        )
        let originalArtistName = Self.artistName(fromHTML: artistHTML)
        var pages: [[String: Any]] = []
        var seenPaintingIDs = Set<String>()
        var expectedTotal: Int?

        for page in 1...maxAPIPages {
            try Task.checkCancellation()
            let request = try apiRequest(for: url, page: page)
            let data = try await HTTPClient.shared.data(
                from: request.url,
                referer: headers.referer ?? artistURL.absoluteString,
                userAgent: headers.userAgent
            )
            let object = try Self.pageObject(from: data)
            let paintings = Self.paintings(from: object)
            guard !paintings.isEmpty else { break }
            pages.append(object)
            expectedTotal = Self.totalPaintings(from: object)
            for painting in paintings {
                let identity = Self.artworkID(
                    from: painting,
                    referer: Self.stringValue(painting["paintingUrl"]),
                    fallback: Self.stringValue(painting["image"]) ?? ""
                )
                seenPaintingIDs.insert(identity)
            }
            if let expectedTotal, seenPaintingIDs.count == expectedTotal {
                break
            }
        }

        var resolved = try Self.resolvedDownload(
            fromPages: pages,
            artistSlug: firstRequest.artistSlug,
            sourceURL: url,
            artistName: originalArtistName
        )
        resolved.metadata["collection_page_count"] = String(pages.count)
        resolved.metadata["listed_painting_count"] = String(seenPaintingIDs.count)
        if let expectedTotal {
            resolved.metadata["expected_painting_count"] = String(expectedTotal)
        }
        return resolved
    }

    func apiRequest(for url: URL, page: Int = 1) throws -> WikiArtAPIRequest {
        guard let artistSlug = artistSlug(from: url),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw NativeDownloadError.invalidURL(url.absoluteString)
        }

        components.host = apiHost(for: url.host)
        components.path = "/en/\(artistSlug)/mode/all-paintings"
        components.queryItems = [
            URLQueryItem(name: "json", value: "2"),
            URLQueryItem(name: "layout", value: "new"),
            URLQueryItem(name: "page", value: String(max(1, page))),
            URLQueryItem(name: "resultType", value: "masonry")
        ]

        guard let apiURL = components.url else {
            throw NativeDownloadError.invalidURL(url.absoluteString)
        }
        return WikiArtAPIRequest(url: apiURL, artistSlug: artistSlug, page: max(1, page))
    }

    static func canonicalArtistURL(for slug: String, sourceURL: URL? = nil) -> URL? {
        let cleaned = slug.trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard !cleaned.isEmpty,
              cleaned.range(of: #"^[A-Za-z0-9-]+$"#, options: .regularExpression) != nil else {
            return nil
        }
        var components = URLComponents()
        components.scheme = sourceURL?.scheme ?? "https"
        let host = sourceURL?.host?.lowercased() ?? ""
        components.host = host == "wikiart.test" || host.hasSuffix(".wikiart.test") ? "wikiart.test" : "www.wikiart.org"
        components.path = "/en/\(cleaned)"
        return components.url
    }

    static func resolvedDownload(from data: Data, artistSlug: String, sourceURL: URL) throws -> ResolvedDownload {
        let page = try pageObject(from: data)
        return try resolvedDownload(fromPages: [page], artistSlug: artistSlug, sourceURL: sourceURL)
    }

    static func resolvedDownload(
        fromPages pages: [[String: Any]],
        artistSlug: String,
        sourceURL: URL,
        artistName originalArtistName: String? = nil
    ) throws -> ResolvedDownload {
        var assets: [ResolvedAsset] = []
        var seen = Set<String>()
        var artistName: String?

        for painting in pages.flatMap(paintings(from:)) {
            if artistName == nil {
                artistName = stringValue(painting["artistName"]) ?? stringValue(painting["artist"])
            }

            guard let rawImage = stringValue(painting["image"]),
                  let remote = absoluteURL(rawImage, baseURL: sourceURL) else {
                continue
            }

            let normalized = URLIdentity.normalize(remote.absoluteString)
            let identity = artworkID(from: painting, referer: stringValue(painting["paintingUrl"]), fallback: normalized)
            guard !seen.contains(identity) else { continue }
            seen.insert(identity)

            let filename = outputFilename(for: painting, remoteURL: remote, index: assets.count + 1)
            let referer = stringValue(painting["paintingUrl"]).flatMap { absoluteURL($0, baseURL: sourceURL)?.absoluteString } ?? sourceURL.absoluteString
            assets.append(ResolvedAsset(
                remoteURL: remote,
                filename: filename,
                metadata: assetMetadata(
                    for: painting,
                    artistSlug: artistSlug,
                    remoteURL: remote,
                    referer: referer,
                    index: assets.count + 1
                ),
                referer: referer
            ))
        }

        guard !assets.isEmpty else {
            throw NativeDownloadError.noFiles
        }

        let title = (originalArtistName ?? artistName ?? artistSlug.replacingOccurrences(of: "-", with: " "))
            .sanitizedFilename(maxLength: 120)
        let artistURL = canonicalArtistURL(for: artistSlug, sourceURL: sourceURL) ?? sourceURL
        return ResolvedDownload(
            title: title,
            folderName: title,
            assets: assets,
            metadata: artistMetadata(
                artistName: title,
                artistSlug: artistSlug,
                sourceURL: sourceURL,
                artistURL: artistURL,
                imageCount: assets.count
            )
        )
    }

    static func pageObject(from data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NativeDownloadError.invalidGalleryData
        }
        return object
    }

    static func paintings(from page: [String: Any]) -> [[String: Any]] {
        if let paintings = page["Paintings"] as? [[String: Any]] {
            return paintings
        }
        if let paintings = page["paintings"] as? [[String: Any]] {
            return paintings
        }
        if let data = page["data"] as? [[String: Any]] {
            return data
        }
        return []
    }

    static func artistName(fromHTML html: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: #"<h3\b[^>]*>(.*?)</h3>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return nil
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, range: range),
              let capture = Range(match.range(at: 1), in: html) else {
            return nil
        }
        let value = String(html[capture])
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmed
        return value.isEmpty ? nil : value
    }

    private func artistSlug(from url: URL) -> String? {
        guard let host = url.host?.lowercased(),
              Self.isWikiArtHost(host),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }

        let parts = url.path.split(separator: "/").map(String.init)
        guard parts.count >= 2, parts[0].lowercased() == "en" else {
            return nil
        }

        let isArtistPage = parts.count == 2
        let isAllPaintingsPage = parts.count >= 4 &&
            parts[2].lowercased() == "mode" &&
            parts[3].lowercased() == "all-paintings"
        guard isArtistPage || isAllPaintingsPage else {
            return nil
        }

        let artist = parts[1].trimmed
        guard !artist.isEmpty,
              !["paintings-by-style", "artists-by-art-movement", "app", "search"].contains(artist.lowercased()) else {
            return nil
        }
        return artist
    }

    private func apiHost(for host: String?) -> String {
        if let host = host?.lowercased(),
           host == "wikiart.test" || host.hasSuffix(".wikiart.test") {
            return "wikiart.test"
        }
        return "www.wikiart.org"
    }

    private static func isWikiArtHost(_ host: String) -> Bool {
        host == "wikiart.org" ||
            host.hasSuffix(".wikiart.org") ||
            host == "wikiart.test" ||
            host.hasSuffix(".wikiart.test")
    }

    private static func totalPaintings(from page: [String: Any]) -> Int {
        intValue(page["AllPaintingsCount"]) ?? intValue(page["allPaintingsCount"]) ?? paintings(from: page).count
    }

    private static func outputFilename(for painting: [String: Any], remoteURL: URL, index: Int) -> String {
        let title = stringValue(painting["title"]) ?? stringValue(painting["name"]) ?? remoteURL.deletingPathExtension().lastPathComponent
        let ext = remoteURL.pathExtension.trimmed.isEmpty ? "jpg" : remoteURL.pathExtension
        let id = artworkID(from: painting, referer: stringValue(painting["paintingUrl"]), fallback: String(index))
        return "\(id) - \(title).\(ext)".sanitizedFilename(maxLength: 180)
    }

    private static func assetMetadata(for painting: [String: Any], artistSlug: String, remoteURL: URL, referer: String, index: Int) -> [String: String] {
        let artist = stringValue(painting["artistName"]) ?? stringValue(painting["artist"]) ?? artistSlug.replacingOccurrences(of: "-", with: " ")
        let title = stringValue(painting["title"]) ?? stringValue(painting["name"]) ?? remoteURL.deletingPathExtension().lastPathComponent
        let year = stringValue(painting["completitionYear"]) ?? stringValue(painting["completionYear"]) ?? stringValue(painting["year"]) ?? ""
        let artworkID = artworkID(from: painting, referer: referer, fallback: String(index))
        let format = mediaFormat(for: remoteURL)
        return DownloadMetadata.clean([
            "site": "WikiArt",
            "series": artist,
            "category": "art",
            "artist": artist,
            "author": artist,
            "creator": artist,
            "uploader": artist,
            "channel": artist,
            "user": artistSlug,
            "username": artistSlug,
            "artwork_id": artworkID,
            "media_id": artworkID,
            "gallery_id": artistSlug,
            "id": artworkID,
            "title": title,
            "artwork_title": title,
            "date": year,
            "year": year,
            "type": "image",
            "media_type": "image",
            "page": String(index),
            "position": String(index),
            "format": format,
            "media_format": format,
            "image_url": remoteURL.absoluteString,
            "media_url": remoteURL.absoluteString,
            "source_url": remoteURL.absoluteString,
            "page_url": referer
        ])
    }

    private static func artistMetadata(artistName: String, artistSlug: String, sourceURL: URL, artistURL: URL, imageCount: Int) -> [String: String] {
        DownloadMetadata.clean([
            "site": "WikiArt",
            "artist": artistName,
            "author": artistName,
            "creator": artistName,
            "uploader": artistName,
            "channel": artistName,
            "series": artistName,
            "user": artistSlug,
            "username": artistSlug,
            "artist_slug": artistSlug,
            "slug": artistSlug,
            "id": artistSlug,
            "gallery_id": artistSlug,
            "category": "art",
            "type": "artist",
            "media_type": "image",
            "media_count": String(imageCount),
            "image_count": String(imageCount),
            "url": artistURL.absoluteString,
            "source_url": artistURL.absoluteString,
            "page_url": artistURL.absoluteString,
            "input_url": sourceURL.absoluteString
        ])
    }

    private static func artworkID(from painting: [String: Any], referer: String?, fallback: String) -> String {
        stringValue(painting["id"]) ??
            stringValue(painting["contentId"]) ??
            referer.flatMap { $0.split(separator: "/").last.map(String.init) } ??
            fallback
    }

    private static func mediaFormat(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        if ext == "jpeg" {
            return "jpg"
        }
        return ext.isEmpty ? "jpg" : ext
    }

    private static func absoluteURL(_ raw: String, baseURL: URL) -> URL? {
        let trimmed = raw.trimmed
        if trimmed.hasPrefix("//") {
            return URL(string: "\(baseURL.scheme ?? "https"):\(trimmed)")
        }
        return URL(string: trimmed, relativeTo: baseURL)?.absoluteURL
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        if let int = value as? Int { return String(int) }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) }
        return nil
    }
}
