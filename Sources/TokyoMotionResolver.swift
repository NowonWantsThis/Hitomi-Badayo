import Foundation

final class TokyoMotionResolver {
    enum ContentKind: Equatable {
        case video(id: String)
        case album(id: String)
    }

    private static let productionRoots = ["tokyomotion.net"]
    private static let fixtureRoots = ["tokyomotion.test"]

    func canResolve(_ url: URL) -> Bool {
        Self.canonicalURL(for: url) != nil
    }

    func resolve(
        _ url: URL,
        headers: HTTPRequestOptions = HTTPRequestOptions()
    ) async throws -> ResolvedDownload {
        guard let pageURL = Self.canonicalURL(for: url),
              let kind = Self.contentKind(for: pageURL) else {
            throw NativeDownloadError.invalidURL(url.absoluteString)
        }

        let pageHTML = try await HTTPClient.shared.string(
            from: pageURL,
            referer: headers.referer,
            userAgent: headers.userAgent
        )
        switch kind {
        case .video(let id):
            return try Self.resolvedVideo(
                fromHTML: pageHTML,
                pageURL: pageURL,
                videoID: id,
                userAgent: headers.userAgent
            )
        case .album(let id):
            let slideshowURL = Self.slideshowURL(albumID: id)
            let slideshowHTML = try await HTTPClient.shared.string(
                from: slideshowURL,
                referer: nil,
                userAgent: headers.userAgent
            )
            return try Self.resolvedAlbum(
                fromPageHTML: pageHTML,
                slideshowHTML: slideshowHTML,
                pageURL: pageURL,
                slideshowURL: slideshowURL,
                albumID: id,
                userAgent: headers.userAgent
            )
        }
    }

    static func isSupportedHost(_ rawHost: String) -> Bool {
        let host = rawHost.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return (productionRoots + fixtureRoots).contains { root in
            host == root || host.hasSuffix(".\(root)")
        }
    }

    static func canonicalURL(for url: URL) -> URL? {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host,
              isSupportedHost(host),
              contentKind(for: url) != nil,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.queryItems = nil
        components.fragment = nil
        return components.url
    }

    static func contentKind(for url: URL) -> ContentKind? {
        let parts = url.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        guard !parts.isEmpty else { return nil }

        if parts[0].lowercased() == "album" {
            return albumID(from: url).map(ContentKind.album)
        }
        guard ["video", "videos"].contains(parts[0].lowercased()),
              parts.count >= 2,
              !parts[1].trimmed.isEmpty else {
            return nil
        }
        return .video(id: parts[1])
    }

    static func albumID(from url: URL) -> String? {
        firstCapture(
            pattern: #"album/.*?([0-9]+)"#,
            in: url.absoluteString,
            options: [.caseInsensitive]
        )
    }

    static func slideshowURL(albumID: String) -> URL {
        URL(string: "https://www.tokyomotion.net/album/slideshow/\(albumID)")!
    }

    static func resolvedVideo(
        fromHTML html: String,
        pageURL: URL,
        videoID: String,
        userAgent: String? = nil
    ) throws -> ResolvedDownload {
        guard let video = elementBlock(
            named: "video",
            attribute: "id",
            value: "vjsplayer",
            in: html
        ),
        let sourceTag = allTags(named: "source", in: video.body).first,
        let sourceRaw = attributeValue("src", in: sourceTag),
        let sourceURL = absoluteURL(sourceRaw, baseURL: pageURL),
        let posterRaw = attributeValue("poster", in: video.openingTag),
        let posterURL = absoluteURL(posterRaw, baseURL: pageURL),
        let rawTitle = firstElementText(named: "h3", in: html) else {
            throw NativeDownloadError.unsupported(
                "TokyoMotion video did not contain video#vjsplayer, its first source, poster, and first h3."
            )
        }

        let title = rawTitle.sanitizedFilename(maxLength: 120)
        let filename = "\(title).mp4".sanitizedFilename(maxLength: 180)
        let metadata = DownloadMetadata.clean([
            "site": "TokyoMotion",
            "title": title,
            "series": title,
            "category": "video",
            "type": "video",
            "media_type": "video",
            "format": "mp4",
            "media_format": "mp4",
            "host": pageURL.host ?? "",
            "id": videoID,
            "video_id": videoID,
            "media_id": videoID,
            "gallery_id": videoID,
            "media_count": "1",
            "video_count": "1",
            "thumbnail": posterURL.absoluteString,
            "thumbnail_referer": pageURL.absoluteString,
            "video_url": sourceURL.absoluteString,
            "media_url": sourceURL.absoluteString,
            "url": pageURL.absoluteString,
            "source_url": pageURL.absoluteString,
            "page_url": pageURL.absoluteString
        ])
        var assetMetadata = metadata
        assetMetadata["page"] = "1"
        assetMetadata["position"] = "1"

        return ResolvedDownload(
            title: title,
            folderName: title,
            assets: [
                ResolvedAsset(
                    remoteURL: sourceURL,
                    filename: filename,
                    metadata: assetMetadata,
                    referer: pageURL.absoluteString,
                    userAgent: userAgent
                )
            ],
            packageMode: .concatenate(outputFilename: filename),
            metadata: metadata
        )
    }

