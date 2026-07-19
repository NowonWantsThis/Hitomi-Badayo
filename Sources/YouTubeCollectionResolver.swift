import Foundation

enum YouTubeCollectionKind: String, Equatable {
    case channel
    case playlist
}

struct YouTubeCollectionRequest: Equatable {
    var kind: YouTubeCollectionKind
    var identifier: String
    var sourceURL: URL
}

struct YouTubeCollectionEntry: Equatable {
    var id: String
    var title: String
    var uploader: String
    var thumbnailURL: URL?
    var pageURL: URL
}

struct YouTubeCollectionPage: Equatable {
    var entries: [YouTubeCollectionEntry]
    var continuationToken: String?
    var title: String?
    var uploader: String?
    var uploaderID: String?
    var thumbnailURL: URL?
    var totalCount: Int?
}

struct YouTubeBrowseAPIConfiguration {
    var apiKey: String
    var context: [String: Any]
    var clientNumber: String
    var clientVersion: String
    var visitorData: String?
    var endpoint: URL
}

final class YouTubeCollectionResolver {
    static let defaultCollectionItemLimit = 2_000
    private static let defaultUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/126.0.0.0 Safari/537.36"

    func canResolve(_ url: URL) -> Bool {
        Self.request(from: url) != nil
    }

    func resolve(
        _ url: URL,
        headers: HTTPRequestOptions = HTTPRequestOptions(),
        preferredResolution: String = "",
        codecPriority: [YouTubeVideoCodec] = YouTubeVideoCodec.originalDefaultPriority,
        reverse: Bool = false,
        numberPlaylistFiles: Bool = false,
        itemLimit: Int? = nil,
        rangeExpression: String = ""
    ) async throws -> ResolvedDownload {
        guard let request = Self.request(from: url) else {
            throw NativeDownloadError.invalidURL(url.absoluteString)
        }
        let userAgent = headers.userAgent ?? Self.defaultUserAgent
        let html = try await HTTPClient.shared.string(
            from: request.sourceURL,
            referer: headers.referer,
            userAgent: userAgent
        )
        let objects = YouTubeResolver.jsonObjects(fromHTML: html)
        var page = Self.collectionPage(from: objects, pageURL: request.sourceURL)
        var entries = page.entries
        var seen = Set(entries.map(\.id))
        var continuation = page.continuationToken
        var fetchedPageCount = 1
        let itemRange = rangeExpression.trimmed
        let effectiveLimit = try Self.collectionItemLimit(
            for: itemRange,
            itemLimit: itemLimit
        )

        if continuation != nil, entries.count < effectiveLimit {
            let browse = try Self.browseAPIConfiguration(fromHTML: html, pageURL: request.sourceURL)
            var requestedTokens = Set<String>()
            while entries.count < effectiveLimit, let token = continuation {
                guard requestedTokens.insert(token).inserted else { break }
                try Task.checkCancellation()
                let object = try await Self.fetchContinuation(
                    token: token,
                    configuration: browse,
                    pageURL: request.sourceURL,
                    userAgent: userAgent
                )
                fetchedPageCount += 1
                let next = Self.collectionPage(from: object, pageURL: request.sourceURL)
                let previousCount = entries.count
                for entry in next.entries where seen.insert(entry.id).inserted {
                    entries.append(entry)
                    if entries.count >= effectiveLimit { break }
                }
                if page.title == nil { page.title = next.title }
                if page.uploader == nil { page.uploader = next.uploader }
                if page.uploaderID == nil { page.uploaderID = next.uploaderID }
                if page.thumbnailURL == nil { page.thumbnailURL = next.thumbnailURL }
                if page.totalCount == nil { page.totalCount = next.totalCount }
                continuation = next.continuationToken
                if entries.count == previousCount { break }
            }
        }

        entries = Array(entries.prefix(effectiveLimit))
        if reverse {
            entries.reverse()
        }
        let listedItemCount = entries.count
        var selectedPositions: [Int]?
        if !itemRange.isEmpty {
            let indexes = try Self.itemIndexes(for: itemRange, total: entries.count)
            entries = indexes.map { entries[$0] }
            selectedPositions = indexes.map { $0 + 1 }
        }
        guard !entries.isEmpty else { throw NativeDownloadError.noFiles }

        guard let player = YouTubeResolver.playerAPIConfiguration(
            fromHTML: html,
            pageURL: request.sourceURL
        ) else {
            throw NativeDownloadError.unsupported("YouTube player API configuration is missing.")
        }

        var posts: [(entry: YouTubeCollectionEntry, download: ResolvedDownload)] = []
        var failures: [Error] = []
        for entry in entries {
            try Task.checkCancellation()
            do {
                let response = try await YouTubeResolver.fetchAndroidPlayerResponse(
                    videoID: entry.id,
                    configuration: player,
                    pageURL: entry.pageURL
                )
                var resolved = try await YouTubeResolver.resolvedDownload(
                    fromHTML: "",
                    supplementalObjects: [response],
                    pageURL: entry.pageURL,
                    preferredResolution: preferredResolution,
                    codecPriority: codecPriority,
                    userAgent: YouTubeResolver.androidUserAgent
                )
                resolved.metadata["player_client"] = YouTubeResolver.androidClientName
                resolved.metadata["player_client_version"] = YouTubeResolver.androidClientVersion
                resolved.metadata["player_api"] = "innertube"
                posts.append((entry, resolved))
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                failures.append(error)
            }
        }
        guard !posts.isEmpty else {
            throw failures.first ?? NativeDownloadError.noFiles
        }

        let plainTitle = Self.cleanText(
            page.title ?? page.uploader ?? request.identifier
        )
        let displayTitle: String
        switch request.kind {
        case .channel:
            displayTitle = "[Channel] \(plainTitle)"
        case .playlist:
            displayTitle = "[Playlist] \(plainTitle)"
        }
        var combined = try Self.combinedDownload(
            request: request,
            displayTitle: displayTitle,
            collectionTitle: plainTitle,
            uploader: Self.cleanText(page.uploader ?? (request.kind == .channel ? plainTitle : "")),
            uploaderID: page.uploaderID ?? (request.kind == .channel ? request.identifier : ""),
            thumbnailURL: page.thumbnailURL,
            posts: posts,
            numberPlaylistFiles: numberPlaylistFiles
        )
        combined.metadata["listed_item_count"] = String(listedItemCount)
        combined.metadata["collection_pages"] = String(fetchedPageCount)
        if let total = page.totalCount {
            combined.metadata["collection_total"] = String(total)
        }
        if let selectedPositions {
            combined.metadata["range"] = itemRange
            combined.metadata["range_scope"] = "collection_items"
            combined.metadata["range_total"] = String(page.totalCount ?? listedItemCount)
            combined.metadata["range_selected"] = String(selectedPositions.count)
            combined.metadata["range_indexes"] = selectedPositions.map(String.init).joined(separator: ",")
        }
        if reverse {
            combined.metadata["collection_reversed"] = "true"
        }
        if !failures.isEmpty {
            combined.metadata["skipped_count"] = String(failures.count)
            combined.metadata["resolved_item_count"] = String(posts.count)
        }
        return combined
    }

