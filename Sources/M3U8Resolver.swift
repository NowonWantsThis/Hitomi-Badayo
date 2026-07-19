import Foundation

final class M3U8Resolver {
    private struct VariantCandidate {
        var bandwidth: Int
        var height: Int
        var index: Int
        var url: URL
    }

    private struct AlternateAudioCandidate {
        var selection: HLSAlternateAudioSelection
        var index: Int
    }

    func canResolve(_ url: URL) -> Bool {
        let path = url.path.lowercased()
        return path.hasSuffix(".m3u8") || url.absoluteString.lowercased().contains(".m3u8")
    }

    func resolve(
        _ url: URL,
        headers: HTTPRequestOptions = HTTPRequestOptions(),
        preferredResolution: String = "",
        additionalHeaders: [String: String] = [:],
        segmentReferer: String? = nil,
        originBoundHeaderNames: Set<String> = []
    ) async throws -> ResolvedDownload {
        let playlist = try await HTTPClient.shared.string(
            from: url,
            referer: headers.referer,
            userAgent: headers.userAgent,
            additionalHeaders: additionalHeaders
        )
        guard playlist.contains("#EXTM3U") else {
            throw NativeDownloadError.invalidPlaylist
        }

        let variants = try orderedVariantCandidates(
            in: playlist,
            baseURL: url,
            preferredResolution: preferredResolution
        )
        if !variants.isEmpty {
            var lastError: Error?
            for variant in variants {
                try Task.checkCancellation()
                do {
                    var resolved = try await resolveMediaPlaylist(
                        variant.url,
                        titleHint: title(from: url),
                        headers: headers,
                        additionalHeaders: additionalHeaders,
                        segmentReferer: segmentReferer,
                        headerOriginURL: url,
                        originBoundHeaderNames: originBoundHeaderNames
                    )
                    resolved.metadata["master_playlist_url"] = url.absoluteString
                    resolved.metadata["selected_variant_url"] = variant.url.absoluteString
                    resolved.metadata["selected_variant_index"] = String(variant.index)
                    resolved.metadata["selected_variant_bandwidth"] = String(variant.bandwidth)
                    if variant.height > 0 {
                        resolved.metadata["selected_variant_height"] = String(variant.height)
                    }
                    resolved.metadata["original_contract"] = "m3u8-4.2-improved-resolution-bandwidth"
                    return resolved
                } catch {
                    if Task.isCancelled || (error as? URLError)?.code == .cancelled {
                        throw error
                    }
                    lastError = error
                }
            }
            throw lastError ?? NativeDownloadError.invalidPlaylist
        }

        return try parseMediaPlaylist(
            playlist,
            url: url,
            titleHint: title(from: url),
            headers: headers,
            additionalHeaders: additionalHeaders,
            segmentReferer: segmentReferer,
            headerOriginURL: url,
            originBoundHeaderNames: originBoundHeaderNames
        )
    }

