import Foundation

struct SOOPVideoCandidate {
    var url: URL
    var height: Int
    var label: String
    var score: Int
}

struct SOOPLiveQualityPreset: Equatable {
    var name: String
    var label: String
    var height: Int
}

final class SOOPVODResolver {
    private let liveNonceProvider: () -> Double

    init(liveNonceProvider: @escaping () -> Double = { Double.random(in: 0..<10_000) }) {
        self.liveNonceProvider = liveNonceProvider
    }

    func canResolve(_ url: URL) -> Bool {
        Self.videoID(from: url) != nil || Self.liveID(from: url) != nil
    }

    func resolve(_ url: URL, headers: HTTPRequestOptions = HTTPRequestOptions(), preferredResolution: String = "") async throws -> ResolvedDownload {
        if let id = Self.videoID(from: url) {
            let primaryKind = Self.isCatchURL(url) ? APIKind.catchView : APIKind.vodView
            let data: Data
            do {
                data = try await Self.fetchAPI(kind: primaryKind, id: id, sourceURL: url, headers: headers)
            } catch {
                let fallbackKind: APIKind = primaryKind == .catchView ? .vodView : .catchView
                data = try await Self.fetchAPI(kind: fallbackKind, id: id, sourceURL: url, headers: headers)
            }
            return try await Self.resolvedDownload(fromAPIData: data, sourceURL: url, preferredResolution: preferredResolution)
        }

        guard let liveID = Self.liveID(from: url) else {
            throw NativeDownloadError.invalidURL(url.absoluteString)
        }

        let pageURL = Self.canonicalLiveURL(liveID: liveID, sourceURL: url)
        let pageHTML = try? await HTTPClient.shared.string(from: pageURL, referer: headers.referer, userAgent: headers.userAgent)
        let statusData = try? await HTTPClient.shared.data(
            from: Self.liveStatusURL(liveID: liveID, sourceURL: pageURL),
            referer: headers.referer ?? pageURL.absoluteString,
            userAgent: headers.userAgent
        )
        let statusObject = statusData.flatMap { try? JSONSerialization.jsonObject(with: $0) }
        let broadNo = Self.liveBroadNo(fromHTML: pageHTML ?? "") ??
            Self.recursiveString(in: statusObject as Any, keys: ["nBroadNo", "broad_no", "broadNo", "bno"]) ??
            ""
        guard !broadNo.trimmed.isEmpty else {
            throw NativeDownloadError.unsupported("SOOP returned no live broadcast number.")
        }
        let presetData = try await Self.fetchLiveAPI(
            liveID: liveID,
            broadNo: broadNo,
            requestType: "live",
            quality: "original",
            sourceURL: pageURL,
            headers: headers
        )
        let presetObject = try JSONSerialization.jsonObject(with: presetData)
        if Self.liveResult(in: presetObject) == -6 {
            throw NativeDownloadError.unsupported("SOOP login is required for this live stream.")
        }
        guard let preset = Self.liveQualityPreset(
            in: presetObject,
            preferredResolution: preferredResolution
        ) else {
            throw NativeDownloadError.unsupported("SOOP returned no usable live quality preset.")
        }

        let aidData = try await Self.fetchLiveAPI(
            liveID: liveID,
            broadNo: broadNo,
            requestType: "aid",
            quality: preset.name,
            sourceURL: pageURL,
            headers: headers
        )
        let aidObject = try JSONSerialization.jsonObject(with: aidData)
        if Self.liveResult(in: aidObject) == -6 {
            throw NativeDownloadError.unsupported("SOOP login is required for this live stream.")
        }
        guard let aid = Self.recursiveString(in: aidObject, keys: ["AID", "aid"]),
              !aid.trimmed.isEmpty else {
            throw NativeDownloadError.unsupported("SOOP returned no live AID.")
        }

        let assignmentURL = Self.liveStreamAssignmentURL(
            broadNo: broadNo,
            sourceURL: pageURL,
            nonce: liveNonceProvider()
        )
        let assignmentData = try await HTTPClient.shared.data(
            from: assignmentURL,
            referer: pageURL.absoluteString,
            userAgent: headers.userAgent
        )
        let assignmentObject = try JSONSerialization.jsonObject(with: assignmentData)
        guard let rawViewURL = Self.recursiveString(in: assignmentObject, keys: ["view_url", "viewUrl"]),
              let viewURL = Self.absoluteURL(rawViewURL, baseURL: pageURL),
              let playlistURL = Self.authenticatedLivePlaylistURL(viewURL: viewURL, aid: aid) else {
            throw NativeDownloadError.unsupported("SOOP returned no live playlist URL.")
        }

        let selectedLiveObject: [String: Any] = [
            "file": playlistURL.absoluteString,
            "quality": preset.name,
            "height": preset.height,
            "live": true,
            "nBroadNo": broadNo,
            "user_nick": Self.recursiveString(in: presetObject, keys: ["user_nick"]) ?? liveID
        ]
        var resolved = try await Self.resolvedLiveDownload(
            fromJSONObject: selectedLiveObject,
            statusObject: statusObject,
            pageHTML: pageHTML ?? "",
            sourceURL: pageURL,
            liveID: liveID,
            preferredResolution: preferredResolution
        )
        let qualityMetadata = [
            "live_aid": aid,
            "live_quality_name": preset.name,
            "live_quality_label": preset.label,
            "live_quality_height": String(preset.height)
        ]
        resolved.metadata.merge(qualityMetadata) { current, _ in current }
        let enrichedAssets = resolved.assets.map { asset -> ResolvedAsset in
            var asset = asset
            asset.metadata.merge(qualityMetadata) { current, _ in current }
            return asset
        }
        return ResolvedDownload(
            title: resolved.title,
            folderName: resolved.folderName,
            assets: enrichedAssets,
            packageMode: resolved.packageMode,
            metadata: resolved.metadata
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
        guard !parts.isEmpty else { return nil }

        if let marker = lower.firstIndex(of: "player"), marker + 1 < parts.count, isNumericID(parts[marker + 1]) {
            return parts[marker + 1]
        }
        if let marker = lower.firstIndex(of: "vod"), marker + 1 < parts.count, isNumericID(parts[marker + 1]) {
            return parts[marker + 1]
        }
        if let marker = lower.firstIndex(of: "catch"), marker + 1 < parts.count, isNumericID(parts[marker + 1]) {
            return parts[marker + 1]
        }
        if let last = parts.last, isNumericID(last), lower.contains("station") && (lower.contains("vod") || lower.contains("catch")) {
            return last
        }

        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        for name in ["nTitleNo", "title_no", "titleNo", "broad_no", "broadNo"] {
            if let value = items.first(where: { $0.name.lowercased() == name.lowercased() })?.value,
               isNumericID(value) {
                return value
            }
        }
        return nil
    }

    static func liveID(from url: URL) -> String? {
        guard let host = url.host?.lowercased(),
              isLiveHost(host),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }

        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        guard parts.count == 1,
              isValidLiveID(parts[0]) else {
            return nil
        }
        return parts[0]
    }

