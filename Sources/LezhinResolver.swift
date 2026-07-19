import Foundation

struct LezhinRequest: Equatable {
    var language: String
    var alias: String
    var episodeName: String?
    var sourceURL: URL
    var collectionURL: URL
}

struct LezhinEpisode: Equatable {
    var id: String
    var name: String
    var sequence: Int
    var coin: Int
    var updatedAt: Int64
    var displayName: String
    var title: String
    var expired: Bool
    var notForSale: Bool
}

struct LezhinCatalog {
    var contentID: String
    var alias: String
    var title: String
    var artists: [String]
    var updatedAt: Int64
    var isAdult: Bool
    var episodes: [LezhinEpisode]
}

final class LezhinResolver {
    private static let maximumEpisodeCount = 500
    private static let imageQuality = 40
    private static let defaultUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/137.0 Safari/537.36"

    func canResolve(_ url: URL) -> Bool {
        Self.request(from: url) != nil
    }

    func resolve(
        _ url: URL,
        headers: HTTPRequestOptions = HTTPRequestOptions(),
        rangeExpression: String = ""
    ) async throws -> ResolvedDownload {
        guard let request = Self.request(from: url) else {
            throw NativeDownloadError.invalidURL(url.absoluteString)
        }

        let userAgent = headers.userAgent ?? Self.defaultUserAgent
        let html = try await HTTPClient.shared.string(
            from: request.collectionURL,
            referer: headers.referer,
            userAgent: userAgent,
            additionalHeaders: Self.frontendHeaders(for: request, isAdult: false)
        )
        let catalog = try Self.catalog(fromHTML: html, alias: request.alias)
        var chronologicalEpisodes = catalog.episodes
            .sorted {
                if $0.sequence != $1.sequence { return $0.sequence < $1.sequence }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        guard !chronologicalEpisodes.isEmpty || request.episodeName != nil else {
            throw NativeDownloadError.noFiles
        }
        if chronologicalEpisodes.count > Self.maximumEpisodeCount {
            chronologicalEpisodes = Array(chronologicalEpisodes.prefix(Self.maximumEpisodeCount))
        }
        var episodes = chronologicalEpisodes

        let isCollection = request.episodeName == nil
        let listedEpisodeCount = episodes.count
        var selectedPositions: [Int]?
        if let episodeName = request.episodeName {
            episodes = [episodes.first(where: { $0.name == episodeName }) ?? LezhinEpisode(
                id: "",
                name: episodeName,
                sequence: 1,
                coin: 0,
                updatedAt: 0,
                displayName: episodeName,
                title: "",
                expired: false,
                notForSale: false
            )]
        } else if !rangeExpression.trimmed.isEmpty {
            let indexes = try Self.itemIndexes(for: rangeExpression.trimmed, total: episodes.count)
            episodes = indexes.map { episodes[$0] }
            selectedPositions = indexes.map { $0 + 1 }
        }

        guard !episodes.isEmpty else { throw NativeDownloadError.noFiles }

        let thumbnailURL = Self.thumbnailURL(for: catalog, request: request)
        var assets: [ResolvedAsset] = []
        var resolvedEpisodes: [LezhinEpisode] = []
        var failures: [Error] = []
        for episode in episodes {
            try Task.checkCancellation()
            do {
                let position = Self.collectionPosition(of: episode, in: chronologicalEpisodes)
                let resolution = try await resolveEpisode(
                    episode,
                    position: position,
                    request: request,
                    catalog: catalog,
                    thumbnailURL: thumbnailURL,
                    userAgent: userAgent,
                    isCollection: isCollection
                )
                resolvedEpisodes.append(resolution.episode)
                assets.append(contentsOf: resolution.assets)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if !isCollection { throw error }
                failures.append(error)
            }
        }

        guard !assets.isEmpty else {
            throw failures.first ?? NativeDownloadError.noFiles
        }

        let artist = catalog.artists.joined(separator: ", ")
        let title: String
        if let episode = resolvedEpisodes.first, !isCollection {
            let label = Self.episodeLabel(episode)
            title = label.isEmpty ? catalog.title : "\(catalog.title) - \(label)"
        } else {
            title = catalog.title
        }
        var metadata = DownloadMetadata.clean([
            "site": "Lezhin Comics",
            "title": title,
            "series": catalog.title,
            "artist": artist,
            "author": artist,
            "creator": artist,
            "type": isCollection ? "series" : "episode",
            "media_type": "image",
            "category": "comic",
            "collection": isCollection ? "true" : "false",
            "comic_id": catalog.contentID,
            "comic_alias": catalog.alias,
            "language": request.language,
            "source_url": request.sourceURL.absoluteString,
            "thumbnail": thumbnailURL?.absoluteString ?? "",
            "image_count": String(assets.count),
            "episode_count": String(resolvedEpisodes.count),
            "listed_episode_count": String(listedEpisodeCount)
        ])
        if let episode = resolvedEpisodes.first, !isCollection {
            metadata["episode_id"] = episode.id
            metadata["episode_name"] = episode.name
            metadata["episode_title"] = Self.episodeLabel(episode)
            metadata["episode_sequence"] = String(episode.sequence)
        }
        if let selectedPositions {
            metadata["range"] = rangeExpression.trimmed
            metadata["range_scope"] = "collection_items"
            metadata["range_total"] = String(listedEpisodeCount)
            metadata["range_selected"] = String(selectedPositions.count)
            metadata["range_indexes"] = selectedPositions.map(String.init).joined(separator: ",")
        }
        if !failures.isEmpty {
            metadata["skipped_count"] = String(failures.count)
            metadata["resolved_item_count"] = String(resolvedEpisodes.count)
        }
        let shuffledImageCount = assets.filter { $0.lezhinImageShuffle != nil }.count
        if shuffledImageCount > 0 {
            metadata["image_shuffle"] = "true"
            metadata["shuffled_image_count"] = String(shuffledImageCount)
        }

        return ResolvedDownload(
            title: title,
            folderName: "[Lezhin] \(title)".sanitizedFilename(maxLength: 120),
            assets: assets,
            metadata: metadata
        )
    }

    static func request(from url: URL) -> LezhinRequest? {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let rawHost = url.host?.lowercased(),
              isSupportedHost(rawHost) else {
            return nil
        }
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        guard parts.count == 3 || parts.count == 4,
              supportedLanguages.contains(parts[0].lowercased()),
              parts[1].lowercased() == "comic",
              isSlug(parts[2]),
              parts.count == 3 || isSlug(parts[3]) else {
            return nil
        }

        let language = parts[0].lowercased()
        let alias = parts[2]
        let episodeName = parts.count == 4 ? parts[3] : nil
        let host = canonicalHost(for: rawHost)
        var collectionComponents = URLComponents()
        collectionComponents.scheme = "https"
        collectionComponents.host = host
        collectionComponents.port = url.port
        collectionComponents.path = "/\(language)/comic/\(alias)"
        guard let collectionURL = collectionComponents.url else { return nil }

        var sourceComponents = collectionComponents
        if let episodeName {
            sourceComponents.path += "/\(episodeName)"
        }
        guard let sourceURL = sourceComponents.url else { return nil }
        return LezhinRequest(
            language: language,
            alias: alias,
            episodeName: episodeName,
            sourceURL: sourceURL,
            collectionURL: collectionURL
        )
    }

    static func catalog(fromHTML html: String, alias: String) throws -> LezhinCatalog {
        let marker = "\"queryKey\":[\"episode\",\"\(alias)\",null]"
        let stateMarker = "\"state\":{\"data\":"
        for chunk in nextFlightStrings(fromHTML: html) {
            guard let markerRange = chunk.range(of: marker) else { continue }
            let prefixRange = chunk.startIndex..<markerRange.lowerBound
            guard let stateRange = chunk.range(of: stateMarker, options: .backwards, range: prefixRange),
                  let objectText = balancedJSONObject(in: chunk, from: stateRange.upperBound),
                  let data = objectText.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let content = object["content"] as? [String: Any],
                  let rawEpisodes = object["episodes"] as? [Any] else {
                continue
            }

            let display = content["display"] as? [String: Any]
            let contentID = stringValue(content["id"]) ?? ""
            let title = cleanText(stringValue(display?["title"]) ?? alias)
            let artists = (content["artists"] as? [Any] ?? []).compactMap { value -> String? in
                guard let artist = value as? [String: Any] else { return nil }
                let name = cleanText(stringValue(artist["name"]) ?? "")
                return name.isEmpty ? nil : name
            }
            let episodes = rawEpisodes.compactMap(episode(from:))
            return LezhinCatalog(
                contentID: contentID,
                alias: stringValue(content["alias"]) ?? alias,
                title: title.isEmpty ? alias : title,
                artists: artists,
                updatedAt: int64Value(content["updatedAt"]) ?? 0,
                isAdult: boolValue(content["isAdult"]) ?? false,
                episodes: episodes
            )
        }
        throw NativeDownloadError.unsupported("Lezhin comic metadata is missing from the current page.")
    }

    private struct EpisodeResolution {
        var episode: LezhinEpisode
        var assets: [ResolvedAsset]
    }

    private func resolveEpisode(
        _ listedEpisode: LezhinEpisode,
        position: Int,
        request: LezhinRequest,
        catalog: LezhinCatalog,
        thumbnailURL: URL?,
        userAgent: String,
        isCollection: Bool
    ) async throws -> EpisodeResolution {
        let pageURL = Self.episodePageURL(request: request, episodeName: listedEpisode.name)
        let apiHeaders = Self.frontendHeaders(for: request, isAdult: catalog.isAdult)
        let permissionURL = Self.apiURL(
            request: request,
            path: "/lz-api/contents/v3/\(request.alias)/episodes/\(listedEpisode.name)",
            queryItems: [
                URLQueryItem(name: "referrerViewType", value: "DIRECT"),
                URLQueryItem(name: "objectType", value: "comic")
            ]
        )
        let permission = try await Self.getJSON(
            permissionURL,
            referer: pageURL.absoluteString,
            userAgent: userAgent,
            headers: apiHeaders,
            context: "Lezhin episode permission"
        )
        let permissionData = try Self.successData(permission, context: "Lezhin episode permission")
        guard let permissionEpisode = permissionData["episode"] as? [String: Any],
              let contentID = Self.stringValue(permissionData["id"]),
              let episodeID = Self.stringValue(permissionEpisode["id"]),
              let firstCheckType = Self.stringValue(permissionEpisode["firstCheckType"]),
              !firstCheckType.isEmpty else {
            throw NativeDownloadError.unsupported("Lezhin did not grant readable episode metadata. Sign in with the in-app browser and verify access to this episode.")
        }
        let isCollected = Self.boolValue(permissionEpisode["isCollected"]) ?? false

        let metadataURL = Self.apiURL(
            request: request,
            path: "/lz-api/v2/viewer/comics/\(request.alias)/episodes/\(listedEpisode.name)/metadata"
        )
        let viewer = try await Self.getJSON(
            metadataURL,
            referer: pageURL.absoluteString,
            userAgent: userAgent,
            headers: apiHeaders,
            context: "Lezhin viewer metadata"
        )
        let viewerData = try Self.successData(viewer, context: "Lezhin viewer metadata")
        guard let media = viewerData["media"] as? [String: Any] else {
            throw NativeDownloadError.noFiles
        }
        let imageShuffle = Self.boolValue(media["imageShuffle"]) == true
        let mediaEntries = Self.mediaEntries(in: media["scrollView"]) + Self.mediaEntries(in: media["pageView"])
        guard !mediaEntries.isEmpty else { throw NativeDownloadError.noFiles }

        let signatureURL = Self.apiURL(
            request: request,
            path: "/lz-api/v2/cloudfront/signed-url/generate",
            queryItems: [
                URLQueryItem(name: "contentId", value: contentID),
                URLQueryItem(name: "episodeId", value: episodeID),
                URLQueryItem(name: "firstCheckType", value: firstCheckType),
                URLQueryItem(name: "q", value: String(Self.imageQuality)),
                URLQueryItem(name: "purchased", value: isCollected ? "true" : "false")
            ]
        )
        let signature = try await Self.getJSON(
            signatureURL,
            referer: pageURL.absoluteString,
            userAgent: userAgent,
            headers: apiHeaders,
            context: "Lezhin image signature"
        )
        let signatureData = try Self.successData(signature, context: "Lezhin image signature")
        guard let policy = Self.stringValue(signatureData["Policy"]),
              let signatureValue = Self.stringValue(signatureData["Signature"]),
              let keyPairID = Self.stringValue(signatureData["Key-Pair-Id"]) else {
            throw NativeDownloadError.unsupported("Lezhin image signature fields are missing.")
        }

        let viewerEpisode = viewerData["episode"] as? [String: Any]
        let actualEpisode = LezhinEpisode(
            id: episodeID,
            name: Self.stringValue(viewerEpisode?["name"]) ?? listedEpisode.name,
            sequence: Self.intValue(viewerEpisode?["seq"]) ?? listedEpisode.sequence,
            coin: Self.intValue(viewerEpisode?["coin"]) ?? listedEpisode.coin,
            updatedAt: Self.int64Value(viewerEpisode?["updatedAt"]) ?? listedEpisode.updatedAt,
            displayName: Self.cleanText(Self.stringValue(viewerEpisode?["displayName"]) ?? listedEpisode.displayName),
            title: Self.cleanText(Self.stringValue(viewerEpisode?["title"]) ?? listedEpisode.title),
            expired: listedEpisode.expired,
            notForSale: listedEpisode.notForSale
        )
        let updatedAt = actualEpisode.updatedAt > 0
            ? actualEpisode.updatedAt
            : Self.int64Value(permissionData["updateAt"]) ?? catalog.updatedAt
        let label = Self.episodeLabel(actualEpisode)
        let prefix = String(format: "%04d - %@", max(1, position), label.isEmpty ? actualEpisode.name : label)
            .sanitizedFilename(maxLength: 120)
        let purchased = isCollected ? "true" : "false"
        let assets = try mediaEntries.enumerated().map { offset, media -> ResolvedAsset in
            guard let path = Self.stringValue(media["path"]),
                  let remoteURL = Self.signedImageURL(
                    path: path,
                    request: request,
                    purchased: purchased,
                    updatedAt: updatedAt,
                    policy: policy,
                    signature: signatureValue,
                    keyPairID: keyPairID
                  ) else {
                throw NativeDownloadError.unsupported("Lezhin returned an invalid image path.")
            }
            let page = offset + 1
            let fileExtension = imageShuffle ? "png" : "webp"
            let filename = isCollection
                ? "\(prefix) - \(String(format: "%04d", page)).\(fileExtension)".sanitizedFilename(maxLength: 180)
                : "\(String(format: "%04d", page)).\(fileExtension)"
            return ResolvedAsset(
                remoteURL: remoteURL,
                filename: filename,
                metadata: DownloadMetadata.clean([
                    "site": "Lezhin Comics",
                    "type": "image",
                    "media_type": "image",
                    "comic_id": contentID,
                    "comic_alias": request.alias,
                    "series": catalog.title,
                    "episode_id": episodeID,
                    "episode_name": actualEpisode.name,
                    "episode_title": label,
                    "episode_sequence": String(actualEpisode.sequence),
                    "collection_index": String(max(1, position)),
                    "page": String(page),
                    "width": Self.stringValue(media["width"]) ?? "",
                    "height": Self.stringValue(media["height"]) ?? "",
                    "format": fileExtension,
                    "lezhin_image_shuffle": imageShuffle ? "true" : "false",
                    "lezhin_shuffle_grid_size": imageShuffle ? "5" : "",
                    "lezhin_shuffle_seed": imageShuffle ? episodeID : "",
                    "source_url": pageURL.absoluteString,
                    "page_url": pageURL.absoluteString,
                    "thumbnail": thumbnailURL?.absoluteString ?? "",
                    "lezhin_signature_expires_at": Self.stringValue(signatureData["expiredAt"]) ?? ""
                ]),
                referer: pageURL.absoluteString,
                userAgent: userAgent,
                additionalHeaders: apiHeaders.map { ResolvedRequestHeader(name: $0.key, value: $0.value) },
                lezhinImageShuffle: imageShuffle
                    ? LezhinImageShuffle(seed: episodeID, gridSize: 5)
                    : nil
            )
        }
        return EpisodeResolution(episode: actualEpisode, assets: assets)
    }

    private static func successData(_ object: [String: Any], context: String) throws -> [String: Any] {
        let code = intValue(object["code"]) ?? -1
        guard code == 0, let data = object["data"] as? [String: Any] else {
            let description = cleanText(stringValue(object["description"]) ?? "")
            let detail = description.isEmpty ? "code \(code)" : "code \(code): \(description)"
            throw NativeDownloadError.unsupported("\(context) was denied (\(detail)). Sign in with the in-app browser and verify that the episode is free or purchased.")
        }
        return data
    }

    private static func getJSON(
        _ url: URL,
        referer: String,
        userAgent: String,
        headers: [String: String],
        context: String
    ) async throws -> [String: Any] {
        let data = try await HTTPClient.shared.data(
            from: url,
            referer: referer,
            userAgent: userAgent,
            additionalHeaders: headers
        )
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NativeDownloadError.unsupported("\(context) returned invalid JSON.")
        }
        return object
    }