    static func request(from url: URL) -> YouTubeCollectionRequest? {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host?.lowercased(),
              isSupportedHost(host),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        let lower = parts.map { $0.lowercased() }
        let query = components.queryItems ?? []

        if lower.first == "playlist",
           let playlistID = query.first(where: { $0.name.lowercased() == "list" })?.value?.trimmed,
           !playlistID.isEmpty {
            components.scheme = "https"
            components.host = canonicalHost(for: host)
            components.path = "/playlist"
            components.queryItems = [URLQueryItem(name: "list", value: playlistID)]
            components.fragment = nil
            guard let sourceURL = components.url else { return nil }
            return YouTubeCollectionRequest(kind: .playlist, identifier: playlistID, sourceURL: sourceURL)
        }

        let identifier: String
        let tab: String?
        if let first = parts.first, first.hasPrefix("@") {
            identifier = first
            tab = lower.dropFirst().first
        } else if let first = lower.first,
                  ["channel", "user", "c"].contains(first),
                  parts.count >= 2 {
            identifier = parts[1]
            tab = lower.dropFirst(2).first
        } else {
            return nil
        }
        guard tab != "live" else { return nil }

        var normalizedParts = parts
        if tab == nil || tab == "featured" {
            if normalizedParts.count >= 3 {
                normalizedParts.removeSubrange(2...)
            }
            normalizedParts.append("videos")
        }
        components.scheme = "https"
        components.host = canonicalHost(for: host)
        components.path = "/" + normalizedParts.joined(separator: "/")
        components.queryItems = nil
        components.fragment = nil
        guard let sourceURL = components.url else { return nil }
        return YouTubeCollectionRequest(kind: .channel, identifier: identifier, sourceURL: sourceURL)
    }

