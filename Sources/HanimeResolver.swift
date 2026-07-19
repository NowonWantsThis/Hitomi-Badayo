import Foundation

final class HanimeResolver {
    private static let originalDefaultHeight = 720
    static let originalHLSConcurrency = 4
    static let originalIgnoredTailSegmentCount = 20

    struct StreamCandidate: Equatable {
        var url: URL
        var height: Int
        var sizeMB: Double
        var extensionHint: String
    }

    struct CurrentAPIConfiguration: Equatable {
        var authenticatedAPIBaseURL: URL
        var csrfTokenURL: URL
    }

    func canResolve(_ url: URL) -> Bool {
        Self.slug(from: url) != nil
    }

    func resolve(_ url: URL, headers: HTTPRequestOptions = HTTPRequestOptions(), preferredResolution: String = "") async throws -> ResolvedDownload {
        guard let slug = Self.slug(from: url) else {
            throw NativeDownloadError.invalidURL(url.absoluteString)
        }

        let pageURL = Self.canonicalURL(for: url) ?? url
        let html: String
        do {
            html = try await HTTPClient.shared.string(
                from: pageURL,
                referer: headers.referer,
                userAgent: headers.userAgent,
                additionalHeaders: ["X-Directive": "api"]
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw NativeDownloadError.unsupported(
                "Hanime page request failed before signed manifest lookup: \(error.localizedDescription)"
            )
        }

        var currentPlayerError: Error?
        if Self.usesCurrentHTVPlayer(fromHTML: html) {
            do {
                return try await Self.resolvedCurrentPlayerDownload(
                    fromPageHTML: html,
                    pageURL: pageURL,
                    userAgent: headers.userAgent,
                    preferredResolution: preferredResolution
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                currentPlayerError = error
            }
        }

        let apiHeaders = Self.apiHeaders()
        var manifestError: Error?
        for manifestURL in Self.manifestAPIURLs(slug: slug, sourceURL: pageURL) {
            let data: Data
            do {
                data = try await HTTPClient.shared.data(
                    from: manifestURL,
                    referer: pageURL.absoluteString,
                    userAgent: headers.userAgent,
                    additionalHeaders: apiHeaders
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                manifestError = error
                continue
            }
            return try await Self.resolvedDownload(
                fromPageHTML: html,
                manifestData: data,
                pageURL: pageURL,
                userAgent: headers.userAgent,
                preferredResolution: preferredResolution
            )
        }

        if let embedded = Self.embeddedManifestObject(fromHTML: html),
           let data = try? JSONSerialization.data(withJSONObject: embedded) {
            return try await Self.resolvedDownload(
                fromPageHTML: html,
                manifestData: data,
                pageURL: pageURL,
                userAgent: headers.userAgent,
                preferredResolution: preferredResolution
            )
        }

        if let currentPlayerError, let manifestError {
            throw NativeDownloadError.unsupported(
                "Hanime did not expose a playable current player or signed manifest: " +
                    "current player \(currentPlayerError.localizedDescription); " +
                    "signed manifest \(manifestError.localizedDescription)"
            )
        }
        if let manifestError {
            throw NativeDownloadError.unsupported(
                "Hanime did not expose a playable signed manifest: \(manifestError.localizedDescription)"
            )
        }
        throw NativeDownloadError.noFiles
    }

    static func slug(from url: URL) -> String? {
        guard let host = url.host?.lowercased(),
              isSupportedHost(host),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }

        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        let lower = parts.map { $0.lowercased() }

        if lower.count >= 3, lower[0] == "videos", lower[1] == "hentai", isValidSlug(parts[2]) {
            return parts[2]
        }
        if lower.count >= 2, ["hentai-videos", "videos", "video"].contains(lower[0]), isValidSlug(parts[1]) {
            return parts[1]
        }
        return nil
    }

    static func canonicalURL(for slug: String, sourceURL: URL) -> URL {
        var components = URLComponents()
        components.scheme = sourceURL.scheme ?? "https"
        components.host = sourceURL.host?.lowercased().hasSuffix(".test") == true ? "hanime.test" : "hanime.tv"
        components.path = "/videos/hentai/\(slug)"
        return components.url!
    }

    static func canonicalURL(for url: URL) -> URL? {
        guard let slug = slug(from: url) else { return nil }
        return canonicalURL(for: slug, sourceURL: url)
    }

    static func manifestAPIURL(slug: String, sourceURL: URL, compatibilityQuery: Bool = false) -> URL {
        var components = URLComponents()
        components.scheme = sourceURL.scheme ?? "https"
        components.host = sourceURL.host?.lowercased().hasSuffix(".test") == true ? "hanime.test" : "hanime.tv"
        components.path = "/rapi/v7/videos_manifests/\(slug)"
        if compatibilityQuery {
            components.queryItems = [URLQueryItem(name: "c", value: "0")]
        }
        return components.url!
    }

    static func manifestAPIURLs(slug: String, sourceURL: URL) -> [URL] {
        [
            manifestAPIURL(slug: slug, sourceURL: sourceURL),
            manifestAPIURL(slug: slug, sourceURL: sourceURL, compatibilityQuery: true)
        ]
    }

    static func videoInfo(fromHTML html: String, pageURL: URL) -> (id: String, title: String, brand: String, displayTitle: String, thumbnail: URL?) {
        let object = nuxtObject(fromHTML: html)
        let info = object.flatMap { firstDictionary(named: "hentai_video", in: $0) } ?? [:]
        let slug = slug(from: pageURL) ?? pageURL.lastPathComponent
        let currentTag = currentVideoTag(fromHTML: html, slug: slug)
        let playerProperties = astroPlayerProperties(fromHTML: html)
        let id = stringValue(info["id"]) ?? currentTag.flatMap { attributeValue("data-video-id", inTag: $0) } ?? slug
        let title = cleanTitle(
            stringValue(info["name"]) ??
                stringValue(info["title"]) ??
                currentTag.flatMap { attributeValue("data-video-name", inTag: $0) } ??
                metaContent(from: html, names: ["og:title", "twitter:title"]) ??
                titleTag(fromHTML: html) ??
                slug.replacingOccurrences(of: "-", with: " "),
            fallback: slug
        )
        let brand = cleanTitle(
            stringValue(info["brand"]) ?? stringValue(info["brand_name"]) ?? currentBrand(fromHTML: html) ?? "",
            fallback: ""
        )
        let displayTitle = brand.isEmpty ? title : "[\(brand)] \(title)"
        let thumbnailRaw = stringValue(info["poster_url"]) ??
            stringValue(info["posterUrl"]) ??
            stringValue(info["cover_url"]) ??
            astroStringValue(playerProperties?["poster_url"]) ??
            metaContent(from: html, names: ["og:image", "twitter:image"])
        return (id, title, brand, displayTitle, thumbnailRaw.flatMap { absoluteURL($0, baseURL: pageURL) })
    }

    static func usesCurrentHTVPlayer(fromHTML html: String) -> Bool {
        guard let properties = astroPlayerProperties(fromHTML: html),
              let slug = astroStringValue(properties["slug"]) else {
            return false
        }
        return isValidSlug(slug)
    }

    static func currentPlayerCandidate(playbackURL: URL, preferredResolution: String = "") -> StreamCandidate {
        let requestedHeight = preferredHeight(from: preferredResolution) ?? originalDefaultHeight
        let detectedHeight = firstCapture(
            pattern: #"(?:^|[^0-9])([0-9]{3,4})p(?:[^0-9]|$)"#,
            in: playbackURL.absoluteString
        ).flatMap(Int.init) ?? 0
        return StreamCandidate(
            url: playbackURL,
            height: detectedHeight > 0 ? detectedHeight : requestedHeight,
            sizeMB: 0,
            extensionHint: "m3u8"
        )
    }

    static func signatureScriptURL(fromHTML html: String, pageURL: URL) -> URL? {
        firstCapture(
            pattern: #"<script\b[^>]*src\s*=\s*[\"']([^\"']*/js/vendor\.[^\"']+\.js)[\"'][^>]*>"#,
            in: html
        ).flatMap { absoluteURL($0, baseURL: pageURL) }
    }

    static func currentAPIConfiguration(fromHTML html: String, pageURL: URL) -> CurrentAPIConfiguration {
        let object = balancedValue(afterPattern: #"window\.AppConfig\s*="#, in: html)
            .flatMap { $0.data(using: .utf8) }
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        let isFixture = pageURL.host?.lowercased().hasSuffix(".test") == true
        let defaultAuth = URL(string: isFixture ? "https://auth.hanime.test" : "https://auth.hanime.tv")!
        let defaultCSRF = URL(string: isFixture ? "https://ct.hanime.test/csrf-token" : "https://ct.hanime.tv/csrf-token")!
        return CurrentAPIConfiguration(
            authenticatedAPIBaseURL: stringValue(object?["authed_api_base_url"])
                .flatMap(URL.init(string:)) ?? defaultAuth,
            csrfTokenURL: stringValue(object?["csrf_token_url"])
                .flatMap(URL.init(string:)) ?? defaultCSRF
        )
    }

    static func bestCurrentPlayerCandidate(
        fromHandshakeObject object: Any,
        pageURL: URL,
        preferredResolution: String = ""
    ) -> StreamCandidate? {
        guard let dictionary = object as? [String: Any],
              let rawSources = dictionary["sources"] as? [Any] else {
            return nil
        }
        let candidates = rawSources.compactMap { value -> StreamCandidate? in
            guard let source = value as? [String: Any],
                  stringValue(source["kind"])?.lowercased() != "promotion",
                  let rawURL = stringValue(source["src"]),
                  let url = absoluteURL(rawURL, baseURL: pageURL),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https" else {
                return nil
            }
            let type = stringValue(source["type"])?.lowercased() ?? ""
            let isHLS = type.contains("mpegurl") ||
                url.path.lowercased().hasPrefix("/hls/") ||
                url.absoluteString.lowercased().contains(".m3u8")
            guard isHLS || isPlayableVideo(url) else { return nil }
            return StreamCandidate(
                url: url,
                height: intValue(source["height"]) ?? qualityFromURL(url),
                sizeMB: doubleValue(source["size_mb"]) ?? 0,
                extensionHint: isHLS ? "m3u8" : url.pathExtension.lowercased()
            )
        }
        return bestCandidate(in: candidates, preferredResolution: preferredResolution)
    }

    static func bestStreamCandidate(fromManifestData data: Data, pageURL: URL, preferredResolution: String = "") throws -> StreamCandidate? {
        let object = try JSONSerialization.jsonObject(with: data)
        let streams = manifestStreamDictionaries(in: object)
        let candidates = streams.compactMap { manifestCandidate(from: $0, pageURL: pageURL) }
        return bestCandidate(in: candidates, preferredResolution: preferredResolution)
    }

    private static func bestCandidate(in candidates: [StreamCandidate], preferredResolution: String) -> StreamCandidate? {
        let requestedHeight = preferredHeight(from: preferredResolution) ?? originalDefaultHeight
        let bounded = candidates.filter { $0.height <= requestedHeight }
        if let highest = bounded.map(\.height).max() {
            return bounded.last { $0.height == highest }
        }
        guard let lowest = candidates.map(\.height).min() else { return nil }
        return candidates.first { $0.height == lowest }
    }

    static func resolvedDirectDownload(candidate: StreamCandidate, pageHTML: String, pageURL: URL) -> ResolvedDownload {
        let info = videoInfo(fromHTML: pageHTML, pageURL: pageURL)
        let ext = candidate.url.pathExtension.trimmed.isEmpty ? (candidate.extensionHint.isEmpty ? "mp4" : candidate.extensionHint) : candidate.url.pathExtension
        let filename = originalOutputFilename(info: info, extension: ext)
        var downloadMetadata = metadata(info: info, pageURL: pageURL, videoURL: candidate.url, candidate: candidate)
        downloadMetadata["filename"] = filename
        downloadMetadata["basename"] = (filename as NSString).deletingPathExtension
        downloadMetadata["ext"] = ext.lowercased()
        return ResolvedDownload(
            title: info.displayTitle,
            folderName: "Hanime \(info.displayTitle)".sanitizedFilename(maxLength: 120),
            assets: [
                ResolvedAsset(
                    remoteURL: candidate.url,
                    filename: filename,
                    metadata: mediaMetadata(for: candidate, info: info, pageURL: pageURL),
                    referer: pageURL.absoluteString
                )
            ],
            packageMode: .concatenate(outputFilename: filename),
            metadata: DownloadMetadata.clean(downloadMetadata)
        )
    }

    static func embeddedManifestObject(fromHTML html: String) -> Any? {
        guard let object = nuxtObject(fromHTML: html) else { return nil }
        return firstDictionary(named: "videos_manifest", in: object) ??
            firstDictionary(named: "video_manifest", in: object) ??
            firstDictionary(named: "manifest", in: object)
    }

    private static func resolvedCurrentPlayerDownload(
        fromPageHTML html: String,
        pageURL: URL,
        userAgent: String?,
        preferredResolution: String
    ) async throws -> ResolvedDownload {
        guard let scriptURL = signatureScriptURL(fromHTML: html, pageURL: pageURL) else {
            throw HanimeHandshakeError.invalidConfiguration
        }
        let script = try await HTTPClient.shared.string(
            from: scriptURL,
            referer: pageURL.absoluteString,
            userAgent: userAgent,
            additionalHeaders: ["Accept": "*/*"]
        )
        let signature = try HanimeSignatureGenerator.generate(script: script, pageURL: pageURL)
        let configuration = currentAPIConfiguration(fromHTML: html, pageURL: pageURL)
        let origin = originString(for: pageURL)
        let baseHeaders = currentAPIHeaders(signature: signature, origin: origin)

        let (csrfData, _) = try await HTTPClient.shared.dataResponse(
            from: configuration.csrfTokenURL,
            referer: pageURL.absoluteString,
            userAgent: userAgent,
            additionalHeaders: baseHeaders
        )
        guard let csrfObject = try JSONSerialization.jsonObject(with: csrfData) as? [String: Any],
              let csrfToken = stringValue(csrfObject["csrf_token"]) else {
            throw HanimeHandshakeError.invalidConfiguration
        }

        let slug = slug(from: pageURL) ?? pageURL.lastPathComponent
        let encryptedRequest = try HanimeHandshakeCrypto.encodeJSONObject([
            "timestamp_unix": signature.timestamp,
            "directive": "htv_player_handshake",
            "slug": slug
        ])
        let body = try JSONSerialization.data(withJSONObject: ["token": encryptedRequest])
        let handshakeURL = appendingPath("api/v11/handshake", to: configuration.authenticatedAPIBaseURL)
        var handshakeHeaders = baseHeaders
        handshakeHeaders["x-csrf-token"] = csrfToken
        let (_, response) = try await HTTPClient.shared.postJSONResponse(
            to: handshakeURL,
            body: body,
            referer: pageURL.absoluteString,
            userAgent: userAgent,
            additionalHeaders: handshakeHeaders
        )
        guard let responseToken = response.value(forHTTPHeaderField: "x-token")?.trimmed,
              !responseToken.isEmpty else {
            throw HanimeHandshakeError.invalidEncryptedToken
        }
        let handshakeObject = try HanimeHandshakeCrypto.decodeJSONObject(responseToken)
        guard let candidate = bestCurrentPlayerCandidate(
            fromHandshakeObject: handshakeObject,
            pageURL: pageURL,
            preferredResolution: preferredResolution
        ) else {
            throw NativeDownloadError.noFiles
        }
        return try await resolvedDownload(
            fromPageHTML: html,
            candidate: candidate,
            pageURL: pageURL,
            userAgent: userAgent,
            preferredResolution: preferredResolution
        )
    }

    private static func currentAPIHeaders(
        signature: HanimeRequestSignature,
        origin: String
    ) -> [String: String] {
        [
            "Accept": "application/json",
            "Origin": origin,
            "x-signature": signature.value,
            "x-signature-version": "web2",
            "x-time": String(signature.timestamp)
        ]
    }

    private static func appendingPath(_ path: String, to baseURL: URL) -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        let prefix = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + [prefix, path]
            .filter { !$0.isEmpty }
            .joined(separator: "/")
        components.query = nil
        components.fragment = nil
        return components.url!
    }

    private static func originString(for url: URL) -> String {
        guard let scheme = url.scheme, let host = url.host else { return "https://hanime.tv" }
        if let port = url.port {
            return "\(scheme)://\(host):\(port)"
        }
        return "\(scheme)://\(host)"
    }

    private static func resolvedDownload(fromPageHTML html: String, manifestData: Data, pageURL: URL, userAgent: String?, preferredResolution: String = "") async throws -> ResolvedDownload {
        guard let candidate = try bestStreamCandidate(fromManifestData: manifestData, pageURL: pageURL, preferredResolution: preferredResolution) else {
            throw NativeDownloadError.noFiles
        }

        return try await resolvedDownload(
            fromPageHTML: html,
            candidate: candidate,
            pageURL: pageURL,
            userAgent: userAgent,
            preferredResolution: preferredResolution
        )
    }

    private static func resolvedDownload(fromPageHTML html: String, candidate: StreamCandidate, pageURL: URL, userAgent: String?, preferredResolution: String = "") async throws -> ResolvedDownload {
        if candidate.isHLS {
            let hls = try await M3U8Resolver().resolve(
                candidate.url,
                headers: HTTPRequestOptions(referer: pageURL.absoluteString, userAgent: userAgent),
                preferredResolution: preferredResolution
            )
            let info = videoInfo(fromHTML: html, pageURL: pageURL)
            let filename = originalOutputFilename(info: info, extension: "mp4")
            let contractedAssets = applyingOriginalHLSContract(to: hls.assets)
            var downloadMetadata = metadata(info: info, pageURL: pageURL, videoURL: candidate.url, candidate: candidate)
                .merging(hls.metadata) { current, _ in current }
            downloadMetadata["filename"] = filename
            downloadMetadata["basename"] = (filename as NSString).deletingPathExtension
            downloadMetadata["ext"] = "mp4"
            downloadMetadata["container"] = "mp4"
            downloadMetadata["segment_concurrency"] = String(originalHLSConcurrency)
            downloadMetadata["ignored_tail_segment_count"] = String(
                min(originalIgnoredTailSegmentCount, contractedAssets.filter { $0.metadata["type"] == "hls_segment" }.count)
            )
            return ResolvedDownload(
                title: info.displayTitle,
                folderName: "Hanime \(info.displayTitle)".sanitizedFilename(maxLength: 120),
                assets: contractedAssets.enumerated().map { offset, asset in
                    var enriched = asset
                    enriched.metadata = asset.metadata.merging(segmentMetadata(info: info, asset: asset, pageURL: pageURL, index: offset + 1)) { _, new in new }
                    return enriched
                },
                packageMode: .concatenate(outputFilename: filename),
                metadata: DownloadMetadata.clean(downloadMetadata)
            )
        }

        let response = try await HTTPClient.shared.head(
            from: candidate.url,
            referer: pageURL.absoluteString,
            userAgent: userAgent
        )
        guard let response, response.expectedContentLength > 0 else {
            throw NativeDownloadError.unsupported("Hanime direct stream size is 0.")
        }
        return resolvedDirectDownload(candidate: candidate, pageHTML: html, pageURL: pageURL)
    }

    static func apiHeaders(signature: String? = nil, timestamp: Int? = nil) -> [String: String] {
        [
            "Accept": "application/json, text/plain, */*",
            "X-Directive": "api",
            "x-signature": signature ?? makeAPISignature(),
            "x-signature-version": "web2",
            "x-time": String(timestamp ?? Int(Date().timeIntervalSince1970))
        ]
    }

    static func makeAPISignature() -> String {
        let digits = Array("0123456789abcdef")
        var generator = SystemRandomNumberGenerator()
        return String((0..<32).map { _ in digits.randomElement(using: &generator)! })
    }

    static func applyingOriginalHLSContract(to assets: [ResolvedAsset]) -> [ResolvedAsset] {
        let segmentIndexes = assets.indices.filter { assets[$0].metadata["type"] == "hls_segment" }
        let ignoredIndexes = Set(segmentIndexes.suffix(originalIgnoredTailSegmentCount))
        return assets.enumerated().map { index, asset in
            var contracted = asset
            contracted.metadata["asset_concurrency_override"] = String(originalHLSConcurrency)
            if ignoredIndexes.contains(index) {
                contracted.metadata["python_ignore_error"] = "true"
                contracted.metadata["ignore_error_scope"] = "hanime_tail_20"
            }
            return contracted
        }
    }

    private static func originalOutputFilename(
        info: (id: String, title: String, brand: String, displayTitle: String, thumbnail: URL?),
        extension rawExtension: String
    ) -> String {
        let ext = rawExtension.trimmingCharacters(in: CharacterSet(charactersIn: ". ")).lowercased()
        let suffix = ext.isEmpty ? "" : ".\(ext)"
        return "\(info.displayTitle) (\(info.id))\(suffix)".sanitizedFilename(maxLength: 180)
    }

    private static func metadata(info: (id: String, title: String, brand: String, displayTitle: String, thumbnail: URL?), pageURL: URL, videoURL: URL, candidate: StreamCandidate) -> [String: String] {
        DownloadMetadata.clean([
            "site": "Hanime",
            "title": info.displayTitle,
            "series": info.brand,
            "artist": info.brand,
            "author": info.brand,
            "creator": info.brand,
            "brand": info.brand,
            "category": "video",
            "type": candidate.isHLS ? "hls" : "video",
            "media_type": candidate.isHLS ? "hls" : "video",
            "format": mediaFormat(for: candidate),
            "media_format": mediaFormat(for: candidate),
            "host": pageURL.host ?? "",
            "id": info.id,
            "video_id": info.id,
            "media_id": info.id,
            "gallery_id": info.id,
            "media_count": candidate.isHLS ? "" : "1",
            "video_count": "1",
            "height": candidate.height > 0 ? String(candidate.height) : "",
            "resolution": resolution(for: candidate),
            "quality": qualityLabel(for: candidate),
            "size_mb": candidate.sizeMB > 0 ? String(candidate.sizeMB) : "",
            "thumbnail": info.thumbnail?.absoluteString ?? "",
            "video_url": videoURL.absoluteString,
            "media_url": videoURL.absoluteString,
            "playlist_url": candidate.isHLS ? videoURL.absoluteString : "",
            "url": pageURL.absoluteString,
            "source_url": pageURL.absoluteString,
            "page_url": pageURL.absoluteString
        ])
    }

    private static func mediaMetadata(for candidate: StreamCandidate, info: (id: String, title: String, brand: String, displayTitle: String, thumbnail: URL?), pageURL: URL) -> [String: String] {
        DownloadMetadata.clean([
            "site": "Hanime",
            "title": info.displayTitle,
            "series": info.brand,
            "artist": info.brand,
            "author": info.brand,
            "creator": info.brand,
            "brand": info.brand,
            "category": "video",
            "type": candidate.isHLS ? "hls" : "video",
            "media_type": candidate.isHLS ? "hls" : "video",
            "format": mediaFormat(for: candidate),
            "media_format": mediaFormat(for: candidate),
            "id": info.id,
            "video_id": info.id,
            "media_id": info.id,
            "gallery_id": info.id,
            "page": "1",
            "position": "1",
            "height": candidate.height > 0 ? String(candidate.height) : "",
            "resolution": resolution(for: candidate),
            "quality": qualityLabel(for: candidate),
            "size_mb": candidate.sizeMB > 0 ? String(candidate.sizeMB) : "",
            "video_url": candidate.url.absoluteString,
            "media_url": candidate.url.absoluteString,
            "playlist_url": candidate.isHLS ? candidate.url.absoluteString : "",
            "source_url": pageURL.absoluteString,
            "page_url": pageURL.absoluteString
        ])
    }

    private static func segmentMetadata(info: (id: String, title: String, brand: String, displayTitle: String, thumbnail: URL?), asset: ResolvedAsset, pageURL: URL, index: Int) -> [String: String] {
        let format = mediaFormat(for: asset.remoteURL, fallback: mediaFormat(forFilename: asset.filename, fallback: "ts"))
        return DownloadMetadata.clean([
            "site": "Hanime",
            "title": info.displayTitle,
            "series": info.brand,
            "artist": info.brand,
            "author": info.brand,
            "creator": info.brand,
            "brand": info.brand,
            "category": "video",
            "type": "hls_segment",
            "media_type": "segment",
            "format": format,
            "media_format": format,
            "id": info.id,
            "video_id": info.id,
            "media_id": "\(info.id)-segment-\(index)",
            "gallery_id": info.id,
            "page": String(index),
            "position": String(index),
            "video_url": asset.remoteURL.absoluteString,
            "media_url": asset.remoteURL.absoluteString,
            "source_url": pageURL.absoluteString,
            "page_url": pageURL.absoluteString
        ])
    }

    private static func mediaFormat(for candidate: StreamCandidate) -> String {
        if candidate.isHLS { return "m3u8" }
        let ext = candidate.url.pathExtension.lowercased()
        if !ext.isEmpty { return ext }
        let hint = candidate.extensionHint.lowercased()
        return hint.isEmpty ? "mp4" : hint
    }

    private static func mediaFormat(for url: URL, fallback: String) -> String {
        let ext = url.pathExtension.trimmed
        return (ext.isEmpty ? fallback : ext).lowercased()
    }

    private static func mediaFormat(forFilename filename: String, fallback: String) -> String {
        let ext = (filename as NSString).pathExtension.trimmed
        return (ext.isEmpty ? fallback : ext).lowercased()
    }

    private static func resolution(for candidate: StreamCandidate) -> String {
        candidate.height > 0 ? "\(candidate.height)p" : ""
    }

    private static func qualityLabel(for candidate: StreamCandidate) -> String {
        resolution(for: candidate)
    }

    private static func preferredHeight(from preferredResolution: String) -> Int? {
        var value = preferredResolution.trimmed.lowercased()
        guard !value.isEmpty else { return nil }
        if value.hasSuffix("p") {
            value.removeLast()
        }
        switch value {
        case "2k": return 1440
        case "4k": return 2160
        case "8k": return 4320
        default: break
        }
        guard value.range(of: #"^[0-9]{3,5}$"#, options: .regularExpression) != nil,
              let height = Int(value),
              (144...8640).contains(height) else {
            return nil
        }
        return height
    }

    private static func manifestStreamDictionaries(in object: Any) -> [[String: Any]] {
        if let dictionary = object as? [String: Any] {
            if let servers = dictionary["servers"] as? [Any] {
                return servers.flatMap { server -> [[String: Any]] in
                    guard let server = server as? [String: Any],
                          let streams = server["streams"] as? [Any] else { return [] }
                    return streams.compactMap { $0 as? [String: Any] }
                }
            }
            for key in ["videos_manifest", "video_manifest", "manifest"] {
                if let manifest = dictionary[key] {
                    let streams = manifestStreamDictionaries(in: manifest)
                    if !streams.isEmpty { return streams }
                }
            }
        }
        return streamDictionaries(in: object)
    }

    private static func manifestCandidate(from dict: [String: Any], pageURL: URL) -> StreamCandidate? {
        let raw = stringValue(dict["url"]) ?? candidateRawURL(from: dict)
        guard let raw,
              !raw.contains("deprecated."),
              let url = absoluteURL(raw, baseURL: pageURL),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }
        let height = intValue(dict["height"]) ??
            intValue(dict["resolution"]) ??
            intValue(dict["quality"]) ??
            qualityFromURL(url)
        let size = doubleValue(dict["filesize_mbs"]) ??
            doubleValue(dict["filesize_mb"]) ??
            doubleValue(dict["size_mb"]) ??
            0
        let ext = stringValue(dict["extension"])?.lowercased() ?? url.pathExtension.lowercased()
        return StreamCandidate(url: url, height: height, sizeMB: size, extensionHint: ext)
    }

    private static func streamDictionaries(in object: Any) -> [[String: Any]] {
        if let dict = object as? [String: Any] {
            var found: [[String: Any]] = []
            if candidateRawURL(from: dict) != nil {
                found.append(dict)
            }
            for value in dict.values {
                found.append(contentsOf: streamDictionaries(in: value))
            }
            return found
        }
        if let array = object as? [Any] {
            return array.flatMap(streamDictionaries(in:))
        }
        return []
    }

    private static func candidateRawURL(from dict: [String: Any]) -> String? {
        for key in ["url", "file", "src", "video_url", "videoUrl", "stream_url", "streamUrl"] {
            if let raw = stringValue(dict[key]), isLikelyVideoURL(raw) {
                return raw
            }
        }
        return nil
    }

    private static func nuxtObject(fromHTML html: String) -> [String: Any]? {
        guard let value = balancedValue(afterPattern: #"window\.__NUXT__\s*="#, in: html),
              let data = value.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object
    }

    private static func astroPlayerProperties(fromHTML html: String) -> [String: Any]? {
        guard let tag = firstCapture(
            pattern: #"(<astro-island\b[^>]*component-url\s*=\s*[\"'][^\"']*HTVPlayer[^\"']*[\"'][^>]*>)"#,
            in: html
        ),
        let rawProperties = attributeValue("props", inTag: tag),
        let data = rawProperties.data(using: .utf8),
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object
    }

    private static func astroStringValue(_ value: Any?) -> String? {
        if let array = value as? [Any], array.count > 1 {
            return stringValue(array[1])
        }
        return stringValue(value)
    }

    private static func currentVideoTag(fromHTML html: String, slug: String) -> String? {
        let escapedSlug = NSRegularExpression.escapedPattern(for: slug)
        return firstCapture(
            pattern: #"(<[^>]+\bdata-video-slug\s*=\s*[\"']\#(escapedSlug)[\"'][^>]*>)"#,
            in: html
        )
    }

    private static func currentBrand(fromHTML html: String) -> String? {
        firstCapture(
            pattern: #"<a\b[^>]*href\s*=\s*[\"']/browse/brands/[^\"']+[\"'][^>]*>.*?<strong\b[^>]*>(.*?)</strong>"#,
            in: html
        ).map { decodeHTML(stripTags($0)).trimmed }
    }

    private static func attributeValue(_ name: String, inTag tag: String) -> String? {
        let escapedName = NSRegularExpression.escapedPattern(for: name)
        guard let value = firstCapture(
            pattern: #"\b\#(escapedName)\s*=\s*[\"']([^\"']*)[\"']"#,
            in: tag
        ) else {
            return nil
        }
        return decodeHTML(value)
    }

    private static func firstDictionary(named key: String, in value: Any) -> [String: Any]? {
        if let dict = value as? [String: Any] {
            if let direct = dict[key] as? [String: Any] {
                return direct
            }
            for child in dict.values {
                if let found = firstDictionary(named: key, in: child) {
                    return found
                }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let found = firstDictionary(named: key, in: child) {
                    return found
                }
            }
        }
        return nil
    }

    private static func balancedValue(afterPattern pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
              let matchRange = Range(match.range, in: text) else {
            return nil
        }
        var index = matchRange.upperBound
        while index < text.endIndex, text[index].isWhitespace {
            index = text.index(after: index)
        }
        guard index < text.endIndex,
              text[index] == "{" || text[index] == "[" else {
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

    private static func titleTag(fromHTML html: String) -> String? {
        guard let raw = firstCapture(pattern: #"<title\b[^>]*>(.*?)</title>"#, in: html) else {
            return nil
        }
        return decodeHTML(stripTags(raw))
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

    private static func absoluteURL(_ raw: String, baseURL: URL) -> URL? {
        var value = decodeHTML(raw)
            .replacingOccurrences(of: #"\/"#, with: "/")
            .trimmed
        guard !value.isEmpty else { return nil }
        if value.hasPrefix("//") {
            value = (baseURL.scheme ?? "https") + ":" + value
        }
        return URL(string: value, relativeTo: baseURL)?.absoluteURL
    }

    private static func isPlayableVideo(_ url: URL) -> Bool {
        let value = url.absoluteString.lowercased()
        return ["mp4", "m3u8", "webm", "m4v", "mov"].contains(url.pathExtension.lowercased()) ||
            value.contains(".mp4") ||
            value.contains(".m3u8")
    }

    private static func isM3U8(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "m3u8" || url.absoluteString.lowercased().contains(".m3u8")
    }

    private static func isLikelyVideoURL(_ raw: String) -> Bool {
        let value = raw.lowercased()
        return value.hasPrefix("http://") || value.hasPrefix("https://") || value.hasPrefix("//")
            ? value.contains(".mp4") || value.contains(".m3u8") || value.contains(".webm")
            : false
    }

    private static func qualityFromURL(_ url: URL) -> Int {
        firstCapture(pattern: #"([0-9]{3,4})p"#, in: url.absoluteString).flatMap(Int.init) ??
            firstCapture(pattern: #"/([0-9]{3,4})/"#, in: url.absoluteString).flatMap(Int.init) ??
            0
    }

    private static func isSupportedHost(_ host: String) -> Bool {
        host == "hanime.tv" ||
            host == "www.hanime.tv" ||
            host == "hanime.test" ||
            host == "www.hanime.test"
    }

    private static func isValidSlug(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z0-9][A-Za-z0-9_-]*$"#, options: .regularExpression) != nil
    }

    private static func cleanTitle(_ raw: String, fallback: String) -> String {
        let title = decodeHTML(stripTags(raw))
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmed
        return title.isEmpty ? fallback : title.sanitizedFilename(maxLength: 120)
    }

    private static func stripTags(_ raw: String) -> String {
        raw.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
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
            return Int(string.trimmingCharacters(in: CharacterSet(charactersIn: "pP ")))
        default:
            return nil
        }
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        switch value {
        case let double as Double:
            return double
        case let number as NSNumber:
            return number.doubleValue
        case let string as String:
            return Double(string)
        default:
            return nil
        }
    }
}

private extension HanimeResolver.StreamCandidate {
    var isHLS: Bool {
        extensionHint.lowercased() == "m3u8" ||
            url.pathExtension.lowercased() == "m3u8" ||
            url.absoluteString.lowercased().contains(".m3u8") ||
            url.path.lowercased().hasPrefix("/hls/")
    }
}