    private static func frontendHeaders(for request: LezhinRequest, isAdult: Bool) -> [String: String] {
        let locale: String
        let country: String
        switch request.language {
        case "ja":
            locale = "ja-JP"
            country = "jp"
        case "en":
            locale = "en-US"
            country = "us"
        default:
            locale = "ko-KR"
            country = "kr"
        }
        return [
            "Accept": "application/json, text/plain, */*",
            "Content-Type": "application/json",
            "X-LZ-Locale": locale,
            "X-LZ-Country": country,
            "X-LZ-Adult": isAdult ? "2" : "0",
            "X-LZ-AllowAdult": "false"
        ]
    }

    private static func apiURL(
        request: LezhinRequest,
        path: String,
        queryItems: [URLQueryItem] = []
    ) -> URL {
        var components = URLComponents()
        components.scheme = request.collectionURL.scheme ?? "https"
        components.host = request.collectionURL.host
        components.port = request.collectionURL.port
        components.path = path
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        return components.url!
    }

    private static func episodePageURL(request: LezhinRequest, episodeName: String) -> URL {
        var components = URLComponents(url: request.collectionURL, resolvingAgainstBaseURL: false)!
        components.path += "/\(episodeName)"
        return components.url!
    }

    private static func thumbnailURL(for catalog: LezhinCatalog, request: LezhinRequest) -> URL? {
        guard !catalog.contentID.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = request.collectionURL.host?.hasSuffix(".test") == true
            ? "ccdn.lezhin.test"
            : "ccdn.lezhin.com"
        components.path = "/v2/comics/\(catalog.contentID)/images/wide.jpg"
        if catalog.updatedAt > 0 {
            components.queryItems = [URLQueryItem(name: "updated", value: String(catalog.updatedAt))]
        }
        return components.url
    }

