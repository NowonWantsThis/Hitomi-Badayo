import Foundation

struct SoundCloudStreamCandidate {
    var endpointURL: URL
    var protocolName: String
    var mimeType: String
    var quality: String
    var abr: Int?
    var score: Int
}

struct SoundCloudResolvedTrack {
    var id: String
    var title: String
    var username: String
    var streamURL: URL
    var webpageURL: URL
    var protocolName: String = ""
    var mimeType: String = ""
    var quality: String = ""
}

final class SoundCloudResolver {
    func canResolve(_ url: URL) -> Bool {
        Self.canonicalPageURL(for: url) != nil
    }

    func resolve(
        _ url: URL,
        headers: HTTPRequestOptions = HTTPRequestOptions(),
        assetLimit: Int? = nil
    ) async throws -> ResolvedDownload {
        guard let normalizedURL = Self.canonicalPageURL(for: url) else {
            throw NativeDownloadError.invalidURL(url.absoluteString)
        }
        let html = try await HTTPClient.shared.string(from: normalizedURL, referer: headers.referer, userAgent: headers.userAgent)
        let clientID = try await clientID(fromHTML: html, pageURL: normalizedURL, headers: headers)
        var tracks = try Self.trackObjects(fromHTML: html)
        var collectionTitle = try Self.collectionTitle(fromHTML: html)

        if tracks.isEmpty {
            let resolved = try await resolveAPIObject(pageURL: normalizedURL, clientID: clientID, headers: headers)
            collectionTitle = collectionTitle ?? Self.collectionTitle(fromResolvedObject: resolved)
            tracks = Self.trackObjects(fromResolvedObject: resolved)
        }

        let discoveredTrackCount = tracks.count
        if let finiteAssetLimit = assetLimit.flatMap({ $0 > 0 ? $0 : nil }) {
            tracks = Array(tracks.prefix(finiteAssetLimit))
        }
        guard !tracks.isEmpty else {
            throw NativeDownloadError.noFiles
        }

        var resolvedTracks: [SoundCloudResolvedTrack] = []
        var firstHLS: (url: URL, candidate: SoundCloudStreamCandidate)?
        for track in tracks {
            try Task.checkCancellation()
            guard let candidate = Self.bestStreamCandidate(fromTrack: track, clientID: clientID, pageURL: normalizedURL) else {
                continue
            }
            let streamURL: URL
            do {
                let streamData = try await HTTPClient.shared.data(
                    from: candidate.endpointURL,
                    referer: normalizedURL.absoluteString,
                    userAgent: headers.userAgent,
                    additionalHeaders: ["Accept": "application/json, text/plain, */*"]
                )
                guard let parsed = try Self.streamURL(fromEndpointData: streamData, pageURL: normalizedURL) else {
                    continue
                }
                streamURL = parsed
            } catch {
                try Task.checkCancellation()
                continue
            }

            if candidate.protocolName.lowercased().contains("hls") {
                if firstHLS == nil { firstHLS = (streamURL, candidate) }
                continue
            }

            resolvedTracks.append(Self.resolvedTrack(fromTrack: track, streamURL: streamURL, candidate: candidate, pageURL: normalizedURL))
        }

        if !resolvedTracks.isEmpty {
            var resolved = try Self.resolvedDownload(
                fromResolvedTracks: resolvedTracks,
                sourceURL: normalizedURL,
                collectionTitle: collectionTitle
            )
            resolved.metadata["discovered_track_count"] = String(discoveredTrackCount)
            resolved.metadata["selected_track_count"] = String(tracks.count)
            resolved.metadata["resolved_track_count"] = String(resolvedTracks.count)
            return resolved
        }

        if tracks.count == 1, let firstHLS {
            let parsed = try await M3U8Resolver().resolve(
                firstHLS.url,
                headers: HTTPRequestOptions(referer: normalizedURL.absoluteString, userAgent: headers.userAgent)
            )
            let info = Self.trackInfo(fromTrack: tracks[0], pageURL: normalizedURL)
            var metadata = Self.soundCloudMetadata(
                username: info.username,
                sourceURL: normalizedURL,
                title: info.displayTitle,
                mediaCount: 1,
                trackID: info.id,
                streamURL: firstHLS.url,
                format: "m3u8",
                protocolName: firstHLS.candidate.protocolName,
                mimeType: firstHLS.candidate.mimeType,
                quality: firstHLS.candidate.quality,
                packageMode: "hls"
            )
            metadata["discovered_track_count"] = String(discoveredTrackCount)
            metadata["selected_track_count"] = String(tracks.count)
            metadata["resolved_track_count"] = "1"
            return ResolvedDownload(
                title: info.displayTitle,
                folderName: "SoundCloud \(info.displayTitle)".sanitizedFilename(maxLength: 120),
                assets: Self.hlsAssetsWithPageMetadata(
                    parsed.assets,
                    trackID: info.id,
                    title: info.displayTitle,
                    username: info.username,
                    webpageURL: info.webpageURL,
                    playlistURL: firstHLS.url,
                    candidate: firstHLS.candidate
                ),
                packageMode: .concatenate(outputFilename: "\(info.displayTitle).ts".sanitizedFilename(maxLength: 180)),
                metadata: metadata
            )
        }

        throw NativeDownloadError.noFiles
    }