    static func browseAPIConfiguration(
        fromHTML html: String,
        pageURL: URL
    ) throws -> YouTubeBrowseAPIConfiguration {
        let objects = YouTubeResolver.jsonObjects(fromHTML: html)
        let dictionaries = recursiveDictionaries(in: objects)
        guard let apiKey = dictionaries.lazy
            .compactMap({ stringValue($0["INNERTUBE_API_KEY"]) ?? stringValue($0["innertubeApiKey"]) })
            .map(\.trimmed)
            .first(where: { !$0.isEmpty }) else {
            throw NativeDownloadError.unsupported("YouTube browse API key is missing.")
        }

        let configuredContext = dictionaries.lazy
            .compactMap { $0["INNERTUBE_CONTEXT"] as? [String: Any] }
            .first
        let configuredVersion = dictionaries.lazy
            .compactMap { stringValue($0["INNERTUBE_CLIENT_VERSION"]) }
            .map(\.trimmed)
            .first(where: { !$0.isEmpty })
        let contextClient = configuredContext?["client"] as? [String: Any]
        let clientVersion = configuredVersion ?? stringValue(contextClient?["clientVersion"])?.trimmed ?? "2.20260708.00.00"
        var context = configuredContext ?? [
            "client": [
                "clientName": "WEB",
                "clientVersion": clientVersion,
                "hl": "en",
                "gl": "US"
            ]
        ]
        if var client = context["client"] as? [String: Any] {
            client["clientName"] = stringValue(client["clientName"]) ?? "WEB"
            client["clientVersion"] = stringValue(client["clientVersion"]) ?? clientVersion
            context["client"] = client
        }
        guard JSONSerialization.isValidJSONObject(context) else {
            throw NativeDownloadError.unsupported("YouTube browse API context is invalid.")
        }

        let clientNumber = dictionaries.lazy
            .compactMap { stringValue($0["INNERTUBE_CONTEXT_CLIENT_NAME"]) }
            .map(\.trimmed)
            .first(where: { !$0.isEmpty }) ?? "1"
        let visitorData = dictionaries.lazy
            .compactMap { stringValue($0["VISITOR_DATA"]) ?? stringValue($0["visitorData"]) }
            .map(\.trimmed)
            .first(where: { !$0.isEmpty }) ?? stringValue(contextClient?["visitorData"])?.trimmed

        var endpoint = URLComponents()
        endpoint.scheme = pageURL.scheme ?? "https"
        endpoint.host = pageURL.host
        endpoint.path = "/youtubei/v1/browse"
        endpoint.queryItems = [
            URLQueryItem(name: "key", value: apiKey),
            URLQueryItem(name: "prettyPrint", value: "false")
        ]
        guard let endpointURL = endpoint.url else {
            throw NativeDownloadError.invalidURL(pageURL.absoluteString)
        }
        return YouTubeBrowseAPIConfiguration(
            apiKey: apiKey,
            context: context,
            clientNumber: clientNumber,
            clientVersion: clientVersion,
            visitorData: visitorData,
            endpoint: endpointURL
        )
    }

    static func browseRequestBody(
        continuation: String,
        configuration: YouTubeBrowseAPIConfiguration
    ) throws -> Data {
        let body: [String: Any] = [
            "context": configuration.context,
            "continuation": continuation
        ]
        return try JSONSerialization.data(withJSONObject: body)
    }

