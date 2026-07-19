import Foundation

final class VimeoResolver {
    func canResolve(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(),
              Self.isVimeoHost(host),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return false
        }
        return Self.videoID(from: url) != nil
    }

    func resolve(_ url: URL, headers: HTTPRequestOptions = HTTPRequestOptions()) async throws -> ResolvedDownload {
        guard let id = Self.videoID(from: url) else {
            throw NativeDownloadError.invalidURL(url.absoluteString)
        }

        let configURL: URL
        if url.host?.lowercased() == "player.vimeo.com", url.path.lowercased().hasSuffix("/config") {
            configURL = url
        } else {
            let html = try await HTTPClient.shared.string(from: url, referer: headers.referer, userAgent: headers.userAgent)
            configURL = Self.configURL(fromHTML: html, pageURL: url) ?? Self.playerConfigURL(id: id, sourceURL: url)
        }

        let data = try await HTTPClient.shared.data(
            from: configURL,
            referer: headers.referer ?? url.absoluteString,
            userAgent: headers.userAgent,
            additionalHeaders: ["Accept": "application/json, text/plain, */*"]
        )

        if let resolved = try await Self.resolvedDownload(
            fromConfigData: data,
            pageURL: url,
            userAgent: headers.userAgent
        ) {
            return resolved
        }

        throw NativeDownloadError.noFiles
    }

    static func resolvedDownload(
        fromConfigData data: Data,
        pageURL: URL,
        userAgent: String? = nil
    ) async throws -> ResolvedDownload? {
        let object = try jsonObject(from: data)
        let info = fullVideoInfo(from: object, pageURL: pageURL)

        if let selection = improvedFormatSelection(in: object, pageURL: pageURL) {
            return try await download(
                video: selection.video,
                audio: selection.audio,
                info: info,
                pageURL: pageURL,
                userAgent: userAgent
            )
        }

        let playlistURL = hlsURL(from: object, pageURL: pageURL)
        if let playlistURL,
           let alternate = try? await M3U8Resolver().resolveAlternateAudioMux(
               playlistURL,
               titleHint: info.title,
               outputFilename: outputFilename(info: info, extension: "mp4"),
               headers: HTTPRequestOptions(referer: pageURL.absoluteString, userAgent: userAgent)
           ) {
            return alternateAudioDownload(
                alternate,
                playlistURL: playlistURL,
                info: info,
                pageURL: pageURL
            )
        }

        if let candidate = bestProgressiveCandidate(in: object, pageURL: pageURL) {
            return directDownload(
                candidate: candidate,
                info: info,
                pageURL: pageURL,
                userAgent: userAgent
            )
        }

        guard let playlistURL else {
            return nil
        }
        let candidate = MediaCandidate(
            url: playlistURL,
            width: 0,
            height: 0,
            quality: "",
            mime: "application/vnd.apple.mpegurl",
            formatID: "hls",
            protocolName: "m3u8_native",
            vbr: 1,
            abr: 1,
            contentLength: 0,
            sourceOrder: 0
        )
        return try await download(
            video: candidate,
            audio: nil,
            info: info,
            pageURL: pageURL,
            userAgent: userAgent
        )
    }

    static func progressiveDownload(fromConfigData data: Data, pageURL: URL) throws -> ResolvedDownload? {
        let object = try jsonObject(from: data)
        let info = fullVideoInfo(from: object, pageURL: pageURL)
        guard let candidate = bestProgressiveCandidate(in: object, pageURL: pageURL) else {
            return nil
        }
        return directDownload(candidate: candidate, info: info, pageURL: pageURL, userAgent: nil)
    }

    static func hlsURL(fromConfigData data: Data, pageURL: URL) throws -> URL? {
        let object = try jsonObject(from: data)
        return hlsURL(from: object, pageURL: pageURL)
    }

    static func videoInfo(fromConfigData data: Data, pageURL: URL) throws -> (id: String, title: String, folderTitle: String, uploader: String) {
        let info = fullVideoInfo(from: try jsonObject(from: data), pageURL: pageURL)
        return (info.id, info.title, info.folderTitle, info.uploader)
    }

    static func configURL(fromHTML html: String, pageURL: URL) -> URL? {
        let decoded = decodeHTML(normalizeEscapes(html))
        let patterns = [
            #""config_url"\s*:\s*"([^"]+)""#,
            #""configUrl"\s*:\s*"([^"]+)""#,
            #"\bdata-config-url\s*=\s*["']([^"']+)["']"#,
            #"\bconfig_url\s*=\s*["']([^"']+)["']"#
        ]

        for pattern in patterns {
            guard let raw = firstCapture(pattern: pattern, in: decoded) else { continue }
            let normalized = normalizeEscapes(decodeHTML(raw))
            if let remote = absoluteURL(normalized, baseURL: pageURL) {
                return remote
            }
        }
        return nil
    }

    static func playerConfigURL(id: String, sourceURL: URL) -> URL {
        var components = URLComponents()
        components.scheme = sourceURL.scheme ?? "https"
        components.host = sourceURL.host?.lowercased().hasSuffix(".test") == true ? "player.vimeo.test" : "player.vimeo.com"
        components.path = "/video/\(id)/config"
        return components.url!
    }

    static func canonicalURL(for url: URL) -> URL? {
        guard let host = url.host?.lowercased(),
              isVimeoHost(host),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let id = videoID(from: url) else {
            return nil
        }
        var components = URLComponents()
        components.scheme = url.scheme ?? "https"
        components.host = host.hasSuffix(".test") ? "vimeo.test" : "vimeo.com"
        components.path = "/\(id)"
        return components.url
    }

    static func videoID(from url: URL) -> String? {
        let parts = url.path.split(separator: "/").map(String.init)
        if let videoIndex = parts.firstIndex(where: { $0.lowercased() == "video" }),
           videoIndex + 1 < parts.count,
           isNumericID(parts[videoIndex + 1]) {
            return parts[videoIndex + 1]
        }

        for part in parts.reversed() {
            let clean = part.removingPercentEncoding ?? part
            if isNumericID(clean) {
                return clean
            }
        }
        return nil
    }

    private struct VideoInfo {
        var id: String
        var title: String
        var folderTitle: String
        var uploader: String
        var thumbnail: URL?
    }

    private struct MediaCandidate {
        var url: URL
        var width: Int64
        var height: Int64
        var quality: String
        var mime: String
        var formatID: String
        var protocolName: String
        var vbr: Int64
        var abr: Int64
        var contentLength: Int64
        var sourceOrder: Int

        var isDirect: Bool {
            let value = protocolName.lowercased()
            if !value.isEmpty {
                return value == "http" || value == "https"
            }
            let scheme = url.scheme?.lowercased() ?? ""
            return scheme == "http" || scheme == "https"
        }
    }

    private static func improvedFormatSelection(
        in object: [String: Any],
        pageURL: URL
    ) -> (video: MediaCandidate, audio: MediaCandidate?)? {
        let candidates = improvedFormatCandidates(in: object, pageURL: pageURL)
        let videos = candidates
            .filter { $0.vbr != 0 }
            .sorted {
                if $0.width != $1.width { return $0.width > $1.width }
                return $0.sourceOrder < $1.sourceOrder
            }
        guard let video = videos.first else { return nil }
        let audio = video.abr == 0 ? candidates.last(where: { $0.vbr == 0 }) : nil
        return (video, audio)
    }

    private static func improvedFormatCandidates(in object: [String: Any], pageURL: URL) -> [MediaCandidate] {
        let containers: [[String: Any]] = [
            object,
            object["info"] as? [String: Any],
            object["video"] as? [String: Any]
        ].compactMap { $0 }
        guard let formats = containers.compactMap({ $0["formats"] as? [[String: Any]] }).first else {
            return []
        }
        return formats.enumerated().compactMap { offset, format in
            formatCandidate(from: format, pageURL: pageURL, sourceOrder: offset)
        }
    }

    private static func formatCandidate(
        from object: [String: Any],
        pageURL: URL,
        sourceOrder: Int
    ) -> MediaCandidate? {
        guard let raw = stringValue(object["url"]),
              let url = absoluteURL(raw, baseURL: pageURL) else {
            return nil
        }
        let resolution = stringValue(object["resolution"]) ?? ""
        let quality = stringValue(object["format"]) ??
            stringValue(object["format_note"]) ??
            stringValue(object["quality"]) ??
            resolution
        return MediaCandidate(
            url: url,
            width: int64Value(object["width"]) ?? 0,
            height: int64Value(object["height"]) ?? 0,
            quality: quality,
            mime: stringValue(object["mime_type"]) ?? stringValue(object["mime"]) ?? stringValue(object["type"]) ?? "",
            formatID: stringValue(object["format_id"]) ?? stringValue(object["id"]) ?? String(sourceOrder),
            protocolName: stringValue(object["protocol"])?.lowercased() ?? url.scheme?.lowercased() ?? "",
            vbr: int64Value(object["vbr"]) ?? 0,
            abr: int64Value(object["abr"]) ?? 0,
            contentLength: int64Value(object["filesize"]) ?? int64Value(object["filesize_approx"]) ?? 0,
            sourceOrder: sourceOrder
        )
    }

    private static func bestProgressiveCandidate(in object: [String: Any], pageURL: URL) -> MediaCandidate? {
        progressiveCandidates(in: object, pageURL: pageURL).sorted {
            if $0.width != $1.width { return $0.width > $1.width }
            return $0.sourceOrder < $1.sourceOrder
        }.first
    }

    private static func progressiveCandidates(in object: [String: Any], pageURL: URL) -> [MediaCandidate] {
        var candidates: [MediaCandidate] = []
        let groups = [
            dictionary(at: ["request", "files"], in: object)?["progressive"] as? [[String: Any]],
            dictionary(at: ["video", "files"], in: object)?["progressive"] as? [[String: Any]],
            object["progressive"] as? [[String: Any]]
        ]
        for group in groups.compactMap({ $0 }) {
            for item in group {
                if let candidate = progressiveCandidate(
                    from: item,
                    pageURL: pageURL,
                    sourceOrder: candidates.count
                ) {
                    candidates.append(candidate)
                }
            }
        }
        return candidates
    }

    private static func progressiveCandidate(
        from object: [String: Any],
        pageURL: URL,
        sourceOrder: Int
    ) -> MediaCandidate? {
        if let protocolValue = stringValue(object["protocol"])?.lowercased(),
           !["http", "https"].contains(protocolValue) {
            return nil
        }
        guard let raw = stringValue(object["url"]),
              let url = absoluteURL(raw, baseURL: pageURL),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            return nil
        }
        let height = int64Value(object["height"]) ?? 0
        let quality = stringValue(object["quality"]) ?? stringValue(object["rendition"]) ?? ""
        return MediaCandidate(
            url: url,
            width: int64Value(object["width"]) ?? 0,
            height: height,
            quality: quality,
            mime: stringValue(object["mime"]) ?? stringValue(object["mime_type"]) ?? stringValue(object["type"]) ?? "",
            formatID: stringValue(object["id"]) ?? stringValue(object["quality"]) ?? String(sourceOrder),
            protocolName: stringValue(object["protocol"])?.lowercased() ?? url.scheme?.lowercased() ?? "https",
            vbr: 1,
            abr: 1,
            contentLength: int64Value(object["filesize"]) ?? int64Value(object["size"]) ?? 0,
            sourceOrder: sourceOrder
        )
    }

    private static func download(
        video: MediaCandidate,
        audio: MediaCandidate?,
        info: VideoInfo,
        pageURL: URL,
        userAgent: String?
    ) async throws -> ResolvedDownload {
        if let audio {
            let videoAssets = try await streamAssets(
                for: video,
                role: "video",
                info: info,
                pageURL: pageURL,
                userAgent: userAgent
            )
            let audioAssets = try await streamAssets(
                for: audio,
                role: "audio",
                info: info,
                pageURL: pageURL,
                userAgent: userAgent
            )
            let assets = videoAssets + audioAssets
            let filename = outputFilename(info: info, extension: "mp4")
            return ResolvedDownload(
                title: info.title,
                folderName: "Vimeo \(info.folderTitle)".sanitizedFilename(maxLength: 120),
                assets: assets,
                packageMode: .mux(
                    videoAssets: videoAssets,
                    audioAssets: audioAssets,
                    outputFilename: filename
                ),
                metadata: videoMetadata(
                    info,
                    video: video,
                    audio: audio,
                    pageURL: pageURL,
                    packageMode: "mux"
                )
            )
        }

        if video.isDirect {
            return directDownload(
                candidate: video,
                info: info,
                pageURL: pageURL,
                userAgent: userAgent
            )
        }

        let assets = try await streamAssets(
            for: video,
            role: "video",
            info: info,
            pageURL: pageURL,
            userAgent: userAgent
        )
        return ResolvedDownload(
            title: info.title,
            folderName: "Vimeo \(info.folderTitle)".sanitizedFilename(maxLength: 120),
            assets: assets,
            packageMode: .concatenate(
                outputFilename: outputFilename(info: info, extension: "ts")
            ),
            metadata: videoMetadata(
                info,
                video: video,
                audio: nil,
                pageURL: pageURL,
                packageMode: "hls"
            )
        )
    }

    private static func directDownload(
        candidate: MediaCandidate,
        info: VideoInfo,
        pageURL: URL,
        userAgent: String?
    ) -> ResolvedDownload {
        let filename = outputFilename(info: info, extension: "mp4")
        let asset = ResolvedAsset(
            remoteURL: candidate.url,
            filename: filename,
            metadata: assetMetadata(for: candidate, role: "video", info: info, pageURL: pageURL),
            referer: pageURL.absoluteString,
            userAgent: userAgent
        )
        return ResolvedDownload(
            title: info.title,
            folderName: "Vimeo \(info.folderTitle)".sanitizedFilename(maxLength: 120),
            assets: [asset],
            packageMode: .concatenate(outputFilename: filename),
            metadata: videoMetadata(
                info,
                video: candidate,
                audio: nil,
                pageURL: pageURL,
                packageMode: "concatenate"
            )
        )
    }

    private static func alternateAudioDownload(
        _ resolved: ResolvedDownload,
        playlistURL: URL,
        info: VideoInfo,
        pageURL: URL
    ) -> ResolvedDownload {
        guard case .mux(let videoAssets, let audioAssets, _) = resolved.packageMode,
              let videoPlaylistURL = URL(string: resolved.metadata["video_playlist_url"] ?? ""),
              let audioPlaylistURL = URL(string: resolved.metadata["audio_playlist_url"] ?? "") else {
            return resolved
        }
        let video = MediaCandidate(
            url: videoPlaylistURL,
            width: int64Value(resolved.metadata["width"]) ?? 0,
            height: int64Value(resolved.metadata["height"]) ?? 0,
            quality: resolved.metadata["resolution"] ?? "",
            mime: "application/vnd.apple.mpegurl",
            formatID: "hls-\(resolved.metadata["bandwidth"] ?? "video")",
            protocolName: "m3u8_native",
            vbr: (int64Value(resolved.metadata["bandwidth"]) ?? 0) / 1_000,
            abr: 0,
            contentLength: 0,
            sourceOrder: 0
        )
        let audio = MediaCandidate(
            url: audioPlaylistURL,
            width: 0,
            height: 0,
            quality: resolved.metadata["audio_group"] ?? "audio",
            mime: "audio/mp4",
            formatID: resolved.metadata["audio_group"] ?? "hls-audio",
            protocolName: "m3u8_native",
            vbr: 0,
            abr: 1,
            contentLength: 0,
            sourceOrder: 1
        )
        let enrichedVideo = enrichHLSAssets(
            videoAssets,
            role: "video",
            info: info,
            pageURL: pageURL,
            playlistURL: videoPlaylistURL
        )
        let enrichedAudio = enrichHLSAssets(
            audioAssets,
            role: "audio",
            info: info,
            pageURL: pageURL,
            playlistURL: audioPlaylistURL
        )
        var metadata = resolved.metadata
        for (key, value) in videoMetadata(
            info,
            video: video,
            audio: audio,
            pageURL: pageURL,
            packageMode: "mux"
        ) {
            metadata[key] = value
        }
        metadata["manifest_url"] = playlistURL.absoluteString
        metadata["playlist_url"] = playlistURL.absoluteString

        return ResolvedDownload(
            title: info.title,
            folderName: "Vimeo \(info.folderTitle)".sanitizedFilename(maxLength: 120),
            assets: enrichedVideo + enrichedAudio,
            packageMode: .mux(
                videoAssets: enrichedVideo,
                audioAssets: enrichedAudio,
                outputFilename: outputFilename(info: info, extension: "mp4")
            ),
            metadata: DownloadMetadata.clean(metadata)
        )
    }

    private static func enrichHLSAssets(
        _ assets: [ResolvedAsset],
        role: String,
        info: VideoInfo,
        pageURL: URL,
        playlistURL: URL
    ) -> [ResolvedAsset] {
        assets.enumerated().map { offset, asset in
            var enriched = asset
            enriched.metadata = asset.metadata.merging(
                segmentMetadata(
                    info: info,
                    pageURL: pageURL,
                    playlistURL: playlistURL,
                    asset: asset,
                    index: offset + 1,
                    role: role
                )
            ) { _, new in new }
            return enriched
        }
    }

    private static func streamAssets(
        for candidate: MediaCandidate,
        role: String,
        info: VideoInfo,
        pageURL: URL,
        userAgent: String?
    ) async throws -> [ResolvedAsset] {
        if candidate.isDirect {
            let fallback = role == "audio" ? "m4a" : "mp4"
            let format = mediaFormat(for: candidate, fallback: fallback)
            return [
                ResolvedAsset(
                    remoteURL: candidate.url,
                    filename: "vimeo-\(role)-\(candidate.formatID).\(format)".sanitizedFilename(maxLength: 160),
                    metadata: assetMetadata(for: candidate, role: role, info: info, pageURL: pageURL),
                    referer: pageURL.absoluteString,
                    userAgent: userAgent
                )
            ]
        }

        let parsed = try await M3U8Resolver().resolve(
            candidate.url,
            headers: HTTPRequestOptions(referer: pageURL.absoluteString, userAgent: userAgent)
        )
        return enrichHLSAssets(
            parsed.assets,
            role: role,
            info: info,
            pageURL: pageURL,
            playlistURL: candidate.url
        )
    }

    private static func outputFilename(info: VideoInfo, extension ext: String) -> String {
        "\(info.title)-\(info.id).\(ext)".sanitizedFilename(maxLength: 180)
    }

    private static func hlsURL(from object: [String: Any], pageURL: URL) -> URL? {
        if let hls = dictionary(at: ["request", "files", "hls"], in: object) ??
            dictionary(at: ["video", "files", "hls"], in: object) ??
            object["hls"] as? [String: Any] {
            let defaultCDN = stringValue(hls["default_cdn"])
            if let cdns = hls["cdns"] as? [String: Any] {
                let orderedKeys = [defaultCDN].compactMap { $0 } + cdns.keys.sorted()
                for key in orderedKeys {
                    guard let item = cdns[key] as? [String: Any],
                          let raw = stringValue(item["url"]) ?? stringValue(item["avc_url"]) ?? stringValue(item["captions"]),
                          let url = absoluteURL(raw, baseURL: pageURL) else {
                        continue
                    }
                    return url
                }
            }
            if let raw = stringValue(hls["url"]) ?? stringValue(hls["avc_url"]),
               let url = absoluteURL(raw, baseURL: pageURL) {
                return url
            }
        }
        return nil
    }

    private static func fullVideoInfo(from object: [String: Any], pageURL: URL) -> VideoInfo {
        let video = object["video"] as? [String: Any] ?? object
        let id = stringValue(object["id"]) ?? stringValue(video["id"]) ?? videoID(from: pageURL) ?? "vimeo"
        let title = cleanTitle(stringValue(object["title"]) ?? stringValue(video["title"]) ?? "Vimeo \(id)")
        let owner = dictionary(at: ["video", "owner"], in: object) ??
            dictionary(at: ["owner"], in: object)
        let artist = cleanTitle(
            stringValue(object["uploader"]) ??
                stringValue(video["uploader"]) ??
                stringValue(owner?["name"]) ??
                ""
        )
        let folderTitle = artist.isEmpty ? title : "\(artist) - \(title)"
        return VideoInfo(
            id: id,
            title: title,
            folderTitle: folderTitle,
            uploader: artist,
            thumbnail: firstThumbnailURL(in: object, video: video, pageURL: pageURL)
        )
    }

    private static func firstThumbnailURL(
        in object: [String: Any],
        video: [String: Any],
        pageURL: URL
    ) -> URL? {
        for container in [object, video] {
            if let thumbnails = container["thumbnails"] as? [[String: Any]] {
                for thumbnail in thumbnails {
                    if let raw = stringValue(thumbnail["url"]),
                       let url = absoluteURL(raw, baseURL: pageURL) {
                        return url
                    }
                }
            }
            if let raw = stringValue(container["thumbnail"]) ?? stringValue(container["thumbnail_url"]),
               let url = absoluteURL(raw, baseURL: pageURL) {
                return url
            }
        }
        if let thumbs = video["thumbs"] as? [String: Any] {
            for key in thumbs.keys.sorted(by: numericStringLessThan) {
                if let raw = stringValue(thumbs[key]),
                   let url = absoluteURL(raw, baseURL: pageURL) {
                    return url
                }
            }
        }
        return nil
    }

    private static func numericStringLessThan(_ lhs: String, _ rhs: String) -> Bool {
        let left = Int(lhs)
        let right = Int(rhs)
        if let left, let right, left != right { return left < right }
        return lhs < rhs
    }

    private static func videoMetadata(
        _ info: VideoInfo,
        video: MediaCandidate,
        audio: MediaCandidate?,
        pageURL: URL,
        packageMode: String
    ) -> [String: String] {
        let isHLS = !video.isDirect
        let resolution = video.height > 0 ? "\(video.height)p" : ""
        let outputFormat = isHLS && audio == nil ? "m3u8" : "mp4"
        return DownloadMetadata.clean([
            "site": "Vimeo",
            "title": info.title,
            "type": isHLS && audio == nil ? "hls" : "video",
            "media_type": "video",
            "package_mode": packageMode,
            "media_count": audio == nil ? "1" : "2",
            "video_count": "1",
            "audio_count": audio == nil ? "" : "1",
            "id": info.id,
            "video_id": info.id,
            "media_id": info.id,
            "format": outputFormat,
            "media_format": outputFormat,
            "source_format": mediaFormat(for: video, fallback: isHLS ? "m3u8" : "mp4"),
            "format_id": video.formatID,
            "protocol": video.protocolName,
            "vbr": String(video.vbr),
            "abr": String(video.abr),
            "width": video.width > 0 ? String(video.width) : "",
            "height": video.height > 0 ? String(video.height) : "",
            "resolution": resolution,
            "quality": video.quality.isEmpty ? resolution : video.quality,
            "video_url": video.url.absoluteString,
            "audio_url": audio?.url.absoluteString ?? "",
            "media_url": video.url.absoluteString,
            "playlist_url": isHLS ? video.url.absoluteString : "",
            "hls_remux_required": isHLS && audio == nil ? "true" : "",
            "thumbnail": info.thumbnail?.absoluteString ?? "",
            "thumbnail_url": info.thumbnail?.absoluteString ?? "",
            "source_url": pageURL.absoluteString,
            "page_url": pageURL.absoluteString,
            "artist": info.uploader,
            "author": info.uploader,
            "creator": info.uploader,
            "uploader": info.uploader,
            "channel": info.uploader,
            "user": info.uploader,
            "username": info.uploader
        ])
    }

    private static func assetMetadata(
        for candidate: MediaCandidate,
        role: String,
        info: VideoInfo,
        pageURL: URL
    ) -> [String: String] {
        let format = mediaFormat(for: candidate, fallback: role == "audio" ? "m4a" : "mp4")
        let height = candidate.height > 0 ? String(candidate.height) : ""
        let resolution = candidate.height > 0 ? "\(candidate.height)p" : ""
        let isAudio = role == "audio"
        return DownloadMetadata.clean([
            "site": "Vimeo",
            "title": info.title,
            "type": role,
            "media_type": role,
            "media_role": role,
            "id": info.id,
            "video_id": info.id,
            "media_id": "\(info.id)-\(role)",
            "page": "1",
            "position": isAudio ? "2" : "1",
            "format": format,
            "media_format": format,
            "format_id": candidate.formatID,
            "protocol": candidate.protocolName,
            "vbr": String(candidate.vbr),
            "abr": String(candidate.abr),
            "mime": candidate.mime,
            "width": candidate.width > 0 ? String(candidate.width) : "",
            "height": height,
            "resolution": resolution,
            "quality": candidate.quality.isEmpty ? resolution : candidate.quality,
            "byte_count": candidate.contentLength > 0 ? String(candidate.contentLength) : "",
            "video_url": isAudio ? "" : candidate.url.absoluteString,
            "audio_url": isAudio ? candidate.url.absoluteString : "",
            "media_url": candidate.url.absoluteString,
            "thumbnail": info.thumbnail?.absoluteString ?? "",
            "source_url": pageURL.absoluteString,
            "page_url": pageURL.absoluteString,
            "artist": info.uploader,
            "author": info.uploader,
            "creator": info.uploader,
            "uploader": info.uploader,
            "channel": info.uploader,
            "user": info.uploader,
            "username": info.uploader
        ])
    }

    static func hlsAssetsWithPageMetadata(_ assets: [ResolvedAsset], info: (id: String, title: String, folderTitle: String, uploader: String), pageURL: URL, playlistURL: URL) -> [ResolvedAsset] {
        let fullInfo = VideoInfo(
            id: info.id,
            title: info.title,
            folderTitle: info.folderTitle,
            uploader: info.uploader,
            thumbnail: nil
        )
        return assets.enumerated().map { offset, asset in
            var enriched = asset
            enriched.metadata = asset.metadata.merging(segmentMetadata(
                info: fullInfo,
                pageURL: pageURL,
                playlistURL: playlistURL,
                asset: asset,
                index: offset + 1,
                role: "video"
            )) { _, new in new }
            return enriched
        }
    }

    private static func segmentMetadata(
        info: VideoInfo,
        pageURL: URL,
        playlistURL: URL,
        asset: ResolvedAsset,
        index: Int,
        role: String
    ) -> [String: String] {
        let type = asset.metadata["type"] ?? "hls_segment"
        let format = mediaFormat(for: asset.remoteURL, fallback: mediaFormat(forFilename: asset.filename, fallback: "ts"))
        let isAudio = role == "audio"
        return DownloadMetadata.clean([
            "site": "Vimeo",
            "title": info.title,
            "series": info.title,
            "type": type,
            "media_type": type == "hls_segment" ? "segment" : role,
            "media_role": role,
            "category": role,
            "id": info.id,
            "video_id": info.id,
            "media_id": "\(info.id)-\(role)-segment-\(index)",
            "gallery_id": info.id,
            "page": String(index),
            "position": String(index),
            "format": format,
            "media_format": format,
            "playlist_url": asset.metadata["playlist_url"] ?? playlistURL.absoluteString,
            "video_url": isAudio ? "" : asset.remoteURL.absoluteString,
            "audio_url": isAudio ? asset.remoteURL.absoluteString : "",
            "media_url": asset.remoteURL.absoluteString,
            "thumbnail": info.thumbnail?.absoluteString ?? "",
            "source_url": pageURL.absoluteString,
            "page_url": pageURL.absoluteString,
            "artist": info.uploader,
            "author": info.uploader,
            "creator": info.uploader,
            "uploader": info.uploader,
            "channel": info.uploader,
            "user": info.uploader,
            "username": info.uploader
        ])
    }

    private static func mediaFormat(for candidate: MediaCandidate, fallback: String) -> String {
        let ext = candidate.url.pathExtension.trimmed.lowercased()
        if !ext.isEmpty { return ext }
        let mime = candidate.mime.lowercased()
        if mime.contains("audio/mp4") || mime.contains("m4a") { return "m4a" }
        if mime.contains("mp4") { return "mp4" }
        if mime.contains("mpegurl") || mime.contains("m3u8") { return "m3u8" }
        return fallback
    }

    private static func mediaFormat(for url: URL, fallback: String) -> String {
        let ext = url.pathExtension.trimmed.lowercased()
        return ext.isEmpty ? fallback : ext
    }

    private static func mediaFormat(forFilename filename: String, fallback: String) -> String {
        let ext = (filename as NSString).pathExtension.lowercased()
        return ext.isEmpty ? fallback : ext
    }

    private static func isVimeoHost(_ host: String) -> Bool {
        host == "vimeo.com" ||
            host == "www.vimeo.com" ||
            host == "player.vimeo.com" ||
            host == "vimeo.test" ||
            host == "www.vimeo.test" ||
            host == "player.vimeo.test"
    }

    private static func absoluteURL(_ raw: String, baseURL: URL) -> URL? {
        let value = raw.trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        if value.hasPrefix("//") {
            return URL(string: "\(baseURL.scheme ?? "https"):\(value)")
        }
        return URL(string: value, relativeTo: baseURL)?.absoluteURL
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

    private static func jsonObject(from data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NativeDownloadError.invalidGalleryData
        }
        return object
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

    private static func isNumericID(_ value: String) -> Bool {
        value.range(of: #"^[0-9]{4,}$"#, options: .regularExpression) != nil
    }
}