    func resolveAlternateAudioMux(
        _ url: URL,
        titleHint: String,
        outputFilename: String,
        headers: HTTPRequestOptions = HTTPRequestOptions(),
        preferredResolution: String = "",
        additionalHeaders: [String: String] = [:],
        segmentReferer: String? = nil
    ) async throws -> ResolvedDownload? {
        let playlist = try await HTTPClient.shared.string(
            from: url,
            referer: headers.referer,
            userAgent: headers.userAgent,
            additionalHeaders: additionalHeaders
        )
        guard playlist.contains("#EXTM3U") else {
            throw NativeDownloadError.invalidPlaylist
        }
        guard let selection = alternateAudioSelection(
            in: playlist,
            baseURL: url,
            preferredResolution: preferredResolution
        ) else {
            return nil
        }

        let video = try await resolveMediaPlaylist(
            selection.videoURL,
            titleHint: "\(titleHint) video",
            headers: headers,
            additionalHeaders: additionalHeaders,
            segmentReferer: segmentReferer
        )
        let audio = try await resolveMediaPlaylist(
            selection.audioURL,
            titleHint: "\(titleHint) audio",
            headers: headers,
            additionalHeaders: additionalHeaders,
            segmentReferer: segmentReferer
        )
        guard !video.assets.isEmpty, !audio.assets.isEmpty else {
            throw NativeDownloadError.noFiles
        }

        let safeTitle = titleHint.sanitizedFilename()
        let assets = video.assets + audio.assets
        let videoSegments = video.assets.filter { $0.metadata["type"] == "hls_segment" }.count
        let audioSegments = audio.assets.filter { $0.metadata["type"] == "hls_segment" }.count
        let metadata = DownloadMetadata.clean([
            "site": url.host ?? "M3U8",
            "title": safeTitle,
            "series": safeTitle,
            "category": "video",
            "type": "hls",
            "media_type": "hls",
            "format": "m3u8",
            "media_format": "m3u8",
            "package_mode": "mux",
            "playlist_url": url.absoluteString,
            "manifest_url": url.absoluteString,
            "video_playlist_url": selection.videoURL.absoluteString,
            "audio_playlist_url": selection.audioURL.absoluteString,
            "audio_group": selection.audioGroup,
            "bandwidth": String(selection.bandwidth),
            "width": selection.width > 0 ? String(selection.width) : "",
            "height": selection.height > 0 ? String(selection.height) : "",
            "resolution": selection.height > 0 ? "\(selection.height)p" : "",
            "media_count": String(assets.count),
            "video_count": "1",
            "audio_count": "1",
            "video_segment_count": String(videoSegments),
            "audio_segment_count": String(audioSegments),
            "segment_count": String(videoSegments + audioSegments),
            "source_url": url.absoluteString,
            "page_url": url.absoluteString
        ])

        return ResolvedDownload(
            title: safeTitle,
            folderName: "\(safeTitle) hls".sanitizedFilename(),
            assets: assets,
            packageMode: .mux(
                videoAssets: video.assets,
                audioAssets: audio.assets,
                outputFilename: outputFilename.sanitizedFilename()
            ),
            metadata: metadata
        )
    }

    func resolveCustomSegments(
        _ segmentURLs: [URL],
        playlistURL: URL,
        titleHint: String = "",
        headers: HTTPRequestOptions = HTTPRequestOptions(),
        additionalHeaders: [String: String] = [:],
        segmentReferer: String? = nil,
        live: Bool = false
    ) throws -> ResolvedDownload {
        guard !segmentURLs.isEmpty else {
            throw NativeDownloadError.noFiles
        }

        let assetReferer = Self.nonEmpty(segmentReferer)
            ?? Self.nonEmpty(headers.referer)
            ?? playlistURL.absoluteString
        let assetHeaders = additionalHeaders
            .filter { !["referer", "user-agent"].contains($0.key.lowercased()) }
            .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
            .map { ResolvedRequestHeader(name: $0.key, value: $0.value) }
        let assets = segmentURLs.enumerated().map { index, remote in
            let ext = remote.pathExtension.trimmed.isEmpty ? "ts" : remote.pathExtension.lowercased()
            return ResolvedAsset(
                remoteURL: remote,
                filename: String(format: "%06d.%@", index, ext).sanitizedFilename(),
                metadata: Self.segmentMetadata(
                    for: remote,
                    playlistURL: playlistURL,
                    index: index,
                    kind: "hls_segment",
                    segmentNumber: index + 1,
                    mediaSequence: index,
                    decryption: nil
                ),
                referer: assetReferer,
                userAgent: headers.userAgent,
                additionalHeaders: assetHeaders
            )
        }
        let enrichedAssets = Self.assetsWithSegmentTotals(assets, segmentTotal: assets.count)
        let rawTitle = titleHint.trimmed.isEmpty ? title(from: playlistURL) : titleHint
        let safeTitle = rawTitle.sanitizedFilename()
        var metadata = Self.hlsMetadata(
            title: safeTitle,
            playlistURL: playlistURL,
            assets: enrichedAssets,
            playlistType: live ? "" : "VOD",
            hasEndList: !live
        )
        metadata["custom_segment_urls"] = "true"
        metadata["custom_segment_count"] = String(enrichedAssets.count)

        return ResolvedDownload(
            title: safeTitle,
            folderName: "\(safeTitle) m3u8".sanitizedFilename(),
            assets: enrichedAssets,
            packageMode: .concatenate(outputFilename: "\(safeTitle).ts".sanitizedFilename()),
            metadata: DownloadMetadata.clean(metadata)
        )
    }