    static func collectionPage(from value: Any, pageURL: URL) -> YouTubeCollectionPage {
        var entries: [YouTubeCollectionEntry] = []
        var seen = Set<String>()
        var continuation: String?

        func visit(_ candidate: Any) {
            if let array = candidate as? [Any] {
                let localEntries = array.compactMap { collectionEntry(from: $0, pageURL: pageURL) }
                if !localEntries.isEmpty {
                    for entry in localEntries where seen.insert(entry.id).inserted {
                        entries.append(entry)
                    }
                    if let token = array.reversed().compactMap(continuationToken(from:)).first {
                        continuation = token
                    }
                    return
                }
                for item in array { visit(item) }
                return
            }
            guard let dictionary = candidate as? [String: Any] else { return }
            for child in dictionary.values { visit(child) }
        }

        visit(value)
        let dictionaries = recursiveDictionaries(in: value)
        let channel = firstDictionary(named: "channelMetadataRenderer", in: value)
        let playlist = firstDictionary(named: "playlistMetadataRenderer", in: value)
        let sidebar = firstDictionary(named: "playlistSidebarPrimaryInfoRenderer", in: value)
        let owner = firstDictionary(named: "videoOwnerRenderer", in: value)
        let pageHeader = firstDictionary(named: "pageHeaderViewModel", in: value)

        let channelTitle = cleanOptionalText(stringValue(channel?["title"]))
        let playlistTitle = cleanOptionalText(stringValue(playlist?["title"]))
        let headerTitle = cleanOptionalText(
            stringValue(pageHeader?["pageTitle"]) ?? textValue(pageHeader?["title"])
        )
        let ownerTitle = cleanOptionalText(textValue(owner?["title"]))
        let channelID = cleanOptionalText(
            stringValue(channel?["externalId"]) ??
                stringValue(channel?["channelId"]) ??
                recursiveString(in: owner as Any, keys: ["browseId"])
        )
        let thumbnailValue = channel?["avatar"] ?? sidebar?["thumbnailRenderer"] ?? pageHeader?["image"]
        let thumbnail = bestThumbnailURL(in: thumbnailValue).flatMap { absoluteURL($0, baseURL: pageURL) }
        let statsText = (sidebar?["stats"] as? [Any])?.first.flatMap(textValue)
        let total = integerFromText(statsText)

        let inferredTitle = playlistTitle ?? channelTitle ?? headerTitle ?? ownerTitle ??
            dictionaries.lazy.compactMap { dictionary in
                guard let metadata = dictionary["metadata"] as? [String: Any],
                      let title = metadata["title"] else { return nil }
                return cleanOptionalText(textValue(title))
            }.first
        return YouTubeCollectionPage(
            entries: entries,
            continuationToken: continuation,
            title: inferredTitle,
            uploader: channelTitle ?? ownerTitle,
            uploaderID: channelID,
            thumbnailURL: thumbnail,
            totalCount: total
        )
    }

