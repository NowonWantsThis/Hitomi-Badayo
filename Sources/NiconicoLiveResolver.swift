import Foundation

final class NiconicoLiveResolver {
    private static let defaultUserAgent = "Mozilla/5.0 (Macintosh; Apple Silicon Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
    private let m3u8Resolver: M3U8Resolver
    private let socketFactory: NiconicoLiveWebSocketFactory
    private let sessionRegistry: NiconicoLiveSessionRegistry

    init(
        m3u8Resolver: M3U8Resolver = M3U8Resolver(),
        socketFactory: @escaping NiconicoLiveWebSocketFactory = { URLSessionNiconicoLiveWebSocket(request: $0) },
        sessionRegistry: NiconicoLiveSessionRegistry = .shared
    ) {
        self.m3u8Resolver = m3u8Resolver
        self.socketFactory = socketFactory
        self.sessionRegistry = sessionRegistry
    }

    func canResolve(_ url: URL) -> Bool {
        Self.liveID(from: url) != nil ||
            Self.userID(from: url) != nil ||
            Self.channelID(from: url) != nil
    }

    func stopSession(_ token: String) async {
        await sessionRegistry.stop(token)
    }

    func resolve(
        _ url: URL,
        headers: HTTPRequestOptions = HTTPRequestOptions(),
        preferredResolution: String = ""
    ) async throws -> ResolvedDownload {
        let watchURL: URL
        if let liveID = Self.liveID(from: url) {
            watchURL = Self.liveWatchURL(liveID: liveID, sourceURL: url)
        } else if let userID = Self.userID(from: url) {
            let apiURL = Self.userBroadcastHistoryAPIURL(providerID: userID, sourceURL: url)
            let data = try await HTTPClient.shared.data(
                from: apiURL,
                referer: headers.referer ?? Self.canonicalInputURL(for: url)?.absoluteString ?? url.absoluteString,
                userAgent: headers.userAgent,
                additionalHeaders: ["Accept": "application/json, text/plain, */*"]
            )
            watchURL = try Self.liveWatchURL(fromUserHistoryData: data, sourceURL: url)
        } else if let channelID = Self.channelID(from: url) {
            let pageURL = Self.channelLivePageURL(channelID: channelID, sourceURL: url)
            let html = try await HTTPClient.shared.string(
                from: pageURL,
                referer: headers.referer ?? url.absoluteString,
                userAgent: headers.userAgent
            )
            watchURL = try Self.liveWatchURL(fromChannelHTML: html, sourceURL: pageURL)
        } else {
            throw NativeDownloadError.invalidURL(url.absoluteString)
        }

        let html = try await HTTPClient.shared.string(
            from: watchURL,
            referer: headers.referer ?? url.absoluteString,
            userAgent: headers.userAgent
        )
        if Self.embeddedDataAttribute(in: html) != nil {
            let context = try Self.livePageContext(fromHTML: html, pageURL: watchURL)
            return try await resolvedReliveDownload(
                context: context,
                pageURL: watchURL,
                sourceURL: Self.canonicalInputURL(for: url) ?? url,
                userAgent: headers.userAgent,
                preferredResolution: preferredResolution
            )
        }
        return try await Self.resolvedWatchDownload(
            fromHTML: html,
            pageURL: watchURL,
            sourceURL: Self.canonicalInputURL(for: url) ?? url,
            userAgent: headers.userAgent
        )
    }