    static func resolvedDownload(fromResolvedTracks tracks: [SoundCloudResolvedTrack], sourceURL: URL, collectionTitle: String? = nil) throws -> ResolvedDownload {
        guard !tracks.isEmpty else {
            throw NativeDownloadError.noFiles
        }

        let normalizedSourceURL = canonicalPageURL(for: sourceURL) ?? sourceURL
        let assets = tracks.enumerated().map { offset, track in
            ResolvedAsset(
                remoteURL: track.streamURL,
                filename: filename(for: track, index: offset + 1, total: tracks.count),
                metadata: assetMetadata(for: track, index: offset + 1, total: tracks.count),
                referer: track.webpageURL.absoluteString
            )
        }

        let title = collectionTitle?.sanitizedFilename(maxLength: 120) ??
            (tracks.count == 1 ? tracks[0].title : sourceURL.lastPathComponent.replacingOccurrences(of: "-", with: " ").sanitizedFilename(maxLength: 120))
        let primary = tracks.count == 1 ? tracks[0] : nil
        return ResolvedDownload(
            title: title,
            folderName: "SoundCloud \(title)".sanitizedFilename(maxLength: 120),
            assets: assets,
            metadata: soundCloudMetadata(
                username: tracks.first(where: { !$0.username.isEmpty })?.username,
                collectionTitle: collectionTitle,
                sourceURL: normalizedSourceURL,
                title: title,
                mediaCount: tracks.count,
                trackID: primary?.id,
                streamURL: primary?.streamURL,
                format: primary.map(mediaFormat(for:)) ?? "",
                protocolName: primary?.protocolName ?? "",
                mimeType: primary?.mimeType ?? "",
                quality: primary?.quality ?? "",
                packageMode: "files"
            )
        )
    }

    static func trackObjects(fromHTML html: String) throws -> [[String: Any]] {
        guard let hydration = hydrationJSON(fromHTML: html) else { return [] }
        guard let array = try JSONSerialization.jsonObject(with: hydration) as? [[String: Any]] else { return [] }
        var tracks: [[String: Any]] = []

        for item in array {
            let data = item["data"] as? [String: Any] ?? item
            tracks.append(contentsOf: trackObjects(fromResolvedObject: data))
        }
        return tracks
    }

    static func trackObjects(fromResolvedObject object: [String: Any]) -> [[String: Any]] {
        if hasTranscodings(object) {
            return [object]
        }

        let arrays = [
            object["tracks"] as? [[String: Any]],
            object["collection"] as? [[String: Any]]
        ].compactMap { $0 }

        return arrays.flatMap { values in
            values.flatMap { item -> [[String: Any]] in
                if hasTranscodings(item) { return [item] }
                if let track = item["track"] as? [String: Any], hasTranscodings(track) { return [track] }
                return []
            }
        }
    }

    static func collectionTitle(fromHTML html: String) throws -> String? {
        guard let hydration = hydrationJSON(fromHTML: html),
              let array = try JSONSerialization.jsonObject(with: hydration) as? [[String: Any]] else {
            return nil
        }

        for item in array {
            let data = item["data"] as? [String: Any] ?? item
            if let title = collectionTitle(fromResolvedObject: data) {
                return title
            }
        }
        return nil
    }

