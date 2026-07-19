import Foundation

final class XVideoPageResolver {
    enum Site: String {
        case xvideos = "XVideos"
        case xnxx = "XNXX"
    }

    func canResolve(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(),
              Self.site(forHost: host) != nil,
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return false
        }
        return Self.videoID(from: url) != nil
    }

    func resolve(_ url: URL, headers: HTTPRequestOptions = HTTPRequestOptions()) async throws -> ResolvedDownload {
        let pageURL = Self.canonicalURL(for: url) ?? url
        guard let routeID = Self.videoID(from: pageURL),
              let host = pageURL.host?.lowercased(),
              let site = Self.site(forHost: host) else {
            throw NativeDownloadError.invalidURL(url.absoluteString)
        }
        let id = Self.originalContentID(from: pageURL, site: site, fallback: routeID)

        let html = try await HTTPClient.shared.string(from: pageURL, referer: headers.referer, userAgent: headers.userAgent)
        guard let videoURL = Self.videoURL(fromHTML: html, pageURL: pageURL) else {
            throw NativeDownloadError.noFiles
        }

        if Self.isM3U8(videoURL) {
            let hls = try await M3U8Resolver().resolve(
                videoURL,
                headers: HTTPRequestOptions(referer: pageURL.absoluteString, userAgent: headers.userAgent)
            )
            let title = Self.title(fromHTML: html, site: site, videoID: id)
            let outputExtension = site == .xnxx ? "mp4" : "ts"
            let outputFilename = "\(title)-\(id).\(outputExtension)".sanitizedFilename(maxLength: 180)
            return ResolvedDownload(
                title: title,
                folderName: "\(site.rawValue) \(title)".sanitizedFilename(maxLength: 120),
                assets: Self.hlsAssetsWithPageMetadata(
                    hls.assets,
                    site: site,
                    videoID: id,
                    title: title,
                    pageURL: pageURL,
                    pageHTML: html
                ),
                packageMode: .concatenate(outputFilename: outputFilename),
                metadata: Self.metadata(site: site, videoID: id, title: title, pageURL: pageURL, videoURL: videoURL, html: html)
                    .merging(hls.metadata) { current, _ in current }
            )
        }

        return Self.resolvedDirectDownload(videoURL: videoURL, pageURL: pageURL, pageHTML: html, videoID: id, site: site)
    }

    static func videoID(from url: URL) -> String? {
        guard let host = url.host?.lowercased(),
              let site = site(forHost: host) else {
            return nil
        }

        let path = url.path.removingPercentEncoding ?? url.path
        let patterns: [String]
        switch site {
        case .xvideos:
            if let id = xvideosSWFVideoID(from: url) {
                return id
            }
            if let id = xvideosProfVideoClickID(from: path) {
                return id
            }
            patterns = [
                #"^/embedframe/([0-9A-Za-z]+)"#,
                #"^/video\.([0-9A-Za-z]+)"#,
                #"^/video/([0-9A-Za-z]+)"#,
                #"^/video([0-9][0-9A-Za-z]*)"#
            ]
        case .xnxx:
            patterns = [
                #"^/video[-_\.]([0-9A-Za-z]+)"#,
                #"^/video([0-9][0-9A-Za-z]*)"#
            ]
        }

        for pattern in patterns {
            guard let id = firstCapture(pattern: pattern, in: path),
                  id.range(of: #"^[0-9A-Za-z]+$"#, options: .regularExpression) != nil else {
                continue
            }
            return id
        }
        return nil
    }

    static func canonicalURL(for url: URL) -> URL? {
        guard let host = url.host?.lowercased(),
              let site = site(forHost: host),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              videoID(from: url) != nil else {
            return nil
        }

        var path = url.path.removingPercentEncoding ?? url.path
        if site == .xvideos {
            if let swfID = xvideosSWFVideoID(from: url) {
                path = xvideosCanonicalVideoPath(for: swfID)
            } else if let embedID = firstCapture(pattern: #"^/embedframe/([0-9A-Za-z]+)"#, in: path) {
                path = xvideosCanonicalVideoPath(for: embedID)
            } else if let profClickPath = xvideosProfVideoClickCanonicalPath(from: path) {
                path = profClickPath
            } else {
                path = path.replacingOccurrences(of: "/THUMBNUM/", with: "/", options: .caseInsensitive)
            }
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = canonicalHost(for: site, sourceHost: host)
        components.path = path
        return components.url
    }

    static func videoURL(fromHTML html: String, pageURL: URL) -> URL? {
        let decoded = normalizeEscapes(decodeHTML(html))
        let prefersOriginalXNXXHLS = pageURL.host
            .flatMap { site(forHost: $0.lowercased()) } == .xnxx
        let hlsPriority = prefersOriginalXNXXHLS ? 70_000_000 : 30_000_000
        let patterns: [(pattern: String, baseScore: Int)] = [
            (#"setVideoUrlHD\(\s*['"]([^'"]+)['"]\s*\)"#, 60_000_000),
            (#"setVideoUrlHigh\(\s*['"]([^'"]+)['"]\s*\)"#, 50_000_000),
            (#"setVideoUrl\(\s*['"]([^'"]+)['"]\s*\)"#, 40_000_000),
            (#"setVideoUrlHLS\(\s*['"]([^'"]+)['"]\s*\)"#, hlsPriority),
            (#"setVideoHLS\(\s*['"]([^'"]+)['"]\s*\)"#, hlsPriority),
            (#"setVideoUrlLow\(\s*['"]([^'"]+)['"]\s*\)"#, 10_000_000),
            (#"setVideo(?:[^(]+)\(\s*['"]([^'"]+\.(?:m3u8|mp4|webm|m4v|mov)[^'"]*)['"]\s*\)"#, 25_000_000),
            (#"\bflv_url=([^&"'<>]+)"#, 24_000_000),
            (#""(?:contentUrl|videoUrl|video_url|file)"\s*:\s*"([^"]+\.(?:m3u8|mp4|webm|m4v|mov)[^"]*)""#, 35_000_000),
            (#"<source\b[^>]*\bsrc\s*=\s*["']([^"']+)["']"#, 20_000_000)
        ]

        var candidates: [(url: URL, score: Int)] = []
        for pattern in patterns {
            for raw in captureMatches(pattern: pattern.pattern, in: decoded, group: 1) {
                guard let url = absoluteURL(raw, baseURL: pageURL),
                      isPlayableVideo(url) else {
                    continue
                }
                candidates.append((url, pattern.baseScore + scoreVideoURL(url)))
            }
        }
        return candidates.max { $0.score < $1.score }?.url
    }

    static func originalContentID(from url: URL, site: Site, fallback: String) -> String {
        guard site == .xnxx else { return fallback }
        let path = url.path.removingPercentEncoding ?? url.path
        guard let first = path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
            .first,
              first.range(of: #"^video[-_\.]?[0-9A-Za-z]+$"#, options: .regularExpression) != nil else {
            return fallback
        }
        return first
    }

    static func resolvedDirectDownload(videoURL: URL, pageURL: URL, pageHTML: String, videoID: String, site: Site) -> ResolvedDownload {
        let title = title(fromHTML: pageHTML, site: site, videoID: videoID)
        let filename = filename(for: videoURL, title: title, videoID: videoID)
        let pageMetadata = metadata(site: site, videoID: videoID, title: title, pageURL: pageURL, videoURL: videoURL, html: pageHTML)
        return ResolvedDownload(
            title: title,
            folderName: "\(site.rawValue) \(title)".sanitizedFilename(maxLength: 120),
            assets: [
                ResolvedAsset(
                    remoteURL: videoURL,
                    filename: filename,
                    metadata: mediaMetadata(for: videoURL, pageMetadata: pageMetadata, pageURL: pageURL, index: 1),
                    referer: pageURL.absoluteString
                )
            ],
            packageMode: .concatenate(outputFilename: filename),
            metadata: pageMetadata
        )
    }

    static func hlsAssetsWithPageMetadata(_ assets: [ResolvedAsset], site: Site, videoID: String, title: String, pageURL: URL, pageHTML: String) -> [ResolvedAsset] {
        let uploader = uploaderName(fromHTML: pageHTML)
        let thumbnail = thumbnailURL(fromHTML: pageHTML, pageURL: pageURL)
        return assets.enumerated().map { offset, asset in
            var enriched = asset
            enriched.metadata = asset.metadata.merging(Self.segmentMetadata(
                site: site,
                videoID: videoID,
                title: title,
                pageURL: pageURL,
                asset: asset,
                index: offset + 1,
                uploader: uploader,
                thumbnail: thumbnail
            )) { _, new in new }
            return enriched
        }
    }

    static func title(fromHTML html: String, site: Site, videoID: String) -> String {
        let fallback = "\(site.rawValue) \(videoID)"
        let raw = metaContent(from: html, names: ["og:title", "twitter:title"]) ??
            elementText(pattern: #"<title\b[^>]*>(.*?)</title>"#, in: html) ??
            fallback
        return cleanTitle(raw, site: site, fallback: fallback)
    }

    private static func metadata(site: Site, videoID: String, title: String, pageURL: URL, videoURL: URL, html: String) -> [String: String] {
        let uploader = uploaderName(fromHTML: html)
        return DownloadMetadata.clean([
            "site": site.rawValue,
            "title": title,
            "series": title,
            "category": "video",
            "type": isM3U8(videoURL) ? "hls" : "video",
            "format": isM3U8(videoURL) ? "m3u8" : videoURL.pathExtension.lowercased(),
            "hls_remux_required": site == .xnxx && isM3U8(videoURL) ? "true" : "",
            "media_format": mediaFormat(for: videoURL),
            "height": videoHeight(from: videoURL) ?? "",
            "resolution": videoResolution(from: videoURL) ?? "",
            "quality": videoResolution(from: videoURL) ?? "",
            "artist": uploader ?? "",
            "author": uploader ?? "",
            "creator": uploader ?? "",
            "uploader": uploader ?? "",
            "username": uploader ?? "",
            "host": pageURL.host ?? "",
            "id": videoID,
            "video_id": videoID,
            "media_id": videoID,
            "gallery_id": videoID,
            "media_count": "1",
            "video_count": "1",
            "video_url": videoURL.absoluteString,
            "media_url": videoURL.absoluteString,
            "thumbnail": thumbnailURL(fromHTML: html, pageURL: pageURL)?.absoluteString ?? "",
            "url": pageURL.absoluteString,
            "source_url": pageURL.absoluteString,
            "page_url": pageURL.absoluteString
        ])
    }

    private static func mediaMetadata(for videoURL: URL, pageMetadata: [String: String], pageURL: URL, index: Int) -> [String: String] {
        DownloadMetadata.clean([
            "site": pageMetadata["site"] ?? "",
            "title": pageMetadata["title"] ?? "",
            "series": pageMetadata["series"] ?? "",
            "category": "video",
            "artist": pageMetadata["artist"] ?? "",
            "author": pageMetadata["author"] ?? "",
            "creator": pageMetadata["creator"] ?? "",
            "uploader": pageMetadata["uploader"] ?? "",
            "username": pageMetadata["username"] ?? "",
            "id": pageMetadata["id"] ?? "",
            "video_id": pageMetadata["video_id"] ?? "",
            "media_id": pageMetadata["media_id"] ?? "",
            "gallery_id": pageMetadata["gallery_id"] ?? "",
            "page": String(index),
            "position": String(index),
            "format": mediaFormat(for: videoURL),
            "media_format": mediaFormat(for: videoURL),
            "height": videoHeight(from: videoURL) ?? "",
            "resolution": videoResolution(from: videoURL) ?? "",
            "quality": videoResolution(from: videoURL) ?? "",
            "type": isM3U8(videoURL) ? "hls" : "video",
            "media_type": isM3U8(videoURL) ? "hls" : "video",
            "video_url": videoURL.absoluteString,
            "media_url": videoURL.absoluteString,
            "source_url": videoURL.absoluteString,
            "page_url": pageURL.absoluteString
        ])
    }

    private static func segmentMetadata(site: Site, videoID: String, title: String, pageURL: URL, asset: ResolvedAsset, index: Int, uploader: String?, thumbnail: URL?) -> [String: String] {
        let type = asset.metadata["type"] ?? "hls_segment"
        let format = mediaFormat(for: asset.remoteURL, fallback: mediaFormat(forFilename: asset.filename, fallback: "ts"))
        return DownloadMetadata.clean([
            "site": site.rawValue,
            "title": title,
            "series": title,
            "category": "video",
            "type": type,
            "media_type": type == "hls_segment" ? "segment" : type,
            "format": format,
            "media_format": format,
            "artist": uploader ?? "",
            "author": uploader ?? "",
            "creator": uploader ?? "",
            "uploader": uploader ?? "",
            "username": uploader ?? "",
            "id": videoID,
            "video_id": videoID,
            "media_id": "\(videoID)-segment-\(index)",
            "gallery_id": videoID,
            "page": String(index),
            "position": String(index),
            "thumbnail": thumbnail?.absoluteString ?? "",
            "playlist_url": asset.metadata["playlist_url"] ?? "",
            "video_url": asset.remoteURL.absoluteString,
            "media_url": asset.remoteURL.absoluteString,
            "source_url": pageURL.absoluteString,
            "page_url": pageURL.absoluteString
        ])
    }

    private static func filename(for url: URL, title: String, videoID: String) -> String {
        let ext = url.pathExtension.trimmed.isEmpty ? "mp4" : url.pathExtension
        return "\(title)-\(videoID).\(ext)".sanitizedFilename(maxLength: 180)
    }

    private static func thumbnailURL(fromHTML html: String, pageURL: URL) -> URL? {
        let normalized = normalizeEscapes(decodeHTML(html))
        let raw = metaContent(from: normalized, names: ["og:image", "twitter:image"]) ??
            firstCapture(pattern: #"setThumbUrl(?:169)?\(\s*["']([^"']+)["']"#, in: normalized)
        guard let raw else { return nil }
        return absoluteURL(raw, baseURL: pageURL)
    }

    private static func uploaderName(fromHTML html: String) -> String? {
        let normalized = normalizeEscapes(decodeHTML(html))
        let metadata = metaContent(from: normalized, names: [
            "author",
            "article:author",
            "twitter:creator",
            "video:actor",
            "og:video:actor"
        ])
        if let metadata {
            return cleanMetadataValue(metadata)
        }

        let patterns = [
            #""(?:uploader|author|creator|userName|username|profileName)"\s*:\s*"([^"]+)""#,
            #"'(?:uploader|author|creator|userName|username|profileName)'\s*:\s*'([^']+)'"#,
            #"\bdata-(?:uploader|author|creator|username)\s*=\s*["']([^"']+)["']"#,
            #"<(?:a|span)\b[^>]*(?:class|id)\s*=\s*["'][^"']*(?:uploader|user-name|username|profile-name|name)[^"']*["'][^>]*>(.*?)</(?:a|span)>"#
        ]
        for pattern in patterns {
            if let value = firstCapture(pattern: pattern, in: normalized),
               let cleaned = cleanMetadataValue(value) {
                return cleaned
            }
        }
        return nil
    }

    private static func cleanMetadataValue(_ raw: String) -> String? {
        let value = decodeHTML(stripTags(raw))
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmed
        return value.isEmpty ? nil : value.sanitizedFilename(maxLength: 100)
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
        let text = cleanTitle(stripTags(raw), site: .xvideos, fallback: "")
        return text.isEmpty ? nil : text
    }

    private static func firstCapture(pattern: String, in text: String) -> String? {
        capture(pattern: pattern, in: text, group: 1)
    }

    private static func capture(pattern: String, in text: String, group: Int) -> String? {
        captureMatches(pattern: pattern, in: text, group: group).first
    }

    private static func captureMatches(pattern: String, in text: String, group: Int) -> [String] {
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

    private static func absoluteURL(_ raw: String, baseURL: URL) -> URL? {
        var value = normalizeEscapes(decodeHTML(raw)).trimmed
        if !value.contains("://"),
           let decoded = value.removingPercentEncoding,
           decoded.contains("://") {
            value = normalizeEscapes(decoded).trimmed
        }
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

    private static func normalizeEscapes(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: #"\/"#, with: "/")
            .replacingOccurrences(of: #"\\/"#, with: "/")
            .replacingOccurrences(of: #"\u002F"#, with: "/")
            .replacingOccurrences(of: #"\u002f"#, with: "/")
    }

    private static func isPlayableVideo(_ url: URL) -> Bool {
        ["m3u8", "mp4", "webm", "mov", "m4v"].contains(url.pathExtension.lowercased()) ||
            url.absoluteString.lowercased().contains(".m3u8")
    }

    private static func scoreVideoURL(_ url: URL) -> Int {
        let lower = url.absoluteString.lowercased()
        let ext = url.pathExtension.lowercased()
        var score = ext == "mp4" || ext == "m4v" || ext == "mov" ? 1_000_000 : ext == "m3u8" ? 500_000 : 250_000
        for (marker, value) in [("2160", 2160), ("1440", 1440), ("1080", 1080), ("720", 720), ("480", 480), ("360", 360)] {
            if lower.contains(marker) {
                score += value
                break
            }
        }
        return score
    }

    private static func isM3U8(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "m3u8" || url.absoluteString.lowercased().contains(".m3u8")
    }

    private static func mediaFormat(for url: URL) -> String {
        if isM3U8(url) { return "m3u8" }
        let ext = url.pathExtension.lowercased()
        return ext.isEmpty ? "mp4" : ext
    }

    private static func mediaFormat(for url: URL, fallback: String) -> String {
        let ext = url.pathExtension.lowercased()
        return ext.isEmpty ? fallback : ext
    }

    private static func mediaFormat(forFilename filename: String, fallback: String) -> String {
        let ext = (filename as NSString).pathExtension.lowercased()
        return ext.isEmpty ? fallback : ext
    }

    private static func videoHeight(from url: URL) -> String? {
        let source = url.absoluteString.lowercased()
        let patterns = [
            #"(?<![0-9])([1-9][0-9]{2,3})p(?![0-9])"#,
            #"(?<![0-9])([1-9][0-9]{2,3})[xX][1-9][0-9]{2,4}(?![0-9])"#,
            #"(?<![0-9])[1-9][0-9]{2,4}[xX]([1-9][0-9]{2,3})(?![0-9])"#,
            #"(?:height|res|resolution|quality)[=_-]([1-9][0-9]{2,3})(?:p)?(?:&|$)"#
        ]
        for pattern in patterns {
            guard let value = firstCapture(pattern: pattern, in: source),
                  let number = Int(value),
                  number >= 144,
                  number <= 4320 else {
                continue
            }
            return String(number)
        }
        return nil
    }

    private static func videoResolution(from url: URL) -> String? {
        videoHeight(from: url).map { "\($0)p" }
    }

    private static func site(forHost host: String) -> Site? {
        if host == "xvideos.test" || host == "www.xvideos.test" {
            return .xvideos
        }
        if host == "xnxx.test" || host == "www.xnxx.test" {
            return .xnxx
        }
        guard let labels = hostLabels(host), labels.count >= 2 else { return nil }
        let base = labels[labels.count - 2]
        let topLevelDomain = labels[labels.count - 1]
        if ["com", "in", "es"].contains(topLevelDomain),
           base.range(of: #"^xvideos[0-9]*$"#, options: .regularExpression) != nil {
            return .xvideos
        }
        if ["com", "es"].contains(topLevelDomain),
           base.range(of: #"^xnxx[0-9]*$"#, options: .regularExpression) != nil {
            return .xnxx
        }
        return nil
    }

    private static func canonicalHost(for site: Site, sourceHost: String) -> String {
        switch site {
        case .xvideos:
            return sourceHost.hasSuffix(".test") ? "www.xvideos.test" : "www.xvideos.com"
        case .xnxx:
            return sourceHost.hasSuffix(".test") ? "xnxx.test" : "xnxx.com"
        }
    }

    private static func hostLabels(_ host: String) -> [String]? {
        let labels = host
            .lowercased()
            .split(separator: ".")
            .map(String.init)
            .filter { !$0.isEmpty }
        return labels.count >= 2 ? labels : nil
    }

    private static func stripTags(_ raw: String) -> String {
        raw.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
    }

    private static func xvideosProfVideoClickID(from path: String) -> String? {
        guard let marker = path.range(of: "/prof-video-click/", options: .caseInsensitive) else {
            return nil
        }
        let tail = String(path[marker.upperBound...])
        let parts = tail.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 3 else { return nil }
        let id = parts[2]
        guard id.range(of: #"^[0-9A-Za-z]+$"#, options: .regularExpression) != nil else {
            return nil
        }
        return id
    }

    private static func xvideosSWFVideoID(from url: URL) -> String? {
        guard url.path.lowercased().hasSuffix("/swf/xv-player.swf") ||
            url.path.lowercased().contains("/xv-player.swf") else {
            return nil
        }
        guard let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name.lowercased() == "id_video" })?
            .value?
            .trimmed,
              id.range(of: #"^[0-9A-Za-z]+$"#, options: .regularExpression) != nil else {
            return nil
        }
        return id
    }

    private static func xvideosCanonicalVideoPath(for id: String) -> String {
        if id.first?.isNumber == true {
            return "/video\(id)"
        }
        return "/video.\(id)"
    }

    private static func xvideosProfVideoClickCanonicalPath(from path: String) -> String? {
        guard let marker = path.range(of: "/prof-video-click/", options: .caseInsensitive) else {
            return nil
        }
        let tail = String(path[marker.upperBound...])
        let parts = tail.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 3 else { return nil }
        let id = parts[2]
        guard id.range(of: #"^[0-9A-Za-z]+$"#, options: .regularExpression) != nil else {
            return nil
        }
        let suffix = parts.dropFirst(3).joined(separator: "/")
        return suffix.isEmpty ? "/video\(id)" : "/video\(id)/\(suffix)"
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

    private static func cleanTitle(_ raw: String, site: Site, fallback: String) -> String {
        var text = decodeHTML(stripTags(raw))
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmed
        let suffixes: [String]
        switch site {
        case .xvideos:
            suffixes = [" - XVIDEOS.COM", " | XVIDEOS.COM", " - XVIDEOS", " | XVIDEOS"]
        case .xnxx:
            suffixes = [" - XNXX.COM", " | XNXX.COM", " - XNXX", " | XNXX"]
        }
        for suffix in suffixes {
            if text.lowercased().hasSuffix(suffix.lowercased()) {
                text = String(text.dropLast(suffix.count)).trimmed
            }
        }
        return text.isEmpty ? fallback : text.sanitizedFilename(maxLength: 120)
    }
}