    static func combinedDownload(
        request: YouTubeCollectionRequest,
        displayTitle: String,
        collectionTitle: String,
        uploader: String,
        uploaderID: String,
        thumbnailURL: URL?,
        posts: [(entry: YouTubeCollectionEntry, download: ResolvedDownload)],
        numberPlaylistFiles: Bool
    ) throws -> ResolvedDownload {
        guard !posts.isEmpty else { throw NativeDownloadError.noFiles }
        var assets: [ResolvedAsset] = []
        var fileAssetIndexes: [Int] = []
        var concatenations: [ResolvedConcatenationGroup] = []
        var muxes: [ResolvedMuxGroup] = []

        for (postIndex, post) in posts.enumerated() {
            let offset = assets.count
            let originalAssets = post.download.assets
            let stagePrefix = String(format: "%04d-%@", postIndex + 1, post.entry.id)
            let usesFinalAssetNames: Bool
            if case .files = post.download.packageMode {
                usesFinalAssetNames = true
            } else {
                usesFinalAssetNames = false
            }
            let decorated = originalAssets.map { input -> ResolvedAsset in
                var asset = input
                asset.filename = usesFinalAssetNames
                    ? outputFilename(input.filename, index: postIndex, numbered: numberPlaylistFiles)
                    : prefixedFilename(input.filename, prefix: stagePrefix)
                asset.metadata = input.metadata.merging(
                    collectionMetadata(request: request, entry: post.entry, postIndex: postIndex)
                ) { current, _ in current }
                return asset
            }
            assets.append(contentsOf: decorated)

            switch post.download.packageMode {
            case .files:
                fileAssetIndexes.append(contentsOf: decorated.indices.map { offset + $0 })
            case .concatenate(let output):
                concatenations.append(ResolvedConcatenationGroup(
                    assetIndexes: decorated.indices.map { offset + $0 },
                    outputFilename: outputFilename(output, index: postIndex, numbered: numberPlaylistFiles),
                    metadata: groupMetadata(request: request, post: post, postIndex: postIndex)
                ))
            case .mux(let videos, let audios, let output):
                let videoIndexes = try matchingIndexes(of: videos, in: originalAssets)
                let audioIndexes = try matchingIndexes(of: audios, in: originalAssets)
                muxes.append(ResolvedMuxGroup(
                    videoAssetIndexes: videoIndexes.map { offset + $0 },
                    audioAssetIndexes: audioIndexes.map { offset + $0 },
                    outputFilename: outputFilename(output, index: postIndex, numbered: numberPlaylistFiles),
                    metadata: groupMetadata(request: request, post: post, postIndex: postIndex)
                ))
            case .grouped(let nestedFiles, let nestedConcatenations):
                fileAssetIndexes.append(contentsOf: nestedFiles.map { offset + $0 })
                concatenations.append(contentsOf: nestedConcatenations.map { group in
                    ResolvedConcatenationGroup(
                        assetIndexes: group.assetIndexes.map { offset + $0 },
                        outputFilename: outputFilename(group.outputFilename, index: postIndex, numbered: numberPlaylistFiles),
                        metadata: group.metadata.merging(
                            groupMetadata(request: request, post: post, postIndex: postIndex)
                        ) { current, _ in current }
                    )
                })
            case .groupedMedia(let nestedFiles, let nestedConcatenations, let nestedMuxes):
                fileAssetIndexes.append(contentsOf: nestedFiles.map { offset + $0 })
                concatenations.append(contentsOf: nestedConcatenations.map { group in
                    ResolvedConcatenationGroup(
                        assetIndexes: group.assetIndexes.map { offset + $0 },
                        outputFilename: outputFilename(group.outputFilename, index: postIndex, numbered: numberPlaylistFiles),
                        metadata: group.metadata.merging(
                            groupMetadata(request: request, post: post, postIndex: postIndex)
                        ) { current, _ in current }
                    )
                })
                muxes.append(contentsOf: nestedMuxes.map { group in
                    ResolvedMuxGroup(
                        videoAssetIndexes: group.videoAssetIndexes.map { offset + $0 },
                        audioAssetIndexes: group.audioAssetIndexes.map { offset + $0 },
                        outputFilename: outputFilename(group.outputFilename, index: postIndex, numbered: numberPlaylistFiles),
                        metadata: group.metadata.merging(
                            groupMetadata(request: request, post: post, postIndex: postIndex)
                        ) { current, _ in current }
                    )
                })
            }
        }

        let packageMode: DownloadPackageMode
        if !muxes.isEmpty {
            packageMode = .groupedMedia(
                fileAssetIndexes: fileAssetIndexes,
                concatenations: concatenations,
                muxes: muxes
            )
        } else if !concatenations.isEmpty {
            packageMode = .grouped(
                fileAssetIndexes: fileAssetIndexes,
                concatenations: concatenations
            )
        } else {
            packageMode = .files
        }
        let thumbnail = thumbnailURL?.absoluteString ??
            posts.lazy.compactMap { $0.entry.thumbnailURL?.absoluteString }.first ??
            posts.lazy.compactMap { $0.download.metadata["thumbnail"] }.first ?? ""
        let playlistID = request.kind == .playlist ? request.identifier : ""
        let channelID = request.kind == .channel ? request.identifier : uploaderID
        return ResolvedDownload(
            title: displayTitle,
            folderName: displayTitle.sanitizedFilename(maxLength: 120),
            assets: assets,
            packageMode: packageMode,
            metadata: DownloadMetadata.clean([
                "site": "YouTube",
                "title": displayTitle,
                "series": collectionTitle,
                "playlist": request.kind == .playlist ? collectionTitle : "",
                "playlist_id": playlistID,
                "artist": uploader,
                "author": uploader,
                "creator": uploader,
                "uploader": uploader,
                "channel": uploader,
                "channel_id": channelID,
                "uploader_id": uploaderID,
                "type": request.kind.rawValue,
                "media_type": "video",
                "category": request.kind == .channel ? "videos" : "playlist",
                "collection": "true",
                "collection_kind": request.kind.rawValue,
                "item_count": String(posts.count),
                "media_count": String(assets.count),
                "mux_count": String(muxes.count),
                "thumbnail": thumbnail,
                "url": request.sourceURL.absoluteString,
                "source_url": request.sourceURL.absoluteString,
                "page_url": request.sourceURL.absoluteString,
                "host": request.sourceURL.host ?? "",
                "extractor": "youtube_collection_native",
                "handler": "native",
                "player_client": YouTubeResolver.androidClientName,
                "player_client_version": YouTubeResolver.androidClientVersion,
                "player_api": "innertube"
            ])
        )
    }