    static func resolvedAlbum(
        fromPageHTML pageHTML: String,
        slideshowHTML: String,
        pageURL: URL,
        slideshowURL: URL,
        albumID: String,
        userAgent: String? = nil
    ) throws -> ResolvedDownload {
        guard let rawTitle = firstElementText(named: "title", in: pageHTML) else {
            throw NativeDownloadError.unsupported("TokyoMotion album did not contain a title element.")
        }
        let title = String(rawTitle.components(separatedBy: " Album - ").first ?? rawTitle)
            .trimmed
            .sanitizedFilename(maxLength: 120)
        let imageURLs = albumImageURLs(
            fromHTML: slideshowHTML,
            slideshowURL: slideshowURL,
            albumID: albumID
        )
        guard !imageURLs.isEmpty else {
            throw NativeDownloadError.noFiles
        }

        let assets = imageURLs.enumerated().map { offset, imageURL in
            let index = offset + 1
            let filename = originalBasename(for: imageURL, fallbackIndex: index)
                .sanitizedFilename(maxLength: 180)
            let format = imageURL.pathExtension.lowercased()
            let metadata = DownloadMetadata.clean([
                "site": "TokyoMotion",
                "title": title,
                "series": title,
                "category": "album",
                "type": "image",
                "media_type": "image",
                "format": format,
                "media_format": format,
                "id": albumID,
                "album_id": albumID,
                "gallery_id": albumID,
                "media_id": "\(albumID)-\(index)",
                "page": String(index),
                "position": String(index),
                "total": String(imageURLs.count),
                "image_url": imageURL.absoluteString,
                "media_url": imageURL.absoluteString,
                "source_url": pageURL.absoluteString,
                "page_url": pageURL.absoluteString,
                "slideshow_url": slideshowURL.absoluteString
            ])
            return ResolvedAsset(
                remoteURL: imageURL,
                filename: filename,
                metadata: metadata,
                referer: slideshowURL.absoluteString,
                userAgent: userAgent
            )
        }

        let metadata = DownloadMetadata.clean([
            "site": "TokyoMotion",
            "title": title,
            "series": title,
            "category": "album",
            "type": "image",
            "media_type": "image",
            "format": imageURLs.first?.pathExtension.lowercased() ?? "",
            "media_format": imageURLs.first?.pathExtension.lowercased() ?? "",
            "host": pageURL.host ?? "",
            "id": albumID,
            "album_id": albumID,
            "gallery_id": albumID,
            "media_count": String(imageURLs.count),
            "image_count": String(imageURLs.count),
            "url": pageURL.absoluteString,
            "source_url": pageURL.absoluteString,
            "page_url": pageURL.absoluteString,
            "slideshow_url": slideshowURL.absoluteString
        ])
        return ResolvedDownload(
            title: title,
            folderName: title,
            assets: assets,
            packageMode: .files,
            metadata: metadata
        )
    }

    static func albumImageURLs(
        fromHTML html: String,
        slideshowURL: URL,
        albumID: String
    ) -> [URL] {
        let target = "slideshow-\(albumID)"
        return tagBlocks(named: "a", in: html).compactMap { block in
            guard attributeValue("data-lightbox", in: block.openingTag) == target,
                  let imageTag = allTags(named: "img", in: block.body).first,
                  let source = attributeValue("src", in: imageTag) else {
                return nil
            }
            let originalSource = source.replacingOccurrences(of: "/tmb/", with: "/")
            return absoluteURL(originalSource, baseURL: slideshowURL)
        }
    }