    private func resolvedReliveDownload(
        context: NiconicoLivePageContext,
        pageURL: URL,
        sourceURL: URL,
        userAgent: String?,
        preferredResolution: String
    ) async throws -> ResolvedDownload {
        guard let liveID = Self.liveID(from: pageURL) else {
            throw NativeDownloadError.invalidURL(pageURL.absoluteString)
        }
        let canonicalPageURL = Self.liveWatchURL(liveID: liveID, sourceURL: pageURL)
        let actualUserAgent = userAgent?.trimmed.isEmpty == false ? userAgent!.trimmed : Self.defaultUserAgent
        let webSocketURL = try Self.webSocketURL(
            from: context.webSocketURL,
            frontendID: context.frontendID
        )
        var cookieLookup = URLComponents(url: webSocketURL, resolvingAgainstBaseURL: false)
        cookieLookup?.scheme = "https"
        let webSocketCookie: String?
        if let cookieURL = cookieLookup?.url {
            webSocketCookie = await CookieStore.shared.cookieHeader(for: cookieURL)
        } else {
            webSocketCookie = nil
        }
        let seat = NiconicoLiveSeatSession(
            webSocketURL: webSocketURL,
            userAgent: actualUserAgent,
            cookieHeader: webSocketCookie,
            maximumQuality: context.maximumQuality,
            socketFactory: socketFactory
        )
        let handshake = try await seat.start()
        let token = await sessionRegistry.register(seat)

        do {
            let cookieHeader = handshake.cookieHeader
            var streamHeaders: [String: String] = [:]
            if !cookieHeader.isEmpty {
                streamHeaders["Cookie"] = cookieHeader
            }
            let master = try await HTTPClient.shared.string(
                from: handshake.masterPlaylistURL,
                referer: canonicalPageURL.absoluteString,
                userAgent: actualUserAgent,
                additionalHeaders: streamHeaders
            )
            guard master.contains("#EXTM3U") else {
                throw NativeDownloadError.invalidPlaylist
            }

            let alternate = m3u8Resolver.alternateAudioSelection(
                in: master,
                baseURL: handshake.masterPlaylistURL,
                preferredResolution: preferredResolution
            )
            let videoURL: URL
            let audioURL: URL?
            let width: Int
            let height: Int
            let bandwidth: Int
            let audioGroup: String
            if let alternate {
                videoURL = alternate.videoURL
                audioURL = alternate.audioURL
                width = alternate.width
                height = alternate.height
                bandwidth = alternate.bandwidth
                audioGroup = alternate.audioGroup
            } else {
                videoURL = try m3u8Resolver.bestVariant(
                    in: master,
                    baseURL: handshake.masterPlaylistURL,
                    preferredResolution: preferredResolution
                ) ?? handshake.masterPlaylistURL
                audioURL = nil
                width = 0
                height = 0
                bandwidth = 0
                audioGroup = ""
            }

            let title = (context.title.trimmed.isEmpty ? liveID : context.title.trimmed)
                .sanitizedFilename(maxLength: 150)
            let outputFilename = "\(title)-\(liveID).mp4".sanitizedFilename()
            let videoAsset = Self.livePlaylistAsset(
                url: videoURL,
                filename: "\(liveID)-video.m3u8",
                mediaType: "video",
                pageURL: canonicalPageURL,
                userAgent: actualUserAgent,
                streamHeaders: streamHeaders
            )
            let audioAsset = audioURL.map {
                Self.livePlaylistAsset(
                    url: $0,
                    filename: "\(liveID)-audio.m3u8",
                    mediaType: "audio",
                    pageURL: canonicalPageURL,
                    userAgent: actualUserAgent,
                    streamHeaders: streamHeaders
                )
            }
            let assets = [videoAsset] + [audioAsset].compactMap { $0 }
            let metadata = DownloadMetadata.clean([
                "site": "niconico_live",
                "host": canonicalPageURL.host ?? "live.nicovideo.jp",
                "handler": "native",
                "delivery_api": "relive",
                "type": "hls",
                "media_type": "hls",
                "format": "m3u8",
                "media_format": "m3u8",
                "package_mode": audioAsset == nil ? "live_hls" : "live_hls_mux",
                "live": "true",
                "is_live": "true",
                "was_live": "true",
                "live_active": "true",
                "live_id": liveID,
                "id": liveID,
                "title": title,
                "series": context.channelName.isEmpty ? title : context.channelName,
                "description": context.description,
                "uploader": context.uploader,
                "channel": context.channelName,
                "channel_id": context.channelID,
                "channel_url": context.channelURL,
                "thumbnail": context.thumbnailURL,
                "date": context.date,
                "upload_date": context.uploadDate,
                "timestamp": context.openTimestamp,
                "view_count": context.viewCount,
                "comment_count": context.commentCount,
                "status": context.status,
                "max_quality": context.maximumQuality,
                "available_qualities": handshake.availableQualities.joined(separator: ","),
                "playlist_url": handshake.masterPlaylistURL.absoluteString,
                "manifest_url": handshake.masterPlaylistURL.absoluteString,
                "video_playlist_url": videoURL.absoluteString,
                "audio_playlist_url": audioURL?.absoluteString ?? "",
                "audio_group": audioGroup,
                "width": width > 0 ? String(width) : "",
                "height": height > 0 ? String(height) : "",
                "resolution": height > 0 ? "\(height)p" : "",
                "bandwidth": bandwidth > 0 ? String(bandwidth) : "",
                "media_count": String(assets.count),
                "video_count": "1",
                "audio_count": audioAsset == nil ? "0" : "1",
                "url": canonicalPageURL.absoluteString,
                "live_url": canonicalPageURL.absoluteString,
                "page_url": canonicalPageURL.absoluteString,
                "source_url": sourceURL.absoluteString,
                "source_input_url": sourceURL.absoluteString,
                "live_output_filename": outputFilename,
                "niconico_live_session_token": token
            ])
            let packageMode: DownloadPackageMode
            if let audioAsset {
                packageMode = .mux(
                    videoAssets: [videoAsset],
                    audioAssets: [audioAsset],
                    outputFilename: outputFilename
                )
            } else {
                packageMode = .concatenate(outputFilename: outputFilename)
            }
            return ResolvedDownload(
                title: title,
                folderName: "\(title) (\(liveID))".sanitizedFilename(),
                assets: assets,
                packageMode: packageMode,
                metadata: metadata
            )
        } catch {
            await sessionRegistry.stop(token)
            throw error
        }
    }