    private static func fetchContinuation(
        token: String,
        configuration: YouTubeBrowseAPIConfiguration,
        pageURL: URL,
        userAgent: String
    ) async throws -> Any {
        let body = try browseRequestBody(continuation: token, configuration: configuration)
        var requestHeaders = [
            "X-YouTube-Client-Name": configuration.clientNumber,
            "X-YouTube-Client-Version": configuration.clientVersion,
            "Origin": origin(for: pageURL)
        ]
        if let visitorData = configuration.visitorData {
            requestHeaders["X-Goog-Visitor-Id"] = visitorData
        }
        let data = try await HTTPClient.shared.postJSON(
            to: configuration.endpoint,
            body: body,
            referer: pageURL.absoluteString,
            userAgent: userAgent,
            additionalHeaders: requestHeaders
        )
        return try JSONSerialization.jsonObject(with: data)
    }

    private static func collectionEntry(from value: Any, pageURL: URL) -> YouTubeCollectionEntry? {
        guard let dictionary = value as? [String: Any] else { return nil }
        if let lockup = dictionary["lockupViewModel"] as? [String: Any] {
            return entry(fromLockup: lockup, pageURL: pageURL)
        }
        if dictionary["contentType"] != nil, dictionary["contentId"] != nil {
            return entry(fromLockup: dictionary, pageURL: pageURL)
        }
        if let rich = dictionary["richItemRenderer"] as? [String: Any],
           let content = rich["content"] {
            return collectionEntry(from: content, pageURL: pageURL)
        }
        for key in [
            "playlistVideoRenderer", "gridVideoRenderer", "videoRenderer",
            "compactVideoRenderer", "playlistPanelVideoRenderer", "richGridMedia"
        ] {
            if let renderer = dictionary[key] as? [String: Any],
               let entry = entry(fromRenderer: renderer, pageURL: pageURL) {
                return entry
            }
        }
        return nil
    }

    private static func entry(
        fromLockup lockup: [String: Any],
        pageURL: URL
    ) -> YouTubeCollectionEntry? {
        let contentType = stringValue(lockup["contentType"])?.uppercased() ?? ""
        guard contentType.isEmpty || contentType.contains("VIDEO"),
              let id = stringValue(lockup["contentId"])?.trimmed,
              isVideoID(id) else {
            return nil
        }
        let metadata = lockup["metadata"] as? [String: Any]
        let lockupMetadata = metadata?["lockupMetadataViewModel"] as? [String: Any]
        let title = cleanText(
            textValue(lockupMetadata?["title"]) ?? "YouTube \(id)"
        )
        let rows = ((lockupMetadata?["metadata"] as? [String: Any])?["contentMetadataViewModel"] as? [String: Any])?["metadataRows"] as? [Any]
        let uploader = rows?.first.flatMap(textValue).map(cleanText) ?? ""
        let image = ((lockup["contentImage"] as? [String: Any])?["thumbnailViewModel"] as? [String: Any])?["image"]
        let thumbnail = bestThumbnailURL(in: image).flatMap { absoluteURL($0, baseURL: pageURL) }
        return YouTubeCollectionEntry(
            id: id,
            title: title,
            uploader: uploader,
            thumbnailURL: thumbnail,
            pageURL: watchURL(videoID: id, sourceURL: pageURL)
        )
    }

    private static func entry(
        fromRenderer renderer: [String: Any],
        pageURL: URL
    ) -> YouTubeCollectionEntry? {
        guard let id = stringValue(renderer["videoId"])?.trimmed,
              isVideoID(id) else {
            return nil
        }
        let title = cleanText(
            textValue(renderer["title"]) ??
                textValue(renderer["headline"]) ??
                "YouTube \(id)"
        )
        let uploader = cleanText(
            textValue(renderer["shortBylineText"]) ??
                textValue(renderer["longBylineText"]) ??
                textValue(renderer["ownerText"]) ?? ""
        )
        let thumbnail = bestThumbnailURL(in: renderer["thumbnail"])
            .flatMap { absoluteURL($0, baseURL: pageURL) }
        return YouTubeCollectionEntry(
            id: id,
            title: title,
            uploader: uploader,
            thumbnailURL: thumbnail,
            pageURL: watchURL(videoID: id, sourceURL: pageURL)
        )
    }

