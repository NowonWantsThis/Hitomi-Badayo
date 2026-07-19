import Foundation

enum TwitchClipCollectionRange: String, CaseIterable {
    case day = "24hr"
    case week = "7d"
    case month = "30d"
    case all = "all"

    var graphQLFilter: String {
        switch self {
        case .day: return "LAST_DAY"
        case .week: return "LAST_WEEK"
        case .month: return "LAST_MONTH"
        case .all: return "ALL_TIME"
        }
    }
}

struct TwitchClipCollectionRequest: Equatable {
    var login: String
    var range: TwitchClipCollectionRange
    var sourceURL: URL
}

struct TwitchClipCollectionEntry: Equatable {
    var id: String
    var slug: String
    var title: String
    var createdAt: String
    var durationSeconds: String
    var viewCount: String
    var broadcaster: String
    var curator: String
    var thumbnailURL: URL?
    var pageURL: URL
}

struct TwitchClipCollectionPage: Equatable {
    var userID: String
    var login: String
    var displayName: String
    var profileImageURL: URL?
    var entries: [TwitchClipCollectionEntry]
    var endCursor: String?
    var hasNextPage: Bool
    var redactedNodeCount: Int
}

final class TwitchClipCollectionResolver {
    private static let clientID = "kimne78kx3ncx6brgo4mv6wki5h1ko"
    private static let pageSize = 50
    static let defaultCollectionItemLimit = 2_000
    private static let reservedLogins: Set<String> = [
        "about", "activate", "bits", "broadcast", "clip", "clips", "collections", "creatorcamp",
        "dashboard", "directory", "downloads", "drops", "embed", "event", "following", "friends",
        "inventory", "jobs", "login", "logout", "moderator", "p", "popout", "privacy", "search",
        "settings", "signup", "store", "subscriptions", "team", "terms", "turbo", "videos", "wallet", "watch"
    ]
    private static let clipsQuery = """
    query ClipsCards__User($login: String!, $limit: Int!, $cursor: Cursor, $criteria: UserClipsInput) {
      user(login: $login) {
        id
        login
        displayName
        profileImageURL(width: 150)
        clips(first: $limit, after: $cursor, criteria: $criteria) {
          edges {
            cursor
            node {
              id
              slug
              title
              createdAt
              durationSeconds
              viewCount
              thumbnailURL(width: 480, height: 272)
              broadcaster { id login displayName }
              curator { id login displayName }
              video { id }
            }
          }
          pageInfo { hasNextPage }
        }
      }
    }
    """

    func canResolve(_ url: URL) -> Bool {
        Self.request(from: url) != nil
    }