    private static func livePlaylistAsset(
        url: URL,
        filename: String,
        mediaType: String,
        pageURL: URL,
        userAgent: String,
        streamHeaders: [String: String]
    ) -> ResolvedAsset {
        let headers = streamHeaders.sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
            .map { ResolvedRequestHeader(name: $0.key, value: $0.value) }
        return ResolvedAsset(
            remoteURL: url,
            filename: filename.sanitizedFilename(),
            metadata: DownloadMetadata.clean([
                "type": "hls_live_playlist",
                "media_type": mediaType,
                "format": "m3u8",
                "media_format": "m3u8",
                "playlist_url": url.absoluteString,
                "media_url": url.absoluteString,
                "page_url": pageURL.absoluteString,
                "live": "true",
                "is_live": "true"
            ]),
            referer: pageURL.absoluteString,
            userAgent: userAgent,
            additionalHeaders: headers
        )
    }

    static func canonicalInputURL(for url: URL) -> URL? {
        if let liveID = liveID(from: url) {
            return liveWatchURL(liveID: liveID, sourceURL: url)
        }
        if let userID = userID(from: url) {
            var components = URLComponents()
            components.scheme = "https"
            components.host = isTestHost(url.host) ? "www.nicovideo.test" : "www.nicovideo.jp"
            components.path = "/user/\(userID)"
            return components.url
        }
        if let channelID = channelID(from: url) {
            return channelLivePageURL(channelID: channelID, sourceURL: url)
        }
        return nil
    }