    private static func continuationToken(from value: Any) -> String? {
        guard let dictionary = value as? [String: Any] else { return nil }
        if let renderer = dictionary["continuationItemRenderer"] as? [String: Any] {
            return recursiveString(in: renderer, keys: ["token"])?.trimmed
        }
        if let viewModel = dictionary["continuationItemViewModel"] as? [String: Any] {
            return recursiveString(in: viewModel, keys: ["token"])?.trimmed
        }
        return nil
    }

    private static func groupMetadata(
        request: YouTubeCollectionRequest,
        post: (entry: YouTubeCollectionEntry, download: ResolvedDownload),
        postIndex: Int
    ) -> [String: String] {
        post.download.metadata.merging(
            collectionMetadata(request: request, entry: post.entry, postIndex: postIndex)
        ) { current, _ in current }
    }

    private static func collectionMetadata(
        request: YouTubeCollectionRequest,
        entry: YouTubeCollectionEntry,
        postIndex: Int
    ) -> [String: String] {
        DownloadMetadata.clean([
            "collection_index": String(postIndex + 1),
            "playlist_index": String(postIndex + 1),
            "collection_item_id": entry.id,
            "collection_url": request.sourceURL.absoluteString,
            "collection_kind": request.kind.rawValue,
            "item_title": entry.title,
            "item_author": entry.uploader,
            "item_thumbnail": entry.thumbnailURL?.absoluteString ?? "",
            "item_page_url": entry.pageURL.absoluteString
        ])
    }

    private static func matchingIndexes(
        of needles: [ResolvedAsset],
        in assets: [ResolvedAsset]
    ) throws -> [Int] {
        var used = Set<Int>()
        var indexes: [Int] = []
        for needle in needles {
            guard let index = assets.indices.first(where: { index in
                !used.contains(index) &&
                    assets[index].remoteURL == needle.remoteURL &&
                    assets[index].filename == needle.filename
            }) else {
                throw NativeDownloadError.unsupported("Invalid nested YouTube mux plan.")
            }
            used.insert(index)
            indexes.append(index)
        }
        return indexes
    }

    private static func outputFilename(_ filename: String, index: Int, numbered: Bool) -> String {
        guard numbered else { return filename.sanitizedFilename(maxLength: 180) }
        return String(format: "%03d - %@", index + 1, filename).sanitizedFilename(maxLength: 180)
    }

    private static func prefixedFilename(_ filename: String, prefix: String) -> String {
        "\(prefix)-\(filename)".sanitizedFilename(maxLength: 180)
    }

    private static func recursiveDictionaries(in value: Any) -> [[String: Any]] {
        var result: [[String: Any]] = []
        func visit(_ candidate: Any) {
            if let dictionary = candidate as? [String: Any] {
                result.append(dictionary)
                for child in dictionary.values { visit(child) }
            } else if let array = candidate as? [Any] {
                for child in array { visit(child) }
            }
        }
        visit(value)
        return result
    }

    private static func firstDictionary(named name: String, in value: Any) -> [String: Any]? {
        if let dictionary = value as? [String: Any] {
            if let found = dictionary[name] as? [String: Any] { return found }
            for child in dictionary.values {
                if let found = firstDictionary(named: name, in: child) { return found }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let found = firstDictionary(named: name, in: child) { return found }
            }
        }
        return nil
    }

    private static func recursiveString(in value: Any, keys: Set<String>) -> String? {
        if let dictionary = value as? [String: Any] {
            for key in keys {
                if let found = stringValue(dictionary[key]), !found.trimmed.isEmpty { return found }
            }
            for child in dictionary.values {
                if let found = recursiveString(in: child, keys: keys) { return found }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let found = recursiveString(in: child, keys: keys) { return found }
            }
        }
        return nil
    }

    private static func textValue(_ value: Any?) -> String? {
        if let value = value as? String { return value }
        if let dictionary = value as? [String: Any] {
            for key in ["simpleText", "content", "text"] {
                if let text = dictionary[key] as? String, !text.trimmed.isEmpty { return text }
            }
            if let runs = dictionary["runs"] as? [[String: Any]] {
                let text = runs.compactMap { stringValue($0["text"]) }.joined()
                if !text.trimmed.isEmpty { return text }
            }
            if let parts = dictionary["metadataParts"] as? [Any] {
                let text = parts.compactMap(textValue).joined(separator: " ")
                if !text.trimmed.isEmpty { return text }
            }
            for key in ["title", "label", "accessibilityText"] {
                if let text = textValue(dictionary[key]), !text.trimmed.isEmpty { return text }
            }
        } else if let array = value as? [Any] {
            let text = array.compactMap(textValue).joined(separator: " ")
            if !text.trimmed.isEmpty { return text }
        }
        return nil
    }