    private static func originalBasename(for url: URL, fallbackIndex: Int) -> String {
        let withoutQuery = url.absoluteString.split(separator: "?", maxSplits: 1).first.map(String.init) ?? ""
        let basename = (withoutQuery as NSString).lastPathComponent
        return basename.trimmed.isEmpty ? String(format: "image-%03d", fallbackIndex) : basename
    }

    private static func firstElementText(named name: String, in html: String) -> String? {
        guard let block = tagBlocks(named: name, in: html).first else { return nil }
        let text = decodeHTML(
            block.body.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        )
        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        .trimmed
        return text.isEmpty ? nil : text
    }

    private static func elementBlock(
        named name: String,
        attribute: String,
        value: String,
        in html: String
    ) -> (openingTag: String, body: String)? {
        tagBlocks(named: name, in: html).first {
            attributeValue(attribute, in: $0.openingTag) == value
        }
    }

    private static func tagBlocks(named name: String, in html: String) -> [(openingTag: String, body: String)] {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        guard let regex = try? NSRegularExpression(
            pattern: #"</?\#(escaped)\b[^>]*>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return []
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        let matches = regex.matches(in: html, range: range)
        var blocks: [(openingTag: String, body: String)] = []

        for (index, match) in matches.enumerated() {
            guard let openingRange = Range(match.range(at: 0), in: html) else { continue }
            let openingTag = String(html[openingRange])
            guard !openingTag.lowercased().hasPrefix("</"),
                  !openingTag.hasSuffix("/>") else {
                continue
            }

            var depth = 1
            for nested in matches.dropFirst(index + 1) {
                guard let nestedRange = Range(nested.range(at: 0), in: html) else { continue }
                let nestedTag = String(html[nestedRange])
                if nestedTag.lowercased().hasPrefix("</") {
                    depth -= 1
                    if depth == 0 {
                        blocks.append((openingTag, String(html[openingRange.upperBound..<nestedRange.lowerBound])))
                        break
                    }
                } else if !nestedTag.hasSuffix("/>") {
                    depth += 1
                }
            }
        }
        return blocks
    }

    private static func allTags(named name: String, in html: String) -> [String] {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        guard let regex = try? NSRegularExpression(
            pattern: #"<\#(escaped)\b[^>]*>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return []
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        return regex.matches(in: html, range: range).compactMap { match in
            Range(match.range(at: 0), in: html).map { String(html[$0]) }
        }
    }

    private static func attributeValue(_ name: String, in tag: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        guard let regex = try? NSRegularExpression(
            pattern: #"(?:^|\s)\#(escaped)\s*=\s*(?:\"([^\"]*)\"|'([^']*)'|([^\s>\"']+))"#,
            options: [.caseInsensitive]
        ) else {
            return nil
        }
        let range = NSRange(tag.startIndex..<tag.endIndex, in: tag)
        guard let match = regex.firstMatch(in: tag, range: range) else { return nil }
        for index in 1..<match.numberOfRanges {
            if let capture = Range(match.range(at: index), in: tag) {
                return decodeHTML(String(tag[capture])).trimmed
            }
        }
        return nil
    }

    private static func absoluteURL(_ raw: String, baseURL: URL) -> URL? {
        var value = decodeHTML(raw).trimmed
        if value.hasPrefix("//") {
            value = "\(baseURL.scheme ?? "https"):\(value)"
        }
        guard let url = URL(string: value, relativeTo: baseURL)?.absoluteURL,
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }
        return url
    }

    private static func firstCapture(
        pattern: String,
        in text: String,
        options: NSRegularExpression.Options
    ) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let capture = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[capture])
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
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        for match in regex.matches(in: text, range: range).reversed() {
            guard let whole = Range(match.range(at: 0), in: text) else { continue }
            let scalarValue: UInt32?
            if let hex = Range(match.range(at: 1), in: text) {
                scalarValue = UInt32(String(text[hex]), radix: 16)
            } else if let decimal = Range(match.range(at: 2), in: text) {
                scalarValue = UInt32(String(text[decimal]), radix: 10)
            } else {
                scalarValue = nil
            }
            if let scalarValue, let scalar = UnicodeScalar(scalarValue) {
                text.replaceSubrange(whole, with: String(Character(scalar)))
            }
        }
        return text
    }
}
