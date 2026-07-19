import Foundation

enum IwaraCollectionKind: String, Equatable {
    case videos
    case images

    var displayName: String {
        rawValue.capitalized
    }

    var singularCategory: String {
        self == .videos ? "video" : "image"
    }
}

struct IwaraCollectionRequest: Equatable {
    var username: String
    var kind: IwaraCollectionKind
    var sourceURL: URL
}

struct IwaraProfileInfo: Equatable {
    var id: String
    var username: String
    var displayName: String
}

struct IwaraCollectionEntry: Equatable {
    var id: String
    var slug: String
}

struct IwaraCollectionPage: Equatable {
    var entries: [IwaraCollectionEntry]
    var count: Int?
    var limit: Int?
}

final class IwaraCollectionResolver {
    private static let maximumPageCount = 100
    static let defaultCollectionItemLimit = 2_000

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

        let profileData = try await HTTPClient.shared.data(
            from: Self.profileAPIURL(for: request),
            referer: request.sourceURL.absoluteString,
            userAgent: headers.userAgent,
            additionalHeaders: Self.apiHeaders
        )
        let profile = try Self.profileInfo(from: profileData, fallbackUsername: request.username)
        let itemRange = rangeExpression.trimmed
        let itemLimit = try Self.collectionItemLimit(for: itemRange)
        let discovery = try await collectionEntries(
            for: request,
            profile: profile,
            userAgent: headers.userAgent,
            maximumEntryCount: request.kind == .videos ? itemLimit : nil
        )
        let entries = discovery.entries
        guard !entries.isEmpty else {
            throw NativeDownloadError.noFiles
        }

        let selectedIndexes: [Int]?
        let selectedEntries: [IwaraCollectionEntry]
        switch request.kind {
        case .videos:
            let indexes = try Self.collectionItemIndexes(for: itemRange, total: entries.count)
            selectedIndexes = indexes
            selectedEntries = indexes.map { entries[$0] }
        case .images:
            selectedIndexes = nil
            selectedEntries = entries
        }

        var resolvedPosts: [(entry: IwaraCollectionEntry, download: ResolvedDownload)] = []
        var skippedErrors: [Error] = []
        var resolvedMediaCount = 0
        for entry in selectedEntries {
            try Task.checkCancellation()
            let pageURL = Self.postURL(for: entry, kind: request.kind, sourceURL: request.sourceURL)
            do {
                let resolved: ResolvedDownload
                switch request.kind {
                case .videos:
                    resolved = try await IwaraVideoResolver().resolve(pageURL, headers: headers)
                case .images:
                    resolved = try await IwaraImageResolver().resolve(pageURL, headers: headers)
                }
                resolvedPosts.append((entry, resolved))
                resolvedMediaCount += resolved.assets.count
                if request.kind == .images, resolvedMediaCount >= itemLimit {
                    break
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                skippedErrors.append(error)
            }
        }

        guard !resolvedPosts.isEmpty else {
            throw skippedErrors.first ?? NativeDownloadError.noFiles
        }

        var combined = try Self.combinedDownload(
            request: request,
            profile: profile,
            posts: resolvedPosts
        )
        if request.kind == .images {
            combined = Self.limitingImageFiles(combined, to: itemLimit)
        }
        combined.metadata["listed_item_count"] = String(entries.count)
        combined.metadata["discovered_item_count"] = String(entries.count)
        combined.metadata["resolved_item_count"] = String(resolvedPosts.count)
        combined.metadata["resolved_media_count"] = String(combined.assets.count)
        combined.metadata["collection_pages"] = String(discovery.pageCount)
        if let declaredCount = discovery.declaredCount {
            combined.metadata["collection_total"] = String(declaredCount)
        }
        if request.kind == .videos {
            combined.metadata["selected_item_count"] = String(selectedEntries.count)
            combined.metadata["collection_item_limit"] = itemLimit == Int.max ? "unbounded" : String(itemLimit)
            if !itemRange.isEmpty, let selectedIndexes {
                combined.metadata["range"] = itemRange
                combined.metadata["range_scope"] = "collection_items"
                combined.metadata["range_total"] = String(discovery.declaredCount ?? entries.count)
                combined.metadata["range_selected"] = String(selectedEntries.count)
                combined.metadata["range_indexes"] = Self.compactRangeDescription(fromZeroBasedIndexes: selectedIndexes)
            }
        } else {
            combined.metadata["collection_media_limit"] = itemLimit == Int.max ? "unbounded" : String(itemLimit)
        }
        if !skippedErrors.isEmpty {
            combined.metadata["skipped_count"] = String(skippedErrors.count)
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
            throw NativeDownloadError.unsupported("Range did not match any Iwara videos.")
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

    static func request(from url: URL) -> IwaraCollectionRequest? {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host?.lowercased(),
              isSupportedHost(host) else {
            return nil
        }

        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        guard parts.count >= 2,
              ["profile", "users"].contains(parts[0].lowercased()) else {
            return nil
        }
        let username = parts[1].trimmed
        guard !username.isEmpty,
              username.range(of: #"^[0-9A-Za-z._-]+$"#, options: .regularExpression) != nil else {
            return nil
        }

        let kind: IwaraCollectionKind
        if parts.count == 2 {
            kind = .videos
        } else if parts.count == 3,
                  let parsed = IwaraCollectionKind(rawValue: parts[2].lowercased()) {
            kind = parsed
        } else {
            return nil
        }

        var components = URLComponents()
        components.scheme = scheme
        components.host = host.hasSuffix(".test") ? "iwara.test" : "iwara.tv"
        components.path = "/profile/\(username)/\(kind.rawValue)"
        guard let sourceURL = components.url else { return nil }
        return IwaraCollectionRequest(username: username, kind: kind, sourceURL: sourceURL)
    }

    static func profileAPIURL(for request: IwaraCollectionRequest) -> URL {
        var components = apiComponents(for: request.sourceURL)
        components.path = "/profile/\(request.username)"
        return components.url!
    }

    static func collectionAPIURL(
        for request: IwaraCollectionRequest,
        profileID: String,
        page: Int
    ) -> URL {
        var components = apiComponents(for: request.sourceURL)
        components.path = "/\(request.kind.rawValue)"
        switch request.kind {
        case .videos:
            components.queryItems = [
                URLQueryItem(name: "sort", value: "date"),
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "user", value: profileID)
            ]
        case .images:
            components.queryItems = [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "sort", value: "date"),
                URLQueryItem(name: "user", value: profileID)
            ]
        }
        return components.url!
    }