    static func livePageContext(fromHTML html: String, pageURL: URL) throws -> NiconicoLivePageContext {
        guard let raw = embeddedDataAttribute(in: html) else {
            throw NativeDownloadError.unsupported("Niconico Live playback data was not found.")
        }
        let decoded = decodeHTML(raw)
        guard let data = decoded.data(using: .utf8),
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let site = root["site"] as? [String: Any],
              let relive = site["relive"] as? [String: Any],
              let rawWebSocketURL = string(relive["webSocketUrl"]),
              let parsedWebSocketURL = URL(string: rawWebSocketURL),
              let socketScheme = parsedWebSocketURL.scheme?.lowercased(),
              socketScheme == "ws" || socketScheme == "wss" else {
            throw NativeDownloadError.unsupported(
                "This Niconico Live program is not currently available for playback."
            )
        }

        let program = root["program"] as? [String: Any] ?? [:]
        let stream = program["stream"] as? [String: Any] ?? [:]
        let supplier = program["supplier"] as? [String: Any] ?? [:]
        let statistics = program["statistics"] as? [String: Any] ?? [:]
        let socialGroup = root["socialGroup"] as? [String: Any] ?? [:]
        let timestamp = integer(program["openTime"])
        let dates = dateStrings(timestamp: timestamp)
        let title = string(program["title"])
            ?? firstMetaContent(named: ["og:title", "twitter:title"], in: html)
            ?? liveID(from: pageURL)
            ?? "Niconico Live"
        let thumbnail = bestThumbnailURL(in: program["thumbnail"])
            ?? firstMetaContent(named: ["og:image", "twitter:image"], in: html)
            ?? ""

        return NiconicoLivePageContext(
            frontendID: string(site["frontendId"]) ?? "9",
            webSocketURL: parsedWebSocketURL,
            title: cleanHTMLText(title),
            description: cleanHTMLText(string(program["description"]) ?? ""),
            status: string(program["status"]) ?? "",
            maximumQuality: string(stream["maxQuality"]) ?? "normal",
            openTimestamp: timestamp.map(String.init) ?? "",
            date: dates.date,
            uploadDate: dates.uploadDate,
            uploader: cleanHTMLText(string(supplier["name"]) ?? ""),
            channelName: cleanHTMLText(string(socialGroup["name"]) ?? ""),
            channelID: string(socialGroup["id"]) ?? "",
            channelURL: string(socialGroup["socialGroupPageUrl"]) ?? "",
            thumbnailURL: thumbnail,
            viewCount: string(statistics["watchCount"]) ?? "",
            commentCount: string(statistics["commentCount"]) ?? ""
        )
    }

    static func webSocketURL(from rawURL: URL, frontendID: String) throws -> URL {
        guard var components = URLComponents(url: rawURL, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              scheme == "ws" || scheme == "wss" else {
            throw NativeDownloadError.unsupported("Niconico Live returned an invalid WebSocket URL.")
        }
        var items = components.queryItems ?? []
        items.removeAll { $0.name.caseInsensitiveCompare("frontend_id") == .orderedSame }
        items.append(URLQueryItem(name: "frontend_id", value: frontendID.trimmed.isEmpty ? "9" : frontendID.trimmed))
        components.queryItems = items
        guard let url = components.url else {
            throw NativeDownloadError.unsupported("Niconico Live returned an invalid WebSocket URL.")
        }
        return url
    }

    static func embeddedDataAttribute(in html: String) -> String? {
        firstCapture(
            pattern: #"<script\b[^>]*\bid\s*=\s*(?:\"embedded-data\"|'embedded-data')[^>]*\bdata-props\s*=\s*(?:\"([^\"]+)\"|'([^']+)')[^>]*>"#,
            in: html,
            groups: [1, 2]
        )
    }

    private static func firstMetaContent(named names: [String], in html: String) -> String? {
        for name in names {
            let escaped = NSRegularExpression.escapedPattern(for: name)
            let patterns = [
                #"<meta\b[^>]*(?:property|name)\s*=\s*[\"']\#(escaped)[\"'][^>]*content\s*=\s*[\"']([^\"']+)[\"'][^>]*>"#,
                #"<meta\b[^>]*content\s*=\s*[\"']([^\"']+)[\"'][^>]*(?:property|name)\s*=\s*[\"']\#(escaped)[\"'][^>]*>"#
            ]
            for pattern in patterns {
                if let value = firstCapture(pattern: pattern, in: html) {
                    return decodeHTML(value).trimmed
                }
            }
        }
        return nil
    }

    private static func bestThumbnailURL(in value: Any?) -> String? {
        let urls = recursiveStrings(in: value as Any).filter { raw in
            guard let url = URL(string: raw),
                  let scheme = url.scheme?.lowercased() else { return false }
            return scheme == "http" || scheme == "https"
        }
        return urls.max { thumbnailScore($0) < thumbnailScore($1) }
    }

    private static func thumbnailScore(_ value: String) -> Int {
        var score = value.count
        let lower = value.lowercased()
        if lower.contains("large") || lower.contains("original") { score += 1_000_000 }
        if lower.contains("small") || lower.contains("64x64") { score -= 500_000 }
        if let regex = try? NSRegularExpression(pattern: #"([0-9]{2,5})x([0-9]{2,5})"#),
           let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..<value.endIndex, in: value)),
           match.numberOfRanges > 2,
           let widthRange = Range(match.range(at: 1), in: value),
           let heightRange = Range(match.range(at: 2), in: value),
           let width = Int(value[widthRange]),
           let height = Int(value[heightRange]) {
            score += min(width * height, 900_000)
        }
        return score
    }