    static func collectionTitle(fromResolvedObject object: [String: Any]) -> String? {
        let kind = stringValue(object["kind"])?.lowercased() ?? ""
        let hasTrackList = (object["tracks"] as? [[String: Any]])?.isEmpty == false ||
            (object["collection"] as? [[String: Any]])?.isEmpty == false
        guard hasTrackList || ["playlist", "album", "system-playlist"].contains(kind) else {
            return nil
        }

        let title = cleanTitle(
            stringValue(object["title"]) ??
                stringValue(object["display_name"]) ??
                stringValue(object["permalink"]) ??
                ""
        )
        guard !title.isEmpty else { return nil }

        let user = object["user"] as? [String: Any]
        let username = cleanTitle(stringValue(user?["username"]) ?? stringValue(object["username"]) ?? "")
        return username.isEmpty ? title : "\(username) - \(title)"
    }

    static func bestStreamCandidate(fromTrack track: [String: Any], clientID: String, pageURL: URL) -> SoundCloudStreamCandidate? {
        let transcodings = dictionary(at: ["media"], in: track)?["transcodings"] as? [[String: Any]] ?? []
        let candidates = transcodings.compactMap { candidate(fromTranscoding: $0, clientID: clientID, pageURL: pageURL) }
        let progressive = candidates.filter { !$0.protocolName.lowercased().contains("hls") }
        if let best = progressive.max(by: { $0.score < $1.score }) {
            return best
        }
        return candidates.max(by: { $0.score < $1.score })
    }

    static func clientID(fromHTML html: String) -> String? {
        let patterns = [
            #""client_id"\s*:\s*"([A-Za-z0-9_-]+)""#,
            #""clientId"\s*:\s*"([A-Za-z0-9_-]+)""#,
            #"client_id=([A-Za-z0-9_-]+)"#,
            #"client_id\s*:\s*["']([A-Za-z0-9_-]+)["']"#
        ]

        for pattern in patterns {
            if let value = firstCapture(pattern: pattern, in: html) {
                return value
            }
        }
        return nil
    }

    static func scriptURLs(fromHTML html: String, pageURL: URL) -> [URL] {
        guard let regex = try? NSRegularExpression(
            pattern: #"<script\b[^>]*\bsrc\s*=\s*["']([^"']+)["']"#,
            options: [.caseInsensitive]
        ) else {
            return []
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        return regex.matches(in: html, range: range).compactMap { match in
            guard let capture = Range(match.range(at: 1), in: html) else { return nil }
            let raw = String(html[capture])
            guard raw.contains("sndcdn.") || raw.contains("soundcloud.") else { return nil }
            return absoluteURL(raw, baseURL: pageURL)
        }
    }

    static func streamURL(fromEndpointData data: Data, pageURL: URL) throws -> URL? {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = stringValue(object["url"]) else {
            return nil
        }
        return absoluteURL(raw, baseURL: pageURL)
    }

    static func resolveAPIURL(pageURL: URL, clientID: String) -> URL {
        let pageURL = canonicalPageURL(for: pageURL) ?? pageURL
        var components = URLComponents()
        components.scheme = pageURL.scheme ?? "https"
        components.host = pageURL.host?.lowercased().hasSuffix(".test") == true ? "api-v2.soundcloud.test" : "api-v2.soundcloud.com"
        components.path = "/resolve"
        components.queryItems = [
            URLQueryItem(name: "url", value: pageURL.absoluteString),
            URLQueryItem(name: "client_id", value: clientID)
        ]
        return components.url!
    }

    private func clientID(fromHTML html: String, pageURL: URL, headers: HTTPRequestOptions) async throws -> String {
        if let id = Self.clientID(fromHTML: html) {
            return id
        }

        for scriptURL in Self.scriptURLs(fromHTML: html, pageURL: pageURL) {
            try Task.checkCancellation()
            let script: String
            do {
                script = try await HTTPClient.shared.string(
                    from: scriptURL,
                    referer: pageURL.absoluteString,
                    userAgent: headers.userAgent
                )
            } catch {
                try Task.checkCancellation()
                continue
            }
            if let id = Self.clientID(fromHTML: script) {
                return id
            }
        }

        throw NativeDownloadError.unsupported("Could not find a SoundCloud client id on the page.")
    }

    private func resolveAPIObject(pageURL: URL, clientID: String, headers: HTTPRequestOptions) async throws -> [String: Any] {
        let data = try await HTTPClient.shared.data(
            from: Self.resolveAPIURL(pageURL: pageURL, clientID: clientID),
            referer: pageURL.absoluteString,
            userAgent: headers.userAgent,
            additionalHeaders: ["Accept": "application/json, text/plain, */*"]
        )
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NativeDownloadError.invalidGalleryData
        }
        return object
    }

