import Foundation

final class CoubResolver {
    func canResolve(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(),
              Self.isCoubHost(host),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return false
        }
        return Self.coubID(from: url) != nil
    }

    func resolve(_ url: URL, headers: HTTPRequestOptions = HTTPRequestOptions()) async throws -> ResolvedDownload {
        guard let id = Self.coubID(from: url) else {
            throw NativeDownloadError.invalidURL(url.absoluteString)
        }

        let data = try await HTTPClient.shared.data(
            from: Self.apiURL(id: id, sourceURL: url),
            referer: headers.referer ?? url.absoluteString,
            userAgent: headers.userAgent,
            additionalHeaders: ["Accept": "application/json, text/plain, */*"]
        )
        return try Self.resolvedDownload(fromAPIData: data, sourceURL: url)
    }

    static func resolvedDownload(fromAPIData data: Data, sourceURL: URL) throws -> ResolvedDownload {
        let object = try jsonObject(from: data)
        let coub = object["coub"] as? [String: Any] ?? object
        let title = cleanTitle(stringValue(coub["title"]) ?? "Coub \(coubID(from: sourceURL) ?? "")")
        let id = stringValue(coub["permalink"]) ?? stringValue(coub["id"]) ?? coubID(from: sourceURL) ?? "coub"
        let fileVersions = coub["file_versions"] as? [String: Any] ?? coub

        guard let video = bestCandidate(in: fileVersions, kind: .video, sourceURL: sourceURL) else {
            throw NativeDownloadError.noFiles
        }

        let videoAsset = ResolvedAsset(
            remoteURL: video.url,
            filename: "video.\(extensionName(for: video.url, fallback: "mp4"))",
            metadata: assetMetadata(for: video, role: "video", coub: coub, id: id, title: title, sourceURL: sourceURL),
            referer: sourceURL.absoluteString
        )
        let outputFilename = "\(title)-\(id).mp4".sanitizedFilename(maxLength: 180)

        if let audio = bestCandidate(in: fileVersions, kind: .audio, sourceURL: sourceURL) {
            let audioAsset = ResolvedAsset(
                remoteURL: audio.url,
                filename: "audio.\(extensionName(for: audio.url, fallback: "m4a"))",
                metadata: assetMetadata(for: audio, role: "audio", coub: coub, id: id, title: title, sourceURL: sourceURL),
                referer: sourceURL.absoluteString
            )
            let assets = [videoAsset, audioAsset]
            return ResolvedDownload(
                title: title,
                folderName: "Coub \(title)".sanitizedFilename(maxLength: 120),
                assets: assets,
                packageMode: .mux(videoAssets: [videoAsset], audioAssets: [audioAsset], outputFilename: outputFilename),
                metadata: coubMetadata(coub: coub, id: id, title: title, assets: assets, packageMode: "mux", sourceURL: sourceURL)
            )
        }

        let assets = [videoAsset]
        return ResolvedDownload(
            title: title,
            folderName: "Coub \(title)".sanitizedFilename(maxLength: 120),
            assets: assets,
            packageMode: .concatenate(outputFilename: outputFilename),
            metadata: coubMetadata(coub: coub, id: id, title: title, assets: assets, packageMode: "concatenate", sourceURL: sourceURL)
        )
    }

    static func coubMetadata(coub: [String: Any], id: String, title: String, assets: [ResolvedAsset] = [], packageMode: String = "", sourceURL: URL? = nil) -> [String: String] {
        let channel = coub["channel"] as? [String: Any]
        let user = coub["user"] as? [String: Any]
        let author = stringValue(channel?["title"]) ??
            stringValue(channel?["permalink"]) ??
            stringValue(user?["name"]) ??
            stringValue(user?["username"]) ??
            ""
        let channelID = stringValue(channel?["id"]) ??
            stringValue(channel?["permalink"]) ??
            ""
        let category = stringValue(coub["type"]) ??
            stringValue(coub["category"]) ??
            ""
        let tags = tagText(from: coub["tags"])
        let video = assets.first { ($0.metadata["media_type"] ?? $0.metadata["type"]) == "video" }
        let audio = assets.first { ($0.metadata["media_type"] ?? $0.metadata["type"]) == "audio" }
        let videoCount = assets.filter { ($0.metadata["media_type"] ?? $0.metadata["type"]) == "video" }.count
        let audioCount = assets.filter { ($0.metadata["media_type"] ?? $0.metadata["type"]) == "audio" }.count

        return DownloadMetadata.clean([
            "artist": author,
            "author": author,
            "creator": author,
            "uploader": author,
            "channel": author,
            "username": author,
            "channel_id": channelID,
            "uploader_id": stringValue(user?["id"]) ?? "",
            "series": title,
            "category": category,
            "type": category,
            "media_type": "video",
            "package_mode": packageMode,
            "media_count": assets.isEmpty ? "" : String(assets.count),
            "video_count": videoCount > 0 ? String(videoCount) : "",
            "audio_count": audioCount > 0 ? String(audioCount) : "",
            "tag": tags,
            "tags": tags,
            "id": id,
            "video_id": id,
            "media_id": id,
            "coub_id": id,
            "slug": id,
            "site": "Coub",
            "title": title,
            "format": video?.metadata["format"] ?? "",
            "media_format": video?.metadata["media_format"] ?? "",
            "width": video?.metadata["width"] ?? "",
            "height": video?.metadata["height"] ?? "",
            "resolution": video?.metadata["resolution"] ?? "",
            "quality": video?.metadata["quality"] ?? "",
            "video_url": video?.remoteURL.absoluteString ?? "",
            "audio_url": audio?.remoteURL.absoluteString ?? "",
            "media_url": video?.remoteURL.absoluteString ?? "",
            "source_url": sourceURL?.absoluteString ?? "",
            "page_url": sourceURL?.absoluteString ?? ""
        ])
    }

    static func apiURL(id: String, sourceURL: URL) -> URL {
        var components = URLComponents()
        components.scheme = sourceURL.scheme ?? "https"
        components.host = sourceURL.host?.lowercased().hasSuffix(".test") == true ? "coub.test" : "coub.com"
        components.path = "/api/v2/coubs/\(id)"
        return components.url!
    }

    static func canonicalViewURL(id: String, sourceURL: URL) -> URL? {
        guard var components = URLComponents(url: sourceURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        let host = components.host?.lowercased() ?? ""
        if isImagizerHost(host) {
            components.host = host.hasSuffix(".test") ? "coub.test" : "coub.com"
        }
        components.path = "/view/\(id)"
        components.queryItems = nil
        components.fragment = nil
        return components.url
    }

    static func canonicalURL(for url: URL) -> URL? {
        guard let host = url.host?.lowercased(),
              isCoubHost(host),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let id = coubID(from: url) else {
            return nil
        }
        return canonicalViewURL(id: id, sourceURL: url)
    }

    static func coubID(from url: URL) -> String? {
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        let lower = parts.map { $0.lowercased() }
        if let marker = lower.firstIndex(where: { $0 == "view" || $0 == "embed" }),
           marker + 1 < parts.count,
           isCoubID(parts[marker + 1]) {
            return parts[marker + 1]
        }
        if parts.count == 1, let id = parts.first, isCoubID(id) {
            return id
        }

        let absolute = normalizedCoubURLString(url)
        let patterns = [
            #"/view/([0-9A-Za-z]+)"#,
            #"/embed/([0-9A-Za-z]+)"#,
            #"coub(?:\.test|\.com)/([0-9A-Za-z]+)$"#
        ]

        for pattern in patterns {
            if let id = firstCapture(pattern: pattern, in: absolute) {
                return id
            }
        }
        return nil
    }

    private static func isCoubID(_ value: String) -> Bool {
        value.range(of: #"^[0-9A-Za-z]+$"#, options: .regularExpression) != nil
    }

    private enum MediaKind {
        case video
        case audio
    }

    private struct MediaCandidate {
        var url: URL
        var score: Int64
        var width: Int64
        var height: Int64
        var size: Int64
        var quality: String
        var mime: String
        var path: [String]
    }

    private static func bestCandidate(in value: Any, kind: MediaKind, sourceURL: URL) -> MediaCandidate? {
        var seen = Set<String>()
        let candidates = mediaCandidates(in: value, kind: kind, sourceURL: sourceURL)
            .filter { candidate in
                let normalized = URLIdentity.normalize(candidate.url.absoluteString)
                guard !seen.contains(normalized) else { return false }
                seen.insert(normalized)
                return true
            }
        return candidates.max { $0.score < $1.score }
    }

    private static func mediaCandidates(in value: Any, kind: MediaKind, sourceURL: URL, path: [String] = []) -> [MediaCandidate] {
        var candidates: [MediaCandidate] = []

        if let dictionary = value as? [String: Any] {
            if let raw = stringValue(dictionary["url"]) ?? stringValue(dictionary["remote_url"]) ?? stringValue(dictionary["src"]),
               let url = absoluteURL(raw, sourceURL: sourceURL),
               matches(url: url, path: path, dictionary: dictionary, kind: kind) {
                candidates.append(mediaCandidate(url: url, dictionary: dictionary, path: path, kind: kind))
            }

            for (key, child) in dictionary {
                candidates.append(contentsOf: mediaCandidates(in: child, kind: kind, sourceURL: sourceURL, path: path + [key.lowercased()]))
            }
        } else if let array = value as? [Any] {
            for child in array {
                candidates.append(contentsOf: mediaCandidates(in: child, kind: kind, sourceURL: sourceURL, path: path))
            }
        }

        return candidates
    }

    private static func mediaCandidate(url: URL, dictionary: [String: Any], path: [String], kind: MediaKind) -> MediaCandidate {
        let size = int64Value(dictionary["filesize"]) ??
            int64Value(dictionary["file_size"]) ??
            int64Value(dictionary["size"]) ??
            int64Value(dictionary["content_length"]) ??
            0
        let width = int64Value(dictionary["width"]) ?? 0
        let height = int64Value(dictionary["height"]) ?? 0
        let quality = stringValue(dictionary["quality"]) ??
            stringValue(dictionary["label"]) ??
            qualityLabel(from: path)
        let mime = stringValue(dictionary["type"]) ??
            stringValue(dictionary["mime_type"]) ??
            stringValue(dictionary["mime"]) ??
            ""
        return MediaCandidate(
            url: url,
            score: score(for: dictionary, path: path, url: url, kind: kind),
            width: width,
            height: height,
            size: size,
            quality: quality,
            mime: mime,
            path: path
        )
    }

    private static func matches(url: URL, path: [String], dictionary: [String: Any], kind: MediaKind) -> Bool {
        let labels = Set(path.map { $0.lowercased() })
        let ext = url.pathExtension.lowercased()
        let mime = (stringValue(dictionary["type"]) ?? stringValue(dictionary["mime_type"]) ?? stringValue(dictionary["mime"]))?.lowercased() ?? ""
        let raw = url.absoluteString.lowercased()

        switch kind {
        case .video:
            return labels.contains("video") ||
                ["mp4", "m4v", "mov"].contains(ext) ||
                mime.hasPrefix("video/") ||
                raw.contains(".mp4")
        case .audio:
            return labels.contains("audio") ||
                ["m4a", "mp3", "aac", "ogg", "opus"].contains(ext) ||
                mime.hasPrefix("audio/")
        }
    }

    private static func score(for dictionary: [String: Any], path: [String], url: URL, kind: MediaKind) -> Int64 {
        let size = int64Value(dictionary["filesize"]) ??
            int64Value(dictionary["file_size"]) ??
            int64Value(dictionary["size"]) ??
            int64Value(dictionary["content_length"]) ??
            0
        var score = size > 0 ? size * 1_000_000 : 0

        let width = int64Value(dictionary["width"]) ?? 0
        let height = int64Value(dictionary["height"]) ?? 0
        score += width * height

        for label in path {
            switch label.lowercased() {
            case "higher", "highest", "large", "big", "high":
                score += 10_000_000
            case "medium", "med":
                score += 1_000_000
            case "low", "small", "tiny":
                score += 100_000
            default:
                break
            }
        }

        if kind == .video && url.pathExtension.lowercased() == "mp4" {
            score += 50_000_000
        }
        return score
    }

    private static func assetMetadata(for candidate: MediaCandidate, role: String, coub: [String: Any], id: String, title: String, sourceURL: URL) -> [String: String] {
        let channel = coub["channel"] as? [String: Any]
        let user = coub["user"] as? [String: Any]
        let author = stringValue(channel?["title"]) ??
            stringValue(channel?["permalink"]) ??
            stringValue(user?["name"]) ??
            stringValue(user?["username"]) ??
            ""
        let format = mediaFormat(for: candidate, fallback: role == "audio" ? "m4a" : "mp4")
        let isAudio = role == "audio"
        let position = isAudio ? "2" : "1"
        let resolution = candidate.height > 0 ? "\(candidate.height)p" : ""
        return DownloadMetadata.clean([
            "site": "Coub",
            "title": title,
            "type": role,
            "media_type": role,
            "id": id,
            "video_id": id,
            "media_id": "\(id)-\(role)",
            "coub_id": id,
            "stream_id": candidate.path.joined(separator: "."),
            "page": "1",
            "position": position,
            "format": format,
            "media_format": format,
            "mime": candidate.mime,
            "width": candidate.width > 0 ? String(candidate.width) : "",
            "height": candidate.height > 0 ? String(candidate.height) : "",
            "resolution": resolution,
            "quality": candidate.quality.isEmpty ? resolution : candidate.quality,
            "byte_count": candidate.size > 0 ? String(candidate.size) : "",
            "video_url": isAudio ? "" : candidate.url.absoluteString,
            "audio_url": isAudio ? candidate.url.absoluteString : "",
            "media_url": candidate.url.absoluteString,
            "source_url": sourceURL.absoluteString,
            "page_url": sourceURL.absoluteString,
            "artist": author,
            "author": author,
            "creator": author,
            "uploader": author,
            "channel": author,
            "username": author
        ])
    }

    private static func mediaFormat(for candidate: MediaCandidate, fallback: String) -> String {
        let ext = candidate.url.pathExtension.trimmed.lowercased()
        if !ext.isEmpty { return ext }
        let mime = candidate.mime.lowercased()
        if mime.contains("mp4") { return "mp4" }
        if mime.contains("m4a") { return "m4a" }
        if mime.contains("mpeg") || mime.contains("mp3") { return "mp3" }
        if mime.contains("aac") { return "aac" }
        return fallback
    }

    private static func qualityLabel(from path: [String]) -> String {
        for label in path.reversed() {
            switch label.lowercased() {
            case "higher", "highest", "large", "big", "high", "medium", "med", "low", "small", "tiny":
                return label
            default:
                continue
            }
        }
        return ""
    }

    private static func apiCompatibleHost(_ host: String) -> Bool {
        host == "coub.com" ||
            host == "www.coub.com" ||
            host == "coub.test" ||
            host == "www.coub.test"
    }

    private static func isCoubHost(_ host: String) -> Bool {
        apiCompatibleHost(host) ||
            host.hasSuffix(".coub.com") ||
            host.hasSuffix(".coub.test") ||
            isImagizerHost(host)
    }

    static func isImagizerHost(_ host: String) -> Bool {
        host.range(of: #"^coub-com-.+\.imagizer\.(?:com|test)$"#, options: .regularExpression) != nil
    }

    private static func normalizedCoubURLString(_ url: URL) -> String {
        guard let host = url.host?.lowercased(),
              !apiCompatibleHost(host),
              isCoubHost(host) else {
            return url.absoluteString
        }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.host = host.hasSuffix(".test") ? "coub.test" : "coub.com"
        return components?.url?.absoluteString ?? url.absoluteString
    }

    private static func absoluteURL(_ raw: String, sourceURL: URL) -> URL? {
        let value = raw.trimmed
        if value.hasPrefix("//") {
            return URL(string: "\(sourceURL.scheme ?? "https"):\(value)")
        }
        return URL(string: value, relativeTo: sourceURL)?.absoluteURL
    }

    private static func extensionName(for url: URL, fallback: String) -> String {
        let ext = url.pathExtension.trimmed
        return ext.isEmpty ? fallback : ext
    }

    private static func firstCapture(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
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

    private static func cleanTitle(_ raw: String) -> String {
        raw.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmed
            .sanitizedFilename(maxLength: 120)
    }

    private static func jsonObject(from data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NativeDownloadError.invalidGalleryData
        }
        return object
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    private static func tagText(from value: Any?) -> String {
        if let array = value as? [Any] {
            return array.compactMap { item -> String? in
                if let dictionary = item as? [String: Any] {
                    return stringValue(dictionary["title"]) ??
                        stringValue(dictionary["name"]) ??
                        stringValue(dictionary["value"])
                }
                return stringValue(item)
            }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        }
        return stringValue(value) ?? ""
    }

    private static func int64Value(_ value: Any?) -> Int64? {
        if let int = value as? Int { return Int64(int) }
        if let int64 = value as? Int64 { return int64 }
        if let number = value as? NSNumber { return number.int64Value }
        if let string = value as? String { return Int64(string) }
        return nil
    }
}