    private static func signedImageURL(
        path: String,
        request: LezhinRequest,
        purchased: String,
        updatedAt: Int64,
        policy: String,
        signature: String,
        keyPairID: String
    ) -> URL? {
        let normalizedPath = path.hasPrefix("/") ? path : "/\(path)"
        var components = URLComponents()
        components.scheme = "https"
        components.host = request.collectionURL.host?.hasSuffix(".test") == true
            ? "rcdn.lezhin.test"
            : "rcdn.lezhin.com"
        components.path = "/v2\(normalizedPath).webp"
        components.queryItems = [
            URLQueryItem(name: "purchased", value: purchased),
            URLQueryItem(name: "q", value: String(imageQuality)),
            URLQueryItem(name: "updated", value: String(max(0, updatedAt))),
            URLQueryItem(name: "Policy", value: policy),
            URLQueryItem(name: "Signature", value: signature),
            URLQueryItem(name: "Key-Pair-Id", value: keyPairID)
        ]
        return components.url
    }

    private static func nextFlightStrings(fromHTML html: String) -> [String] {
        let marker = "self.__next_f.push("
        let endMarker = ")</script>"
        var values: [String] = []
        var cursor = html.startIndex
        while cursor < html.endIndex,
              let markerRange = html.range(of: marker, range: cursor..<html.endIndex) {
            let payloadStart = markerRange.upperBound
            guard let endRange = html.range(of: endMarker, range: payloadStart..<html.endIndex) else { break }
            let payload = String(html[payloadStart..<endRange.lowerBound])
            if let data = payload.data(using: .utf8),
               let array = try? JSONSerialization.jsonObject(with: data) as? [Any],
               array.count > 1,
               let value = array[1] as? String {
                values.append(value)
            }
            cursor = endRange.upperBound
        }
        return values
    }