    private func resolveMediaPlaylist(
        _ url: URL,
        titleHint: String,
        headers: HTTPRequestOptions,
        additionalHeaders: [String: String],
        segmentReferer: String?,
        headerOriginURL: URL? = nil,
        originBoundHeaderNames: Set<String> = []
    ) async throws -> ResolvedDownload {
        let requestHeaders = Self.headers(
            additionalHeaders,
            for: url,
            originURL: headerOriginURL,
            originBoundHeaderNames: originBoundHeaderNames
        )
        let playlist = try await HTTPClient.shared.string(
            from: url,
            referer: headers.referer,
            userAgent: headers.userAgent,
            additionalHeaders: requestHeaders
        )
        guard playlist.contains("#EXTM3U") else {
            throw NativeDownloadError.invalidPlaylist
        }
        return try parseMediaPlaylist(
            playlist,
            url: url,
            titleHint: titleHint,
            headers: headers,
            additionalHeaders: additionalHeaders,
            segmentReferer: segmentReferer,
            headerOriginURL: headerOriginURL,
            originBoundHeaderNames: originBoundHeaderNames
        )
    }

    func bestVariant(in playlist: String, baseURL: URL, preferredResolution: String = "") throws -> URL? {
        try orderedVariantCandidates(
            in: playlist,
            baseURL: baseURL,
            preferredResolution: preferredResolution
        ).first?.url
    }

    private func orderedVariantCandidates(
        in playlist: String,
        baseURL: URL,
        preferredResolution: String
    ) throws -> [VariantCandidate] {
        let lines = cleanedLines(from: playlist)
        var variants: [VariantCandidate] = []
        var pendingVariant: (bandwidth: Int, height: Int)?

        for line in lines {
            if line.hasPrefix("#EXT-X-STREAM-INF") {
                pendingVariant = (
                    bandwidth: attribute("BANDWIDTH", in: line).flatMap(Int.init) ?? 0,
                    height: variantHeight(from: line)
                )
                continue
            }

            if let pending = pendingVariant, !line.hasPrefix("#") {
                guard let resolved = URL(string: line, relativeTo: baseURL)?.absoluteURL else {
                    throw NativeDownloadError.invalidPlaylist
                }
                variants.append(VariantCandidate(
                    bandwidth: pending.bandwidth,
                    height: pending.height,
                    index: variants.count,
                    url: resolved
                ))
                pendingVariant = nil
            }
        }

        guard !variants.isEmpty else { return [] }
        var pool = variants
        if let preferredHeight = Self.preferredHeight(from: preferredResolution),
           let minimumHeight = variants.map(\.height).min() {
            let effectiveHeight = max(preferredHeight, minimumHeight)
            pool = variants.filter { $0.height <= effectiveHeight }
        }

        return pool.sorted { left, right in
            if left.height != right.height {
                return left.height > right.height
            }
            if left.bandwidth != right.bandwidth {
                return left.bandwidth > right.bandwidth
            }
            return left.index > right.index
        }
    }

