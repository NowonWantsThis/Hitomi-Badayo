import Foundation

struct BilibiliMediaCandidate {
    var url: URL
    var score: Int64
    var extensionName: String
    var mediaID: String
    var width: Int64
    var height: Int64
    var bandwidth: Int64
    var codec: String
}

private struct BilibiliVideoIdentifier {
    var displayID: String
    var bvid: String?
    var aid: String?
}

final class BilibiliResolver {
    func canResolve(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(),
              Self.isSupportedHost(host),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return false
        }
        return Self.videoID(from: url) != nil || Self.shortLinkCode(from: url) != nil
    }

    func resolve(_ url: URL, headers: HTTPRequestOptions = HTTPRequestOptions()) async throws -> ResolvedDownload {
        if Self.shortLinkCode(from: url) != nil {
            let target = try await Self.expandedShortURL(url, headers: headers)
            var resolved = try await resolve(target, headers: headers)
            resolved.metadata["short_url"] = url.absoluteString
            resolved.metadata["redirect_url"] = target.absoluteString
            return resolved
        }

        let html = try await HTTPClient.shared.string(from: url, referer: headers.referer, userAgent: headers.userAgent)
        if let playInfo = Self.playInfoObject(fromHTML: html) {
            return try Self.resolvedDownload(fromPlayInfo: playInfo, initialState: Self.initialStateObject(fromHTML: html), sourceURL: url)
        }

        if let state = Self.initialStateObject(fromHTML: html),
           let request = Self.playURLAPI(fromInitialState: state, sourceURL: url) {
            let data = try await HTTPClient.shared.data(
                from: request,
                referer: headers.referer ?? url.absoluteString,
                userAgent: headers.userAgent,
                additionalHeaders: ["Accept": "application/json, text/plain, */*"]
            )
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw NativeDownloadError.invalidGalleryData
            }
            return try Self.resolvedDownload(fromPlayInfo: object, initialState: state, sourceURL: url)
        }

        throw NativeDownloadError.invalidGalleryData
    }

    static func resolvedDownload(fromPlayInfo playInfo: [String: Any], initialState: [String: Any]?, sourceURL: URL) throws -> ResolvedDownload {
        let mediaRoot = mediaRoot(fromPlayInfo: playInfo)
        let info = videoInfo(initialState: initialState, sourceURL: sourceURL)
        let outputFilename = "\(info.title)-\(info.id).mp4".sanitizedFilename(maxLength: 180)

        if let video = bestDASHVideo(in: mediaRoot, sourceURL: sourceURL) {
            let videoAsset = ResolvedAsset(
                remoteURL: video.url,
                filename: "video.\(video.extensionName)",
                metadata: assetMetadata(for: video, role: "video", info: info, sourceURL: sourceURL, index: 1),
                referer: sourceURL.absoluteString
            )

            if let audio = bestDASHAudio(in: mediaRoot, sourceURL: sourceURL) {
                let audioAsset = ResolvedAsset(
                    remoteURL: audio.url,
                    filename: "audio.\(audio.extensionName)",
                    metadata: assetMetadata(for: audio, role: "audio", info: info, sourceURL: sourceURL, index: 1),
                    referer: sourceURL.absoluteString
                )
                return ResolvedDownload(
                    title: info.displayTitle,
                    folderName: "Bilibili \(info.folderTitle)".sanitizedFilename(maxLength: 120),
                    assets: [videoAsset, audioAsset],
                    packageMode: .mux(videoAssets: [videoAsset], audioAssets: [audioAsset], outputFilename: outputFilename),
                    metadata: bilibiliMetadata(info: info, assets: [videoAsset, audioAsset], packageMode: "mux", sourceURL: sourceURL)
                )
            }

            return ResolvedDownload(
                title: info.displayTitle,
                folderName: "Bilibili \(info.folderTitle)".sanitizedFilename(maxLength: 120),
                assets: [videoAsset],
                packageMode: .concatenate(outputFilename: outputFilename),
                metadata: bilibiliMetadata(info: info, assets: [videoAsset], packageMode: "concatenate", sourceURL: sourceURL)
            )
        }

        let durlAssets = durlCandidates(in: mediaRoot, sourceURL: sourceURL).enumerated().map { offset, item in
            ResolvedAsset(
                remoteURL: item.url,
                filename: String(format: "%04d.%@", offset + 1, item.extensionName),
                metadata: assetMetadata(for: item, role: "video", info: info, sourceURL: sourceURL, index: offset + 1),
                referer: sourceURL.absoluteString
            )
        }
        guard !durlAssets.isEmpty else {
            throw NativeDownloadError.noFiles
        }

        return ResolvedDownload(
            title: info.displayTitle,
            folderName: "Bilibili \(info.folderTitle)".sanitizedFilename(maxLength: 120),
            assets: durlAssets,
            packageMode: .concatenate(outputFilename: "\(info.title)-\(info.id).flv".sanitizedFilename(maxLength: 180)),
            metadata: bilibiliMetadata(info: info, assets: durlAssets, packageMode: "concatenate", sourceURL: sourceURL)
        )
    }

    static func videoID(from url: URL) -> String? {
        videoIdentifier(from: url)?.displayID
    }

    static func canonicalURL(for url: URL) -> URL? {
        guard let host = url.host?.lowercased(),
              Self.isSupportedHost(host),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }

        if let tvID = tvVideoID(from: url) {
            var components = URLComponents()
            components.scheme = url.scheme ?? "https"
            components.host = "www.bilibili.tv"
            let parts = url.path.split(separator: "/").map { String($0).removingPercentEncoding ?? String($0) }
            let lower = parts.map { $0.lowercased() }
            let videoIndex = lower.firstIndex(of: "video") ?? 0
            let prefix = parts.prefix(videoIndex)
            components.path = "/" + (Array(prefix) + ["video", tvID]).joined(separator: "/")
            return components.url
        }

        if isB23Host(host),
           let identifier = directShortVideoIdentifier(from: url) {
            var components = URLComponents()
            components.scheme = "https"
            components.host = host.hasSuffix(".test") ? "www.bilibili.test" : "www.bilibili.com"
            components.path = "/video/\(identifier.displayID)"
            return components.url
        }

        if let anime = animePlayIdentifier(from: url) {
            var components = URLComponents()
            components.scheme = url.scheme ?? "https"
            components.host = host.hasSuffix(".test") ? "bangumi.bilibili.test" : "bangumi.bilibili.com"
            components.path = "/anime/\(anime.animeID)/play"
            components.fragment = anime.aid
            return components.url
        }

        guard let identifier = videoIdentifier(from: url) else { return nil }
        var components = URLComponents()
        components.scheme = url.scheme ?? "https"
        components.host = host.hasSuffix(".test") ? "www.bilibili.test" : "www.bilibili.com"
        components.path = "/video/\(identifier.displayID)"
        return components.url
    }

    static func canonicalInputURL(for url: URL) -> URL? {
        guard let canonical = canonicalURL(for: url) else { return nil }
        guard var components = URLComponents(url: canonical, resolvingAgainstBaseURL: false) else {
            return canonical
        }
        components.query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.query
        return components.url ?? canonical
    }

    static func tvVideoID(from url: URL) -> String? {
        guard let host = url.host?.lowercased(),
              isBilibiliTVHost(host),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        let lower = parts.map { $0.lowercased() }
        guard let videoIndex = lower.firstIndex(of: "video"),
              videoIndex + 1 < parts.count else {
            return nil
        }
        let value = parts[videoIndex + 1].trimmed
        guard value.range(of: #"^[0-9A-Za-z_-]{4,}$"#, options: .regularExpression) != nil else {
            return nil
        }
        return value
    }

    static func shortLinkCode(from url: URL) -> String? {
        guard let host = url.host?.lowercased(),
              isB23Host(host),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              directShortVideoIdentifier(from: url) == nil else {
            return nil
        }
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        guard parts.count == 1 else { return nil }
        let code = parts[0].trimmed
        guard code.range(of: #"^[0-9A-Za-z_-]{4,64}$"#, options: .regularExpression) != nil else {
            return nil
        }
        return code
    }

    private static func expandedShortURL(_ url: URL, headers: HTTPRequestOptions) async throws -> URL {
        guard let response = try await HTTPClient.shared.head(
            from: url,
            referer: headers.referer,
            userAgent: headers.userAgent
        ),
              let finalURL = response.url,
              finalURL.absoluteString != url.absoluteString,
              videoID(from: finalURL) != nil,
              let canonical = canonicalInputURL(for: finalURL) else {
            throw NativeDownloadError.unsupported("Bilibili short link did not resolve to a supported video URL.")
        }
        return canonical
    }

    private static func videoIdentifier(from url: URL) -> BilibiliVideoIdentifier? {
        if let host = url.host?.lowercased(),
           isB23Host(host),
           let identifier = directShortVideoIdentifier(from: url) {
            return identifier
        }

        let parts = url.path.split(separator: "/").map { String($0).removingPercentEncoding ?? String($0) }
        if let videoIndex = parts.firstIndex(where: { $0.lowercased() == "video" }),
           videoIndex + 1 < parts.count {
            let value = parts[videoIndex + 1].trimmed
            guard !value.isEmpty else { return nil }
            if value.range(of: #"^BV[0-9A-Za-z]+$"#, options: [.caseInsensitive, .regularExpression]) != nil {
                return BilibiliVideoIdentifier(displayID: value, bvid: value, aid: nil)
            }
            if value.range(of: #"^av[0-9]+$"#, options: [.caseInsensitive, .regularExpression]) != nil {
                let aid = String(value.dropFirst(2))
                return BilibiliVideoIdentifier(displayID: value, bvid: nil, aid: aid)
            }
            if value.range(of: #"^[0-9A-Za-z_-]{6,}$"#, options: .regularExpression) != nil {
                return BilibiliVideoIdentifier(displayID: value, bvid: value, aid: nil)
            }
        }

        if let anime = animePlayIdentifier(from: url) {
            return BilibiliVideoIdentifier(displayID: "av\(anime.aid)", bvid: nil, aid: anime.aid)
        }

        return nil
    }

    private static func directShortVideoIdentifier(from url: URL) -> BilibiliVideoIdentifier? {
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        guard let value = parts.first?.trimmed,
              parts.count == 1 else {
            return nil
        }
        if value.range(of: #"^BV[0-9A-Za-z]+$"#, options: [.caseInsensitive, .regularExpression]) != nil {
            return BilibiliVideoIdentifier(displayID: value, bvid: value, aid: nil)
        }
        if value.range(of: #"^av[0-9]+$"#, options: [.caseInsensitive, .regularExpression]) != nil {
            let aid = String(value.dropFirst(2))
            return BilibiliVideoIdentifier(displayID: value, bvid: nil, aid: aid)
        }
        return nil
    }

    private static func animePlayIdentifier(from url: URL) -> (animeID: String, aid: String)? {
        let parts = url.path.split(separator: "/").map { String($0).removingPercentEncoding ?? String($0) }
        guard let animeIndex = parts.firstIndex(where: { $0.lowercased() == "anime" }),
              animeIndex + 2 < parts.count,
              parts[animeIndex + 2].lowercased() == "play",
              let fragment = url.fragment?.trimmed,
              fragment.range(of: #"^[0-9]+$"#, options: .regularExpression) != nil else {
            return nil
        }
        return (parts[animeIndex + 1], fragment)
    }

    static func playURLAPI(fromInitialState state: [String: Any], sourceURL: URL) -> URL? {
        guard let cid = stringValue(dictionary(at: ["videoData"], in: state)?["cid"]) ??
            stringValue(dictionary(at: ["videoData", "pages"], in: state)?["cid"]) ??
            ((dictionary(at: ["videoData"], in: state)?["pages"] as? [[String: Any]])?.first).flatMap({ stringValue($0["cid"]) }) else {
            return nil
        }

        let videoData = dictionary(at: ["videoData"], in: state) ?? [:]
        let sourceIdentifier = videoIdentifier(from: sourceURL)
        let bvid = stringValue(videoData["bvid"]) ?? sourceIdentifier?.bvid
        let aid = stringValue(videoData["aid"]) ?? stringValue(videoData["aid_str"]) ?? sourceIdentifier?.aid

        guard bvid != nil || aid != nil else { return nil }

        var components = URLComponents()
        components.scheme = sourceURL.scheme ?? "https"
        components.host = sourceURL.host?.lowercased().hasSuffix(".test") == true ? "api.bilibili.test" : "api.bilibili.com"
        components.path = "/x/player/playurl"
        var query = [
            URLQueryItem(name: "cid", value: cid),
            URLQueryItem(name: "qn", value: "0"),
            URLQueryItem(name: "fnval", value: "4048"),
            URLQueryItem(name: "fourk", value: "1")
        ]
        if let bvid {
            query.append(URLQueryItem(name: "bvid", value: bvid))
        } else if let aid {
            query.append(URLQueryItem(name: "avid", value: aid))
        }
        components.queryItems = query
        return components.url
    }

    static func playInfoObject(fromHTML html: String) -> [String: Any]? {
        assignmentJSONObject(named: #"window\.__playinfo__"#, fromHTML: html)
    }

    static func initialStateObject(fromHTML html: String) -> [String: Any]? {
        assignmentJSONObject(named: #"window\.__INITIAL_STATE__"#, fromHTML: html)
    }

    static func bestDASHVideo(in mediaRoot: [String: Any], sourceURL: URL) -> BilibiliMediaCandidate? {
        let dash = mediaRoot["dash"] as? [String: Any] ?? mediaRoot
        let videos = dash["video"] as? [[String: Any]] ?? []
        return videos.compactMap { mediaCandidate(from: $0, sourceURL: sourceURL, fallbackExtension: "m4s", video: true) }
            .max { $0.score < $1.score }
    }

    static func bestDASHAudio(in mediaRoot: [String: Any], sourceURL: URL) -> BilibiliMediaCandidate? {
        let dash = mediaRoot["dash"] as? [String: Any] ?? mediaRoot
        var audios = dash["audio"] as? [[String: Any]] ?? []
        if audios.isEmpty,
           let dolbyAudio = dictionary(at: ["dolby"], in: dash)?["audio"] as? [[String: Any]] {
            audios = dolbyAudio
        }
        if audios.isEmpty,
           let flacAudio = dictionary(at: ["flac", "audio"], in: dash) {
            audios = [flacAudio]
        }
        return audios.compactMap { mediaCandidate(from: $0, sourceURL: sourceURL, fallbackExtension: "m4a", video: false) }
            .max { $0.score < $1.score }
    }

    static func durlCandidates(in mediaRoot: [String: Any], sourceURL: URL) -> [BilibiliMediaCandidate] {
        let values = mediaRoot["durl"] as? [[String: Any]] ?? []
        return values.enumerated().compactMap { offset, item in
            guard var candidate = mediaCandidate(from: item, sourceURL: sourceURL, fallbackExtension: "flv", video: true) else {
                return nil
            }
            candidate.score = Int64(offset)
            return candidate
        }
    }

    private static func mediaRoot(fromPlayInfo playInfo: [String: Any]) -> [String: Any] {
        if let data = playInfo["data"] as? [String: Any] {
            return data
        }
        if let result = playInfo["result"] as? [String: Any] {
            return result
        }
        return playInfo
    }

    private static func videoInfo(initialState: [String: Any]?, sourceURL: URL) -> (id: String, title: String, displayTitle: String, folderTitle: String, artist: String, username: String?, bvid: String, aid: String, cid: String) {
        let videoData = initialState.flatMap { dictionary(at: ["videoData"], in: $0) } ?? [:]
        let sourceIdentifier = videoIdentifier(from: sourceURL)
        let bvid = stringValue(videoData["bvid"]) ?? sourceIdentifier?.bvid ?? ""
        let aid = stringValue(videoData["aid"]) ?? stringValue(videoData["aid_str"]) ?? sourceIdentifier?.aid ?? ""
        let cid = stringValue(videoData["cid"]) ??
            stringValue(dictionary(at: ["videoData", "pages"], in: initialState ?? [:])?["cid"]) ??
            ((videoData["pages"] as? [[String: Any]])?.first).flatMap { stringValue($0["cid"]) } ??
            ""
        let id = bvid.isEmpty ? (aid.isEmpty ? videoID(from: sourceURL) ?? "bilibili" : "av\(aid)") : bvid
        let title = cleanTitle(
            stringValue(videoData["title"]) ??
                stringValue(initialState?["title"]) ??
                "Bilibili \(id)"
        )
        let owner = videoData["owner"] as? [String: Any] ?? videoData["upData"] as? [String: Any]
        let artist = cleanTitle(stringValue(owner?["name"]) ?? stringValue(owner?["mid"]) ?? "")
        let username = stringValue(owner?["mid"]) ?? stringValue(owner?["name"])
        let displayTitle = artist.isEmpty ? title : "\(artist) - \(title)"
        return (id, title, displayTitle.sanitizedFilename(maxLength: 120), displayTitle, artist, username, bvid, aid, cid)
    }

    private static func bilibiliMetadata(info: (id: String, title: String, displayTitle: String, folderTitle: String, artist: String, username: String?, bvid: String, aid: String, cid: String), assets: [ResolvedAsset], packageMode: String, sourceURL: URL) -> [String: String] {
        let videoCount = assets.filter { ($0.metadata["media_type"] ?? $0.metadata["type"]) == "video" }.count
        let audioCount = assets.filter { ($0.metadata["media_type"] ?? $0.metadata["type"]) == "audio" }.count
        return DownloadMetadata.clean([
            "site": "Bilibili",
            "title": info.title,
            "type": "video",
            "media_type": "video",
            "package_mode": packageMode,
            "media_count": String(assets.count),
            "video_count": videoCount > 0 ? String(videoCount) : "",
            "audio_count": audioCount > 0 ? String(audioCount) : "",
            "id": info.id,
            "video_id": info.id,
            "media_id": info.id,
            "bvid": info.bvid,
            "aid": info.aid,
            "cid": info.cid,
            "artist": info.artist,
            "author": info.artist,
            "creator": info.artist,
            "user": info.username ?? info.artist,
            "username": info.username ?? info.artist,
            "uploader": info.artist,
            "uploader_id": info.username ?? "",
            "channel": info.artist,
            "channel_id": info.username ?? "",
            "url": sourceURL.absoluteString,
            "source_url": sourceURL.absoluteString,
            "page_url": sourceURL.absoluteString
        ])
    }

    private static func assetMetadata(for candidate: BilibiliMediaCandidate, role: String, info: (id: String, title: String, displayTitle: String, folderTitle: String, artist: String, username: String?, bvid: String, aid: String, cid: String), sourceURL: URL, index: Int) -> [String: String] {
        let format = candidate.extensionName.lowercased()
        let isAudio = role == "audio"
        return DownloadMetadata.clean([
            "site": "Bilibili",
            "title": info.title,
            "type": role,
            "media_type": role,
            "id": info.id,
            "video_id": info.id,
            "media_id": isAudio ? "\(info.id)-audio-\(index)" : "\(info.id)-video-\(index)",
            "bvid": info.bvid,
            "aid": info.aid,
            "cid": info.cid,
            "stream_id": candidate.mediaID,
            "page": String(index),
            "position": String(index),
            "format": format,
            "media_format": format,
            "width": candidate.width > 0 ? String(candidate.width) : "",
            "height": candidate.height > 0 ? String(candidate.height) : "",
            "resolution": candidate.height > 0 ? "\(candidate.height)p" : "",
            "quality": candidate.height > 0 ? "\(candidate.height)p" : candidate.mediaID,
            "bandwidth": candidate.bandwidth > 0 ? String(candidate.bandwidth) : "",
            "codec": candidate.codec,
            "video_url": isAudio ? "" : candidate.url.absoluteString,
            "audio_url": isAudio ? candidate.url.absoluteString : "",
            "media_url": candidate.url.absoluteString,
            "source_url": candidate.url.absoluteString,
            "page_url": sourceURL.absoluteString,
            "artist": info.artist,
            "author": info.artist,
            "creator": info.artist,
            "user": info.username ?? info.artist,
            "username": info.username ?? info.artist,
            "uploader": info.artist,
            "uploader_id": info.username ?? "",
            "channel": info.artist,
            "channel_id": info.username ?? ""
        ])
    }

    private static func mediaCandidate(from item: [String: Any], sourceURL: URL, fallbackExtension: String, video: Bool) -> BilibiliMediaCandidate? {
        let raw = stringValue(item["baseUrl"]) ??
            stringValue(item["base_url"]) ??
            stringValue(item["url"]) ??
            firstBackupURL(from: item)
        guard let raw,
              let url = absoluteURL(raw, baseURL: sourceURL) else {
            return nil
        }

        let bandwidth = int64Value(item["bandwidth"]) ?? int64Value(item["vbr"]) ?? int64Value(item["size"]) ?? 0
        let width = int64Value(item["width"]) ?? 0
        let height = int64Value(item["height"]) ?? 0
        let id = int64Value(item["id"]) ?? 0
        let mediaID = stringValue(item["id"]) ?? stringValue(item["quality"]) ?? ""
        let codec = stringValue(item["codecs"]) ?? stringValue(item["mimeType"]) ?? stringValue(item["mime_type"]) ?? ""
        let bitrate = int64Value(item["vbr"]) ?? bandwidth
        let audioBitrate = int64Value(item["abr"]) ?? bandwidth
        let score = video ? height * 1_000_000_000 + bitrate * 1_000 + id : audioBitrate * 1_000 + bandwidth + id
        return BilibiliMediaCandidate(
            url: url,
            score: score,
            extensionName: extensionName(for: url, fallback: fallbackExtension),
            mediaID: mediaID,
            width: width,
            height: height,
            bandwidth: bandwidth,
            codec: codec
        )
    }

    private static func firstBackupURL(from item: [String: Any]) -> String? {
        if let values = item["backupUrl"] as? [String], let first = values.first {
            return first
        }
        if let values = item["backup_url"] as? [String], let first = values.first {
            return first
        }
        return nil
    }

    private static func assignmentJSONObject(named name: String, fromHTML html: String) -> [String: Any]? {
        let patterns = [
            name + #"\s*=\s*(\{.*?\})\s*;"#,
            name + #"\s*=\s*(\{.*?\})\s*</script>"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
                continue
            }
            let range = NSRange(html.startIndex..<html.endIndex, in: html)
            guard let match = regex.firstMatch(in: html, range: range),
                  let capture = Range(match.range(at: 1), in: html) else {
                continue
            }
            let text = decodeHTML(normalizeEscapes(String(html[capture]))).trimmed
            guard let data = text.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            return object
        }
        return nil
    }

    private static func absoluteURL(_ raw: String, baseURL: URL) -> URL? {
        let value = decodeHTML(normalizeEscapes(raw))
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'").union(.whitespacesAndNewlines))
        if value.hasPrefix("//") {
            return URL(string: "\(baseURL.scheme ?? "https"):\(value)")
        }
        return URL(string: value, relativeTo: baseURL)?.absoluteURL
    }

    private static func extensionName(for url: URL, fallback: String) -> String {
        let ext = url.pathExtension.trimmed
        return ext.isEmpty ? fallback : ext
    }

    private static func isSupportedHost(_ host: String) -> Bool {
            host == "bilibili.com" ||
            host == "www.bilibili.com" ||
            host == "m.bilibili.com" ||
            host == "bangumi.bilibili.com" ||
            host.hasSuffix(".bilibili.com") ||
            isBilibiliTVHost(host) ||
            isB23Host(host) ||
            host == "bilibili.test" ||
            host == "www.bilibili.test" ||
            host.hasSuffix(".bilibili.test")
    }

    private static func isBilibiliTVHost(_ host: String) -> Bool {
        host == "bilibili.tv" ||
            host == "www.bilibili.tv" ||
            host == "m.bilibili.tv" ||
            host.hasSuffix(".bilibili.tv")
    }

    private static func isB23Host(_ host: String) -> Bool {
        host == "b23.tv" ||
            host == "www.b23.tv" ||
            host == "b23.test" ||
            host == "www.b23.test"
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

    private static func int64Value(_ value: Any?) -> Int64? {
        if let int = value as? Int { return Int64(int) }
        if let int64 = value as? Int64 { return int64 }
        if let number = value as? NSNumber { return number.int64Value }
        if let string = value as? String { return Int64(string) }
        return nil
    }

    private static func cleanTitle(_ raw: String) -> String {
        raw.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmed
            .sanitizedFilename(maxLength: 120)
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
}