    static func postURL(
        for entry: IwaraCollectionEntry,
        kind: IwaraCollectionKind,
        sourceURL: URL
    ) -> URL {
        switch kind {
        case .videos:
            return IwaraVideoResolver.canonicalURL(for: entry.id, sourceURL: sourceURL)
        case .images:
            return IwaraImageResolver.canonicalURL(for: entry.id, sourceURL: sourceURL)
        }
    }

    static func profileInfo(from data: Data, fallbackUsername: String) throws -> IwaraProfileInfo {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let root = object as? [String: Any] else {
            throw NativeDownloadError.invalidGalleryData
        }
        let user = root["user"] as? [String: Any] ?? root
        guard let id = stringValue(user["id"]), !id.isEmpty else {
            throw NativeDownloadError.unsupported("Iwara profile metadata did not include a user id.")
        }
        let username = nonEmptyString(user["username"]) ?? fallbackUsername
        let displayName = nonEmptyString(user["name"]) ?? username
        return IwaraProfileInfo(id: id, username: username, displayName: displayName)
    }

    static func collectionPage(from data: Data) throws -> IwaraCollectionPage {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let root = object as? [String: Any] else {
            throw NativeDownloadError.invalidGalleryData
        }
        let rawResults = root["results"] as? [Any] ?? []
        var entries: [IwaraCollectionEntry] = []
        var seen = Set<String>()
        for case let item as [String: Any] in rawResults {
            guard let id = nonEmptyString(item["id"]),
                  seen.insert(id).inserted else {
                continue
            }
            entries.append(IwaraCollectionEntry(
                id: id,
                slug: stringValue(item["slug"])?.trimmed ?? ""
            ))
        }
        return IwaraCollectionPage(
            entries: entries,
            count: integerValue(root["count"]),
            limit: integerValue(root["limit"])
        )
    }