    func alternateAudioSelection(
        in playlist: String,
        baseURL: URL,
        preferredResolution: String
    ) -> HLSAlternateAudioSelection? {
        let lines = cleanedLines(from: playlist)
        var audioURLs: [String: URL] = [:]
        var variants: [AlternateAudioCandidate] = []

        for line in lines where line.hasPrefix("#EXT-X-MEDIA") {
            guard attribute("TYPE", in: line)?.uppercased() == "AUDIO",
                  let group = attribute("GROUP-ID", in: line),
                  let rawURL = attribute("URI", in: line),
                  let audioURL = URL(string: rawURL, relativeTo: baseURL)?.absoluteURL else {
                continue
            }
            audioURLs[group] = audioURL
        }

        var pending: (bandwidth: Int, width: Int, height: Int, audioGroup: String)?
        for line in lines {
            if line.hasPrefix("#EXT-X-STREAM-INF") {
                let resolution = variantDimensions(from: line)
                pending = (
                    bandwidth: attribute("BANDWIDTH", in: line).flatMap(Int.init) ?? 0,
                    width: resolution.width,
                    height: resolution.height,
                    audioGroup: attribute("AUDIO", in: line) ?? ""
                )
                continue
            }

            guard let candidate = pending, !line.hasPrefix("#") else { continue }
            pending = nil
            guard let videoURL = URL(string: line, relativeTo: baseURL)?.absoluteURL,
                  let audioURL = audioURLs[candidate.audioGroup] else {
                continue
            }
            variants.append(AlternateAudioCandidate(
                selection: HLSAlternateAudioSelection(
                    videoURL: videoURL,
                    audioURL: audioURL,
                    audioGroup: candidate.audioGroup,
                    bandwidth: candidate.bandwidth,
                    width: candidate.width,
                    height: candidate.height
                ),
                index: variants.count
            ))
        }

        guard !variants.isEmpty else { return nil }
        var pool = variants
        if let preferredHeight = Self.preferredHeight(from: preferredResolution),
           let minimumHeight = variants.map(\.selection.height).min() {
            let effectiveHeight = max(preferredHeight, minimumHeight)
            pool = variants.filter { $0.selection.height <= effectiveHeight }
        }
        return pool.sorted { left, right in
            if left.selection.height != right.selection.height {
                return left.selection.height > right.selection.height
            }
            if left.selection.bandwidth != right.selection.bandwidth {
                return left.selection.bandwidth > right.selection.bandwidth
            }
            return left.index > right.index
        }.first?.selection
    }