    func resolve(
        _ url: URL,
        headers: HTTPRequestOptions = HTTPRequestOptions(),
        preferredResolution: String = "",
        rangeExpression: String = ""
    ) async throws -> ResolvedDownload {
        guard let request = Self.request(from: url) else {
            throw NativeDownloadError.invalidURL(url.absoluteString)
        }

        var entries: [TwitchClipCollectionEntry] = []
        var seen = Set<String>()
        var cursor: String?
        var userID = ""
        var login = request.login
        var displayName = request.login
        var profileImageURL: URL?
        var redactedNodeCount = 0
        var collectionPageCount = 0
        let itemRange = rangeExpression.trimmed
        let itemLimit = try Self.collectionItemLimit(for: itemRange)

        while entries.count < itemLimit {
            try Task.checkCancellation()
            let body = try Self.graphQLRequestBody(request: request, cursor: cursor)
            let data = try await HTTPClient.shared.postJSON(
                to: Self.graphQLURL(for: request),
                body: body,
                referer: request.sourceURL.absoluteString,
                userAgent: headers.userAgent,
                additionalHeaders: Self.graphQLHeaders()
            )
            collectionPageCount += 1
            let page = try Self.collectionPage(from: data, request: request)
            if userID.isEmpty { userID = page.userID }
            if !page.login.isEmpty { login = page.login }
            if !page.displayName.isEmpty { displayName = page.displayName }
            if profileImageURL == nil { profileImageURL = page.profileImageURL }
            redactedNodeCount += page.redactedNodeCount
            for entry in page.entries where seen.insert(entry.slug.lowercased()).inserted {
                entries.append(entry)
                if entries.count >= itemLimit { break }
            }

            if page.entries.isEmpty, page.redactedNodeCount > 0 {
                if entries.isEmpty {
                    throw NativeDownloadError.unsupported(
                        "Twitch returned redacted clip records for this channel. Clips may be unavailable in the current region or require a signed-in Twitch session."
                    )
                }
                break
            }

            guard page.hasNextPage,
                  let nextCursor = page.endCursor?.trimmed,
                  !nextCursor.isEmpty,
                  nextCursor != cursor else {
                break
            }
            cursor = nextCursor
        }

        if entries.isEmpty, redactedNodeCount > 0 {
            throw NativeDownloadError.unsupported(
                "Twitch returned redacted clip records for this channel. Clips may be unavailable in the current region or require a signed-in Twitch session."
            )
        }
        guard !entries.isEmpty else {
            throw NativeDownloadError.noFiles
        }

        entries = Self.originalOrder(entries)
        let listedItemCount = entries.count
        let selectedIndexes = try Self.collectionItemIndexes(for: itemRange, total: listedItemCount)
        let selectedEntries = selectedIndexes.map { entries[$0] }
        let mediaResolver = TwitchVODResolver()
        var posts: [(entry: TwitchClipCollectionEntry, download: ResolvedDownload)] = []
        var failures: [Error] = []
        for entry in selectedEntries {
            try Task.checkCancellation()
            do {
                let resolved = try await mediaResolver.resolve(
                    entry.pageURL,
                    headers: headers,
                    preferredResolution: preferredResolution
                )
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

        var combined = try Self.combinedDownload(
            request: request,
            userID: userID,
            login: login,
            displayName: displayName,
            profileImageURL: profileImageURL,
            posts: posts
        )
        combined.metadata["listed_item_count"] = String(listedItemCount)
        combined.metadata["discovered_item_count"] = String(listedItemCount)
        combined.metadata["selected_item_count"] = String(selectedEntries.count)
        combined.metadata["resolved_item_count"] = String(posts.count)
        combined.metadata["collection_pages"] = String(collectionPageCount)
        combined.metadata["collection_item_limit"] = itemLimit == Int.max ? "unbounded" : String(itemLimit)
        if !itemRange.isEmpty {
            combined.metadata["range"] = itemRange
            combined.metadata["range_scope"] = "collection_items"
            combined.metadata["range_total"] = String(listedItemCount)
            combined.metadata["range_selected"] = String(selectedEntries.count)
            combined.metadata["range_indexes"] = Self.compactRangeDescription(fromZeroBasedIndexes: selectedIndexes)
        }
        if redactedNodeCount > 0 {
            combined.metadata["redacted_item_count"] = String(redactedNodeCount)
        }
        if !failures.isEmpty {
            combined.metadata["skipped_count"] = String(failures.count)
        }
        return combined
    }

    private struct ItemRangeSegment {
        var start: Int?
        var end: Int?
    }

    static func collectionItemLimit(for expression: String) throws -> Int {
        let segments = try itemRangeSegments(from: expression.trimmed)
        guard !segments.isEmpty else { return defaultCollectionItemLimit }
        if segments.contains(where: { $0.end == nil }) { return Int.max }
        return max(1, segments.compactMap(\.end).max() ?? defaultCollectionItemLimit)
    }

    static func collectionItemIndexes(for expression: String, total: Int) throws -> [Int] {
        let segments = try itemRangeSegments(from: expression.trimmed)
        guard total > 0 else { return [] }
        if segments.isEmpty {
            return Array(0..<min(total, defaultCollectionItemLimit))
        }

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
            throw NativeDownloadError.unsupported("Range did not match any Twitch clips.")
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

    private static func compactRangeDescription(fromZeroBasedIndexes indexes: [Int]) -> String {
        guard !indexes.isEmpty else { return "" }
        var pieces: [String] = []
        var start = indexes[0] + 1
        var previous = start
        for index in indexes.dropFirst().map({ $0 + 1 }) {
            if index == previous + 1 {
                previous = index
                continue
            }
            pieces.append(start == previous ? "\(start)" : "\(start)-\(previous)")
            start = index
            previous = index
        }
        pieces.append(start == previous ? "\(start)" : "\(start)-\(previous)")
        return pieces.joined(separator: ",")
    }

    static func request(from url: URL) -> TwitchClipCollectionRequest? {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host?.lowercased(),
              isSupportedHost(host),
              !host.hasPrefix("clips.") else {
            return nil
        }

        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        guard parts.count == 2 else { return nil }
        let login = parts[0].trimmed
        let tab = parts[1].lowercased()
        guard isValidLogin(login), !reservedLogins.contains(login.lowercased()) else { return nil }

        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let filter = queryValue(named: "filter", in: queryItems)?.lowercased()
        if tab == "clips" {
            guard filter == nil || filter == "clips" else { return nil }
        } else if tab == "videos" {
            guard filter == "clips" else { return nil }
        } else {
            return nil
        }
        let range = TwitchClipCollectionRange(
            rawValue: queryValue(named: "range", in: queryItems)?.lowercased() ?? "all"
        ) ?? .all
        guard let sourceURL = canonicalURL(login: login, range: range, sourceURL: url) else { return nil }
        return TwitchClipCollectionRequest(login: login, range: range, sourceURL: sourceURL)
    }

    static func canonicalURL(
        login: String,
        range: TwitchClipCollectionRange,
        sourceURL: URL
    ) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = sourceURL.host?.lowercased().hasSuffix(".test") == true
            ? "www.twitch.test"
            : "www.twitch.tv"
        components.path = "/\(login)/clips"
        components.queryItems = [
            URLQueryItem(name: "filter", value: "clips"),
            URLQueryItem(name: "range", value: range.rawValue)
        ]
        return components.url
    }

    static func graphQLURL(for request: TwitchClipCollectionRequest) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = request.sourceURL.host?.lowercased().hasSuffix(".test") == true
            ? "gql.twitch.test"
            : "gql.twitch.tv"
        components.path = "/gql"
        return components.url!
    }

    static func graphQLRequestBody(
        request: TwitchClipCollectionRequest,
        cursor: String?
    ) throws -> Data {
        let variables: [String: Any] = [
            "login": request.login,
            "limit": pageSize,
            "cursor": cursor ?? NSNull(),
            "criteria": ["filter": request.range.graphQLFilter]
        ]
        return try JSONSerialization.data(withJSONObject: [
            "operationName": "ClipsCards__User",
            "query": clipsQuery,
            "variables": variables
        ])
    }

    static func collectionPage(
        from data: Data,
        request: TwitchClipCollectionRequest
    ) throws -> TwitchClipCollectionPage {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let root = object as? [String: Any] else {
            throw NativeDownloadError.invalidGalleryData
        }
        if let errors = root["errors"] as? [[String: Any]], !errors.isEmpty {
            let messages = errors.compactMap { stringValue($0["message"]) }.joined(separator: "; ")
            throw NativeDownloadError.unsupported(
                messages.isEmpty ? "Twitch clips API returned an error." : "Twitch clips API error: \(messages)"
            )
        }
        guard let dataObject = root["data"] as? [String: Any],
              let user = dataObject["user"] as? [String: Any] else {
            throw NativeDownloadError.unsupported("Twitch channel \(request.login) was not found or is unavailable.")
        }

        let clips = user["clips"] as? [String: Any] ?? [:]
        let edges = clips["edges"] as? [Any] ?? []
        var entries: [TwitchClipCollectionEntry] = []
        var seen = Set<String>()
        var endCursor: String?
        var redactedNodeCount = 0
        for case let edge as [String: Any] in edges {
            if let value = stringValue(edge["cursor"]), !value.isEmpty {
                endCursor = value
            }
            guard let node = edge["node"] as? [String: Any] else {
                redactedNodeCount += 1
                continue
            }
            guard let entry = entry(from: node, request: request),
                  seen.insert(entry.slug.lowercased()).inserted else {
                continue
            }
            entries.append(entry)
        }

        let pageInfo = clips["pageInfo"] as? [String: Any]
        return TwitchClipCollectionPage(
            userID: stringValue(user["id"]) ?? "",
            login: stringValue(user["login"]) ?? request.login,
            displayName: stringValue(user["displayName"]) ?? request.login,
            profileImageURL: stringValue(user["profileImageURL"]).flatMap(URL.init(string:)),
            entries: entries,
            endCursor: endCursor,
            hasNextPage: boolValue(pageInfo?["hasNextPage"]),
            redactedNodeCount: redactedNodeCount
        )
    }

    static func combinedDownload(
        request: TwitchClipCollectionRequest,
        userID: String,
        login rawLogin: String,
        displayName rawDisplayName: String,
        profileImageURL: URL?,
        posts: [(entry: TwitchClipCollectionEntry, download: ResolvedDownload)]
    ) throws -> ResolvedDownload {
        guard !posts.isEmpty else { throw NativeDownloadError.noFiles }

        var assets: [ResolvedAsset] = []
        var fileAssetIndexes: [Int] = []
        var concatenations: [ResolvedConcatenationGroup] = []
        var muxes: [ResolvedMuxGroup] = []
        for (postIndex, post) in posts.enumerated() {
            let offset = assets.count
            let prefix = String(format: "%04d-%@", postIndex + 1, post.entry.slug)
            let originalAssets = post.download.assets
            let itemMetadata = collectionMetadata(
                request: request,
                entry: post.entry,
                postIndex: postIndex
            )
            let decorated = originalAssets.map { input -> ResolvedAsset in
                var asset = input
                asset.filename = prefixedFilename(input.filename, prefix: prefix)
                asset.metadata = input.metadata.merging(itemMetadata) { current, _ in current }
                return asset
            }
            assets.append(contentsOf: decorated)

            let groupMetadata = post.download.metadata.merging(itemMetadata) { current, _ in current }
            switch post.download.packageMode {
            case .files:
                fileAssetIndexes.append(contentsOf: decorated.indices.map { offset + $0 })
            case .concatenate(let outputFilename):
                concatenations.append(ResolvedConcatenationGroup(
                    assetIndexes: decorated.indices.map { offset + $0 },
                    outputFilename: prefixedFilename(outputFilename, prefix: prefix),
                    metadata: groupMetadata
                ))
            case .mux(let videoAssets, let audioAssets, let outputFilename):
                let videoIndexes = try matchingIndexes(of: videoAssets, in: originalAssets)
                let audioIndexes = try matchingIndexes(of: audioAssets, in: originalAssets)
                muxes.append(ResolvedMuxGroup(
                    videoAssetIndexes: videoIndexes.map { offset + $0 },
                    audioAssetIndexes: audioIndexes.map { offset + $0 },
                    outputFilename: prefixedFilename(outputFilename, prefix: prefix),
                    metadata: groupMetadata
                ))
            case .grouped(let nestedFiles, let nestedConcatenations):
                fileAssetIndexes.append(contentsOf: nestedFiles.map { offset + $0 })
                concatenations.append(contentsOf: nestedConcatenations.map { group in
                    ResolvedConcatenationGroup(
                        assetIndexes: group.assetIndexes.map { offset + $0 },
                        outputFilename: prefixedFilename(group.outputFilename, prefix: prefix),
                        metadata: group.metadata.merging(groupMetadata) { current, _ in current }
                    )
                })
            case .groupedMedia(let nestedFiles, let nestedConcatenations, let nestedMuxes):
                fileAssetIndexes.append(contentsOf: nestedFiles.map { offset + $0 })
                concatenations.append(contentsOf: nestedConcatenations.map { group in
                    ResolvedConcatenationGroup(
                        assetIndexes: group.assetIndexes.map { offset + $0 },
                        outputFilename: prefixedFilename(group.outputFilename, prefix: prefix),
                        metadata: group.metadata.merging(groupMetadata) { current, _ in current }
                    )
                })
                muxes.append(contentsOf: nestedMuxes.map { group in
                    ResolvedMuxGroup(
                        videoAssetIndexes: group.videoAssetIndexes.map { offset + $0 },
                        audioAssetIndexes: group.audioAssetIndexes.map { offset + $0 },
                        outputFilename: prefixedFilename(group.outputFilename, prefix: prefix),
                        metadata: group.metadata.merging(groupMetadata) { current, _ in current }
                    )
                })
            }
        }

        let login = cleanText(rawLogin, fallback: request.login)
        let displayName = cleanText(rawDisplayName, fallback: login)
        let title = "[Clip] \(displayName)"
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
        let thumbnail = profileImageURL?.absoluteString ??
            posts.lazy.compactMap { $0.entry.thumbnailURL?.absoluteString }.first ??
            posts.lazy.compactMap { $0.download.metadata["thumbnail"] }.first ?? ""
        return ResolvedDownload(
            title: title,
            folderName: title.sanitizedFilename(maxLength: 120),
            assets: assets,
            packageMode: packageMode,
            metadata: DownloadMetadata.clean([
                "site": "Twitch",
                "title": title,
                "series": displayName,
                "artist": displayName,
                "author": displayName,
                "creator": displayName,
                "uploader": displayName,
                "channel": displayName,
                "user": login,
                "username": login,
                "channel_login": login,
                "user_id": userID,
                "type": "collection",
                "media_type": "video",
                "category": "clips",
                "collection": "true",
                "playlist": "true",
                "collection_filter": "clips",
                "collection_range": request.range.rawValue,
                "item_count": String(posts.count),
                "media_count": String(assets.count),
                "thumbnail": thumbnail,
                "url": request.sourceURL.absoluteString,
                "source_url": request.sourceURL.absoluteString,
                "page_url": request.sourceURL.absoluteString
            ])
        )
    }

    static func originalOrder(_ entries: [TwitchClipCollectionEntry]) -> [TwitchClipCollectionEntry] {
        guard entries.allSatisfy({ UInt64($0.id) != nil }) else { return entries }
        return entries.sorted { (UInt64($0.id) ?? 0) > (UInt64($1.id) ?? 0) }
    }

    private static func entry(
        from node: [String: Any],
        request: TwitchClipCollectionRequest
    ) -> TwitchClipCollectionEntry? {
        guard let id = stringValue(node["id"])?.trimmed, !id.isEmpty,
              let slug = stringValue(node["slug"])?.trimmed, isValidSlug(slug) else {
            return nil
        }
        let broadcaster = node["broadcaster"] as? [String: Any]
        let curator = node["curator"] as? [String: Any]
        return TwitchClipCollectionEntry(
            id: id,
            slug: slug,
            title: cleanText(stringValue(node["title"]) ?? slug, fallback: slug),
            createdAt: stringValue(node["createdAt"]) ?? "",
            durationSeconds: stringValue(node["durationSeconds"]) ?? "",
            viewCount: stringValue(node["viewCount"]) ?? "",
            broadcaster: cleanText(
                stringValue(broadcaster?["displayName"]) ?? stringValue(broadcaster?["login"]) ?? request.login,
                fallback: request.login
            ),
            curator: cleanText(
                stringValue(curator?["displayName"]) ?? stringValue(curator?["login"]) ?? "",
                fallback: ""
            ),
            thumbnailURL: stringValue(node["thumbnailURL"]).flatMap(URL.init(string:)),
            pageURL: clipURL(slug: slug, request: request)
        )
    }

    private static func collectionMetadata(
        request: TwitchClipCollectionRequest,
        entry: TwitchClipCollectionEntry,
        postIndex: Int
    ) -> [String: String] {
        DownloadMetadata.clean([
            "collection_index": String(postIndex + 1),
            "collection_item_id": entry.id,
            "collection_url": request.sourceURL.absoluteString,
            "collection_filter": "clips",
            "collection_range": request.range.rawValue,
            "clip_id": entry.id,
            "clip_slug": entry.slug,
            "item_title": entry.title,
            "item_author": entry.broadcaster,
            "item_curator": entry.curator,
            "item_created_at": entry.createdAt,
            "item_duration": entry.durationSeconds,
            "item_view_count": entry.viewCount,
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
                throw NativeDownloadError.unsupported("Invalid nested Twitch clip mux plan.")
            }
            used.insert(index)
            indexes.append(index)
        }
        return indexes
    }

    private static func clipURL(slug: String, request: TwitchClipCollectionRequest) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = request.sourceURL.host?.hasSuffix(".test") == true
            ? "clips.twitch.test"
            : "clips.twitch.tv"
        components.path = "/\(slug)"
        return components.url!
    }

    private static func graphQLHeaders() -> [String: String] {
        [
            "Client-ID": clientID,
            "Content-Type": "application/json",
            "Accept": "application/json"
        ]
    }

    private static func isSupportedHost(_ host: String) -> Bool {
        host == "twitch.tv" || host == "www.twitch.tv" || host == "m.twitch.tv" ||
            host == "twitch.test" || host == "www.twitch.test" || host == "m.twitch.test"
    }

    private static func isValidLogin(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z0-9_]{3,25}$"#, options: .regularExpression) != nil
    }

    private static func isValidSlug(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil
    }

    private static func queryValue(named name: String, in items: [URLQueryItem]) -> String? {
        items.first(where: { $0.name.lowercased() == name.lowercased() })?.value?.trimmed
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return nil
    }

    private static func boolValue(_ value: Any?) -> Bool {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        if let value = value as? String { return ["1", "true", "yes"].contains(value.lowercased()) }
        return false
    }

    private static func cleanText(_ raw: String, fallback: String) -> String {
        let value = raw
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmed
        return value.isEmpty ? fallback : value
    }

    private static func prefixedFilename(_ filename: String, prefix: String) -> String {
        "\(prefix)-\(filename)".sanitizedFilename(maxLength: 180)
    }
}
