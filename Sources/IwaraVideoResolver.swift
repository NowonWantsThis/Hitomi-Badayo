import CryptoKit
import Foundation

struct IwaraVideoCandidate: Equatable {
    var url: URL
    var quality: Int
    var label: String
}

final class IwaraVideoResolver {
    private static let versionSecret = "5nFp9kmbNnHdAFhaqMvt"

    func canResolve(_ url: URL) -> Bool {
        Self.videoID(from: url) != nil
    }

    func resolve(_ url: URL, headers: HTTPRequestOptions = HTTPRequestOptions()) async throws -> ResolvedDownload {
        guard let videoID = Self.videoID(from: url) else {
            throw NativeDownloadError.invalidURL(url.absoluteString)
        }

        let html = try await HTTPClient.shared.string(from: url, referer: headers.referer, userAgent: headers.userAgent)
        let apiURL = Self.videoAPIURL(for: videoID, sourceURL: url)
        let apiObject = try? await Self.jsonObject(from: apiURL, referer: url.absoluteString, userAgent: headers.userAgent)
        var filesObject: Any?
        if let fileURL = apiObject.flatMap({ Self.fileListURL(from: $0, pageURL: url) }) {
            var apiHeaders = Self.apiHeaders()
            if let xVersion = Self.xVersionHeader(for: fileURL) {
                apiHeaders["X-Version"] = xVersion
            }
            filesObject = try? await Self.jsonObject(from: fileURL, referer: url.absoluteString, userAgent: headers.userAgent, additionalHeaders: apiHeaders)
        }

        return try await Self.resolvedDownload(
            fromPageHTML: html,
            apiObject: apiObject,
            filesObject: filesObject,
            pageURL: url,
            userAgent: headers.userAgent
        )
    }