    private func parseMediaPlaylist(
        _ playlist: String,
        url: URL,
        titleHint: String,
        headers: HTTPRequestOptions,
        additionalHeaders: [String: String],
        segmentReferer: String?,
        headerOriginURL: URL? = nil,
        originBoundHeaderNames: Set<String> = []
    ) throws -> ResolvedDownload {
        let lines = cleanedLines(from: playlist)
        let assetReferer = Self.nonEmpty(segmentReferer) ?? Self.nonEmpty(headers.referer) ?? url.absoluteString
        var assets: [ResolvedAsset] = []
        var index = 0
        var segmentNumber = 0
        var mediaSequence = 0
        var targetDuration: Double?
        var playlistType = ""
        var hasEndList = false
        var discontinuityCount = 0
        var totalDuration: Double = 0
        var currentKey: HLSKey?
        var pendingSegmentDuration: Double?
        var pendingSegmentTitle: String?

        for line in lines {
            if line.hasPrefix("#EXT-X-MEDIA-SEQUENCE") {
                mediaSequence = Int(line.components(separatedBy: ":").dropFirst().joined(separator: ":").trimmed) ?? 0
                continue
            }

            if line.hasPrefix("#EXT-X-TARGETDURATION") {
                targetDuration = Double(line.components(separatedBy: ":").dropFirst().joined(separator: ":").trimmed)
                continue
            }

            if line.hasPrefix("#EXT-X-PLAYLIST-TYPE") {
                playlistType = line.components(separatedBy: ":").dropFirst().joined(separator: ":").trimmed.uppercased()
                continue
            }

            if line.hasPrefix("#EXT-X-ENDLIST") {
                hasEndList = true
                continue
            }

            if line.hasPrefix("#EXT-X-DISCONTINUITY") {
                discontinuityCount += 1
                continue
            }

            if line.hasPrefix("#EXT-X-KEY") {
                let method = attribute("METHOD", in: line)?.uppercased() ?? ""
                if method == "NONE" {
                    currentKey = nil
                    continue
                }
                guard method == "AES-128" else {
                    throw NativeDownloadError.encryptedPlaylist("Unsupported HLS encryption method: \(method)")
                }
                guard let uri = attribute("URI", in: line),
                      let keyURL = URL(string: uri, relativeTo: url)?.absoluteURL else {
                    throw NativeDownloadError.invalidPlaylist
                }
                currentKey = HLSKey(keyURL: keyURL, explicitIV: try parseIV(attribute("IV", in: line)))
                continue
            }

            if line.hasPrefix("#EXTINF") {
                pendingSegmentDuration = extinfDuration(from: line)
                pendingSegmentTitle = extinfTitle(from: line)
                continue
            }

            if line.hasPrefix("#EXT-X-MAP") {
                guard let uri = attribute("URI", in: line),
                      let remote = URL(string: uri, relativeTo: url)?.absoluteURL else {
                    throw NativeDownloadError.invalidPlaylist
                }
                let decryption = currentKey.map { SegmentDecryption(keyURL: $0.keyURL, iv: $0.explicitIV ?? ivData(for: mediaSequence)) }
                let assetHeaders = Self.resolvedHeaders(Self.headers(
                    additionalHeaders,
                    for: remote,
                    originURL: headerOriginURL,
                    originBoundHeaderNames: originBoundHeaderNames
                ))
                assets.append(ResolvedAsset(
                    remoteURL: remote,
                    filename: String(format: "%06d-map.mp4", index),
                    metadata: Self.segmentMetadata(
                        for: remote,
                        playlistURL: url,
                        index: index,
                        kind: "hls_map",
                        decryption: decryption
                    ),
                    referer: assetReferer,
                    userAgent: headers.userAgent,
                    additionalHeaders: assetHeaders,
                    decryption: decryption
                ))
                index += 1
                continue
            }

            guard !line.hasPrefix("#") else { continue }
            guard let remote = URL(string: line, relativeTo: url)?.absoluteURL else {
                throw NativeDownloadError.invalidPlaylist
            }

            segmentNumber += 1
            if let pendingSegmentDuration {
                totalDuration += pendingSegmentDuration
            }
            let ext = remote.pathExtension.isEmpty ? "ts" : remote.pathExtension
            let filename = String(format: "%06d.%@", index, ext).sanitizedFilename()
            let decryption = currentKey.map { SegmentDecryption(keyURL: $0.keyURL, iv: $0.explicitIV ?? ivData(for: mediaSequence)) }
            let assetHeaders = Self.resolvedHeaders(Self.headers(
                additionalHeaders,
                for: remote,
                originURL: headerOriginURL,
                originBoundHeaderNames: originBoundHeaderNames
            ))
            assets.append(ResolvedAsset(
                remoteURL: remote,
                filename: filename,
                metadata: Self.segmentMetadata(
                    for: remote,
                    playlistURL: url,
                    index: index,
                    kind: "hls_segment",
                    segmentNumber: segmentNumber,
                    mediaSequence: mediaSequence,
                    duration: pendingSegmentDuration,
                    segmentTitle: pendingSegmentTitle,
                    discontinuitySequence: discontinuityCount,
                    decryption: decryption
                ),
                referer: assetReferer,
                userAgent: headers.userAgent,
                additionalHeaders: assetHeaders,
                decryption: decryption
            ))
            pendingSegmentDuration = nil
            pendingSegmentTitle = nil
            index += 1
            mediaSequence += 1
        }

        guard !assets.isEmpty else {
            throw NativeDownloadError.noFiles
        }

        let segmentTotal = assets.filter { $0.metadata["type"] == "hls_segment" }.count
        let enrichedAssets = Self.assetsWithSegmentTotals(assets, segmentTotal: segmentTotal)
        let safeTitle = titleHint.sanitizedFilename()
        return ResolvedDownload(
            title: safeTitle,
            folderName: "\(safeTitle) m3u8".sanitizedFilename(),
            assets: enrichedAssets,
            packageMode: .concatenate(outputFilename: "\(safeTitle).ts".sanitizedFilename()),
            metadata: Self.hlsMetadata(
                title: safeTitle,
                playlistURL: url,
                assets: enrichedAssets,
                targetDuration: targetDuration,
                playlistType: playlistType,
                hasEndList: hasEndList,
                discontinuityCount: discontinuityCount,
                totalDuration: totalDuration
            )
        )
    }

    private static func headers(
        _ headers: [String: String],
        for targetURL: URL,
        originURL: URL?,
        originBoundHeaderNames: Set<String>
    ) -> [String: String] {
        guard let originURL,
              !sameOrigin(targetURL, originURL),
              !originBoundHeaderNames.isEmpty else {
            return headers
        }
        let normalizedNames = Set(originBoundHeaderNames.map { $0.lowercased() })
        return headers.filter { !normalizedNames.contains($0.key.lowercased()) }
    }