    static func canonicalURL(for url: URL) -> URL? {
        if let liveID = liveID(from: url) {
            return canonicalLiveURL(liveID: liveID, sourceURL: url)
        }

        guard let id = videoID(from: url),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        let lowerPath = url.path.lowercased()
        if lowerPath.contains("/catch") {
            components.path = "/catch/\(id)"
        } else if lowerPath.contains("/vod") {
            components.path = "/vod/\(id)"
        } else {
            components.path = "/player/\(id)"
        }
        components.queryItems = nil
        components.fragment = nil
        return components.url
    }

    static func canonicalLiveURL(liveID: String, sourceURL: URL) -> URL {
        var components = URLComponents()
        components.scheme = sourceURL.scheme ?? "https"
        components.host = sourceURL.host?.lowercased().hasSuffix(".test") == true ? "play.sooplive.test" : "play.sooplive.com"
        components.path = "/\(liveID)"
        return components.url!
    }

    static func apiURL(kind: APIKind, sourceURL: URL) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = sourceURL.host?.lowercased().hasSuffix(".test") == true ? "api.m.sooplive.test" : "api.m.sooplive.co.kr"
        switch kind {
        case .vodView:
            components.path = "/station/video/a/view"
        case .catchView:
            components.path = "/station/video/a/catchview"
        }
        return components.url!
    }

    static func liveStatusURL(liveID: String, sourceURL: URL) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = sourceURL.host?.lowercased().hasSuffix(".test") == true ? "st.sooplive.test" : "st.sooplive.co.kr"
        components.path = "/api/get_station_status.php"
        components.queryItems = [URLQueryItem(name: "szBjId", value: liveID)]
        return components.url!
    }

    static func livePlayerAPIURL(liveID: String, sourceURL: URL) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = sourceURL.host?.lowercased().hasSuffix(".test") == true ? "live.sooplive.test" : "live.sooplive.co.kr"
        components.path = "/afreeca/player_live_api.php"
        components.queryItems = [URLQueryItem(name: "bjid", value: liveID)]
        return components.url!
    }

    static func livePlaylistURL(aid: String, sourceURL: URL) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = sourceURL.host?.lowercased().hasSuffix(".test") == true ? "pc-web.stream.sooplive.test" : "pc-web.stream.sooplive.co.kr"
        components.path = "/live-stm-16/auth_master_playlist.m3u8"
        components.queryItems = [URLQueryItem(name: "aid", value: aid)]
        return components.url!
    }

    static func formFields(kind: APIKind, id: String) -> [String: String] {
        switch kind {
        case .vodView:
            return [
                "nTitleNo": id,
                "nApiLevel": "10",
                "nPlaylistIdx": "0"
            ]
        case .catchView:
            return [
                "nTitleNo": id,
                "nPageNo": "1",
                "nLimit": "20"
            ]
        }
    }

    static func livePlayerFormFields(
        liveID: String,
        broadNo: String = "",
        requestType: String = "live",
        quality: String = "original"
    ) -> [String: String] {
        [
            "bid": liveID,
            "bno": broadNo,
            "type": requestType,
            "pwd": "",
            "player_type": "html5",
            "stream_type": "common",
            "quality": quality,
            "mode": "landing",
            "from_api": "0",
            "is_revive": "false"
        ]
    }

    static func liveStreamAssignmentURL(broadNo: String, sourceURL: URL, nonce: Double) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        let isTest = sourceURL.host?.lowercased().hasSuffix(".test") == true
        components.host = isTest
            ? "livestream-manager.sooplive.test"
            : "livestream-manager.sooplive.com"
        components.path = "/broad_stream_assign.html"
        components.queryItems = [
            URLQueryItem(name: "return_type", value: "gcp_cdn"),
            URLQueryItem(name: "use_cors", value: "true"),
            URLQueryItem(name: "cors_origin_url", value: isTest ? "play.sooplive.test" : "play.sooplive.com"),
            URLQueryItem(name: "broad_key", value: "\(broadNo)-common-master-hls"),
            URLQueryItem(name: "time", value: String(nonce))
        ]
        return components.url!
    }

    static func authenticatedLivePlaylistURL(viewURL: URL, aid: String) -> URL? {
        let replaced = viewURL.absoluteString.replacingOccurrences(
            of: "auth_master_playlist.m3u8",
            with: "auth_playlist.m3u8"
        )
        guard var components = URLComponents(string: replaced) else { return nil }
        var queryItems = components.queryItems ?? []
        queryItems.append(URLQueryItem(name: "aid", value: aid))
        components.queryItems = queryItems
        return components.url
    }

    static func liveQualityPreset(in value: Any, preferredResolution: String = "") -> SOOPLiveQualityPreset? {
        guard let root = value as? [String: Any],
              let channel = root["CHANNEL"] as? [String: Any],
              let rawPresets = channel["VIEWPRESET"] as? [Any] else {
            return nil
        }

        let presets = rawPresets.enumerated().compactMap { offset, value -> (Int, SOOPLiveQualityPreset)? in
            guard let item = value as? [String: Any],
                  let heightText = stringValue(item["label_resolution"]),
                  let height = Int(heightText),
                  height > 0,
                  let name = stringValue(item["name"]) else {
                return nil
            }
            let label = stringValue(item["label"]) ?? name
            return (offset, SOOPLiveQualityPreset(name: name, label: label, height: height))
        }
        .sorted { lhs, rhs in
            lhs.1.height == rhs.1.height ? lhs.0 < rhs.0 : lhs.1.height > rhs.1.height
        }
        .map(\.1)

        guard let minimumHeight = presets.map(\.height).min() else { return nil }
        let requestedHeight = max(preferredHeight(from: preferredResolution) ?? Int.max, minimumHeight)
        return presets.first(where: { $0.height <= requestedHeight })
    }

    static func liveResult(in value: Any) -> Int? {
        recursiveString(in: value, keys: ["RESULT", "result"]).flatMap(Int.init)
    }

    static func resolvedDownload(fromAPIData data: Data, sourceURL: URL, preferredResolution: String = "") async throws -> ResolvedDownload {
        let object = try JSONSerialization.jsonObject(with: data)
        return try await resolvedDownload(fromJSONObject: object, sourceURL: sourceURL, preferredResolution: preferredResolution)
    }

    static func resolvedDownload(fromJSONObject object: Any, sourceURL: URL, preferredResolution: String = "") async throws -> ResolvedDownload {
        guard let id = videoID(from: sourceURL) else {
            throw NativeDownloadError.invalidURL(sourceURL.absoluteString)
        }
        let candidates = videoCandidates(in: object, sourceURL: sourceURL)
        guard let best = bestCandidate(candidates, preferredResolution: preferredResolution) else {
            throw NativeDownloadError.noFiles
        }

        let info = videoInfo(in: object, fallbackID: id)
        if isM3U8(best.url) {
            let hls = try await M3U8Resolver().resolve(
                best.url,
                headers: HTTPRequestOptions(referer: sourceURL.absoluteString)
            )
            return ResolvedDownload(
                title: info.displayTitle,
                folderName: "SOOP \(info.displayTitle)".sanitizedFilename(maxLength: 120),
                assets: hls.assets.enumerated().map { offset, asset in
                    var enriched = asset
                    enriched.metadata = asset.metadata.merging(segmentMetadata(info: info, asset: asset, sourceURL: sourceURL, index: offset + 1)) { current, _ in current }
                    return enriched
                },
                packageMode: .concatenate(outputFilename: "\(info.title)-\(info.id).ts".sanitizedFilename(maxLength: 180)),
                metadata: hls.metadata.merging(metadata(info: info, candidate: best, sourceURL: sourceURL)) { _, new in new }
            )
        }

        let ext = best.url.pathExtension.trimmed.isEmpty ? "mp4" : best.url.pathExtension.lowercased()
        let filename = "\(info.title)-\(info.id).\(ext)".sanitizedFilename(maxLength: 180)
        return ResolvedDownload(
            title: info.displayTitle,
            folderName: "SOOP \(info.displayTitle)".sanitizedFilename(maxLength: 120),
            assets: [
                ResolvedAsset(
                    remoteURL: best.url,
                    filename: filename,
                    metadata: assetMetadata(info: info, candidate: best, sourceURL: sourceURL),
                    referer: sourceURL.absoluteString
                )
            ],
            packageMode: .concatenate(outputFilename: filename),
            metadata: metadata(info: info, candidate: best, sourceURL: sourceURL)
        )
    }

    static func resolvedLiveDownload(fromAPIData data: Data, statusObject: Any? = nil, pageHTML: String = "", sourceURL: URL, liveID: String, preferredResolution: String = "") async throws -> ResolvedDownload {
        let object = try JSONSerialization.jsonObject(with: data)
        return try await resolvedLiveDownload(
            fromJSONObject: object,
            statusObject: statusObject,
            pageHTML: pageHTML,
            sourceURL: sourceURL,
            liveID: liveID,
            preferredResolution: preferredResolution
        )
    }

    static func resolvedLiveDownload(fromJSONObject object: Any, statusObject: Any? = nil, pageHTML: String = "", sourceURL: URL, liveID: String, preferredResolution: String = "") async throws -> ResolvedDownload {
        let candidates = liveVideoCandidates(in: object, sourceURL: sourceURL)
        guard let best = bestCandidate(candidates, preferredResolution: preferredResolution) else {
            throw NativeDownloadError.noFiles
        }

        let info = liveInfo(in: object, statusObject: statusObject, pageHTML: pageHTML, liveID: liveID, sourceURL: sourceURL)
        if isM3U8(best.url) {
            let hls = try await M3U8Resolver().resolve(
                best.url,
                headers: HTTPRequestOptions(referer: sourceURL.absoluteString)
            )
            return resolvedLiveDownload(fromHLS: hls, info: info, candidate: best, sourceURL: sourceURL)
        }

        let ext = best.url.pathExtension.trimmed.isEmpty ? "mp4" : best.url.pathExtension.lowercased()
        let filename = "\(info.title)-\(info.id).\(ext)".sanitizedFilename(maxLength: 180)
        return ResolvedDownload(
            title: info.displayTitle,
            folderName: "SOOP \(info.displayTitle)".sanitizedFilename(maxLength: 120),
            assets: [
                ResolvedAsset(
                    remoteURL: best.url,
                    filename: filename,
                    metadata: liveAssetMetadata(info: info, candidate: best, sourceURL: sourceURL),
                    referer: sourceURL.absoluteString
                )
            ],
            packageMode: .concatenate(outputFilename: filename),
            metadata: liveMetadata(info: info, candidate: best, sourceURL: sourceURL)
        )
    }

    static func resolvedLiveDownload(fromHLS hls: ResolvedDownload, info: (id: String, title: String, displayTitle: String, uploader: String, date: String, thumbnail: URL?, liveID: String, broadNo: String), candidate: SOOPVideoCandidate, sourceURL: URL) -> ResolvedDownload {
        ResolvedDownload(
            title: info.displayTitle,
            folderName: "SOOP \(info.displayTitle)".sanitizedFilename(maxLength: 120),
            assets: hls.assets.enumerated().map { offset, asset in
                var enriched = asset
                enriched.metadata = asset.metadata.merging(liveSegmentMetadata(info: info, asset: asset, sourceURL: sourceURL, index: offset + 1)) { current, _ in current }
                return enriched
            },
            packageMode: .concatenate(outputFilename: "\(info.title)-\(info.id).ts".sanitizedFilename(maxLength: 180)),
            metadata: hls.metadata.merging(liveMetadata(info: info, candidate: candidate, sourceURL: sourceURL)) { _, new in new }
        )
    }

    static func videoCandidates(in value: Any, sourceURL: URL) -> [SOOPVideoCandidate] {
        var candidates: [SOOPVideoCandidate] = []
        collectVideoCandidates(in: value, sourceURL: sourceURL, keyPath: [], candidates: &candidates)

        var seen = Set<String>()
        return candidates.compactMap { candidate in
            let normalized = URLIdentity.normalize(candidate.url.absoluteString)
            guard !seen.contains(normalized) else { return nil }
            seen.insert(normalized)
            return candidate
        }
    }

    static func liveVideoCandidates(in value: Any, sourceURL: URL) -> [SOOPVideoCandidate] {
        var candidates = videoCandidates(in: value, sourceURL: sourceURL)
        if let aid = recursiveString(in: value, keys: ["AID", "aid"]),
           !aid.trimmed.isEmpty {
            candidates.append(SOOPVideoCandidate(
                url: livePlaylistURL(aid: aid, sourceURL: sourceURL),
                height: 0,
                label: "master",
                score: 1_000_000
            ))
        }

        var seen = Set<String>()
        return candidates.compactMap { candidate in
            let normalized = URLIdentity.normalize(candidate.url.absoluteString)
            guard !seen.contains(normalized) else { return nil }
            seen.insert(normalized)
            return candidate
        }
    }

    static func bestCandidate(_ candidates: [SOOPVideoCandidate], preferredResolution: String = "") -> SOOPVideoCandidate? {
        let heightLimit = preferredHeight(from: preferredResolution)
        let filtered: [SOOPVideoCandidate]
        if let heightLimit {
            let underLimit = candidates.filter { $0.height == 0 || $0.height <= heightLimit }
            filtered = underLimit.isEmpty ? candidates : underLimit
        } else {
            filtered = candidates
        }

        return filtered.max { lhs, rhs in
            if lhs.height != rhs.height { return lhs.height < rhs.height }
            if isM3U8(lhs.url) != isM3U8(rhs.url) { return !isM3U8(lhs.url) && isM3U8(rhs.url) }
            return lhs.score < rhs.score
        }
    }

    private static func fetchAPI(kind: APIKind, id: String, sourceURL: URL, headers: HTTPRequestOptions) async throws -> Data {
        try await HTTPClient.shared.postForm(
            to: apiURL(kind: kind, sourceURL: sourceURL),
            fields: formFields(kind: kind, id: id),
            referer: headers.referer ?? sourceURL.absoluteString,
            userAgent: headers.userAgent,
            additionalHeaders: ["Origin": "https://www.sooplive.co.kr"]
        )
    }

    private static func fetchLiveAPI(
        liveID: String,
        broadNo: String,
        requestType: String,
        quality: String,
        sourceURL: URL,
        headers: HTTPRequestOptions
    ) async throws -> Data {
        try await HTTPClient.shared.postForm(
            to: livePlayerAPIURL(liveID: liveID, sourceURL: sourceURL),
            fields: livePlayerFormFields(
                liveID: liveID,
                broadNo: broadNo,
                requestType: requestType,
                quality: quality
            ),
            referer: headers.referer ?? sourceURL.absoluteString,
            userAgent: headers.userAgent,
            additionalHeaders: ["Origin": "https://play.sooplive.com"]
        )
    }

    private static func collectVideoCandidates(in value: Any, sourceURL: URL, keyPath: [String], candidates: inout [SOOPVideoCandidate]) {
        if let raw = stringValue(value),
           let url = absoluteURL(raw, baseURL: sourceURL),
           isLikelyVideoURL(url) {
            candidates.append(SOOPVideoCandidate(
                url: url,
                height: heightFromContext(raw: raw, keyPath: keyPath),
                label: keyPath.last ?? "",
                score: score(raw: raw, keyPath: keyPath)
            ))
            return
        }

        if let dict = value as? [String: Any] {
            if let url = candidateURL(from: dict, sourceURL: sourceURL) {
                candidates.append(SOOPVideoCandidate(
                    url: url,
                    height: heightFromDictionary(dict, url: url),
                    label: label(from: dict),
                    score: score(raw: url.absoluteString, keyPath: keyPath + [label(from: dict)])
                ))
            }
            for (key, child) in dict {
                collectVideoCandidates(in: child, sourceURL: sourceURL, keyPath: keyPath + [key], candidates: &candidates)
            }
            return
        }

        if let array = value as? [Any] {
            for child in array {
                collectVideoCandidates(in: child, sourceURL: sourceURL, keyPath: keyPath, candidates: &candidates)
            }
        }
    }

    private static func candidateURL(from dict: [String: Any], sourceURL: URL) -> URL? {
        for key in ["file", "url", "src", "path", "video_url", "videoUrl", "stream_url", "streamUrl", "m3u8", "playlist"] {
            guard let raw = stringValue(dict[key]),
                  let url = absoluteURL(raw, baseURL: sourceURL),
                  isLikelyVideoURL(url) else {
                continue
            }
            return url
        }
        return nil
    }

    private static func videoInfo(in value: Any, fallbackID: String) -> (id: String, title: String, displayTitle: String, uploader: String, date: String, thumbnail: URL?) {
        let id = recursiveString(in: value, keys: ["nTitleNo", "title_no", "titleNo", "broad_no", "broadNo", "id"]) ?? fallbackID
        let title = cleanTitle(
            recursiveString(in: value, keys: ["full_title", "title", "subject", "broad_title", "broadTitle"]) ??
                "SOOP VOD \(fallbackID)",
            fallback: "SOOP VOD \(fallbackID)"
        )
        let uploader = cleanTitle(
            recursiveString(in: value, keys: ["writer_nick", "copyright_nickname", "original_user_nick", "user_nick", "nickname", "bj_id"]) ?? "",
            fallback: ""
        )
        let date = normalizedDate(
            recursiveString(in: value, keys: ["reg_date", "broad_start", "write_tm", "date", "upload_date"]) ?? ""
        )
        let thumbnailRaw = recursiveString(in: value, keys: ["thumb", "thumbnail", "thumbnail_url", "url_thumb", "poster"])
        let displayTitle = uploader.isEmpty ? title : "\(uploader) - \(title)"
        return (id, title, displayTitle.sanitizedFilename(maxLength: 120), uploader, date, thumbnailRaw.flatMap { absoluteURL($0, baseURL: URL(string: "https://www.sooplive.co.kr/")!) })
    }

    static func liveInfo(in value: Any, statusObject: Any? = nil, pageHTML: String = "", liveID: String, sourceURL: URL) -> (id: String, title: String, displayTitle: String, uploader: String, date: String, thumbnail: URL?, liveID: String, broadNo: String) {
        let broadNo = recursiveString(in: value, keys: ["nBroadNo", "broad_no", "broadNo", "bno"]) ??
            recursiveString(in: statusObject as Any, keys: ["nBroadNo", "broad_no", "broadNo", "bno"]) ??
            liveBroadNo(fromHTML: pageHTML) ??
            ""
        let title = cleanTitle(
            recursiveString(in: value, keys: ["broad_title", "broadTitle", "title", "full_title", "station_title"]) ??
                recursiveString(in: statusObject as Any, keys: ["broad_title", "broadTitle", "title", "station_title"]) ??
                metaContent(from: pageHTML, names: ["og:title", "twitter:title"]) ??
                "SOOP Live \(liveID)",
            fallback: "SOOP Live \(liveID)"
        )
        let uploader = cleanTitle(
            recursiveString(in: value, keys: ["user_nick", "bj_nick", "nickname", "writer_nick", "bj_id", "bid"]) ??
                recursiveString(in: statusObject as Any, keys: ["user_nick", "bj_nick", "nickname", "bj_id", "szBjId"]) ??
                liveID,
            fallback: liveID
        )
        let date = normalizedDate(
            recursiveString(in: value, keys: ["broad_start", "start_time", "date"]) ??
                recursiveString(in: statusObject as Any, keys: ["broad_start", "start_time", "date"]) ??
                ""
        )
        let thumbnailRaw = recursiveString(in: value, keys: ["url_thumb", "thumb", "thumbnail", "thumbnail_url", "poster"]) ??
            recursiveString(in: statusObject as Any, keys: ["url_thumb", "thumb", "thumbnail", "thumbnail_url", "poster"]) ??
            metaContent(from: pageHTML, names: ["og:image", "twitter:image"])
        let displayTitle = uploader.isEmpty || uploader.caseInsensitiveCompare(title) == .orderedSame ? title : "\(uploader) - \(title)"
        return (
            liveID,
            title,
            displayTitle.sanitizedFilename(maxLength: 120),
            uploader,
            date,
            thumbnailRaw.flatMap { absoluteURL($0, baseURL: sourceURL) },
            liveID,
            broadNo
        )
    }

    private static func metadata(info: (id: String, title: String, displayTitle: String, uploader: String, date: String, thumbnail: URL?), candidate: SOOPVideoCandidate, sourceURL: URL) -> [String: String] {
        let lowerPath = sourceURL.path.lowercased()
        let isCatch = lowerPath.contains("/catch")
        let isHLS = isM3U8(candidate.url)
        let pageURL = pageURL(for: sourceURL)
        let format = isHLS ? "m3u8" : mediaFormat(for: candidate.url, fallback: "mp4")
        return DownloadMetadata.clean([
            "site": "SOOP",
            "title": info.title,
            "series": info.uploader,
            "artist": info.uploader,
            "author": info.uploader,
            "creator": info.uploader,
            "uploader": info.uploader,
            "channel": info.uploader,
            "category": "video",
            "type": isHLS ? "hls" : "video",
            "media_type": isHLS ? "hls" : "video",
            "format": format,
            "media_format": format,
            "host": sourceURL.host ?? "",
            "id": info.id,
            "vod_id": info.id,
            "video_id": info.id,
            "media_id": info.id,
            "gallery_id": info.id,
            "media_count": isHLS ? "" : "1",
            "video_count": "1",
            "title_no": info.id,
            "broad_no": info.id,
            "content_id": info.id,
            "catch_id": isCatch ? info.id : "",
            "date": info.date,
            "published_date": info.date,
            "type_id": isCatch ? "catch" : "vod",
            "height": candidate.height > 0 ? String(candidate.height) : "",
            "quality": candidate.label,
            "thumbnail": info.thumbnail?.absoluteString ?? "",
            "video_url": candidate.url.absoluteString,
            "media_url": candidate.url.absoluteString,
            "playlist_url": isHLS ? candidate.url.absoluteString : "",
            "url": sourceURL.absoluteString,
            "source_url": sourceURL.absoluteString,
            "page_url": pageURL.absoluteString
        ])
    }

    private static func liveMetadata(info: (id: String, title: String, displayTitle: String, uploader: String, date: String, thumbnail: URL?, liveID: String, broadNo: String), candidate: SOOPVideoCandidate, sourceURL: URL) -> [String: String] {
        let isHLS = isM3U8(candidate.url)
        let pageURL = pageURL(for: sourceURL)
        let format = isHLS ? "m3u8" : mediaFormat(for: candidate.url, fallback: "mp4")
        return DownloadMetadata.clean([
            "site": "SOOP",
            "title": info.title,
            "series": info.uploader,
            "artist": info.uploader,
            "author": info.uploader,
            "creator": info.uploader,
            "uploader": info.uploader,
            "channel": info.uploader,
            "category": "video",
            "type": "live",
            "media_type": "live",
            "format": format,
            "media_format": format,
            "live": "true",
            "host": sourceURL.host ?? "",
            "id": info.id,
            "live_login": info.liveID,
            "bj_id": info.liveID,
            "broad_no": info.broadNo,
            "video_id": info.broadNo.isEmpty ? info.liveID : info.broadNo,
            "media_id": info.broadNo.isEmpty ? info.liveID : info.broadNo,
            "gallery_id": info.broadNo.isEmpty ? info.liveID : info.broadNo,
            "media_count": isHLS ? "" : "1",
            "video_count": "1",
            "date": info.date,
            "published_date": info.date,
            "type_id": "live",
            "height": candidate.height > 0 ? String(candidate.height) : "",
            "quality": candidate.label,
            "thumbnail": info.thumbnail?.absoluteString ?? "",
            "video_url": candidate.url.absoluteString,
            "media_url": candidate.url.absoluteString,
            "playlist_url": isHLS ? candidate.url.absoluteString : "",
            "url": sourceURL.absoluteString,
            "source_url": sourceURL.absoluteString,
            "page_url": pageURL.absoluteString
        ])
    }

    private static func assetMetadata(info: (id: String, title: String, displayTitle: String, uploader: String, date: String, thumbnail: URL?), candidate: SOOPVideoCandidate, sourceURL: URL) -> [String: String] {
        let lowerPath = sourceURL.path.lowercased()
        let isCatch = lowerPath.contains("/catch")
        let isHLS = isM3U8(candidate.url)
        let pageURL = pageURL(for: sourceURL)
        let format = isHLS ? "m3u8" : mediaFormat(for: candidate.url, fallback: "mp4")
        return DownloadMetadata.clean([
            "site": "SOOP",
            "title": info.title,
            "series": info.uploader,
            "artist": info.uploader,
            "author": info.uploader,
            "creator": info.uploader,
            "uploader": info.uploader,
            "channel": info.uploader,
            "category": "video",
            "type": isHLS ? "hls" : "video",
            "media_type": isHLS ? "hls" : "video",
            "format": format,
            "media_format": format,
            "id": info.id,
            "vod_id": info.id,
            "video_id": info.id,
            "media_id": info.id,
            "gallery_id": info.id,
            "title_no": info.id,
            "broad_no": info.id,
            "content_id": info.id,
            "catch_id": isCatch ? info.id : "",
            "date": info.date,
            "published_date": info.date,
            "type_id": isCatch ? "catch" : "vod",
            "page": "1",
            "position": "1",
            "height": candidate.height > 0 ? String(candidate.height) : "",
            "quality": candidate.label,
            "thumbnail": info.thumbnail?.absoluteString ?? "",
            "video_url": candidate.url.absoluteString,
            "media_url": candidate.url.absoluteString,
            "playlist_url": isHLS ? candidate.url.absoluteString : "",
            "source_url": sourceURL.absoluteString,
            "page_url": pageURL.absoluteString
        ])
    }

    private static func liveAssetMetadata(info: (id: String, title: String, displayTitle: String, uploader: String, date: String, thumbnail: URL?, liveID: String, broadNo: String), candidate: SOOPVideoCandidate, sourceURL: URL) -> [String: String] {
        let isHLS = isM3U8(candidate.url)
        let pageURL = pageURL(for: sourceURL)
        let baseID = info.broadNo.isEmpty ? info.liveID : info.broadNo
        let format = isHLS ? "m3u8" : mediaFormat(for: candidate.url, fallback: "mp4")
        return DownloadMetadata.clean([
            "site": "SOOP",
            "title": info.title,
            "series": info.uploader,
            "artist": info.uploader,
            "author": info.uploader,
            "creator": info.uploader,
            "uploader": info.uploader,
            "channel": info.uploader,
            "category": "video",
            "type": "live",
            "media_type": "live",
            "format": format,
            "media_format": format,
            "live": "true",
            "id": info.id,
            "live_login": info.liveID,
            "bj_id": info.liveID,
            "broad_no": info.broadNo,
            "video_id": baseID,
            "media_id": baseID,
            "gallery_id": baseID,
            "date": info.date,
            "published_date": info.date,
            "type_id": "live",
            "page": "1",
            "position": "1",
            "height": candidate.height > 0 ? String(candidate.height) : "",
            "quality": candidate.label,
            "thumbnail": info.thumbnail?.absoluteString ?? "",
            "video_url": candidate.url.absoluteString,
            "media_url": candidate.url.absoluteString,
            "playlist_url": isHLS ? candidate.url.absoluteString : "",
            "source_url": sourceURL.absoluteString,
            "page_url": pageURL.absoluteString
        ])
    }

    private static func segmentMetadata(info: (id: String, title: String, displayTitle: String, uploader: String, date: String, thumbnail: URL?), asset: ResolvedAsset, sourceURL: URL, index: Int) -> [String: String] {
        let lowerPath = sourceURL.path.lowercased()
        let isCatch = lowerPath.contains("/catch")
        let pageURL = pageURL(for: sourceURL)
        let format = mediaFormat(for: asset.remoteURL, fallback: mediaFormat(forFilename: asset.filename, fallback: "ts"))
        return DownloadMetadata.clean([
            "site": "SOOP",
            "title": info.title,
            "series": info.uploader,
            "artist": info.uploader,
            "author": info.uploader,
            "creator": info.uploader,
            "uploader": info.uploader,
            "channel": info.uploader,
            "category": "video",
            "type": "hls_segment",
            "media_type": "segment",
            "format": format,
            "media_format": format,
            "id": info.id,
            "vod_id": info.id,
            "video_id": info.id,
            "media_id": "\(info.id)-segment-\(index)",
            "gallery_id": info.id,
            "title_no": info.id,
            "broad_no": info.id,
            "content_id": info.id,
            "catch_id": isCatch ? info.id : "",
            "date": info.date,
            "published_date": info.date,
            "type_id": isCatch ? "catch" : "vod",
            "page": String(index),
            "position": String(index),
            "video_url": asset.remoteURL.absoluteString,
            "media_url": asset.remoteURL.absoluteString,
            "source_url": sourceURL.absoluteString,
            "page_url": pageURL.absoluteString
        ])
    }

    private static func liveSegmentMetadata(info: (id: String, title: String, displayTitle: String, uploader: String, date: String, thumbnail: URL?, liveID: String, broadNo: String), asset: ResolvedAsset, sourceURL: URL, index: Int) -> [String: String] {
        let pageURL = pageURL(for: sourceURL)
        let baseID = info.broadNo.isEmpty ? info.liveID : info.broadNo
        let format = mediaFormat(for: asset.remoteURL, fallback: mediaFormat(forFilename: asset.filename, fallback: "ts"))
        return DownloadMetadata.clean([
            "site": "SOOP",
            "title": info.title,
            "series": info.uploader,
            "artist": info.uploader,
            "author": info.uploader,
            "creator": info.uploader,
            "uploader": info.uploader,
            "channel": info.uploader,
            "category": "video",
            "type": "hls_segment",
            "media_type": "segment",
            "format": format,
            "media_format": format,
            "live": "true",
            "id": info.id,
            "live_login": info.liveID,
            "bj_id": info.liveID,
            "broad_no": info.broadNo,
            "video_id": baseID,
            "media_id": "\(baseID)-segment-\(index)",
            "gallery_id": baseID,
            "date": info.date,
            "published_date": info.date,
            "type_id": "live",
            "page": String(index),
            "position": String(index),
            "video_url": asset.remoteURL.absoluteString,
            "media_url": asset.remoteURL.absoluteString,
            "source_url": sourceURL.absoluteString,
            "page_url": pageURL.absoluteString
        ])
    }

    private static func pageURL(for sourceURL: URL) -> URL {
        canonicalURL(for: sourceURL) ?? sourceURL
    }

    private static func mediaFormat(for url: URL, fallback: String) -> String {
        let ext = url.pathExtension.trimmed
        return (ext.isEmpty ? fallback : ext).lowercased()
    }

    private static func mediaFormat(forFilename filename: String, fallback: String) -> String {
        let ext = (filename as NSString).pathExtension.trimmed
        return (ext.isEmpty ? fallback : ext).lowercased()
    }

    private static func recursiveString(in value: Any, keys: [String]) -> String? {
        if let dict = value as? [String: Any] {
            for key in keys {
                if let direct = stringValue(dict[key]) {
                    return direct
                }
            }
            for child in dict.values {
                if let found = recursiveString(in: child, keys: keys) {
                    return found
                }
            }
        }
        if let array = value as? [Any] {
            for child in array {
                if let found = recursiveString(in: child, keys: keys) {
                    return found
                }
            }
        }
        return nil
    }

    private static func heightFromDictionary(_ dict: [String: Any], url: URL) -> Int {
        for key in ["height", "resolution", "quality", "label", "name", "quality_name"] {
            if let value = stringValue(dict[key]) ?? intValue(dict[key]).map(String.init),
               let height = heightFromText(value) {
                return height
            }
        }
        return heightFromText(url.absoluteString) ?? 0
    }

    private static func heightFromContext(raw: String, keyPath: [String]) -> Int {
        let text = (keyPath + [raw]).joined(separator: " ")
        return heightFromText(text) ?? 0
    }

    private static func heightFromText(_ text: String) -> Int? {
        let patterns = [
            #"([0-9]{3,4})\s*p"#,
            #"([0-9]{3,4})\s*[xX]\s*[0-9]{3,4}"#,
            #"[^0-9]([0-9]{3,4})[^0-9]"#
        ]
        for pattern in patterns {
            if let value = firstCapture(pattern: pattern, in: text), let height = Int(value), (144...8640).contains(height) {
                return height
            }
        }
        return nil
    }

    private static func label(from dict: [String: Any]) -> String {
        for key in ["label", "quality", "quality_name", "resolution", "name"] {
            if let value = stringValue(dict[key]) {
                return cleanTitle(value, fallback: "")
            }
        }
        return ""
    }

    private static func score(raw: String, keyPath: [String]) -> Int {
        let lower = (keyPath.joined(separator: ".") + " " + raw).lowercased()
        var value = 0
        if lower.contains("original") || lower.contains("source") { value += 1_000_000 }
        if lower.contains("master") { value += 700_000 }
        if lower.contains("quality_info") { value += 500_000 }
        if lower.contains(".m3u8") { value += 100_000 }
        if lower.contains(".mp4") { value += 50_000 }
        value += heightFromText(lower) ?? 0
        return value
    }

    private static func preferredHeight(from value: String) -> Int? {
        var text = value.trimmed.lowercased()
        guard !text.isEmpty, text != "best", text != "source", text != "original" else {
            return nil
        }
        if text.hasSuffix("p") {
            text.removeLast()
        }
        switch text {
        case "2k": return 1_440
        case "4k": return 2_160
        case "8k": return 4_320
        default: break
        }
        guard text.range(of: #"^[0-9]{3,5}$"#, options: .regularExpression) != nil,
              let height = Int(text),
              (144...8_640).contains(height) else {
            return nil
        }
        return height
    }

    private static func isCatchURL(_ url: URL) -> Bool {
        url.path.lowercased().contains("catch")
    }

    private static func isLiveHost(_ host: String) -> Bool {
        host == "play.afreecatv.com" ||
            host == "bj.afreecatv.com" ||
            host == "ch.afreecatv.com" ||
            host == "play.sooplive.co.kr" ||
            host == "bj.sooplive.co.kr" ||
            host == "ch.sooplive.co.kr" ||
            host == "play.sooplive.com" ||
            host == "bj.sooplive.com" ||
            host == "ch.sooplive.com" ||
            host == "play.afreecatv.test" ||
            host == "bj.afreecatv.test" ||
            host == "ch.afreecatv.test" ||
            host == "play.sooplive.test" ||
            host == "bj.sooplive.test" ||
            host == "ch.sooplive.test"
    }

    private static func isSupportedHost(_ host: String) -> Bool {
        host == "afreecatv.com" ||
            host.hasSuffix(".afreecatv.com") ||
            host == "sooplive.com" ||
            host.hasSuffix(".sooplive.com") ||
            host == "sooplive.co.kr" ||
            host.hasSuffix(".sooplive.co.kr") ||
            host == "afreecatv.test" ||
            host.hasSuffix(".afreecatv.test") ||
            host == "sooplive.test" ||
            host.hasSuffix(".sooplive.test")
    }

    private static func absoluteURL(_ raw: String, baseURL: URL) -> URL? {
        var value = decodeHTML(normalizeEscapes(raw))
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'").union(.whitespacesAndNewlines))
        guard !value.isEmpty else { return nil }
        if value.hasPrefix("//") {
            value = "\(baseURL.scheme ?? "https"):\(value)"
        }
        return URL(string: value, relativeTo: baseURL)?.absoluteURL
    }

    private static func isLikelyVideoURL(_ url: URL) -> Bool {
        let value = url.absoluteString.lowercased()
        return ["mp4", "m3u8", "ts"].contains(url.pathExtension.lowercased()) ||
            value.contains(".mp4") ||
            value.contains(".m3u8") ||
            value.contains("auth_master_playlist") ||
            value.contains("playlist.m3u8")
    }

    private static func isValidLiveID(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z0-9_]{2,32}$"#, options: .regularExpression) != nil
    }

    private static func isM3U8(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "m3u8" || url.absoluteString.lowercased().contains(".m3u8")
    }

    private static func normalizedDate(_ raw: String) -> String {
        let value = raw.trimmed
        if let date = firstDateComponents(
            pattern: #"\b([12][0-9]{3})\s*[-./]\s*([0-9]{1,2})\s*[-./]\s*([0-9]{1,2})\b"#,
            in: value
        ) {
            return date
        }

        if let date = firstDateComponents(
            pattern: #"([12][0-9]{3})\s*년\s*([0-9]{1,2})\s*월\s*([0-9]{1,2})\s*일"#,
            in: value
        ) {
            return date
        }

        if let compact = firstCapture(pattern: #"(?<![0-9])([12][0-9]{3}(?:0[1-9]|1[0-2])(?:0[1-9]|[12][0-9]|3[01]))(?![0-9])"#, in: value) {
            let year = compact.prefix(4)
            let monthStart = compact.index(compact.startIndex, offsetBy: 4)
            let monthEnd = compact.index(compact.startIndex, offsetBy: 6)
            let month = compact[monthStart..<monthEnd]
            let day = compact.suffix(2)
            return normalizedDateString(year: Int(year), month: Int(month), day: Int(day)) ?? ""
        }

        if let timestamp = firstCapture(pattern: #"(?<![0-9])([0-9]{10}|[0-9]{13})(?![0-9])"#, in: value),
           let date = normalizedTimestampDate(timestamp) {
            return date
        }
        return ""
    }

    private static func firstDateComponents(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
              match.numberOfRanges > 3,
              let yearRange = Range(match.range(at: 1), in: text),
              let monthRange = Range(match.range(at: 2), in: text),
              let dayRange = Range(match.range(at: 3), in: text) else {
            return nil
        }
        return normalizedDateString(
            year: Int(text[yearRange]),
            month: Int(text[monthRange]),
            day: Int(text[dayRange])
        )
    }

    private static func normalizedDateString(year: Int?, month: Int?, day: Int?) -> String? {
        guard let year, let month, let day else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let components = DateComponents(calendar: calendar, timeZone: calendar.timeZone, year: year, month: month, day: day)
        guard let date = calendar.date(from: components) else { return nil }
        let resolved = calendar.dateComponents([.year, .month, .day], from: date)
        guard resolved.year == year, resolved.month == month, resolved.day == day else { return nil }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    private static func normalizedTimestampDate(_ raw: String) -> String? {
        guard let numeric = Double(raw) else { return nil }
        let seconds = raw.count == 13 ? numeric / 1_000 : numeric
        guard seconds > 0 else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Seoul") ?? TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date(timeIntervalSince1970: seconds))
    }

    private static func firstCapture(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[range])
    }

    private static func liveBroadNo(fromHTML html: String) -> String? {
        for pattern in [
            #"nBroadNo\s*=\s*['"]?([0-9]+)"#,
            #""nBroadNo"\s*:\s*"?([0-9]+)"#,
            #""broadNo"\s*:\s*"?([0-9]+)"#,
            #""broad_no"\s*:\s*"?([0-9]+)"#
        ] {
            if let value = firstCapture(pattern: pattern, in: html) {
                return value
            }
        }
        return nil
    }

    private static func metaContent(from html: String, names: [String]) -> String? {
        for name in names {
            let patterns = [
                #"<meta\b[^>]*(?:property|name)\s*=\s*["']\#(name)["'][^>]*content\s*=\s*["']([^"']+)["'][^>]*>"#,
                #"<meta\b[^>]*content\s*=\s*["']([^"']+)["'][^>]*(?:property|name)\s*=\s*["']\#(name)["'][^>]*>"#
            ]
            for pattern in patterns {
                if let value = firstCapture(pattern: pattern, in: html) {
                    return decodeHTML(value)
                }
            }
        }
        return nil
    }

    private static func cleanTitle(_ raw: String, fallback: String) -> String {
        let title = decodeHTML(stripTags(raw))
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmed
        return title.isEmpty ? fallback.sanitizedFilename(maxLength: 120) : title.sanitizedFilename(maxLength: 120)
    }

    private static func stripTags(_ raw: String) -> String {
        raw.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
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

    private static func decodeHTML(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#34;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
    }

    private static func stringValue(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            return string.trimmed.isEmpty ? nil : string
        case let number as NSNumber:
            return number.stringValue
        default:
            return nil
        }
    }

    private static func intValue(_ value: Any?) -> Int? {
        switch value {
        case let int as Int:
            return int
        case let number as NSNumber:
            return number.intValue
        case let string as String:
            return Int(string)
        default:
            return nil
        }
    }

    private static func isNumericID(_ value: String) -> Bool {
        value.range(of: #"^[0-9]{4,}$"#, options: .regularExpression) != nil
    }
}

enum APIKind {
    case vodView
    case catchView
}
