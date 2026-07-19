import Foundation

struct TwitterMediaAsset {
    var remoteURL: URL
    var type: String
    var filenameExtension: String
}

struct TwitterSpaceMediaCandidate {
    var url: URL
    var format: String
    var mediaType: String
    var score: Int
}

final class TwitterResolver {
    func canResolve(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(),
              Self.isSupportedHost(host),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return false
        }
        return Self.tweetID(from: url) != nil ||
            Self.twitpicID(from: url) != nil ||
            Self.twitterSpaceID(from: url) != nil ||
            Self.twitterBroadcastID(from: url) != nil
    }

    func resolve(
        _ url: URL,
        headers: HTTPRequestOptions = HTTPRequestOptions(),
        preferGraphQL: Bool = true
    ) async throws -> ResolvedDownload {
        if let spaceID = Self.twitterSpaceID(from: url) {
            let html = try await HTTPClient.shared.string(from: url, referer: headers.referer, userAgent: headers.userAgent)
            return try await Self.resolvedSpaceDownload(fromHTML: html, spaceID: spaceID, sourceURL: url, headers: headers)
        }

        if let broadcastID = Self.twitterBroadcastID(from: url) {
            let html = try await HTTPClient.shared.string(from: url, referer: headers.referer, userAgent: headers.userAgent)
            return try await Self.resolvedBroadcastDownload(fromHTML: html, broadcastID: broadcastID, sourceURL: url, headers: headers)
        }

        if let twitpicID = Self.twitpicID(from: url) {
            let html = try await HTTPClient.shared.string(from: url, referer: headers.referer, userAgent: headers.userAgent)
            return try Self.resolvedTwitPicDownload(fromHTML: html, twitpicID: twitpicID, sourceURL: url)
        }

        guard let tweetID = Self.tweetID(from: url) else {
            throw NativeDownloadError.invalidURL(url.absoluteString)
        }

        var graphQLError: Error?
        if preferGraphQL {
            do {
                let api = TwitterGraphQLAPI(sourceURL: url, options: headers)
                let tweets = try await api.tweetChain(tweetID: tweetID)
                let payloads = tweets.map(TwitterGraphQLAPI.mediaPayload)
                let twitPicMedia = await Self.twitpicMediaAssets(in: payloads, sourceURL: url, headers: headers)
                var resolved = try Self.resolvedDownload(
                    fromJSONObject: payloads,
                    tweetID: tweetID,
                    sourceURL: url,
                    extraMedia: twitPicMedia
                )
                resolved.metadata["resolver_api"] = "TweetResultByRestId"
                resolved.metadata["quoted_tweet_count"] = String(max(0, tweets.count - 1))
                return resolved
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as TwitterGraphQLAPIError {
                throw error
            } catch {
                graphQLError = error
            }
        }

        var htmlError: Error?
        do {
            let html = try await HTTPClient.shared.string(from: url, referer: headers.referer, userAgent: headers.userAgent)
            let htmlTwitPicMedia = await Self.twitpicMediaAssets(fromText: html, sourceURL: url, headers: headers)
            if let resolved = try? Self.resolvedDownload(
                fromHTML: html,
                tweetID: tweetID,
                sourceURL: url,
                extraMedia: htmlTwitPicMedia
            ) {
                return resolved
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            htmlError = error
        }

        do {
            let data = try await HTTPClient.shared.data(
                from: Self.syndicationURL(tweetID: tweetID, sourceURL: url),
                referer: headers.referer ?? url.absoluteString,
                userAgent: headers.userAgent,
                additionalHeaders: ["Accept": "application/json, text/plain, */*"]
            )
            let object = try JSONSerialization.jsonObject(with: data)
            let twitPicMedia = await Self.twitpicMediaAssets(in: object, sourceURL: url, headers: headers)
            return try Self.resolvedDownload(
                fromJSONObject: object,
                tweetID: tweetID,
                sourceURL: url,
                extraMedia: twitPicMedia
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw graphQLError ?? htmlError ?? error
        }
    }

    static func resolvedDownload(fromHTML html: String, tweetID: String, sourceURL: URL, extraMedia: [TwitterMediaAsset] = []) throws -> ResolvedDownload {
        let objects = jsonObjects(fromHTML: html)
        var media: [TwitterMediaAsset] = []
        for object in objects {
            media.append(contentsOf: mediaAssets(in: object, sourceURL: sourceURL))
        }
        media.append(contentsOf: metadataMediaAssets(fromHTML: html, sourceURL: sourceURL))
        media.append(contentsOf: extraMedia)
        return try resolvedDownload(
            fromMedia: media,
            tweetID: tweetID,
            username: username(fromHTML: html),
            userID: userID(fromHTML: html),
            title: title(fromHTML: html),
            sourceURL: sourceURL
        )
    }

    static func resolvedDownload(fromJSONData data: Data, tweetID: String, sourceURL: URL, extraMedia: [TwitterMediaAsset] = []) throws -> ResolvedDownload {
        let object = try JSONSerialization.jsonObject(with: data)
        return try resolvedDownload(fromJSONObject: object, tweetID: tweetID, sourceURL: sourceURL, extraMedia: extraMedia)
    }

    static func resolvedDownload(fromJSONObject object: Any, tweetID: String, sourceURL: URL, extraMedia: [TwitterMediaAsset] = []) throws -> ResolvedDownload {
        let username = authorUsername(in: object) ?? username(in: object)
        let userID = authorUserID(in: object) ?? userID(in: object)
        let title = text(in: object)
        return try resolvedDownload(
            fromMedia: mediaAssets(in: object, sourceURL: sourceURL) + extraMedia,
            tweetID: tweetID,
            username: username,
            userID: userID,
            title: title,
            sourceURL: sourceURL
        )
    }

    static func resolvedTwitPicDownload(fromHTML html: String, twitpicID: String, sourceURL: URL) throws -> ResolvedDownload {
        guard let media = twitpicMediaAsset(fromHTML: html, pageURL: sourceURL) else {
            throw NativeDownloadError.noFiles
        }

        let title = (title(fromHTML: html) ?? "TwitPic \(twitpicID)").sanitizedFilename(maxLength: 120)
        return ResolvedDownload(
            title: title,
            folderName: "TwitPic \(title)".sanitizedFilename(maxLength: 120),
            assets: [
                ResolvedAsset(
                    remoteURL: media.remoteURL,
                    filename: "\(twitpicID).\(media.filenameExtension.trimmed.isEmpty ? "jpg" : media.filenameExtension)".sanitizedFilename(maxLength: 180),
                    metadata: mediaMetadata(for: media, sourceURL: sourceURL, index: 1),
                    referer: sourceURL.absoluteString
                )
            ],
            metadata: DownloadMetadata.clean([
                "id": twitpicID,
                "photo_id": twitpicID,
                "post_id": twitpicID,
                "series": title,
                "category": "twitpic",
                "type": "photo",
                "format": mediaFormat(for: media),
                "media_format": mediaFormat(for: media),
                "media_id": twitpicID,
                "gallery_id": twitpicID,
                "media_count": "1",
                "photo_count": "1",
                "video_count": "0",
                "media_url": media.remoteURL.absoluteString,
                "image_url": media.remoteURL.absoluteString,
                "url": sourceURL.absoluteString,
                "source": sourceURL.absoluteString,
                "source_url": sourceURL.absoluteString,
                "page_url": sourceURL.absoluteString,
                "site": "TwitPic",
                "title": title
            ])
        )
    }

    static func tweetID(from url: URL) -> String? {
        let parts = url.path.split(separator: "/").map { String($0).removingPercentEncoding ?? String($0) }
        let markers = ["status", "statuses"]
        for marker in markers {
            guard let index = parts.firstIndex(where: { $0.lowercased() == marker }),
                  index + 1 < parts.count else {
                continue
            }
            let candidate = parts[index + 1]
            if isNumericID(candidate) {
                return candidate
            }
        }

        if parts.count >= 3,
           parts[0].lowercased() == "i",
           parts[1].lowercased() == "web",
           parts[2].lowercased() == "status",
           parts.count > 3,
           isNumericID(parts[3]) {
            return parts[3]
        }
        return nil
    }

    static func twitpicID(from url: URL) -> String? {
        guard let host = url.host?.lowercased(),
              host == "twitpic.com" || host == "www.twitpic.com" || host == "twitpic.test" || host == "www.twitpic.test" else {
            return nil
        }
        let parts = url.path.split(separator: "/").map { String($0).removingPercentEncoding ?? String($0) }
        guard let first = parts.first?.trimmed,
              first.range(of: #"^[A-Za-z0-9_]+$"#, options: .regularExpression) != nil,
              !["photos", "media", "search", "account", "home"].contains(first.lowercased()) else {
            return nil
        }
        return first
    }

    static func twitterSpaceID(from url: URL) -> String? {
        let parts = url.path.split(separator: "/").map { String($0).removingPercentEncoding ?? String($0) }
        guard parts.count >= 3,
              parts[0].lowercased() == "i",
              parts[1].lowercased() == "spaces" else {
            return nil
        }
        let candidate = parts[2].trimmed
        guard candidate.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil else {
            return nil
        }
        return candidate
    }

    static func twitterBroadcastID(from url: URL) -> String? {
        let parts = url.path.split(separator: "/").map { String($0).removingPercentEncoding ?? String($0) }
        guard parts.count >= 3,
              parts[0].lowercased() == "i",
              parts[1].lowercased() == "broadcasts" else {
            return nil
        }
        let candidate = parts[2].trimmed
        guard candidate.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil else {
            return nil
        }
        return candidate
    }

    static func resolvedSpaceDownload(fromHTML html: String, spaceID: String, sourceURL: URL, headers: HTTPRequestOptions = HTTPRequestOptions()) async throws -> ResolvedDownload {
        guard let candidate = bestSpaceMediaCandidate(fromHTML: html, sourceURL: sourceURL) else {
            throw NativeDownloadError.noFiles
        }

        let title = spaceTitle(fromHTML: html, fallbackID: spaceID)
        if candidate.format == "m3u8" {
            let hls = try await M3U8Resolver().resolve(
                candidate.url,
                headers: HTTPRequestOptions(referer: sourceURL.absoluteString, userAgent: headers.userAgent)
            )
            return ResolvedDownload(
                title: title,
                folderName: "Twitter Space \(title)".sanitizedFilename(maxLength: 120),
                assets: hlsAssetsWithPageMetadata(
                    hls.assets,
                    id: spaceID,
                    idKey: "space_id",
                    title: title,
                    category: "space",
                    sourceURL: sourceURL,
                    candidate: candidate
                ),
                packageMode: .concatenate(outputFilename: "\(title)-\(spaceID).ts".sanitizedFilename(maxLength: 180)),
                metadata: spaceMetadata(spaceID: spaceID, title: title, sourceURL: sourceURL, candidate: candidate)
                    .merging(hls.metadata) { current, _ in current }
            )
        }

        let filename = "\(title)-\(spaceID).\(candidate.format)".sanitizedFilename(maxLength: 180)
        return ResolvedDownload(
            title: title,
            folderName: "Twitter Space \(title)".sanitizedFilename(maxLength: 120),
            assets: [
                ResolvedAsset(
                    remoteURL: candidate.url,
                    filename: filename,
                    metadata: mediaMetadata(for: candidate, sourceURL: sourceURL),
                    referer: sourceURL.absoluteString
                )
            ],
            packageMode: .concatenate(outputFilename: filename),
            metadata: spaceMetadata(spaceID: spaceID, title: title, sourceURL: sourceURL, candidate: candidate)
        )
    }

    static func resolvedBroadcastDownload(fromHTML html: String, broadcastID: String, sourceURL: URL, headers: HTTPRequestOptions = HTTPRequestOptions()) async throws -> ResolvedDownload {
        guard let candidate = bestSpaceMediaCandidate(fromHTML: html, sourceURL: sourceURL) else {
            throw NativeDownloadError.noFiles
        }

        let title = broadcastTitle(fromHTML: html, fallbackID: broadcastID)
        if candidate.format == "m3u8" {
            let hls = try await M3U8Resolver().resolve(
                candidate.url,
                headers: HTTPRequestOptions(referer: sourceURL.absoluteString, userAgent: headers.userAgent)
            )
            return ResolvedDownload(
                title: title,
                folderName: "Twitter Broadcast \(title)".sanitizedFilename(maxLength: 120),
                assets: hlsAssetsWithPageMetadata(
                    hls.assets,
                    id: broadcastID,
                    idKey: "broadcast_id",
                    title: title,
                    category: "broadcast",
                    sourceURL: sourceURL,
                    candidate: candidate
                ),
                packageMode: .concatenate(outputFilename: "\(title)-\(broadcastID).ts".sanitizedFilename(maxLength: 180)),
                metadata: broadcastMetadata(broadcastID: broadcastID, title: title, sourceURL: sourceURL, candidate: candidate)
                    .merging(hls.metadata) { current, _ in current }
            )
        }

        let filename = "\(title)-\(broadcastID).\(candidate.format)".sanitizedFilename(maxLength: 180)
        return ResolvedDownload(
            title: title,
            folderName: "Twitter Broadcast \(title)".sanitizedFilename(maxLength: 120),
            assets: [
                ResolvedAsset(
                    remoteURL: candidate.url,
                    filename: filename,
                    metadata: mediaMetadata(for: candidate, sourceURL: sourceURL),
                    referer: sourceURL.absoluteString
                )
            ],
            packageMode: .concatenate(outputFilename: filename),
            metadata: broadcastMetadata(broadcastID: broadcastID, title: title, sourceURL: sourceURL, candidate: candidate)
        )
    }

    static func mediaAssets(in value: Any, sourceURL: URL) -> [TwitterMediaAsset] {
        var results: [TwitterMediaAsset] = []
        collectMediaAssets(in: value, sourceURL: sourceURL, results: &results)
        return deduped(results)
    }

    static func syndicationURL(tweetID: String, sourceURL: URL) -> URL {
        var components = URLComponents()
        components.scheme = sourceURL.scheme ?? "https"
        components.host = sourceURL.host?.lowercased().hasSuffix(".test") == true ? "cdn.syndication.twitter.test" : "cdn.syndication.twimg.com"
        components.path = "/tweet-result"
        components.queryItems = [
            URLQueryItem(name: "id", value: tweetID),
            URLQueryItem(name: "lang", value: "en")
        ]
        return components.url!
    }

    static func bestSpaceMediaCandidate(fromHTML html: String, sourceURL: URL) -> TwitterSpaceMediaCandidate? {
        var candidates = spaceMediaCandidates(fromText: html, sourceURL: sourceURL)
        for object in jsonObjects(fromHTML: html) {
            candidates.append(contentsOf: spaceMediaCandidates(in: object, sourceURL: sourceURL))
        }
        var seen = Set<String>()
        let unique = candidates.filter { candidate in
            let key = URLIdentity.normalize(candidate.url.absoluteString)
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
        return unique.max {
            if $0.score == $1.score {
                return $0.url.absoluteString < $1.url.absoluteString
            }
            return $0.score < $1.score
        }
    }

    private static func resolvedDownload(fromMedia media: [TwitterMediaAsset], tweetID: String, username: String?, userID: String?, title: String?, sourceURL: URL) throws -> ResolvedDownload {
        let media = deduped(media)
        guard !media.isEmpty else {
            throw NativeDownloadError.noFiles
        }

        let cleanUsername = cleanTitle(username ?? "")
        let baseTitle = cleanTitle(title ?? "")
        let displayTitle: String
        if !cleanUsername.isEmpty, !baseTitle.isEmpty {
            displayTitle = "@\(cleanUsername) - \(baseTitle)"
        } else if !cleanUsername.isEmpty {
            displayTitle = "@\(cleanUsername) - \(tweetID)"
        } else if !baseTitle.isEmpty {
            displayTitle = baseTitle
        } else {
            displayTitle = "Tweet \(tweetID)"
        }

        let assets = media.enumerated().map { offset, item in
            ResolvedAsset(
                remoteURL: item.remoteURL,
                filename: filename(for: item, tweetID: tweetID, index: offset + 1, total: media.count),
                metadata: mediaMetadata(for: item, sourceURL: sourceURL, index: offset + 1),
                referer: sourceURL.absoluteString
            )
        }
        let photoCount = media.filter { $0.type == "photo" }.count
        let videoCount = media.filter { $0.type == "video" }.count
        let mediaType = photoCount > 0 && videoCount > 0 ? "mixed" : (videoCount > 0 ? "video" : "photo")
        let firstMedia = media.first?.remoteURL.absoluteString ?? ""
        let firstPhoto = media.first(where: { $0.type == "photo" })?.remoteURL.absoluteString ?? ""

        return ResolvedDownload(
            title: displayTitle.sanitizedFilename(maxLength: 120),
            folderName: "Twitter \(displayTitle)".sanitizedFilename(maxLength: 120),
            assets: assets,
            metadata: DownloadMetadata.clean([
                "site": "Twitter",
                "title": displayTitle,
                "series": displayTitle,
                "category": "post",
                "type": mediaType,
                "id": tweetID,
                "tweet_id": tweetID,
                "post_id": tweetID,
                "media_id": tweetID,
                "gallery_id": tweetID,
                "media_count": String(media.count),
                "photo_count": String(photoCount),
                "video_count": String(videoCount),
                "media_url": firstMedia,
                "thumbnail": firstPhoto,
                "url": sourceURL.absoluteString,
                "source": sourceURL.absoluteString,
                "source_url": sourceURL.absoluteString,
                "page_url": sourceURL.absoluteString,
                "uid": userID ?? "",
                "user_id": userID ?? "",
                "uploader_id": userID ?? "",
                "channel_id": userID ?? "",
                "artist": cleanUsername,
                "author": cleanUsername,
                "creator": cleanUsername,
                "user": cleanUsername,
                "username": cleanUsername,
                "uploader": cleanUsername,
                "channel": cleanUsername
            ])
        )
    }

    private static func collectMediaAssets(in value: Any, sourceURL: URL, results: inout [TwitterMediaAsset]) {
        if let dictionary = value as? [String: Any] {
            if let item = mediaAsset(fromMediaDictionary: dictionary, sourceURL: sourceURL) {
                results.append(item)
            }

            for key in ["extended_entities", "entities"] {
                if let media = (dictionary[key] as? [String: Any])?["media"] as? [[String: Any]] {
                    results.append(contentsOf: media.compactMap { mediaAsset(fromMediaDictionary: $0, sourceURL: sourceURL) })
                }
            }

            if let media = dictionary["media"] as? [[String: Any]] {
                results.append(contentsOf: media.compactMap { mediaAsset(fromMediaDictionary: $0, sourceURL: sourceURL) })
            }
            if let mediaDetails = dictionary["mediaDetails"] as? [[String: Any]] {
                results.append(contentsOf: mediaDetails.compactMap { mediaAsset(fromMediaDictionary: $0, sourceURL: sourceURL) })
            }
            if let photos = dictionary["photos"] as? [[String: Any]] {
                results.append(contentsOf: photos.compactMap { photoAsset(from: $0, sourceURL: sourceURL) })
            }
            if let video = dictionary["video"] as? [String: Any],
               let item = videoAsset(from: video, sourceURL: sourceURL) {
                results.append(item)
            }

            for child in dictionary.values {
                collectMediaAssets(in: child, sourceURL: sourceURL, results: &results)
            }
        } else if let array = value as? [Any] {
            for child in array {
                collectMediaAssets(in: child, sourceURL: sourceURL, results: &results)
            }
        }
    }

    private static func mediaAsset(fromMediaDictionary dictionary: [String: Any], sourceURL: URL) -> TwitterMediaAsset? {
        let type = (stringValue(dictionary["type"]) ?? stringValue(dictionary["media_type"]) ?? "").lowercased()
        if type == "video" || type == "animated_gif" || dictionary["video_info"] is [String: Any] {
            let videoInfo = dictionary["video_info"] as? [String: Any] ?? dictionary
            return videoAsset(from: videoInfo, sourceURL: sourceURL)
        }

        if type == "photo" || dictionary["media_url_https"] != nil || dictionary["media_url"] != nil {
            let raw = stringValue(dictionary["media_url_https"]) ??
                stringValue(dictionary["media_url"]) ??
                stringValue(dictionary["url"]) ??
                stringValue(dictionary["expanded_url"])
            guard let raw,
                  let remote = imageURL(from: raw, sourceURL: sourceURL) else {
                return nil
            }
            return TwitterMediaAsset(remoteURL: remote, type: "photo", filenameExtension: filenameExtension(forImageURL: remote))
        }

        return nil
    }

    private static func photoAsset(from dictionary: [String: Any], sourceURL: URL) -> TwitterMediaAsset? {
        guard let raw = stringValue(dictionary["url"]) ?? stringValue(dictionary["media_url_https"]) ?? stringValue(dictionary["media_url"]),
              let remote = imageURL(from: raw, sourceURL: sourceURL) else {
            return nil
        }
        return TwitterMediaAsset(remoteURL: remote, type: "photo", filenameExtension: filenameExtension(forImageURL: remote))
    }

    private static func videoAsset(from dictionary: [String: Any], sourceURL: URL) -> TwitterMediaAsset? {
        let variants = dictionary["variants"] as? [[String: Any]] ??
            dictionary["videoVariants"] as? [[String: Any]] ??
            dictionary["video_variants"] as? [[String: Any]] ??
            []
        let direct = variants.compactMap { videoCandidate(from: $0, sourceURL: sourceURL) }
        if let best = direct.max(by: { $0.score < $1.score }) {
            return TwitterMediaAsset(remoteURL: best.url, type: "video", filenameExtension: "mp4")
        }

        if let raw = stringValue(dictionary["url"]) ?? stringValue(dictionary["src"]) ?? stringValue(dictionary["playbackUrl"]),
           let remote = absoluteURL(raw, baseURL: sourceURL),
           isMP4Video(remote.absoluteString, mimeType: stringValue(dictionary["content_type"]) ?? stringValue(dictionary["type"])) {
            return TwitterMediaAsset(remoteURL: remote, type: "video", filenameExtension: "mp4")
        }
        return nil
    }

    private struct VideoCandidate {
        var url: URL
        var score: Int
    }

    private static func videoCandidate(from dictionary: [String: Any], sourceURL: URL) -> VideoCandidate? {
        let raw = stringValue(dictionary["url"]) ?? stringValue(dictionary["src"]) ?? stringValue(dictionary["playbackUrl"])
        let mimeType = stringValue(dictionary["content_type"]) ?? stringValue(dictionary["contentType"]) ?? stringValue(dictionary["type"])
        guard let raw,
              let url = absoluteURL(raw, baseURL: sourceURL),
              isMP4Video(raw, mimeType: mimeType) else {
            return nil
        }
        let bitrate = intValue(dictionary["bitrate"]) ?? intValue(dictionary["bit_rate"]) ?? 0
        let width = intValue(dictionary["width"]) ?? 0
        let height = intValue(dictionary["height"]) ?? 0
        return VideoCandidate(url: url, score: bitrate * 10_000 + width * 100 + height)
    }

    private static func metadataMediaAssets(fromHTML html: String, sourceURL: URL) -> [TwitterMediaAsset] {
        let imageNames: Set<String> = ["og:image", "og:image:url", "og:image:secure_url", "twitter:image", "twitter:image:src"]
        let videoNames: Set<String> = ["og:video", "og:video:url", "og:video:secure_url", "twitter:player:stream"]
        var assets: [TwitterMediaAsset] = []

        for raw in metaContents(fromHTML: html, names: imageNames) {
            if let remote = imageURL(from: raw, sourceURL: sourceURL) {
                assets.append(TwitterMediaAsset(remoteURL: remote, type: "photo", filenameExtension: filenameExtension(forImageURL: remote)))
            }
        }
        for raw in metaContents(fromHTML: html, names: videoNames) {
            if let remote = absoluteURL(raw, baseURL: sourceURL), isMP4Video(remote.absoluteString, mimeType: nil) {
                assets.append(TwitterMediaAsset(remoteURL: remote, type: "video", filenameExtension: "mp4"))
            }
        }
        return deduped(assets)
    }

    static func twitpicURLs(from text: String, sourceURL: URL) -> [URL] {
        let normalized = decodeHTML(normalizeEscapes(text))
        guard let regex = try? NSRegularExpression(
            pattern: #"(?i)(?:https?:)?//twitpic\.(?:com|test)/[A-Za-z0-9_]+"#
        ) else {
            return []
        }

        var urls: [URL] = []
        var seen = Set<String>()
        let range = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
        for match in regex.matches(in: normalized, range: range) {
            guard let matchRange = Range(match.range, in: normalized) else { continue }
            var raw = String(normalized[matchRange])
            if raw.hasPrefix("//") {
                raw = "\(sourceURL.scheme ?? "https"):\(raw)"
            }
            guard let url = URL(string: raw) else { continue }
            let key = URLIdentity.normalize(url.absoluteString)
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            urls.append(url)
        }
        return urls
    }

    static func twitpicMediaAsset(fromHTML html: String, pageURL: URL) -> TwitterMediaAsset? {
        var candidates = metaContents(fromHTML: html, names: ["og:image", "og:image:url", "og:image:secure_url", "twitter:image", "twitter:image:src"])
        let normalized = decodeHTML(normalizeEscapes(html))

        if let regex = try? NSRegularExpression(pattern: #""(?:media_url_https|media_url|url_media|url)"\s*:\s*"([^"]+)""#, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
            let range = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
            for match in regex.matches(in: normalized, range: range) {
                guard let capture = Range(match.range(at: 1), in: normalized) else { continue }
                candidates.append(String(normalized[capture]))
            }
        }

        if let regex = try? NSRegularExpression(pattern: #"<img\b([^>]*)>"#, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
            let range = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
            for match in regex.matches(in: normalized, range: range) {
                guard let attrRange = Range(match.range(at: 1), in: normalized) else { continue }
                let attributes = String(normalized[attrRange])
                let values = attributeValues(from: attributes)
                let marker = "\(values["id"] ?? "") \(values["class"] ?? "") \(values["src"] ?? "")".lowercased()
                guard marker.contains("photo") || marker.contains("media") || marker.contains("twitpic") else { continue }
                if let src = values["src"] ?? values["data-src"] {
                    candidates.append(src)
                }
            }
        }

        for candidate in candidates {
            guard let remote = absoluteURL(candidate, baseURL: pageURL),
                  isTwitPicImageCandidate(remote, pageURL: pageURL) else {
                continue
            }
            let finalURL = imageURL(from: remote.absoluteString, sourceURL: pageURL) ?? remote
            return TwitterMediaAsset(remoteURL: finalURL, type: "photo", filenameExtension: filenameExtension(forImageURL: finalURL))
        }

        return nil
    }

    static func spaceMediaCandidates(fromText text: String, sourceURL: URL) -> [TwitterSpaceMediaCandidate] {
        let normalized = decodeHTML(normalizeEscapes(text))
        guard let regex = try? NSRegularExpression(
            pattern: #"https?://[^"'\\\s<>]+?\.(?:m3u8|mp3|m4a|aac|mp4)(?:\?[^"'\\\s<>]*)?"#,
            options: [.caseInsensitive]
        ) else {
            return []
        }

        var candidates: [TwitterSpaceMediaCandidate] = []
        let range = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
        for match in regex.matches(in: normalized, range: range) {
            guard let matchRange = Range(match.range, in: normalized),
                  let url = absoluteURL(String(normalized[matchRange]), baseURL: sourceURL),
                  let candidate = spaceMediaCandidate(from: url) else {
                continue
            }
            candidates.append(candidate)
        }
        return candidates
    }

    static func spaceMediaCandidates(in value: Any, sourceURL: URL) -> [TwitterSpaceMediaCandidate] {
        var strings: [String] = []
        collectStrings(in: value, into: &strings)
        return strings.flatMap { spaceMediaCandidates(fromText: $0, sourceURL: sourceURL) }
    }

    private static func spaceMediaCandidate(from url: URL) -> TwitterSpaceMediaCandidate? {
        let absolute = url.absoluteString.lowercased()
        let format: String
        if absolute.contains(".m3u8") {
            format = "m3u8"
        } else {
            format = url.pathExtension.lowercased()
        }
        guard ["m3u8", "mp3", "m4a", "aac", "mp4"].contains(format) else {
            return nil
        }

        let mediaType = format == "mp4" ? "video" : "audio"
        let baseScore: Int
        switch format {
        case "m3u8": baseScore = 5_000
        case "m4a", "aac": baseScore = 4_000
        case "mp3": baseScore = 3_000
        case "mp4": baseScore = 2_000
        default: baseScore = 0
        }
        return TwitterSpaceMediaCandidate(url: url, format: format, mediaType: mediaType, score: baseScore + bitrateScore(from: absolute))
    }

    private static func spaceTitle(fromHTML html: String, fallbackID: String) -> String {
        let metaTitle = metaContents(fromHTML: html, names: ["og:title", "twitter:title"]).first.map(cleanTweetTitle)
        let objectTitle = jsonObjects(fromHTML: html).compactMap { spaceTitle(in: $0) }.first
        let title = cleanTitle(metaTitle ?? objectTitle ?? "Twitter Space \(fallbackID)")
        return title.isEmpty ? "Twitter Space \(fallbackID)" : title
    }

    private static func broadcastTitle(fromHTML html: String, fallbackID: String) -> String {
        let metaTitle = metaContents(fromHTML: html, names: ["og:title", "twitter:title"]).first.map(cleanTweetTitle)
        let objectTitle = jsonObjects(fromHTML: html).compactMap { spaceTitle(in: $0) }.first
        let title = cleanTitle(metaTitle ?? objectTitle ?? "Twitter Broadcast \(fallbackID)")
        return title.isEmpty ? "Twitter Broadcast \(fallbackID)" : title
    }

    private static func spaceTitle(in value: Any) -> String? {
        if let dictionary = value as? [String: Any] {
            for key in ["title", "name", "space_title", "spaceTitle"] {
                if let title = stringValue(dictionary[key]), !title.trimmed.isEmpty {
                    return title
                }
            }
            for child in dictionary.values {
                if let title = spaceTitle(in: child) {
                    return title
                }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let title = spaceTitle(in: child) {
                    return title
                }
            }
        }
        return nil
    }

    private static func spaceMetadata(spaceID: String, title: String, sourceURL: URL, candidate: TwitterSpaceMediaCandidate) -> [String: String] {
        let mediaType = candidate.format == "m3u8" ? "hls" : candidate.mediaType
        return DownloadMetadata.clean([
            "site": "Twitter",
            "title": title,
            "series": title,
            "category": "space",
            "type": mediaType,
            "media_type": mediaType,
            "format": candidate.format,
            "media_format": candidate.format,
            "id": spaceID,
            "space_id": spaceID,
            "media_id": spaceID,
            "gallery_id": spaceID,
            "host": sourceURL.host ?? "",
            "url": sourceURL.absoluteString,
            "source_url": sourceURL.absoluteString,
            "page_url": sourceURL.absoluteString,
            "media_url": candidate.url.absoluteString,
            "audio_url": candidate.url.absoluteString
        ])
    }

    private static func broadcastMetadata(broadcastID: String, title: String, sourceURL: URL, candidate: TwitterSpaceMediaCandidate) -> [String: String] {
        let mediaType = candidate.format == "m3u8" ? "hls" : candidate.mediaType
        return DownloadMetadata.clean([
            "site": "Twitter",
            "title": title,
            "series": title,
            "category": "broadcast",
            "type": mediaType,
            "media_type": mediaType,
            "format": candidate.format,
            "media_format": candidate.format,
            "id": broadcastID,
            "broadcast_id": broadcastID,
            "media_id": broadcastID,
            "gallery_id": broadcastID,
            "host": sourceURL.host ?? "",
            "url": sourceURL.absoluteString,
            "source_url": sourceURL.absoluteString,
            "page_url": sourceURL.absoluteString,
            "media_url": candidate.url.absoluteString,
            "audio_url": candidate.mediaType == "audio" || candidate.format == "m3u8" ? candidate.url.absoluteString : "",
            "video_url": candidate.mediaType == "video" || candidate.format == "m3u8" ? candidate.url.absoluteString : "",
            "media_count": "1",
            "audio_count": candidate.mediaType == "audio" || candidate.format == "m3u8" ? "1" : "0",
            "video_count": candidate.mediaType == "video" || candidate.format == "m3u8" ? "1" : "0",
            "live": "true",
            "live_status": "broadcast"
        ])
    }

    private static func mediaMetadata(for candidate: TwitterSpaceMediaCandidate, sourceURL: URL? = nil) -> [String: String] {
        var metadata = [
            "type": candidate.mediaType,
            "media_type": candidate.mediaType,
            "format": candidate.format,
            "media_format": candidate.format,
            "media_url": candidate.url.absoluteString,
            "source_url": candidate.url.absoluteString,
            "page_url": sourceURL?.absoluteString ?? ""
        ]
        if candidate.mediaType == "video" {
            metadata["video_url"] = candidate.url.absoluteString
        } else {
            metadata["audio_url"] = candidate.url.absoluteString
        }
        return DownloadMetadata.clean(metadata)
    }

    static func hlsAssetsWithPageMetadata(_ assets: [ResolvedAsset], id: String, idKey: String, title: String, category: String, sourceURL: URL, candidate: TwitterSpaceMediaCandidate) -> [ResolvedAsset] {
        assets.enumerated().map { offset, asset in
            var enriched = asset
            enriched.metadata = asset.metadata.merging(hlsSegmentMetadata(
                id: id,
                idKey: idKey,
                title: title,
                category: category,
                sourceURL: sourceURL,
                candidate: candidate,
                asset: asset,
                index: offset + 1
            )) { _, new in new }
            return enriched
        }
    }

    private static func hlsSegmentMetadata(id: String, idKey: String, title: String, category: String, sourceURL: URL, candidate: TwitterSpaceMediaCandidate, asset: ResolvedAsset, index: Int) -> [String: String] {
        let type = asset.metadata["type"] ?? "hls_segment"
        let format = mediaFormat(for: asset.remoteURL, fallback: mediaFormat(forFilename: asset.filename, fallback: "ts"))
        let isSpace = category == "space"
        var metadata = DownloadMetadata.clean([
            "site": "Twitter",
            "title": title,
            "series": title,
            "category": category,
            "type": type,
            "media_type": type == "hls_segment" ? "segment" : type,
            "format": format,
            "media_format": format,
            "id": id,
            idKey: id,
            "media_id": "\(id)-segment-\(index)",
            "gallery_id": id,
            "page": String(index),
            "position": String(index),
            "playlist_url": asset.metadata["playlist_url"] ?? candidate.url.absoluteString,
            "media_url": asset.remoteURL.absoluteString,
            "source_url": sourceURL.absoluteString,
            "page_url": sourceURL.absoluteString,
            "live": "true",
            "live_status": category
        ])
        if isSpace {
            metadata["audio_url"] = asset.remoteURL.absoluteString
        } else {
            metadata["video_url"] = asset.remoteURL.absoluteString
        }
        return metadata
    }

    private static func mediaFormat(for url: URL, fallback: String) -> String {
        let ext = url.pathExtension.lowercased()
        return ext.isEmpty ? fallback : ext
    }

    private static func mediaFormat(forFilename filename: String, fallback: String) -> String {
        let ext = (filename as NSString).pathExtension.lowercased()
        return ext.isEmpty ? fallback : ext
    }

    private static func jsonObjects(fromHTML html: String) -> [Any] {
        guard let regex = try? NSRegularExpression(
            pattern: #"<script\b([^>]*)>(.*?)</script>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return []
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        return regex.matches(in: html, range: range).compactMap { match in
            guard let attributesRange = Range(match.range(at: 1), in: html),
                  let contentRange = Range(match.range(at: 2), in: html) else {
                return nil
            }
            let attributes = String(html[attributesRange]).lowercased()
            let content = decodeHTML(normalizeEscapes(String(html[contentRange]))).trimmed
            guard attributes.contains("json") || content.hasPrefix("{") || content.hasPrefix("[") else {
                return nil
            }
            guard let data = content.data(using: .utf8) else { return nil }
            return try? JSONSerialization.jsonObject(with: data)
        }
    }

    private static func metaContents(fromHTML html: String, names: Set<String>) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"<meta\b([^>]*)>"#, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        return regex.matches(in: html, range: range).compactMap { match in
            guard let attributesRange = Range(match.range(at: 1), in: html) else { return nil }
            let values = attributeValues(from: String(html[attributesRange]))
            let name = (values["property"] ?? values["name"])?.lowercased()
            guard let name, names.contains(name),
                  let content = values["content"]?.trimmed,
                  !content.isEmpty else {
                return nil
            }
            return decodeHTML(content)
        }
    }

    private static func title(fromHTML html: String) -> String? {
        let names: Set<String> = ["og:title", "twitter:title"]
        if let title = metaContents(fromHTML: html, names: names).first {
            return cleanTweetTitle(title)
        }
        guard let regex = try? NSRegularExpression(pattern: #"<title[^>]*>(.*?)</title>"#, options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..<html.endIndex, in: html)),
              let capture = Range(match.range(at: 1), in: html) else {
            return nil
        }
        return cleanTweetTitle(decodeHTML(String(html[capture])))
    }

    private static func username(fromHTML html: String) -> String? {
        if let title = metaContents(fromHTML: html, names: ["og:title", "twitter:title"]).first,
           let user = firstCapture(pattern: #"@([A-Za-z0-9_]{1,20})"#, in: title) {
            return user
        }
        return nil
    }

    private static func userID(fromHTML html: String) -> String? {
        metaContents(fromHTML: html, names: ["twitter:site:id", "twitter:creator:id"]).first
    }

    private static func username(in value: Any) -> String? {
        if let dictionary = value as? [String: Any] {
            for key in ["screen_name", "screenName", "username", "user_name"] {
                if let username = stringValue(dictionary[key]), !username.trimmed.isEmpty {
                    return username
                }
            }
            if let user = dictionary["user"] as? [String: Any],
               let username = username(in: user) {
                return username
            }
            if let legacy = dictionary["legacy"] as? [String: Any],
               let username = username(in: legacy) {
                return username
            }
            for child in dictionary.values {
                if let username = username(in: child) {
                    return username
                }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let username = username(in: child) {
                    return username
                }
            }
        }
        return nil
    }

    private static func authorUsername(in value: Any) -> String? {
        guard let author = authorResult(in: value) else { return nil }
        let legacy = author["legacy"] as? [String: Any]
        return stringValue(legacy?["screen_name"]) ??
            stringValue(author["screen_name"]) ??
            stringValue(author["username"])
    }

    private static func authorUserID(in value: Any) -> String? {
        guard let author = authorResult(in: value) else { return nil }
        let legacy = author["legacy"] as? [String: Any]
        return stringValue(author["rest_id"]) ??
            stringValue(author["id_str"]) ??
            stringValue(legacy?["id_str"])
    }

    private static func authorResult(in value: Any) -> [String: Any]? {
        if let dictionary = value as? [String: Any] {
            if let core = dictionary["core"] as? [String: Any],
               let userResults = core["user_results"] as? [String: Any],
               let result = userResults["result"] as? [String: Any] {
                return result["result"] as? [String: Any] ?? result
            }
            if let user = dictionary["user"] as? [String: Any] {
                return user["result"] as? [String: Any] ?? user
            }
            if let legacy = dictionary["legacy"] as? [String: Any],
               let user = legacy["user"] as? [String: Any] {
                return user["result"] as? [String: Any] ?? user
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let result = authorResult(in: child) {
                    return result
                }
            }
        }
        return nil
    }

    private static func userID(in value: Any) -> String? {
        if let dictionary = value as? [String: Any] {
            for key in ["rest_id", "id_str", "id", "user_id", "userId", "uid"] {
                if let id = stringValue(dictionary[key]), !id.trimmed.isEmpty {
                    return id
                }
            }
            if let user = dictionary["user"] as? [String: Any],
               let id = userID(in: user) {
                return id
            }
            if let userResults = dictionary["user_results"] as? [String: Any],
               let id = userID(in: userResults) {
                return id
            }
            if let core = dictionary["core"] as? [String: Any],
               let id = userID(in: core) {
                return id
            }
            if let result = dictionary["result"] as? [String: Any],
               let id = userID(in: result) {
                return id
            }
            for child in dictionary.values {
                if let id = userID(in: child) {
                    return id
                }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let id = userID(in: child) {
                    return id
                }
            }
        }
        return nil
    }

    private static func text(in value: Any) -> String? {
        if let dictionary = value as? [String: Any] {
            for key in ["full_text", "fullText", "text", "tweetText"] {
                if let text = stringValue(dictionary[key]), !text.trimmed.isEmpty {
                    return cleanTweetTitle(text)
                }
            }
            if let legacy = dictionary["legacy"] as? [String: Any],
               let text = text(in: legacy) {
                return text
            }
            for child in dictionary.values {
                if let text = text(in: child) {
                    return text
                }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let text = text(in: child) {
                    return text
                }
            }
        }
        return nil
    }

    private static func twitpicMediaAssets(in value: Any, sourceURL: URL, headers: HTTPRequestOptions) async -> [TwitterMediaAsset] {
        var texts: [String] = []
        collectStrings(in: value, into: &texts)
        return await twitpicMediaAssets(fromText: texts.joined(separator: "\n"), sourceURL: sourceURL, headers: headers)
    }

    private static func twitpicMediaAssets(fromText text: String, sourceURL: URL, headers: HTTPRequestOptions) async -> [TwitterMediaAsset] {
        var assets: [TwitterMediaAsset] = []
        for url in twitpicURLs(from: text, sourceURL: sourceURL) {
            do {
                let html = try await HTTPClient.shared.string(
                    from: url,
                    referer: headers.referer ?? sourceURL.absoluteString,
                    userAgent: headers.userAgent
                )
                if let asset = twitpicMediaAsset(fromHTML: html, pageURL: url) {
                    assets.append(asset)
                }
            } catch {
                continue
            }
        }
        return deduped(assets)
    }

    private static func collectStrings(in value: Any, into strings: inout [String]) {
        if let string = value as? String {
            strings.append(string)
        } else if let dictionary = value as? [String: Any] {
            for child in dictionary.values {
                collectStrings(in: child, into: &strings)
            }
        } else if let array = value as? [Any] {
            for child in array {
                collectStrings(in: child, into: &strings)
            }
        }
    }

    private static func imageURL(from raw: String, sourceURL: URL) -> URL? {
        guard let remote = absoluteURL(raw, baseURL: sourceURL) else { return nil }
        guard let host = remote.host?.lowercased(), host.contains("twimg") || host.hasSuffix(".test") else {
            return remote
        }
        guard host.contains("pbs.") || remote.path.contains("/media/") else {
            return remote
        }
        guard var components = URLComponents(url: remote, resolvingAgainstBaseURL: false) else {
            return remote
        }

        var items = components.queryItems ?? []
        let ext = filenameExtension(forImageURL: remote)
        if !items.contains(where: { $0.name.lowercased() == "format" }), !ext.isEmpty {
            items.append(URLQueryItem(name: "format", value: ext))
        }
        if let index = items.firstIndex(where: { $0.name.lowercased() == "name" }) {
            items[index] = URLQueryItem(name: items[index].name, value: "orig")
        } else {
            items.append(URLQueryItem(name: "name", value: "orig"))
        }
        components.queryItems = items
        return components.url ?? remote
    }

    private static func filename(for item: TwitterMediaAsset, tweetID: String, index: Int, total: Int) -> String {
        let ext = item.filenameExtension.trimmed.isEmpty ? (item.type == "video" ? "mp4" : "jpg") : item.filenameExtension
        let page = total > 1 ? "_p\(String(format: "%04d", index))" : ""
        return "\(tweetID)\(page).\(ext)".sanitizedFilename(maxLength: 180)
    }

    private static func mediaMetadata(for item: TwitterMediaAsset, sourceURL: URL? = nil, index: Int? = nil) -> [String: String] {
        let format = mediaFormat(for: item)
        return DownloadMetadata.clean([
            "type": item.type,
            "media_type": item.type,
            "page": index.map(String.init) ?? "",
            "position": index.map(String.init) ?? "",
            "format": format,
            "media_format": format,
            "media_url": item.remoteURL.absoluteString,
            "image_url": item.type == "photo" ? item.remoteURL.absoluteString : "",
            "video_url": item.type == "video" ? item.remoteURL.absoluteString : "",
            "source_url": item.remoteURL.absoluteString,
            "page_url": sourceURL?.absoluteString ?? ""
        ])
    }

    private static func mediaFormat(for item: TwitterMediaAsset) -> String {
        let ext = item.filenameExtension.trimmed.lowercased()
        if !ext.isEmpty { return ext == "jpeg" ? "jpg" : ext }
        let pathExt = item.remoteURL.pathExtension.lowercased()
        if !pathExt.isEmpty { return pathExt == "jpeg" ? "jpg" : pathExt }
        return item.type == "video" ? "mp4" : "jpg"
    }

    private static func filenameExtension(forImageURL url: URL) -> String {
        if let format = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name.lowercased() == "format" })?.value?.lowercased(),
           !format.trimmed.isEmpty {
            return format == "jpeg" ? "jpg" : format
        }
        let ext = url.pathExtension.lowercased()
        if !ext.isEmpty { return ext == "jpeg" ? "jpg" : ext }
        return "jpg"
    }

    private static func deduped(_ media: [TwitterMediaAsset]) -> [TwitterMediaAsset] {
        var seen = Set<String>()
        var values: [TwitterMediaAsset] = []
        for item in media {
            let normalized = URLIdentity.normalize(item.remoteURL.absoluteString)
            guard !seen.contains(normalized) else { continue }
            seen.insert(normalized)
            values.append(item)
        }
        return values
    }

    private static func isSupportedHost(_ host: String) -> Bool {
        host == "twitter.com" ||
            host == "www.twitter.com" ||
        host == "mobile.twitter.com" ||
            host == "x.com" ||
            host == "www.x.com" ||
            host == "twitpic.com" ||
            host == "www.twitpic.com" ||
            host == "twitter.test" ||
            host == "www.twitter.test" ||
            host == "x.test" ||
            host == "www.x.test" ||
            host == "twitpic.test" ||
            host == "www.twitpic.test"
    }

    private static func isTwitPicImageCandidate(_ url: URL, pageURL: URL) -> Bool {
        let normalized = URLIdentity.normalize(url.absoluteString)
        guard normalized != URLIdentity.normalize(pageURL.absoluteString) else { return false }

        let lowered = url.absoluteString.lowercased()
        guard !["avatar", "profile", "sprite", "logo", "icon", "blank", "placeholder"].contains(where: { lowered.contains($0) }) else {
            return false
        }

        let ext = url.pathExtension.lowercased()
        if ["jpg", "jpeg", "png", "gif", "webp", "avif"].contains(ext) {
            return true
        }

        let host = url.host?.lowercased() ?? ""
        return host.contains("twitpic") ||
            host.contains("twimg") ||
            host.hasSuffix(".test") ||
            lowered.contains("/photos/") ||
            lowered.contains("/media/")
    }

    private static func isMP4Video(_ raw: String, mimeType: String?) -> Bool {
        let value = raw.lowercased()
        let mime = mimeType?.lowercased() ?? ""
        return value.contains(".mp4") || mime.contains("mp4")
    }

    private static func bitrateScore(from text: String) -> Int {
        firstCapture(pattern: #"(?<![0-9])([1-9][0-9]{2,6})(?:k|kbps|bps)(?![A-Za-z0-9])"#, in: text)
            .flatMap(Int.init) ?? 0
    }

    private static func absoluteURL(_ raw: String, baseURL: URL) -> URL? {
        let value = decodeHTML(normalizeEscapes(raw))
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'").union(.whitespacesAndNewlines))
        if value.hasPrefix("//") {
            return URL(string: "\(baseURL.scheme ?? "https"):\(value)")
        }
        return URL(string: value, relativeTo: baseURL)?.absoluteURL
    }

    private static func attributeValues(from text: String) -> [String: String] {
        guard let regex = try? NSRegularExpression(pattern: #"([:\w-]+)\s*=\s*(['"])(.*?)\2"#, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return [:]
        }
        var values: [String: String] = [:]
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        for match in regex.matches(in: text, range: range) {
            guard let keyRange = Range(match.range(at: 1), in: text),
                  let valueRange = Range(match.range(at: 3), in: text) else {
                continue
            }
            values[String(text[keyRange]).lowercased()] = decodeHTML(String(text[valueRange]))
        }
        return values
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
        if let string = value as? String { return Int(string) }
        return nil
    }

    private static func cleanTweetTitle(_ raw: String) -> String {
        raw.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\s*/\s*X\s*$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\s+on\s+(Twitter|X):?\s*"#, with: " ", options: .regularExpression)
            .trimmed
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