    private static func cleanHTMLText(_ raw: String) -> String {
        let withBreaks = raw.replacingOccurrences(
            of: #"<(?:br\s*/?|/p|/div|/li)>"#,
            with: "\n",
            options: [.regularExpression, .caseInsensitive]
        )
        return decodeHTML(
            withBreaks.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        )
        .replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
        .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        .trimmed
    }

    private static func string(_ value: Any?) -> String? {
        if let string = value as? String {
            let trimmed = string.trimmed
            return trimmed.isEmpty ? nil : trimmed
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return nil
    }

    private static func integer(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string.trimmed) }
        return nil
    }

    private static func dateStrings(timestamp: Int?) -> (date: String, uploadDate: String) {
        guard let timestamp, timestamp > 0 else { return ("", "") }
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        let display = formatter.string(from: date)
        formatter.dateFormat = "yyyyMMdd"
        return (display, formatter.string(from: date))
    }

    static func resolvedWatchDownload(fromHTML html: String, pageURL: URL, sourceURL: URL? = nil, userAgent: String? = nil) async throws -> ResolvedDownload {
        guard let liveID = liveID(from: pageURL) else {
            throw NativeDownloadError.invalidURL(pageURL.absoluteString)
        }
        let canonicalPageURL = liveWatchURL(liveID: liveID, sourceURL: pageURL)
        let sourceURL = sourceURL ?? canonicalPageURL
        let resolved = try await EtcVideoPageResolver.resolvedDownload(
            fromHTML: html,
            pageURL: canonicalPageURL,
            site: .niconicoLive,
            contentID: liveID,
            userAgent: userAgent
        )
        return enrichedDownload(resolved, liveID: liveID, pageURL: canonicalPageURL, sourceURL: sourceURL)
    }

    private static func enrichedDownload(_ resolved: ResolvedDownload, liveID: String, pageURL: URL, sourceURL: URL) -> ResolvedDownload {
        let assets = resolved.assets.enumerated().map { offset, asset in
            var enriched = asset
            let position = String(offset + 1)
            let ext = asset.remoteURL.pathExtension.trimmed.lowercased()
            let format = ext == "jpeg" ? "jpg" : ext
            enriched.metadata = asset.metadata.merging(DownloadMetadata.clean([
                "live_id": liveID,
                "live_url": pageURL.absoluteString,
                "page": asset.metadata["page"] ?? position,
                "position": asset.metadata["position"] ?? position,
                "format": asset.metadata["format"] ?? format,
                "media_format": asset.metadata["media_format"] ?? format,
                "page_url": asset.metadata["page_url"] ?? pageURL.absoluteString,
                "source_input_url": sourceURL.absoluteString
            ])) { current, _ in current }
            return enriched
        }
        let primaryFormat = assets.first?.metadata["format"] ?? resolved.metadata["format"] ?? ""
        let primaryMediaFormat = assets.first?.metadata["media_format"] ?? resolved.metadata["media_format"] ?? primaryFormat
        let metadata = resolved.metadata.merging(DownloadMetadata.clean([
            "live_id": liveID,
            "live_url": pageURL.absoluteString,
            "url": pageURL.absoluteString,
            "source_url": sourceURL.absoluteString,
            "page_url": pageURL.absoluteString,
            "media_count": resolved.metadata["media_count"] ?? String(resolved.assets.count),
            "video_count": resolved.metadata["video_count"] ?? "1",
            "format": resolved.metadata["format"] ?? primaryFormat,
            "media_format": resolved.metadata["media_format"] ?? primaryMediaFormat
        ])) { _, new in new }
        return ResolvedDownload(
            title: resolved.title,
            folderName: resolved.folderName,
            assets: assets,
            packageMode: resolved.packageMode,
            metadata: metadata
        )
    }

    static func userBroadcastHistoryAPIURL(providerID: String, sourceURL: URL) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = isTestHost(sourceURL.host) ? "live.nicovideo.test" : "live.nicovideo.jp"
        components.path = "/front/api/v1/user-broadcast-history"
        components.queryItems = [
            URLQueryItem(name: "providerId", value: providerID),
            URLQueryItem(name: "providerType", value: "user"),
            URLQueryItem(name: "isIncludeNonPublic", value: "false"),
            URLQueryItem(name: "offset", value: "0"),
            URLQueryItem(name: "limit", value: "100"),
            URLQueryItem(name: "withTotalCount", value: "true")
        ]
        return components.url!
    }

    static func channelLivePageURL(channelID: String, sourceURL: URL) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = isTestHost(sourceURL.host) ? "ch.nicovideo.test" : "ch.nicovideo.jp"
        components.path = "/\(channelID)/live"
        return components.url!
    }

    static func liveWatchURL(liveID: String, sourceURL: URL) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = isTestHost(sourceURL.host) ? "live.nicovideo.test" : "live.nicovideo.jp"
        components.path = "/watch/\(liveID)"
        return components.url!
    }

    static func liveID(from url: URL) -> String? {
        guard let host = url.host?.lowercased(),
              isLiveHost(host),
              isWebScheme(url) else {
            return nil
        }
        let parts = pathParts(from: url)
        guard parts.count >= 2,
              parts[0].lowercased() == "watch",
              isLiveID(parts[1]) else {
            return nil
        }
        return parts[1]
    }

    static func userID(from url: URL) -> String? {
        guard let host = url.host?.lowercased(),
              isUserHost(host),
              isWebScheme(url) else {
            return nil
        }
        let parts = pathParts(from: url)
        guard let index = parts.firstIndex(where: { $0.lowercased() == "user" }),
              index + 1 < parts.count else {
            return nil
        }
        let value = parts[index + 1].trimmed
        guard value.range(of: #"^[0-9]+$"#, options: .regularExpression) != nil else {
            return nil
        }
        return value
    }

    static func channelID(from url: URL) -> String? {
        guard let host = url.host?.lowercased(),
              isChannelHost(host),
              isWebScheme(url) else {
            return nil
        }
        let parts = pathParts(from: url)
        guard let first = parts.first?.trimmed,
              first.range(of: #"^[A-Za-z0-9][A-Za-z0-9_-]*$"#, options: .regularExpression) != nil else {
            return nil
        }
        return first
    }

    static func liveWatchURL(fromUserHistoryData data: Data, sourceURL: URL) throws -> URL {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let liveID = firstOnAirLiveID(in: object) else {
            throw NativeDownloadError.unsupported("No on-air Niconico Live program was found.")
        }
        return liveWatchURL(liveID: liveID, sourceURL: sourceURL)
    }

    static func liveWatchURL(fromChannelHTML html: String, sourceURL: URL) throws -> URL {
        let anchors = allCaptures(pattern: #"<a\b[^>]*\bhref\s*=\s*(?:"([^"]+)"|'([^']+)'|([^\s>"']+))[^>]*>"#, in: html, groups: [1, 2, 3])
        let preferred = anchors.first { $0.tag.lowercased().contains("live_now") && liveID(in: $0.href) != nil }
        let fallback = preferred ?? anchors.first { liveID(in: $0.href) != nil }
        guard let href = fallback?.href,
              let liveID = liveID(in: href) else {
            throw NativeDownloadError.unsupported("No active Niconico channel live program was found.")
        }
        return liveWatchURL(liveID: liveID, sourceURL: sourceURL)
    }

    private static func firstOnAirLiveID(in value: Any) -> String? {
        if let dict = value as? [String: Any] {
            if dictionaryLooksOnAir(dict),
               let id = directLiveID(in: dict) {
                return id
            }
            for child in dict.values {
                if let found = firstOnAirLiveID(in: child) {
                    return found
                }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let found = firstOnAirLiveID(in: child) {
                    return found
                }
            }
        }
        return nil
    }

    private static func directLiveID(in dict: [String: Any]) -> String? {
        for key in ["nicoliveProgramId", "nicoliveProgramID", "programId", "programID", "contentId", "id"] {
            if let string = dict[key] as? String,
               let id = liveID(in: string) {
                return id
            }
        }
        if let program = dict["program"] as? [String: Any],
           let id = directLiveID(in: program) {
            return id
        }
        return nil
    }

    private static func dictionaryLooksOnAir(_ dict: [String: Any]) -> Bool {
        recursiveStrings(in: dict).contains { value in
            let normalized = value
                .replacingOccurrences(of: "-", with: "_")
                .uppercased()
            return normalized == "ON_AIR" || normalized == "LIVE_NOW"
        }
    }

    private static func recursiveStrings(in value: Any) -> [String] {
        if let string = value as? String {
            return [string]
        }
        if let number = value as? NSNumber {
            return [number.stringValue]
        }
        if let dict = value as? [String: Any] {
            return dict.values.flatMap { recursiveStrings(in: $0) }
        }
        if let array = value as? [Any] {
            return array.flatMap { recursiveStrings(in: $0) }
        }
        return []
    }

    private static func liveID(in text: String) -> String? {
        firstCapture(pattern: #"(lv[0-9]+)"#, in: decodeHTML(text))?.lowercased()
    }

    private static func pathParts(from url: URL) -> [String] {
        url.path.split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
    }

    private static func isWebScheme(_ url: URL) -> Bool {
        let scheme = url.scheme?.lowercased()
        return scheme == "http" || scheme == "https"
    }

    private static func isLiveID(_ value: String) -> Bool {
        value.range(of: #"^lv[0-9]+$"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func isLiveHost(_ host: String) -> Bool {
        host == "live.nicovideo.jp" ||
            host == "live2.nicovideo.jp" ||
            host == "live.nicovideo.test" ||
            host == "live2.nicovideo.test"
    }

    private static func isUserHost(_ host: String) -> Bool {
        host == "nicovideo.jp" ||
            host == "www.nicovideo.jp" ||
            host == "sp.nicovideo.jp" ||
            host == "niconico.com" ||
            host == "www.niconico.com" ||
            host == "nicovideo.test" ||
            host == "www.nicovideo.test" ||
            host == "sp.nicovideo.test" ||
            host == "niconico.test" ||
            host == "www.niconico.test"
    }

    private static func isChannelHost(_ host: String) -> Bool {
        host == "ch.nicovideo.jp" ||
            host == "ch.nicovideo.test"
    }

    private static func isTestHost(_ host: String?) -> Bool {
        host?.lowercased().hasSuffix(".test") == true
    }

    private static func decodeHTML(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#34;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }

    private static func firstCapture(pattern: String, in text: String) -> String? {
        firstCapture(pattern: pattern, in: text, groups: [1])
    }

    private static func firstCapture(pattern: String, in text: String, groups: [Int]) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range) else {
            return nil
        }
        for group in groups {
            guard match.numberOfRanges > group,
                  let capture = Range(match.range(at: group), in: text) else {
                continue
            }
            return String(text[capture])
        }
        return nil
    }

    private static func allCaptures(pattern: String, in text: String, groups: [Int]) -> [(tag: String, href: String)] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let tagRange = Range(match.range(at: 0), in: text) else { return nil }
            for group in groups {
                guard match.numberOfRanges > group,
                      let capture = Range(match.range(at: group), in: text) else {
                    continue
                }
                return (String(text[tagRange]), decodeHTML(String(text[capture])).trimmed)
            }
            return nil
        }
    }
}

struct NiconicoLivePageContext: Equatable, Sendable {
    let frontendID: String
    let webSocketURL: URL
    let title: String
    let description: String
    let status: String
    let maximumQuality: String
    let openTimestamp: String
    let date: String
    let uploadDate: String
    let uploader: String
    let channelName: String
    let channelID: String
    let channelURL: String
    let thumbnailURL: String
    let viewCount: String
    let commentCount: String
}