    private static func balancedJSONObject(in text: String, from start: String.Index) -> String? {
        guard start < text.endIndex, text[start] == "{" else { return nil }
        var index = start
        var depth = 0
        var quoted = false
        var escaped = false
        while index < text.endIndex {
            let character = text[index]
            if quoted {
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    quoted = false
                }
            } else if character == "\"" {
                quoted = true
            } else if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 {
                    return String(text[start...index])
                }
            }
            index = text.index(after: index)
        }
        return nil
    }

    private static func episode(from value: Any) -> LezhinEpisode? {
        guard let dictionary = value as? [String: Any],
              let id = stringValue(dictionary["id"]),
              let name = stringValue(dictionary["name"]),
              let sequence = intValue(dictionary["seq"]) else {
            return nil
        }
        let display = dictionary["display"] as? [String: Any]
        let properties = dictionary["properties"] as? [String: Any]
        return LezhinEpisode(
            id: id,
            name: name,
            sequence: sequence,
            coin: intValue(dictionary["coin"]) ?? 0,
            updatedAt: int64Value(dictionary["updatedAt"]) ?? 0,
            displayName: cleanText(stringValue(display?["displayName"]) ?? name),
            title: cleanText(stringValue(display?["title"]) ?? ""),
            expired: boolValue(properties?["expired"]) ?? false,
            notForSale: boolValue(properties?["notForSale"]) ?? false
        )
    }

    private static func mediaEntries(in value: Any?) -> [[String: Any]] {
        if let dictionary = value as? [String: Any] {
            if stringValue(dictionary["path"]) != nil { return [dictionary] }
            return dictionary.values.flatMap { mediaEntries(in: $0) }
        }
        if let array = value as? [Any] {
            return array.flatMap { mediaEntries(in: $0) }
        }
        return []
    }

    private static func episodeLabel(_ episode: LezhinEpisode) -> String {
        var parts: [String] = []
        for value in [episode.displayName, episode.title].map(cleanText) where !value.isEmpty {
            if !parts.contains(value) { parts.append(value) }
        }
        return parts.joined(separator: " - ")
    }

    private static func collectionPosition(of episode: LezhinEpisode, in episodes: [LezhinEpisode]) -> Int {
        if let index = episodes.firstIndex(where: { $0.id == episode.id || $0.name == episode.name }) {
            return index + 1
        }
        return max(1, episode.sequence)
    }

    private struct ItemRangeSegment {
        var start: Int?
        var end: Int?
    }

    private static func itemIndexes(for expression: String, total: Int) throws -> [Int] {
        let segments = try itemRangeSegments(from: expression)
        guard !segments.isEmpty else { return Array(0..<max(0, total)) }
        guard total > 0 else { return [] }
        var indexes: [Int] = []
        var seen = Set<Int>()
        for segment in segments {
            let start = max(1, segment.start ?? 1)
            let end = min(total, segment.end ?? total)
            guard start <= end else { continue }
            for position in start...end where seen.insert(position - 1).inserted {
                indexes.append(position - 1)
            }
        }
        guard !indexes.isEmpty else {
            throw NativeDownloadError.unsupported("Range did not match any Lezhin episodes.")
        }
        return indexes
    }

    private static func itemRangeSegments(from expression: String) throws -> [ItemRangeSegment] {
        guard !expression.isEmpty else { return [] }
        let compact = expression.filter { !$0.isWhitespace }
        let pieces = compact.components(separatedBy: CharacterSet(charactersIn: ",;"))
            .filter { !$0.isEmpty }
        guard !pieces.isEmpty else { throw NativeDownloadError.unsupported("Invalid range.") }
        return try pieces.map { piece in
            if let split = itemRangeSplit(piece) {
                let start = try positiveItemRangeBound(split.0)
                let end = try positiveItemRangeBound(split.1)
                guard start != nil || end != nil else {
                    throw NativeDownloadError.unsupported("Invalid range.")
                }
                if let start, let end, start > end {
                    throw NativeDownloadError.unsupported("Invalid range.")
                }
                return ItemRangeSegment(start: start, end: end)
            }
            guard let position = Int(piece), position > 0 else {
                throw NativeDownloadError.unsupported("Invalid range.")
            }
            return ItemRangeSegment(start: position, end: position)
        }
    }

    private static func itemRangeSplit(_ value: String) -> (String, String)? {
        for separator in ["...", "..", "~", "-"] {
            if let range = value.range(of: separator) {
                return (String(value[..<range.lowerBound]), String(value[range.upperBound...]))
            }
        }
        return nil
    }

    private static func positiveItemRangeBound(_ value: String) throws -> Int? {
        guard !value.isEmpty else { return nil }
        guard let bound = Int(value), bound > 0 else {
            throw NativeDownloadError.unsupported("Invalid range.")
        }
        return bound
    }

    private static func cleanText(_ value: String) -> String {
        value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return nil
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }

    private static func int64Value(_ value: Any?) -> Int64? {
        if let value = value as? Int64 { return value }
        if let value = value as? NSNumber { return value.int64Value }
        if let value = value as? String { return Int64(value) }
        return nil
    }

    private static func boolValue(_ value: Any?) -> Bool? {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        if let value = value as? String {
            if ["true", "1", "yes"].contains(value.lowercased()) { return true }
            if ["false", "0", "no"].contains(value.lowercased()) { return false }
        }
        return nil
    }

    private static func isSupportedHost(_ host: String) -> Bool {
        host == "lezhin.com" ||
            host == "www.lezhin.com" ||
            host == "lezhinus.com" ||
            host == "www.lezhinus.com" ||
            host == "lezhin.test" ||
            host == "www.lezhin.test"
    }

    private static func canonicalHost(for host: String) -> String {
        if host.hasSuffix(".test") { return host }
        if host == "lezhinus.com" || host == "www.lezhinus.com" {
            return "www.lezhinus.com"
        }
        return "www.lezhin.com"
    }

    private static func isSlug(_ value: String) -> Bool {
        !value.isEmpty && value.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil
    }

    private static let supportedLanguages: Set<String> = ["ko", "ja", "en"]
}