    static func videoID(from url: URL) -> String? {
        guard let host = url.host?.lowercased(),
              isSupportedHost(host),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }

        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        let lower = parts.map { $0.lowercased() }
        guard let videoIndex = lower.firstIndex(where: { $0 == "video" || $0 == "videos" }),
              videoIndex + 1 < parts.count else {
            return nil
        }
        let id = parts[videoIndex + 1].trimmed
        guard id.range(of: #"^[0-9A-Za-z_-]+$"#, options: .regularExpression) != nil else {
            return nil
        }
        return id
    }

    static func canonicalURL(for videoID: String, sourceURL: URL) -> URL {
        var components = URLComponents()
        components.scheme = sourceURL.scheme ?? "https"
        components.host = sourceURL.host?.lowercased().hasSuffix(".test") == true ? "iwara.test" : "iwara.tv"
        components.path = "/video/\(videoID)"
        return components.url!
    }

    static func canonicalURL(for url: URL) -> URL? {
        guard let videoID = videoID(from: url) else { return nil }
        return canonicalURL(for: videoID, sourceURL: url)
    }

    static func videoAPIURL(for videoID: String, sourceURL: URL) -> URL {
        var components = URLComponents()
        components.scheme = sourceURL.scheme ?? "https"
        components.host = sourceURL.host?.lowercased().hasSuffix(".test") == true ? "api.iwara.test" : "api.iwara.tv"
        components.path = "/video/\(videoID)"
        return components.url!
    }

    static func xVersionHeader(for fileURL: URL) -> String? {
        guard let fileID = fileURL.path.split(separator: "/", omittingEmptySubsequences: true).last.map(String.init),
              let components = URLComponents(url: fileURL, resolvingAgainstBaseURL: false),
              let expires = components.queryItems?.first(where: { $0.name == "expires" })?.value,
              !fileID.isEmpty,
              !expires.isEmpty else {
            return nil
        }
        let payload = "\(fileID)_\(expires)_\(versionSecret)"
        let digest = Insecure.SHA1.hash(data: Data(payload.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func fileListURL(from object: Any, pageURL: URL) -> URL? {
        let base = apiBaseURL(for: pageURL)
        guard let raw = firstStringValue(named: ["fileUrl", "file_url", "filesUrl", "files_url"], in: object) else {
            return nil
        }
        return absoluteURL(raw, baseURL: base)
    }

    static func videoCandidates(from object: Any?, pageURL: URL) -> [IwaraVideoCandidate] {
        guard let object else { return [] }
        var candidates: [IwaraVideoCandidate] = []
        collectCandidates(in: object, pageURL: pageURL, inheritedLabel: "", candidates: &candidates)
        return uniqueCandidates(candidates)
    }

    static func videoCandidates(fromHTML html: String, pageURL: URL) -> [IwaraVideoCandidate] {
        var candidates: [IwaraVideoCandidate] = []
        let scope = videoScope(fromHTML: html)
        for object in scriptJSONObjects(fromHTML: html) {
            collectCandidates(in: object, pageURL: pageURL, inheritedLabel: "", candidates: &candidates)
        }
        for pattern in [
            #""(?:view|download|url|src|file|fileUrl|video_url|videoUrl)"\s*:\s*"([^"]+)""#,
            #"\b(?:src|href)\s*=\s*["']([^"']+)["']"#
        ] {
            for raw in allCaptures(pattern: pattern, in: scope) {
                appendCandidate(rawURL: raw, label: "", pageURL: pageURL, candidates: &candidates)
            }
        }
        return uniqueCandidates(candidates)
    }

    static func resolvedDownload(fromPageHTML html: String, apiObject: Any?, filesObject: Any?, pageURL: URL, userAgent: String?) async throws -> ResolvedDownload {
        try throwForAPIErrorIfNeeded(apiObject)

        var candidates = videoCandidates(from: filesObject, pageURL: pageURL)
        candidates.append(contentsOf: videoCandidates(from: apiObject, pageURL: pageURL))
        candidates.append(contentsOf: videoCandidates(fromHTML: html, pageURL: pageURL))
        candidates = uniqueCandidates(candidates)

        guard let candidate = bestCandidate(candidates) else {
            throw NativeDownloadError.noFiles
        }

        let info = videoInfo(fromHTML: html, apiObject: apiObject, pageURL: pageURL)
        let canonicalPageURL = canonicalURL(for: pageURL) ?? pageURL
        if isM3U8(candidate.url) {
            let hls = try await M3U8Resolver().resolve(
                candidate.url,
                headers: HTTPRequestOptions(referer: pageURL.absoluteString, userAgent: userAgent)
            )
            return ResolvedDownload(
                title: info.displayTitle,
                folderName: "Iwara \(info.folderTitle)".sanitizedFilename(maxLength: 120),
                assets: hlsAssetsWithPageMetadata(
                    hls.assets,
                    info: info,
                    candidate: candidate,
                    pageURL: canonicalPageURL
                ),
                packageMode: .concatenate(outputFilename: "\(info.displayTitle)-\(info.id).ts".sanitizedFilename(maxLength: 180)),
                metadata: metadata(info: info, pageURL: canonicalPageURL, videoURL: candidate.url, candidate: candidate)
                    .merging(hls.metadata) { current, _ in current }
            )
        }

        let ext = candidate.url.pathExtension.trimmed.isEmpty ? "mp4" : candidate.url.pathExtension
        let filename = "\(info.displayTitle)-\(info.id).\(ext)".sanitizedFilename(maxLength: 180)
        return ResolvedDownload(
            title: info.displayTitle,
            folderName: "Iwara \(info.folderTitle)".sanitizedFilename(maxLength: 120),
            assets: [
                ResolvedAsset(
                    remoteURL: candidate.url,
                    filename: filename,
                    metadata: mediaMetadata(for: candidate, info: info, pageURL: canonicalPageURL, index: 1),
                    referer: pageURL.absoluteString
                )
            ],
            packageMode: .concatenate(outputFilename: filename),
            metadata: metadata(info: info, pageURL: canonicalPageURL, videoURL: candidate.url, candidate: candidate)
        )
    }

    static func throwForAPIErrorIfNeeded(_ object: Any?) throws {
        guard let message = stringValue(named: ["message"], in: object), !message.isEmpty else {
            return
        }

        switch message {
        case "errors.privateVideo":
            throw NativeDownloadError.unsupported("Iwara private video. Log in with an account that can view this video, then retry.")
        case "errors.notFound":
            throw NativeDownloadError.unsupported("Iwara video was not found or requires login.")
        default:
            throw NativeDownloadError.unsupported("Iwara API error: \(message)")
        }
    }

    private static func jsonObject(from url: URL, referer: String?, userAgent: String?, additionalHeaders: [String: String] = apiHeaders()) async throws -> Any {
        let data = try await HTTPClient.shared.data(
            from: url,
            referer: referer,
            userAgent: userAgent,
            additionalHeaders: additionalHeaders
        )
        return try JSONSerialization.jsonObject(with: data)
    }

    private static func videoInfo(fromHTML html: String, apiObject: Any?, pageURL: URL) -> (id: String, title: String, uploader: String, displayTitle: String, folderTitle: String, thumbnail: URL?) {
        let fallbackID = videoID(from: pageURL) ?? pageURL.lastPathComponent
        let title = cleanTitle(
            stringValue(named: ["title", "name"], in: apiObject) ??
                elementText(pattern: #"<[^>]*\bclass\s*=\s*["'][^"']*text--h1[^"']*["'][^>]*>(.*?)</[^>]+>"#, in: html) ??
                metaContent(from: html, names: ["og:title", "twitter:title"]) ??
                titleTag(fromHTML: html) ??
                "Iwara \(fallbackID)",
            fallback: "Iwara \(fallbackID)"
        )
        let uploader = cleanTitle(
            userValue(named: ["name", "username"], in: apiObject) ??
                elementText(pattern: #"<[^>]*\bclass\s*=\s*["'][^"']*page-profile__header[^"']*["'][^>]*>(.*?)</[^>]+>"#, in: html) ??
                "",
            fallback: ""
        )
        let thumbnailRaw = stringValue(named: ["thumbnail", "thumbnailUrl", "thumbnail_url", "poster", "posterUrl", "poster_url"], in: apiObject) ??
            metaContent(from: html, names: ["og:image", "twitter:image"]) ??
            firstCapture(pattern: #"url\((?:&quot;|["']?)(.+?)(?:&quot;|["']?)\)"#, in: videoScope(fromHTML: html))
        let displayTitle = [uploader, title].filter { !$0.isEmpty }.joined(separator: " - ")
        return (
            fallbackID,
            title,
            uploader,
            displayTitle.isEmpty ? title : displayTitle,
            displayTitle.isEmpty ? title : displayTitle,
            thumbnailRaw.flatMap { absoluteURL($0, baseURL: pageURL) }
        )
    }

    private static func metadata(info: (id: String, title: String, uploader: String, displayTitle: String, folderTitle: String, thumbnail: URL?), pageURL: URL, videoURL: URL, candidate: IwaraVideoCandidate) -> [String: String] {
        DownloadMetadata.clean([
            "site": "Iwara",
            "title": info.title,
            "series": info.title,
            "category": "video",
            "type": isM3U8(videoURL) ? "hls" : "video",
            "format": mediaFormat(for: candidate.url),
            "media_format": mediaFormat(for: candidate.url),
            "host": pageURL.host ?? "",
            "id": info.id,
            "video_id": info.id,
            "media_id": info.id,
            "gallery_id": info.id,
            "media_count": "1",
            "video_count": "1",
            "height": candidateHeight(for: candidate).map(String.init) ?? "",
            "resolution": resolution(for: candidate),
            "quality": qualityLabel(for: candidate),
            "artist": info.uploader,
            "author": info.uploader,
            "creator": info.uploader,
            "uploader": info.uploader,
            "thumbnail": info.thumbnail?.absoluteString ?? "",
            "video_url": videoURL.absoluteString,
            "media_url": videoURL.absoluteString,
            "url": pageURL.absoluteString,
            "source_url": pageURL.absoluteString,
            "page_url": pageURL.absoluteString
        ])
    }

    private static func mediaMetadata(for candidate: IwaraVideoCandidate, info: (id: String, title: String, uploader: String, displayTitle: String, folderTitle: String, thumbnail: URL?), pageURL: URL, index: Int) -> [String: String] {
        DownloadMetadata.clean([
            "site": "Iwara",
            "title": info.title,
            "series": info.title,
            "category": "video",
            "artist": info.uploader,
            "author": info.uploader,
            "creator": info.uploader,
            "uploader": info.uploader,
            "id": info.id,
            "video_id": info.id,
            "media_id": info.id,
            "gallery_id": info.id,
            "type": isM3U8(candidate.url) ? "hls" : "video",
            "media_type": isM3U8(candidate.url) ? "hls" : "video",
            "page": String(index),
            "position": String(index),
            "format": mediaFormat(for: candidate.url),
            "media_format": mediaFormat(for: candidate.url),
            "height": candidateHeight(for: candidate).map(String.init) ?? "",
            "resolution": resolution(for: candidate),
            "quality": qualityLabel(for: candidate),
            "video_url": candidate.url.absoluteString,
            "media_url": candidate.url.absoluteString,
            "source_url": candidate.url.absoluteString,
            "page_url": pageURL.absoluteString
        ])
    }

    static func hlsAssetsWithPageMetadata(_ assets: [ResolvedAsset], info: (id: String, title: String, uploader: String, displayTitle: String, folderTitle: String, thumbnail: URL?), candidate: IwaraVideoCandidate, pageURL: URL) -> [ResolvedAsset] {
        assets.enumerated().map { offset, asset in
            var enriched = asset
            enriched.metadata = asset.metadata.merging(segmentMetadata(
                info: info,
                candidate: candidate,
                asset: asset,
                pageURL: pageURL,
                index: offset + 1
            )) { _, new in new }
            return enriched
        }
    }

    private static func segmentMetadata(info: (id: String, title: String, uploader: String, displayTitle: String, folderTitle: String, thumbnail: URL?), candidate: IwaraVideoCandidate, asset: ResolvedAsset, pageURL: URL, index: Int) -> [String: String] {
        let type = asset.metadata["type"] ?? "hls_segment"
        let format = mediaFormat(for: asset.remoteURL, fallback: mediaFormat(forFilename: asset.filename, fallback: "ts"))
        return DownloadMetadata.clean([
            "site": "Iwara",
            "title": info.title,
            "series": info.title,
            "category": "video",
            "artist": info.uploader,
            "author": info.uploader,
            "creator": info.uploader,
            "uploader": info.uploader,
            "id": info.id,
            "video_id": info.id,
            "media_id": "\(info.id)-segment-\(index)",
            "gallery_id": info.id,
            "type": type,
            "media_type": type == "hls_segment" ? "segment" : type,
            "page": String(index),
            "position": String(index),
            "format": format,
            "media_format": format,
            "height": candidateHeight(for: candidate).map(String.init) ?? "",
            "resolution": resolution(for: candidate),
            "quality": qualityLabel(for: candidate),
            "thumbnail": info.thumbnail?.absoluteString ?? "",
            "playlist_url": asset.metadata["playlist_url"] ?? candidate.url.absoluteString,
            "video_url": asset.remoteURL.absoluteString,
            "media_url": asset.remoteURL.absoluteString,
            "source_url": pageURL.absoluteString,
            "page_url": pageURL.absoluteString
        ])
    }

    private static func collectCandidates(in object: Any, pageURL: URL, inheritedLabel: String, candidates: inout [IwaraVideoCandidate]) {
        if let dictionary = object as? [String: Any] {
            let label = stringValue(dictionary["name"]) ??
                stringValue(dictionary["quality"]) ??
                stringValue(dictionary["resolution"]) ??
                inheritedLabel
            for key in ["view", "download", "url", "src", "file", "fileUrl", "file_url", "video_url", "videoUrl", "source"] {
                if let raw = stringValue(dictionary[key]) {
                    appendCandidate(rawURL: raw, label: label, pageURL: pageURL, candidates: &candidates)
                }
            }
            for value in dictionary.values {
                collectCandidates(in: value, pageURL: pageURL, inheritedLabel: label, candidates: &candidates)
            }
        } else if let array = object as? [Any] {
            for value in array {
                collectCandidates(in: value, pageURL: pageURL, inheritedLabel: inheritedLabel, candidates: &candidates)
            }
        }
    }

    private static func appendCandidate(rawURL: String, label: String, pageURL: URL, candidates: inout [IwaraVideoCandidate]) {
        let bases = [pageURL, apiBaseURL(for: pageURL)]
        for base in bases {
            guard let url = absoluteURL(rawURL, baseURL: base),
                  isPlayableVideo(url) else {
                continue
            }
            let quality = qualityFrom(label: label, url: url)
            candidates.append(IwaraVideoCandidate(url: url, quality: quality, label: label))
            return
        }
    }

    private static func bestCandidate(_ candidates: [IwaraVideoCandidate]) -> IwaraVideoCandidate? {
        candidates.max { lhs, rhs in
            if lhs.quality != rhs.quality {
                return lhs.quality < rhs.quality
            }
            if lhs.isDirectVideo != rhs.isDirectVideo {
                return !lhs.isDirectVideo && rhs.isDirectVideo
            }
            return lhs.url.absoluteString < rhs.url.absoluteString
        }
    }

    private static func uniqueCandidates(_ candidates: [IwaraVideoCandidate]) -> [IwaraVideoCandidate] {
        var seen = Set<String>()
        return candidates.filter { candidate in
            let key = candidate.url.absoluteString
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }

    private static func qualityFrom(label: String, url: URL) -> Int {
        let normalized = label.lowercased()
        if normalized.contains("source") {
            return 10_000
        }
        if let explicit = firstCapture(pattern: #"([0-9]{3,4})\s*p"#, in: normalized).flatMap(Int.init) ??
            firstCapture(pattern: #"([0-9]{3,4})"#, in: normalized).flatMap(Int.init) {
            return explicit
        }
        return qualityFromURL(url)
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

    private static func candidateHeight(for candidate: IwaraVideoCandidate) -> Int? {
        if candidate.quality > 0 && candidate.quality < 10_000 {
            return candidate.quality
        }
        let fromLabel = firstCapture(pattern: #"([0-9]{3,4})\s*p"#, in: candidate.label.lowercased()).flatMap(Int.init) ??
            firstCapture(pattern: #"([0-9]{3,4})"#, in: candidate.label.lowercased()).flatMap(Int.init)
        if let fromLabel, (240...8640).contains(fromLabel) {
            return fromLabel
        }
        let fromURL = qualityFromURL(candidate.url)
        return fromURL > 0 ? fromURL : nil
    }

    private static func resolution(for candidate: IwaraVideoCandidate) -> String {
        candidateHeight(for: candidate).map { "\($0)p" } ?? ""
    }

    private static func qualityLabel(for candidate: IwaraVideoCandidate) -> String {
        candidate.label.isEmpty ? resolution(for: candidate) : candidate.label
    }

    private static func qualityFromURL(_ url: URL) -> Int {
        let text = url.absoluteString.lowercased()
        return firstCapture(pattern: #"([0-9]{3,4})p"#, in: text).flatMap(Int.init) ??
            firstCapture(pattern: #"[/-]([0-9]{3,4})(?:[./_-])"#, in: text).flatMap(Int.init) ??
            0
    }

    private static func apiBaseURL(for pageURL: URL) -> URL {
        var components = URLComponents()
        components.scheme = pageURL.scheme ?? "https"
        components.host = pageURL.host?.lowercased().hasSuffix(".test") == true ? "api.iwara.test" : "api.iwara.tv"
        components.path = "/"
        return components.url!
    }

    private static func apiHeaders() -> [String: String] {
        [
            "Accept": "application/json, text/plain, */*",
            "Origin": "https://iwara.tv"
        ]
    }

    private static func videoScope(fromHTML html: String) -> String {
        guard let marker = html.range(of: "videoPlayer", options: [.caseInsensitive]) ??
            html.range(of: "page-video__details", options: [.caseInsensitive]) else {
            return html
        }
        return String(html[marker.lowerBound...])
    }

    private static func scriptJSONObjects(fromHTML html: String) -> [Any] {
        let scripts = allCaptures(pattern: #"<script\b[^>]*>(.*?)</script>"#, in: html)
        var payloads: [String] = []
        for script in scripts {
            let decoded = decodeHTML(script).trimmed
            if decoded.hasPrefix("{") || decoded.hasPrefix("[") {
                payloads.append(decoded)
            }
            for pattern in [
                #"window\.__NUXT__\s*="#,
                #"window\.__INITIAL_STATE__\s*="#,
                #"__NUXT__\s*="#,
                #"__INITIAL_STATE__\s*="#
            ] {
                guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                    continue
                }
                let range = NSRange(decoded.startIndex..<decoded.endIndex, in: decoded)
                for match in regex.matches(in: decoded, range: range) {
                    guard let matchRange = Range(match.range, in: decoded),
                          let payload = balancedValue(startingAtOrAfter: matchRange.upperBound, in: decoded) else {
                        continue
                    }
                    payloads.append(payload)
                }
            }
        }

        return payloads.compactMap { payload in
            guard let data = payload.data(using: .utf8) else { return nil }
            return try? JSONSerialization.jsonObject(with: data)
        }
    }

    private static func balancedValue(startingAtOrAfter start: String.Index, in text: String) -> String? {
        var index = start
        while index < text.endIndex, text[index].isWhitespace {
            index = text.index(after: index)
        }
        guard index < text.endIndex, text[index] == "{" || text[index] == "[" else {
            return nil
        }
        let opener = text[index]
        let closer: Character = opener == "{" ? "}" : "]"
        var depth = 0
        var inString: Character?
        var escaped = false
        var cursor = index
        while cursor < text.endIndex {
            let char = text[cursor]
            if let quote = inString {
                if escaped {
                    escaped = false
                } else if char == "\\" {
                    escaped = true
                } else if char == quote {
                    inString = nil
                }
                cursor = text.index(after: cursor)
                continue
            }
            if char == "\"" || char == "'" {
                inString = char
            } else if char == opener {
                depth += 1
            } else if char == closer {
                depth -= 1
                if depth == 0 {
                    return String(text[index...cursor])
                }
            }
            cursor = text.index(after: cursor)
        }
        return nil
    }

    private static func stringValue(named names: [String], in object: Any?) -> String? {
        guard let object else { return nil }
        return firstStringValue(named: names, in: object)
    }

    private static func firstStringValue(named names: [String], in object: Any) -> String? {
        if let dictionary = object as? [String: Any] {
            for name in names {
                if let value = stringValue(dictionary[name])?.trimmed, !value.isEmpty {
                    return value
                }
            }
            for value in dictionary.values {
                if let found = firstStringValue(named: names, in: value) {
                    return found
                }
            }
        } else if let array = object as? [Any] {
            for value in array {
                if let found = firstStringValue(named: names, in: value) {
                    return found
                }
            }
        }
        return nil
    }

    private static func userValue(named names: [String], in object: Any?) -> String? {
        guard let object else { return nil }
        if let dictionary = object as? [String: Any],
           let user = dictionary["user"] ?? dictionary["author"] ?? dictionary["profile"] {
            for name in names {
                if let value = firstStringValue(named: [name], in: user), !value.isEmpty {
                    return value
                }
            }
        }
        return nil
    }

    private static func stringValue(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            return number.stringValue
        default:
            return nil
        }
    }

    private static func metaContent(from html: String, names: [String]) -> String? {
        for name in names {
            let escaped = NSRegularExpression.escapedPattern(for: name)
            let patterns = [
                #"<meta\b[^>]*(?:property|name)\s*=\s*["']\#(escaped)["'][^>]*content\s*=\s*["']([^"']+)["'][^>]*>"#,
                #"<meta\b[^>]*content\s*=\s*["']([^"']+)["'][^>]*(?:property|name)\s*=\s*["']\#(escaped)["'][^>]*>"#
            ]
            for pattern in patterns {
                if let value = firstCapture(pattern: pattern, in: html) {
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

    private static func titleTag(fromHTML html: String) -> String? {
        elementText(pattern: #"<title\b[^>]*>(.*?)</title>"#, in: html)
    }

    private static func firstCapture(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let capture = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[capture])
    }

    private static func allCaptures(pattern: String, in text: String) -> [String] {
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

    private static func absoluteURL(_ raw: String, baseURL: URL) -> URL? {
        var value = decodeHTML(raw)
            .replacingOccurrences(of: #"\/"#, with: "/")
            .replacingOccurrences(of: #"\\/"#, with: "/")
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
        let path = url.path.lowercased()
        return ["mp4", "m4v", "webm", "mov", "m3u8"].contains(url.pathExtension.lowercased()) ||
            path.contains(".mp4") ||
            path.contains(".webm") ||
            path.contains(".m3u8")
    }

    private static func isM3U8(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "m3u8" || url.absoluteString.lowercased().contains(".m3u8")
    }

    private static func isSupportedHost(_ host: String) -> Bool {
        host == "iwara.tv" ||
            host == "www.iwara.tv" ||
            host == "ecchi.iwara.tv" ||
            host == "iwara.test" ||
            host == "www.iwara.test"
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
        for suffix in [" - Iwara", " | Iwara", " - iwara.tv", " | iwara.tv"] {
            if text.lowercased().hasSuffix(suffix.lowercased()) {
                text = String(text.dropLast(suffix.count)).trimmed
            }
        }
        return (text.isEmpty ? fallback : text).sanitizedFilename(maxLength: 120)
    }
}

private extension IwaraVideoCandidate {
    var isDirectVideo: Bool {
        let ext = url.pathExtension.lowercased()
        return ["mp4", "m4v", "webm", "mov"].contains(ext)
    }
}