    private static func sameOrigin(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.scheme?.lowercased() == rhs.scheme?.lowercased() &&
            lhs.host?.lowercased() == rhs.host?.lowercased() &&
            effectivePort(lhs) == effectivePort(rhs)
    }

    private static func effectivePort(_ url: URL) -> Int? {
        if let port = url.port { return port }
        switch url.scheme?.lowercased() {
        case "http": return 80
        case "https": return 443
        default: return nil
        }
    }

    private static func resolvedHeaders(_ fields: [String: String]) -> [ResolvedRequestHeader] {
        fields
            .filter { !["referer", "user-agent"].contains($0.key.lowercased()) }
            .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
            .map { ResolvedRequestHeader(name: $0.key, value: $0.value) }
    }

    static func hlsMetadata(
        title: String,
        playlistURL: URL,
        assets: [ResolvedAsset],
        targetDuration: Double? = nil,
        playlistType: String = "",
        hasEndList: Bool = false,
        discontinuityCount: Int = 0,
        totalDuration: Double = 0
    ) -> [String: String] {
        let mapCount = assets.filter { $0.filename.contains("-map.") }.count
        let encryptedCount = assets.filter { $0.decryption != nil }.count
        let segmentCount = max(0, assets.count - mapCount)
        return DownloadMetadata.clean([
            "series": title,
            "category": "video",
            "type": "hls",
            "format": "m3u8",
            "host": playlistURL.host ?? "",
            "site": playlistURL.host ?? "M3U8",
            "playlist_url": playlistURL.absoluteString,
            "media_url": playlistURL.absoluteString,
            "source_url": playlistURL.absoluteString,
            "page_url": playlistURL.absoluteString,
            "media_count": String(assets.count),
            "video_count": "1",
            "segment_count": String(segmentCount),
            "total_segments": String(segmentCount),
            "duration": totalDuration > 0 ? compactNumber(totalDuration) : "",
            "duration_seconds": totalDuration > 0 ? compactNumber(totalDuration) : "",
            "target_duration": targetDuration.map(compactNumber) ?? "",
            "playlist_type": playlistType,
            "live": hasEndList ? "false" : "true",
            "vod": hasEndList ? "true" : "false",
            "is_live": hasEndList ? "false" : "true",
            "discontinuity_count": String(discontinuityCount),
            "map_count": String(mapCount),
            "encrypted_count": String(encryptedCount),
            "encrypted": encryptedCount > 0 ? "true" : "false",
            "slug": title,
            "title": title
        ])
    }

    private static func assetsWithSegmentTotals(_ assets: [ResolvedAsset], segmentTotal: Int) -> [ResolvedAsset] {
        assets.map { asset in
            var copy = asset
            if copy.metadata["type"] == "hls_segment" {
                copy.metadata["segment_total"] = String(segmentTotal)
                copy.metadata["total_segments"] = String(segmentTotal)
            }
            return copy
        }
    }

    private static func segmentMetadata(
        for url: URL,
        playlistURL: URL,
        index: Int,
        kind: String,
        segmentNumber: Int? = nil,
        mediaSequence: Int? = nil,
        duration: Double? = nil,
        segmentTitle: String? = nil,
        discontinuitySequence: Int = 0,
        decryption: SegmentDecryption?
    ) -> [String: String] {
        let format = url.pathExtension.trimmed.isEmpty ? "ts" : url.pathExtension.lowercased()
        return DownloadMetadata.clean([
            "type": kind,
            "media_type": kind,
            "page": String(index + 1),
            "position": String(index + 1),
            "segment_index": String(index),
            "segment_number": segmentNumber.map(String.init) ?? "",
            "media_sequence": mediaSequence.map(String.init) ?? "",
            "duration": duration.map(compactNumber) ?? "",
            "duration_seconds": duration.map(compactNumber) ?? "",
            "discontinuity_sequence": discontinuitySequence > 0 ? String(discontinuitySequence) : "",
            "format": format,
            "media_format": format,
            "playlist_url": playlistURL.absoluteString,
            "media_url": url.absoluteString,
            "video_url": url.absoluteString,
            "source_url": url.absoluteString,
            "page_url": playlistURL.absoluteString,
            "segment_title": segmentTitle ?? "",
            "hls_title": segmentTitle ?? "",
            "encrypted": decryption == nil ? "false" : "true",
            "key_url": decryption?.keyURL.absoluteString ?? ""
        ])
    }