    private static func bestThumbnailURL(in value: Any?) -> String? {
        var best: (url: String, area: Int)?
        func visit(_ candidate: Any?) {
            if let dictionary = candidate as? [String: Any] {
                if let raw = stringValue(dictionary["url"])?.trimmed,
                   !raw.isEmpty,
                   raw.hasPrefix("http") || raw.hasPrefix("//") {
                    let width = integerValue(dictionary["width"]) ?? 0
                    let height = integerValue(dictionary["height"]) ?? 0
                    let area = width * max(1, height)
                    if best == nil || area >= best!.area { best = (raw, area) }
                }
                for child in dictionary.values { visit(child) }
            } else if let array = candidate as? [Any] {
                for child in array { visit(child) }
            }
        }
        visit(value)
        return best?.url
    }

    private static func integerFromText(_ value: String?) -> Int? {
        guard let value else { return nil }
        let digits = value.filter(\.isNumber)
        return digits.isEmpty ? nil : Int(digits)
    }

    private struct ItemRangeSegment {
        var start: Int?
        var end: Int?
    }

    static func collectionItemLimit(for expression: String, itemLimit: Int? = nil) throws -> Int {
        let segments = try itemRangeSegments(from: expression.trimmed)
        guard !segments.isEmpty else {
            return max(1, itemLimit ?? defaultCollectionItemLimit)
        }
        if segments.contains(where: { $0.end == nil }) { return Int.max }
        return max(1, segments.compactMap(\.end).max() ?? defaultCollectionItemLimit)
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
            for position in start...end {
                let index = position - 1
                if seen.insert(index).inserted { indexes.append(index) }
            }
        }
        guard !indexes.isEmpty else {
            throw NativeDownloadError.unsupported("Range did not match any YouTube collection items.")
        }
        return indexes
    }

    private static func itemRangeSegments(from expression: String) throws -> [ItemRangeSegment] {
        guard !expression.isEmpty else { return [] }
        let compact = expression
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\t", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
        let pieces = compact
            .components(separatedBy: CharacterSet(charactersIn: ",;"))
            .filter { !$0.isEmpty }
        guard !pieces.isEmpty else {
            throw NativeDownloadError.unsupported("Invalid range.")
        }
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

    private static func watchURL(videoID: String, sourceURL: URL) -> URL {
        var components = URLComponents()
        components.scheme = sourceURL.scheme ?? "https"
        components.host = sourceURL.host
        components.path = "/watch"
        components.queryItems = [URLQueryItem(name: "v", value: videoID)]
        return components.url!
    }

    private static func absoluteURL(_ raw: String, baseURL: URL) -> URL? {
        let value = raw.trimmed
        if value.hasPrefix("//") {
            return URL(string: "\(baseURL.scheme ?? "https"):\(value)")
        }
        return URL(string: value, relativeTo: baseURL)?.absoluteURL
    }

    private static func origin(for url: URL) -> String {
        guard let scheme = url.scheme, let host = url.host else { return url.absoluteString }
        if let port = url.port { return "\(scheme)://\(host):\(port)" }
        return "\(scheme)://\(host)"
    }

    private static func canonicalHost(for host: String) -> String {
        host.hasSuffix(".test") ? host : "www.youtube.com"
    }

    private static func isSupportedHost(_ host: String) -> Bool {
        host == "youtube.com" ||
            host == "www.youtube.com" ||
            host == "m.youtube.com" ||
            host == "music.youtube.com" ||
            host == "youtube.co" ||
            host == "www.youtube.co" ||
            host == "youtube.test" ||
            host == "www.youtube.test" ||
            host == "m.youtube.test"
    }

    private static func isVideoID(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z0-9_-]{6,64}$"#, options: .regularExpression) != nil
    }

    private static func cleanOptionalText(_ value: String?) -> String? {
        guard let value else { return nil }
        let cleaned = cleanText(value)
        return cleaned.isEmpty ? nil : cleaned
    }

    private static func cleanText(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmed
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return nil
    }

    private static func integerValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }
}