    private static func candidate(fromTranscoding transcoding: [String: Any], clientID: String, pageURL: URL) -> SoundCloudStreamCandidate? {
        guard let raw = stringValue(transcoding["url"]),
              let endpoint = endpointURL(raw: raw, clientID: clientID, pageURL: pageURL) else {
            return nil
        }
        let format = transcoding["format"] as? [String: Any] ?? [:]
        let protocolName = stringValue(format["protocol"]) ?? ""
        let mimeType = stringValue(format["mime_type"]) ?? stringValue(format["mime"]) ?? ""
        let quality = stringValue(transcoding["quality"]) ?? ""
        let abr = intValue(transcoding["abr"]) ??
            intValue(format["abr"]) ??
            intValue(transcoding["bitrate"]) ??
            intValue(format["bitrate"])
        let score = score(protocolName: protocolName, mimeType: mimeType, quality: quality, abr: abr)
        return SoundCloudStreamCandidate(endpointURL: endpoint, protocolName: protocolName, mimeType: mimeType, quality: quality, abr: abr, score: score)
    }

    private static func endpointURL(raw: String, clientID: String, pageURL: URL) -> URL? {
        guard let endpoint = absoluteURL(raw, baseURL: pageURL) ?? URL(string: raw),
              var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            return nil
        }
        var items = components.queryItems ?? []
        if !items.contains(where: { $0.name == "client_id" }) {
            items.append(URLQueryItem(name: "client_id", value: clientID))
        }
        components.queryItems = items
        return components.url
    }

    private static func resolvedTrack(fromTrack track: [String: Any], streamURL: URL, candidate: SoundCloudStreamCandidate, pageURL: URL) -> SoundCloudResolvedTrack {
        let info = trackInfo(fromTrack: track, pageURL: pageURL)
        return SoundCloudResolvedTrack(
            id: info.id,
            title: info.displayTitle,
            username: info.username,
            streamURL: streamURL,
            webpageURL: info.webpageURL,
            protocolName: candidate.protocolName,
            mimeType: candidate.mimeType,
            quality: candidate.quality
        )
    }

    private static func trackInfo(fromTrack track: [String: Any], pageURL: URL) -> (id: String, title: String, username: String, displayTitle: String, webpageURL: URL) {
        let id = stringValue(track["id"]) ?? pageURL.lastPathComponent
        let title = cleanTitle(stringValue(track["title"]) ?? pageURL.lastPathComponent.replacingOccurrences(of: "-", with: " "))
        let user = track["user"] as? [String: Any]
        let username = cleanTitle(stringValue(user?["username"]) ?? stringValue(track["uploader"]) ?? "")
        let displayTitle = username.isEmpty ? title : "\(username) - \(title)"
        let webpageURL = stringValue(track["permalink_url"]).flatMap(URL.init(string:)) ?? pageURL
        return (id, title, username, displayTitle.sanitizedFilename(maxLength: 120), webpageURL)
    }

    private static func filename(for track: SoundCloudResolvedTrack, index: Int, total: Int) -> String {
        let prefix = total > 1 ? "\(String(format: "%04d", index))-" : ""
        return "\(prefix)\(track.title)-\(track.id).mp3".sanitizedFilename(maxLength: 180)
    }

    private static func soundCloudMetadata(
        username: String?,
        collectionTitle: String? = nil,
        sourceURL: URL? = nil,
        title: String? = nil,
        mediaCount: Int = 0,
        trackID: String? = nil,
        streamURL: URL? = nil,
        format: String = "",
        protocolName: String = "",
        mimeType: String = "",
        quality: String = "",
        packageMode: String = "files"
    ) -> [String: String] {
        let isCollection = collectionTitle != nil || mediaCount > 1
        return DownloadMetadata.clean([
            "site": "SoundCloud",
            "title": title ?? "",
            "type": isCollection ? "playlist" : "track",
            "media_type": "audio",
            "package_mode": packageMode,
            "media_count": mediaCount > 0 ? String(mediaCount) : "",
            "audio_count": mediaCount > 0 ? String(mediaCount) : "",
            "track_count": mediaCount > 0 ? String(mediaCount) : "",
            "id": trackID ?? "",
            "track_id": trackID ?? "",
            "media_id": trackID ?? "",
            "format": format,
            "media_format": format,
            "mime": mimeType,
            "protocol": protocolName,
            "quality": quality,
            "stream_url": streamURL?.absoluteString ?? "",
            "audio_url": streamURL?.absoluteString ?? "",
            "media_url": streamURL?.absoluteString ?? "",
            "source_url": sourceURL?.absoluteString ?? "",
            "page_url": sourceURL?.absoluteString ?? "",
            "artist": username ?? "",
            "author": username ?? "",
            "creator": username ?? "",
            "user": username ?? "",
            "username": username ?? "",
            "uploader": username ?? "",
            "channel": username ?? "",
            "album": collectionTitle ?? "",
            "playlist": collectionTitle ?? "",
            "series": collectionTitle ?? ""
        ])
    }

    private static func assetMetadata(for track: SoundCloudResolvedTrack, index: Int, total: Int) -> [String: String] {
        let format = mediaFormat(for: track)
        return DownloadMetadata.clean([
            "site": "SoundCloud",
            "title": track.title,
            "type": "audio",
            "media_type": "audio",
            "id": track.id,
            "track_id": track.id,
            "media_id": track.id,
            "page": String(index),
            "position": String(index),
            "format": format,
            "media_format": format,
            "mime": track.mimeType,
            "protocol": track.protocolName,
            "quality": track.quality,
            "stream_url": track.streamURL.absoluteString,
            "audio_url": track.streamURL.absoluteString,
            "media_url": track.streamURL.absoluteString,
            "source_url": track.webpageURL.absoluteString,
            "page_url": track.webpageURL.absoluteString,
            "artist": track.username,
            "author": track.username,
            "creator": track.username,
            "user": track.username,
            "username": track.username,
            "uploader": track.username,
            "channel": track.username
        ])
    }

    static func hlsAssetsWithPageMetadata(_ assets: [ResolvedAsset], trackID: String, title: String, username: String, webpageURL: URL, playlistURL: URL, candidate: SoundCloudStreamCandidate) -> [ResolvedAsset] {
        assets.enumerated().map { offset, asset in
            var enriched = asset
            enriched.metadata = asset.metadata.merging(hlsSegmentMetadata(
                trackID: trackID,
                title: title,
                username: username,
                webpageURL: webpageURL,
                playlistURL: playlistURL,
                candidate: candidate,
                asset: asset,
                index: offset + 1
            )) { _, new in new }
            return enriched
        }
    }

    private static func hlsSegmentMetadata(trackID: String, title: String, username: String, webpageURL: URL, playlistURL: URL, candidate: SoundCloudStreamCandidate, asset: ResolvedAsset, index: Int) -> [String: String] {
        let type = asset.metadata["type"] ?? "hls_segment"
        let format = mediaFormat(for: asset.remoteURL, fallback: mediaFormat(forFilename: asset.filename, fallback: "ts"))
        return DownloadMetadata.clean([
            "site": "SoundCloud",
            "title": title,
            "type": type,
            "media_type": type == "hls_segment" ? "segment" : type,
            "category": "audio",
            "id": trackID,
            "track_id": trackID,
            "media_id": "\(trackID)-segment-\(index)",
            "page": String(index),
            "position": String(index),
            "format": format,
            "media_format": format,
            "mime": candidate.mimeType,
            "protocol": candidate.protocolName,
            "quality": candidate.quality,
            "playlist_url": asset.metadata["playlist_url"] ?? playlistURL.absoluteString,
            "stream_url": asset.remoteURL.absoluteString,
            "audio_url": asset.remoteURL.absoluteString,
            "media_url": asset.remoteURL.absoluteString,
            "source_url": webpageURL.absoluteString,
            "page_url": webpageURL.absoluteString,
            "artist": username,
            "author": username,
            "creator": username,
            "user": username,
            "username": username,
            "uploader": username,
            "channel": username
        ])
    }

    private static func mediaFormat(for track: SoundCloudResolvedTrack) -> String {
        let ext = track.streamURL.pathExtension.trimmed.lowercased()
        if !ext.isEmpty { return ext }
        let mime = track.mimeType.lowercased()
        if mime.contains("mpeg") || mime.contains("mp3") { return "mp3" }
        if mime.contains("ogg") { return "ogg" }
        if mime.contains("aac") { return "aac" }
        if track.protocolName.lowercased().contains("hls") { return "m3u8" }
        return ""
    }

    private static func mediaFormat(for url: URL, fallback: String) -> String {
        let ext = url.pathExtension.trimmed.lowercased()
        return ext.isEmpty ? fallback : ext
    }

    private static func mediaFormat(forFilename filename: String, fallback: String) -> String {
        let ext = (filename as NSString).pathExtension.lowercased()
        return ext.isEmpty ? fallback : ext
    }

    private static func hydrationJSON(fromHTML html: String) -> Data? {
        guard let regex = try? NSRegularExpression(
            pattern: #"window\.__sc_hydration\s*=\s*(\[.*?\]);"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return nil
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, range: range),
              let capture = Range(match.range(at: 1), in: html) else {
            return nil
        }
        return String(html[capture]).data(using: .utf8)
    }

    private static func hasTranscodings(_ object: [String: Any]) -> Bool {
        let transcodings = dictionary(at: ["media"], in: object)?["transcodings"] as? [[String: Any]]
        return !(transcodings?.isEmpty ?? true)
    }

    private static func score(protocolName: String, mimeType: String, quality: String, abr: Int?) -> Int {
        var score = 0
        let proto = protocolName.lowercased()
        let mime = mimeType.lowercased()
        let quality = quality.lowercased()
        if !proto.contains("hls") { score += 1_000_000 }
        score += (abr ?? 320) * 1_000
        if mime.contains("mpeg") || mime.contains("mp3") { score += 100 }
        if quality == "hq" { score += 10 }
        if quality == "sq" { score += 1 }
        return score
    }

    static func canonicalPageURL(for url: URL) -> URL? {
        guard let host = url.host?.lowercased(),
              isSoundCloudHost(host),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              !url.path.split(separator: "/").isEmpty,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.scheme = "https"
        components.query = nil
        components.fragment = nil
        let parts = components.path.split(separator: "/", omittingEmptySubsequences: true)
        if parts.count == 1 {
            components.path = "/\(parts[0])/tracks"
        }
        return components.url
    }

    private static func isSoundCloudHost(_ host: String) -> Bool {
        host == "soundcloud.com" ||
            host == "www.soundcloud.com" ||
            host.hasSuffix(".soundcloud.com") ||
            host == "soundcloud.test" ||
            host == "www.soundcloud.test" ||
            host.hasSuffix(".soundcloud.test")
    }

    private static func absoluteURL(_ raw: String, baseURL: URL) -> URL? {
        let value = raw.trimmed
        if value.hasPrefix("//") {
            return URL(string: "\(baseURL.scheme ?? "https"):\(value)")
        }
        return URL(string: value, relativeTo: baseURL)?.absoluteURL
    }

    private static func dictionary(at path: [String], in object: [String: Any]) -> [String: Any]? {
        var current: Any? = object
        for key in path {
            current = (current as? [String: Any])?[key]
        }
        return current as? [String: Any]
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

    private static func stringValue(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String {
            if let int = Int(string.trimmed) { return int }
            return Double(string.trimmed).map(Int.init)
        }
        return nil
    }

    private static func cleanTitle(_ raw: String) -> String {
        raw.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmed
            .sanitizedFilename(maxLength: 120)
    }
}