    private func cleanedLines(from playlist: String) -> [String] {
        playlist
            .components(separatedBy: .newlines)
            .map { $0.trimmed }
            .filter { !$0.isEmpty }
    }

    private func attribute(_ name: String, in line: String) -> String? {
        let escapedName = NSRegularExpression.escapedPattern(for: name)
        let pattern = "\(escapedName)=((?:\"[^\"]+\")|[^,]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, options: [], range: range),
              match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: line) else {
            return nil
        }

        return String(line[valueRange]).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    }

    private func variantHeight(from line: String) -> Int {
        variantDimensions(from: line).height
    }

    private func variantDimensions(from line: String) -> (width: Int, height: Int) {
        guard let resolution = attribute("RESOLUTION", in: line) else { return (0, 0) }
        let parts = resolution.lowercased().split(separator: "x", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              let width = Int(parts[0]),
              let height = Int(parts[1]),
              width > 0,
              height > 0 else {
            return (0, 0)
        }
        return (width, height)
    }

    private static func preferredHeight(from preferredResolution: String) -> Int? {
        var value = preferredResolution.trimmed.lowercased()
        guard !value.isEmpty else { return nil }
        if value.hasSuffix("p") {
            value.removeLast()
        }
        guard value.range(of: #"^[0-9]{3,5}$"#, options: .regularExpression) != nil,
              let height = Int(value),
              (144...8640).contains(height) else {
            return nil
        }
        return height
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmed, !value.isEmpty else { return nil }
        return value
    }

    private func extinfTitle(from line: String) -> String? {
        guard let comma = line.firstIndex(of: ",") else {
            return nil
        }
        let title = String(line[line.index(after: comma)...]).trimmed
        return title.isEmpty ? nil : title
    }

    private func extinfDuration(from line: String) -> Double? {
        let value = line
            .components(separatedBy: ":")
            .dropFirst()
            .joined(separator: ":")
            .split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map(String.init)?
            .trimmed
        guard let value, !value.isEmpty else { return nil }
        return Double(value)
    }

    private static func compactNumber(_ value: Double) -> String {
        guard value.isFinite else { return "" }
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(format: "%.3f", value)
            .replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\.$"#, with: "", options: .regularExpression)
    }

    private func title(from url: URL) -> String {
        let last = url.deletingPathExtension().lastPathComponent
        return last.isEmpty ? "playlist" : last
    }

    private func parseIV(_ value: String?) throws -> Data? {
        guard var value else { return nil }
        if value.lowercased().hasPrefix("0x") {
            value.removeFirst(2)
        }
        if value.count % 2 != 0 {
            value = "0" + value
        }
        var bytes = Data()
        var index = value.startIndex
        while index < value.endIndex {
            let next = value.index(index, offsetBy: 2)
            guard let byte = UInt8(value[index..<next], radix: 16) else {
                throw NativeDownloadError.invalidPlaylist
            }
            bytes.append(byte)
            index = next
        }

        if bytes.count < 16 {
            bytes = Data(repeating: 0, count: 16 - bytes.count) + bytes
        }
        if bytes.count > 16 {
            bytes = bytes.suffix(16)
        }
        return bytes
    }

    private func ivData(for sequence: Int) -> Data {
        var bytes = Data(repeating: 0, count: 16)
        var value = UInt64(max(0, sequence))
        for offset in 0..<8 {
            bytes[15 - offset] = UInt8(value & 0xff)
            value >>= 8
        }
        return bytes
    }
}

private struct HLSKey {
    let keyURL: URL
    let explicitIV: Data?
}

struct HLSAlternateAudioSelection {
    let videoURL: URL
    let audioURL: URL
    let audioGroup: String
    let bandwidth: Int
    let width: Int
    let height: Int
}