    static func combinedDownload(
        request: IwaraCollectionRequest,
        profile: IwaraProfileInfo,
        posts: [(entry: IwaraCollectionEntry, download: ResolvedDownload)]
    ) throws -> ResolvedDownload {
        guard !posts.isEmpty else { throw NativeDownloadError.noFiles }

        var assets: [ResolvedAsset] = []
        var fileAssetIndexes: [Int] = []
        var concatenations: [ResolvedConcatenationGroup] = []
        var muxes: [ResolvedMuxGroup] = []
        for (postIndex, post) in posts.enumerated() {
            let offset = assets.count
            let prefix = String(format: "%04d-%@", postIndex + 1, post.entry.id)
            let originalAssets = post.download.assets
            let decorated = originalAssets.map { input -> ResolvedAsset in
                var asset = input
                asset.filename = prefixedFilename(input.filename, prefix: prefix)
                asset.metadata["collection_index"] = String(postIndex + 1)
                asset.metadata["collection_item_id"] = post.entry.id
                asset.metadata["profile_username"] = profile.username
                asset.metadata["collection_url"] = request.sourceURL.absoluteString
                return asset
            }
            assets.append(contentsOf: decorated)

            switch post.download.packageMode {
            case .files:
                fileAssetIndexes.append(contentsOf: decorated.indices.map { offset + $0 })
            case .concatenate(let outputFilename):
                concatenations.append(ResolvedConcatenationGroup(
                    assetIndexes: decorated.indices.map { offset + $0 },
                    outputFilename: prefixedFilename(outputFilename, prefix: prefix),
                    metadata: collectionGroupMetadata(
                        post: post,
                        postIndex: postIndex,
                        request: request,
                        profile: profile
                    )
                ))
            case .grouped(let nestedFileIndexes, let nestedConcatenations):
                fileAssetIndexes.append(contentsOf: nestedFileIndexes.map { offset + $0 })
                concatenations.append(contentsOf: nestedConcatenations.map { group in
                    ResolvedConcatenationGroup(
                        assetIndexes: group.assetIndexes.map { offset + $0 },
                        outputFilename: prefixedFilename(group.outputFilename, prefix: prefix),
                        metadata: group.metadata.merging(
                            collectionGroupMetadata(
                                post: post,
                                postIndex: postIndex,
                                request: request,
                                profile: profile
                            )
                        ) { current, _ in current }
                    )
                })
            case .mux(let videoAssets, let audioAssets, let outputFilename):
                let videoIndexes = try matchingIndexes(of: videoAssets, in: originalAssets)
                let audioIndexes = try matchingIndexes(of: audioAssets, in: originalAssets)
                muxes.append(ResolvedMuxGroup(
                    videoAssetIndexes: videoIndexes.map { offset + $0 },
                    audioAssetIndexes: audioIndexes.map { offset + $0 },
                    outputFilename: prefixedFilename(outputFilename, prefix: prefix),
                    metadata: collectionGroupMetadata(
                        post: post,
                        postIndex: postIndex,
                        request: request,
                        profile: profile
                    )
                ))
            case .groupedMedia(let nestedFileIndexes, let nestedConcatenations, let nestedMuxes):
                fileAssetIndexes.append(contentsOf: nestedFileIndexes.map { offset + $0 })
                concatenations.append(contentsOf: nestedConcatenations.map { group in
                    ResolvedConcatenationGroup(
                        assetIndexes: group.assetIndexes.map { offset + $0 },
                        outputFilename: prefixedFilename(group.outputFilename, prefix: prefix),
                        metadata: group.metadata.merging(
                            collectionGroupMetadata(
                                post: post,
                                postIndex: postIndex,
                                request: request,
                                profile: profile
                            )
                        ) { current, _ in current }
                    )
                })
                muxes.append(contentsOf: nestedMuxes.map { group in
                    ResolvedMuxGroup(
                        videoAssetIndexes: group.videoAssetIndexes.map { offset + $0 },
                        audioAssetIndexes: group.audioAssetIndexes.map { offset + $0 },
                        outputFilename: prefixedFilename(group.outputFilename, prefix: prefix),
                        metadata: group.metadata.merging(
                            collectionGroupMetadata(
                                post: post,
                                postIndex: postIndex,
                                request: request,
                                profile: profile
                            )
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
        let title = "[Channel] [\(request.kind.displayName)] \(profile.displayName) (\(profile.username))"
        return ResolvedDownload(
            title: title,
            folderName: title.sanitizedFilename(maxLength: 120),
            assets: assets,
            packageMode: packageMode,
            metadata: DownloadMetadata.clean([
                "site": "Iwara",
                "title": title,
                "series": title,
                "category": request.kind.rawValue,
                "type": "collection",
                "media_type": request.kind.singularCategory,
                "collection": "true",
                "playlist": "true",
                "profile_id": profile.id,
                "profile_username": profile.username,
                "artist": profile.displayName,
                "author": profile.displayName,
                "creator": profile.displayName,
                "uploader": profile.displayName,
                "item_count": String(posts.count),
                "media_count": String(assets.count),
                "thumbnail": posts.lazy.compactMap { value -> String? in
                    guard let thumbnail = value.download.metadata["thumbnail"]?.trimmed,
                          !thumbnail.isEmpty else { return nil }
                    return thumbnail
                }.first ?? "",
                "url": request.sourceURL.absoluteString,
                "source_url": request.sourceURL.absoluteString,
                "page_url": request.sourceURL.absoluteString
            ])
        )
    }

    private func collectionEntries(
        for request: IwaraCollectionRequest,
        profile: IwaraProfileInfo,
        userAgent: String?,
        maximumEntryCount: Int?
    ) async throws -> (entries: [IwaraCollectionEntry], pageCount: Int, declaredCount: Int?) {
        var entries: [IwaraCollectionEntry] = []
        var seen = Set<String>()
        var pageCount = 0
        var declaredCount: Int?
        for pageIndex in 0..<Self.maximumPageCount {
            try Task.checkCancellation()
            let data = try await HTTPClient.shared.data(
                from: Self.collectionAPIURL(
                    for: request,
                    profileID: profile.id,
                    page: pageIndex
                ),
                referer: request.sourceURL.absoluteString,
                userAgent: userAgent,
                additionalHeaders: Self.apiHeaders
            )
            let page = try Self.collectionPage(from: data)
            pageCount += 1
            if declaredCount == nil { declaredCount = page.count }
            for entry in page.entries where seen.insert(entry.id).inserted {
                entries.append(entry)
            }

            guard !page.entries.isEmpty else { break }
            if let maximumEntryCount, entries.count >= maximumEntryCount { break }
            if let count = page.count, entries.count >= count { break }
            if let count = page.count,
               let limit = page.limit,
               limit > 0,
               (pageIndex + 1) * limit >= count {
                break
            }
        }
        return (entries, pageCount, declaredCount)
    }

    private static func limitingImageFiles(_ download: ResolvedDownload, to limit: Int) -> ResolvedDownload {
        guard limit != Int.max, download.assets.count > limit else { return download }
        guard case .files = download.packageMode else { return download }
        var metadata = download.metadata
        metadata["media_count"] = String(limit)
        return ResolvedDownload(
            title: download.title,
            folderName: download.folderName,
            assets: Array(download.assets.prefix(limit)),
            packageMode: .files,
            metadata: metadata
        )
    }

    private static let apiHeaders = [
        "Accept": "application/json, text/plain, */*",
        "Origin": "https://iwara.tv"
    ]

    private static func apiComponents(for sourceURL: URL) -> URLComponents {
        var components = URLComponents()
        components.scheme = sourceURL.scheme ?? "https"
        components.host = sourceURL.host?.lowercased().hasSuffix(".test") == true
            ? "api.iwara.test"
            : "api.iwara.tv"
        return components
    }

    private static func isSupportedHost(_ host: String) -> Bool {
        host == "iwara.tv" ||
            host == "www.iwara.tv" ||
            host == "ecchi.iwara.tv" ||
            host == "iwara.test" ||
            host == "www.iwara.test"
    }

    private static func stringValue(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            return number.stringValue
        default:
            return nil
        }
    }

    private static func integerValue(_ value: Any?) -> Int? {
        switch value {
        case let integer as Int:
            return integer
        case let number as NSNumber:
            return number.intValue
        case let string as String:
            return Int(string)
        default:
            return nil
        }
    }

    private static func nonEmptyString(_ value: Any?) -> String? {
        guard let string = stringValue(value)?.trimmed, !string.isEmpty else { return nil }
        return string
    }

    private static func prefixedFilename(_ filename: String, prefix: String) -> String {
        "\(prefix)-\(filename)".sanitizedFilename(maxLength: 180)
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
                throw NativeDownloadError.unsupported("Invalid nested Iwara mux plan.")
            }
            used.insert(index)
            indexes.append(index)
        }
        return indexes
    }

    private static func collectionGroupMetadata(
        post: (entry: IwaraCollectionEntry, download: ResolvedDownload),
        postIndex: Int,
        request: IwaraCollectionRequest,
        profile: IwaraProfileInfo
    ) -> [String: String] {
        post.download.metadata.merging(DownloadMetadata.clean([
            "collection_index": String(postIndex + 1),
            "collection_item_id": post.entry.id,
            "profile_username": profile.username,
            "collection_url": request.sourceURL.absoluteString
        ])) { current, _ in current }
    }
}
