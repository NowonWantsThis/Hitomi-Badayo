import Foundation

struct XVideoCollectionRequest: Equatable {
    var header: String
    var username: String
    var sourceURL: URL
}

struct XVideoCollectionEntry: Equatable {
    var id: String
    var pageURL: URL
    var profileName: String
}

struct XVideoCollectionPage: Equatable {
    var entries: [XVideoCollectionEntry]
    var totalCount: Int?
}

final class XVideoCollectionResolver {
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

        let itemRange = rangeExpression.trimmed
        let itemLimit = try Self.collectionItemLimit(for: itemRange)
        var entries: [XVideoCollectionEntry] = []
        var seen = Set<String>()
        var profileName = request.username
        var pageCount = 0
        var declaredCount: Int?
        for pageIndex in 0..<Self.maximumPageCount {
            try Task.checkCancellation()
            let pageURL = Self.pageURL(for: request, page: pageIndex)
            let data = try await HTTPClient.shared.postForm(
                to: pageURL,
                fields: [:],
                referer: request.sourceURL.absoluteString,
                userAgent: headers.userAgent,
                additionalHeaders: ["X-Requested-With": "XMLHttpRequest"]
            )
            let page = try Self.collectionPage(from: data, request: request)
            pageCount += 1
            if declaredCount == nil { declaredCount = page.totalCount }
            guard !page.entries.isEmpty else { break }
            for entry in page.entries where seen.insert(entry.id).inserted {
                entries.append(entry)
                if !entry.profileName.isEmpty {
                    profileName = entry.profileName
                }
            }
            if entries.count >= itemLimit { break }
            if let total = page.totalCount, seen.count >= total { break }
            if pageIndex + 1 < Self.maximumPageCount {
                try await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
        guard !entries.isEmpty else {
            throw NativeDownloadError.noFiles
        }

        let selectedIndexes = try Self.collectionItemIndexes(
            for: itemRange,
            total: entries.count
        )
        let selectedEntries = selectedIndexes.map { entries[$0] }

        let resolver = XVideoPageResolver()
        var posts: [(entry: XVideoCollectionEntry, download: ResolvedDownload)] = []
        var failures: [Error] = []
        for entry in selectedEntries {
            try Task.checkCancellation()
            do {
                let resolved = try await resolver.resolve(entry.pageURL, headers: headers)
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
            profileName: profileName,
            posts: posts
        )
        combined.metadata["listed_item_count"] = String(entries.count)
        combined.metadata["discovered_item_count"] = String(entries.count)
        combined.metadata["selected_item_count"] = String(selectedEntries.count)
        combined.metadata["resolved_item_count"] = String(posts.count)
        combined.metadata["resolved_media_count"] = String(combined.assets.count)
        combined.metadata["collection_pages"] = String(pageCount)
        combined.metadata["collection_item_limit"] = itemLimit == Int.max
            ? "unbounded"
            : String(itemLimit)
        if let declaredCount {
            combined.metadata["collection_total"] = String(declaredCount)
        }
        if !itemRange.isEmpty {
            combined.metadata["range"] = itemRange
            combined.metadata["range_scope"] = "collection_items"
            combined.metadata["range_total"] = String(declaredCount ?? entries.count)
            combined.metadata["range_selected"] = String(selectedEntries.count)
            combined.metadata["range_indexes"] = Self.compactRangeDescription(
                fromZeroBasedIndexes: selectedIndexes
            )
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
            throw NativeDownloadError.unsupported("Range did not match any XVideos videos.")
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

    static func request(from url: URL) -> XVideoCollectionRequest? {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host?.lowercased(),
              isXVideosHost(host) else {
            return nil
        }

        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        guard parts.count >= 2 else { return nil }
        let header = parts[0].lowercased()
        let username = parts[1].trimmed
        guard isChannelHeader(header),
              username.range(of: #"^[0-9A-Za-z_-]+$"#, options: .regularExpression) != nil else {
            return nil
        }
        let remainder = Array(parts.dropFirst(2)).map { $0.lowercased() }
        guard remainder.isEmpty ||
                remainder == ["videos"] ||
                remainder == ["videos", "best"] ||
                (remainder.count == 3 && remainder[0] == "videos" && remainder[1] == "best" && isPageNumber(remainder[2])) else {
            return nil
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = host.hasSuffix(".test") ? "www.xvideos.test" : "www.xvideos.com"
        components.path = "/\(header)/\(username)"
        guard let sourceURL = components.url else { return nil }
        return XVideoCollectionRequest(header: header, username: username, sourceURL: sourceURL)
    }

    static func pageURL(for request: XVideoCollectionRequest, page: Int) -> URL {
        var components = URLComponents(url: request.sourceURL, resolvingAgainstBaseURL: false)!
        components.path = "/\(request.header)/\(request.username)/videos/best/\(max(0, page))"
        components.queryItems = nil
        components.fragment = nil
        return components.url!
    }

    static func collectionPage(from data: Data, request: XVideoCollectionRequest) throws -> XVideoCollectionPage {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let root = object as? [String: Any] else {
            throw NativeDownloadError.invalidGalleryData
        }
        let rawVideos = root["videos"] as? [Any] ?? []
        var entries: [XVideoCollectionEntry] = []
        var seen = Set<String>()
        for case let video as [String: Any] in rawVideos {
            guard let id = nonEmptyString(video["id"]),
                  let rawURL = nonEmptyString(video["u"]),
                  seen.insert(id).inserted,
                  let absolute = absoluteURL(rawURL, baseURL: request.sourceURL),
                  let canonical = canonicalVideoURL(absolute, sourceURL: request.sourceURL),
                  XVideoPageResolver.videoID(from: canonical) != nil else {
                continue
            }
            entries.append(XVideoCollectionEntry(
                id: id,
                pageURL: canonical,
                profileName: nonEmptyString(video["pn"]) ?? ""
            ))
        }
        return XVideoCollectionPage(
            entries: entries,
            totalCount: integerValue(root["nb_videos"])
        )
    }

    static func combinedDownload(
        request: XVideoCollectionRequest,
        profileName rawProfileName: String,
        posts: [(entry: XVideoCollectionEntry, download: ResolvedDownload)]
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
                asset.metadata["profile_username"] = request.username
                asset.metadata["collection_header"] = request.header
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
                    metadata: groupMetadata(post: post, postIndex: postIndex, request: request)
                ))
            case .grouped(let nestedFileIndexes, let nestedConcatenations):
                fileAssetIndexes.append(contentsOf: nestedFileIndexes.map { offset + $0 })
                concatenations.append(contentsOf: nestedConcatenations.map { group in
                    ResolvedConcatenationGroup(
                        assetIndexes: group.assetIndexes.map { offset + $0 },
                        outputFilename: prefixedFilename(group.outputFilename, prefix: prefix),
                        metadata: group.metadata.merging(
                            groupMetadata(post: post, postIndex: postIndex, request: request)
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
                    metadata: groupMetadata(post: post, postIndex: postIndex, request: request)
                ))
            case .groupedMedia(let nestedFileIndexes, let nestedConcatenations, let nestedMuxes):
                fileAssetIndexes.append(contentsOf: nestedFileIndexes.map { offset + $0 })
                concatenations.append(contentsOf: nestedConcatenations.map { group in
                    ResolvedConcatenationGroup(
                        assetIndexes: group.assetIndexes.map { offset + $0 },
                        outputFilename: prefixedFilename(group.outputFilename, prefix: prefix),
                        metadata: group.metadata.merging(
                            groupMetadata(post: post, postIndex: postIndex, request: request)
                        ) { current, _ in current }
                    )
                })
                muxes.append(contentsOf: nestedMuxes.map { group in
                    ResolvedMuxGroup(
                        videoAssetIndexes: group.videoAssetIndexes.map { offset + $0 },
                        audioAssetIndexes: group.audioAssetIndexes.map { offset + $0 },
                        outputFilename: prefixedFilename(group.outputFilename, prefix: prefix),
                        metadata: group.metadata.merging(
                            groupMetadata(post: post, postIndex: postIndex, request: request)
                        ) { current, _ in current }
                    )
                })
            }
        }

        let profileName = cleanText(rawProfileName, fallback: request.username)
        let title = "[Channel] \(profileName)"
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
        return ResolvedDownload(
            title: title,
            folderName: title.sanitizedFilename(maxLength: 120),
            assets: assets,
            packageMode: packageMode,
            metadata: DownloadMetadata.clean([
                "site": "XVideos",
                "title": title,
                "series": title,
                "category": "videos",
                "type": "collection",
                "media_type": "video",
                "collection": "true",
                "playlist": "true",
                "collection_header": request.header,
                "profile_username": request.username,
                "artist": profileName,
                "author": profileName,
                "creator": profileName,
                "uploader": profileName,
                "item_count": String(posts.count),
                "media_count": String(assets.count),
                "thumbnail": posts.lazy.compactMap { post -> String? in
                    guard let thumbnail = post.download.metadata["thumbnail"]?.trimmed,
                          !thumbnail.isEmpty else { return nil }
                    return thumbnail
                }.first ?? "",
                "url": request.sourceURL.absoluteString,
                "source_url": request.sourceURL.absoluteString,
                "page_url": request.sourceURL.absoluteString
            ])
        )
    }

    private static func canonicalVideoURL(_ url: URL, sourceURL: URL) -> URL? {
        guard let canonical = XVideoPageResolver.canonicalURL(for: url),
              var components = URLComponents(url: canonical, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.scheme = "https"
        components.host = sourceURL.host
        return components.url
    }

    private static func absoluteURL(_ raw: String, baseURL: URL) -> URL? {
        let value = raw.trimmed
        guard !value.isEmpty else { return nil }
        if value.hasPrefix("//") {
            return URL(string: "\(baseURL.scheme ?? "https"):\(value)")
        }
        if let absolute = URL(string: value), absolute.scheme != nil {
            return absolute
        }
        return URL(string: value, relativeTo: baseURL)?.absoluteURL
    }

    private static func nonEmptyString(_ value: Any?) -> String? {
        let string: String?
        switch value {
        case let value as String:
            string = value
        case let value as NSNumber:
            string = value.stringValue
        default:
            string = nil
        }
        guard let cleaned = string?.trimmed, !cleaned.isEmpty else { return nil }
        return cleaned
    }

    private static func integerValue(_ value: Any?) -> Int? {
        switch value {
        case let value as Int:
            return value
        case let value as NSNumber:
            return value.intValue
        case let value as String:
            return Int(value)
        default:
            return nil
        }
    }

    private static func isXVideosHost(_ host: String) -> Bool {
        if host == "xvideos.test" || host == "www.xvideos.test" {
            return true
        }
        let labels = host.split(separator: ".").map(String.init)
        guard labels.count >= 2 else { return false }
        let base = labels[labels.count - 2]
        let topLevelDomain = labels[labels.count - 1]
        return ["com", "in", "es"].contains(topLevelDomain) &&
            base.range(of: #"^xvideos[0-9]*$"#, options: .regularExpression) != nil
    }

    private static func isChannelHeader(_ value: String) -> Bool {
        value == "profiles" ||
            value.range(of: #"^[0-9A-Za-z_-]*channels$"#, options: .regularExpression) != nil
    }

    private static func isPageNumber(_ value: String) -> Bool {
        guard let page = Int(value) else { return false }
        return page >= 0
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
                throw NativeDownloadError.unsupported("Invalid nested XVideos mux plan.")
            }
            used.insert(index)
            indexes.append(index)
        }
        return indexes
    }

    private static func groupMetadata(
        post: (entry: XVideoCollectionEntry, download: ResolvedDownload),
        postIndex: Int,
        request: XVideoCollectionRequest
    ) -> [String: String] {
        post.download.metadata.merging(DownloadMetadata.clean([
            "collection_index": String(postIndex + 1),
            "collection_item_id": post.entry.id,
            "profile_username": request.username,
            "collection_header": request.header,
            "collection_url": request.sourceURL.absoluteString
        ])) { current, _ in current }
    }
}
