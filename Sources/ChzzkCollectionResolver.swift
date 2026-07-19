import Foundation

struct ChzzkCollectionRequest: Equatable {
    var channelID: String
    var videoType: String
    var sortType: String
    var sourceURL: URL
}

struct ChzzkCollectionProfile: Equatable {
    var channelName: String
    var thumbnailURL: URL?
}

struct ChzzkCollectionEntry: Equatable {
    var videoNo: String
    var title: String
    var thumbnailURL: URL?
    var publishDate: String
    var duration: String
    var readCount: String
    var vodStatus: String
    var pageURL: URL
}

struct ChzzkCollectionPage: Equatable {
    var entries: [ChzzkCollectionEntry]
    var totalPages: Int
    var totalElements: Int?
}

final class ChzzkCollectionResolver {
    private static let pageSize = 16
    static let defaultCollectionItemLimit = 2_000
    private static let apiHeaders = ["Accept": "application/json, text/plain, */*"]

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

        let profileData = try await HTTPClient.shared.data(
            from: ChzzkResolver.channelAPIURL(for: request.channelID, sourceURL: request.sourceURL),
            referer: request.sourceURL.absoluteString,
            userAgent: headers.userAgent,
            additionalHeaders: Self.apiHeaders
        )
        let profile = try Self.profile(from: profileData, request: request)

        var entries: [ChzzkCollectionEntry] = []
        var seen = Set<String>()
        var expectedTotal: Int?
        var pageNumber = 0
        var collectionPageCount = 0
        while true {
            try Task.checkCancellation()
            let data = try await HTTPClient.shared.data(
                from: Self.pageAPIURL(request: request, page: pageNumber),
                referer: Self.pageRefererURL(request: request, page: pageNumber).absoluteString,
                userAgent: headers.userAgent,
                additionalHeaders: Self.apiHeaders
            )
            collectionPageCount += 1
            let page = try Self.collectionPage(from: data, request: request)
            if expectedTotal == nil { expectedTotal = page.totalElements }
            for entry in page.entries where seen.insert(entry.videoNo).inserted {
                entries.append(entry)
            }

            let reachedLastPage = page.totalPages <= pageNumber + 1
            let reachedTotal = expectedTotal.map { seen.count >= $0 } ?? false
            if reachedLastPage || reachedTotal || page.entries.isEmpty { break }
            pageNumber += 1
            if request.sourceURL.host?.hasSuffix(".test") != true {
                try await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
        guard !entries.isEmpty else { throw NativeDownloadError.noFiles }
        let listedItemCount = entries.count
        let itemRange = rangeExpression.trimmed
        let selectedIndexes = try Self.collectionItemIndexes(for: itemRange, total: listedItemCount)
        let selectedEntries = selectedIndexes.map { entries[$0] }

        let pageResolver = ChzzkResolver()
        var posts: [(entry: ChzzkCollectionEntry, download: ResolvedDownload)] = []
        var failures: [Error] = []
        for entry in selectedEntries {
            try Task.checkCancellation()
            do {
                let download = try await pageResolver.resolve(
                    entry.pageURL,
                    headers: headers,
                    preferredResolution: preferredResolution
                )
                posts.append((entry, download))
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
            profile: profile,
            posts: posts
        )
        combined.metadata["listed_item_count"] = String(listedItemCount)
        combined.metadata["discovered_item_count"] = String(listedItemCount)
        combined.metadata["selected_item_count"] = String(selectedEntries.count)
        combined.metadata["resolved_item_count"] = String(posts.count)
        combined.metadata["collection_pages"] = String(collectionPageCount)
        combined.metadata["collection_item_limit"] = String(Self.defaultCollectionItemLimit)
        if !itemRange.isEmpty {
            combined.metadata["range"] = itemRange
            combined.metadata["range_scope"] = "collection_items"
            combined.metadata["range_total"] = String(listedItemCount)
            combined.metadata["range_selected"] = String(selectedEntries.count)
            combined.metadata["range_indexes"] = Self.compactRangeDescription(fromZeroBasedIndexes: selectedIndexes)
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
            throw NativeDownloadError.unsupported("Range did not match any Chzzk videos.")
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

    static func request(from url: URL) -> ChzzkCollectionRequest? {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host?.lowercased(),
              isChzzkHost(host) else {
            return nil
        }
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        guard parts.count == 2,
              isChannelID(parts[0]),
              parts[1].lowercased() == "videos" else {
            return nil
        }

        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let rawVideoType = queryValue(named: "videoType", in: queryItems) ?? ""
        let rawSortType = queryValue(named: "sortType", in: queryItems) ?? "LATEST"
        guard isSafeQueryValue(rawVideoType), isSafeQueryValue(rawSortType), !rawSortType.isEmpty else {
            return nil
        }
        let videoType = rawVideoType.uppercased()
        let sortType = rawSortType.uppercased()

        var components = URLComponents()
        components.scheme = "https"
        components.host = host.hasSuffix(".test") ? "chzzk.naver.test" : "chzzk.naver.com"
        components.path = "/\(parts[0])/videos"
        components.queryItems = [
            URLQueryItem(name: "videoType", value: videoType),
            URLQueryItem(name: "sortType", value: sortType)
        ]
        guard let sourceURL = components.url else { return nil }
        return ChzzkCollectionRequest(
            channelID: parts[0],
            videoType: videoType,
            sortType: sortType,
            sourceURL: sourceURL
        )
    }

    static func pageAPIURL(request: ChzzkCollectionRequest, page: Int) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = request.sourceURL.host?.hasSuffix(".test") == true
            ? "api.chzzk.naver.test"
            : "api.chzzk.naver.com"
        components.path = "/service/v1/channels/\(request.channelID)/videos"
        components.queryItems = [
            URLQueryItem(name: "sortType", value: request.sortType),
            URLQueryItem(name: "pagingType", value: "PAGE"),
            URLQueryItem(name: "page", value: String(max(0, page))),
            URLQueryItem(name: "size", value: String(Self.pageSize)),
            URLQueryItem(name: "publishDateAt", value: ""),
            URLQueryItem(name: "videoType", value: request.videoType)
        ]
        return components.url!
    }

    static func pageRefererURL(request: ChzzkCollectionRequest, page: Int) -> URL {
        var components = URLComponents(url: request.sourceURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "videoType", value: request.videoType),
            URLQueryItem(name: "sortType", value: request.sortType),
            URLQueryItem(name: "page", value: String(max(0, page)))
        ]
        return components.url!
    }

    static func profile(
        from data: Data,
        request: ChzzkCollectionRequest
    ) throws -> ChzzkCollectionProfile {
        let object = try jsonDictionary(from: data)
        try validateAPIResponse(object)
        guard let content = object["content"] as? [String: Any] else {
            throw NativeDownloadError.invalidGalleryData
        }
        let name = cleanText(stringValue(content["channelName"]) ?? request.channelID)
        let rawThumbnail = stringValue(content["channelImageUrl"]) ??
            stringValue(content["channelImageURL"]) ??
            stringValue(content["thumbnailImageUrl"])
        return ChzzkCollectionProfile(
            channelName: name.isEmpty ? request.channelID : name,
            thumbnailURL: rawThumbnail.flatMap { absoluteURL($0, baseURL: request.sourceURL) }
        )
    }

    static func collectionPage(
        from data: Data,
        request: ChzzkCollectionRequest
    ) throws -> ChzzkCollectionPage {
        let object = try jsonDictionary(from: data)
        try validateAPIResponse(object)
        guard let content = object["content"] as? [String: Any] else {
            throw NativeDownloadError.invalidGalleryData
        }
        let totalPages = max(0, integerValue(content["totalPages"]) ?? 0)
        let totalElements = integerValue(content["totalElements"])
        let rawEntries = content["data"] as? [[String: Any]] ?? []
        var seen = Set<String>()
        let entries = rawEntries.compactMap { item -> ChzzkCollectionEntry? in
            guard let videoNo = stringValue(item["videoNo"])?.trimmed,
                  !videoNo.isEmpty,
                  seen.insert(videoNo).inserted else {
                return nil
            }
            let title = cleanText(stringValue(item["videoTitle"]) ?? stringValue(item["title"]) ?? videoNo)
            let thumbnail = stringValue(item["thumbnailImageUrl"]) ??
                stringValue(item["thumbnailImageURL"]) ??
                stringValue(item["thumbnailUrl"])
            return ChzzkCollectionEntry(
                videoNo: videoNo,
                title: title,
                thumbnailURL: thumbnail.flatMap { absoluteURL($0, baseURL: request.sourceURL) },
                publishDate: stringValue(item["publishDate"]) ?? stringValue(item["openDate"]) ?? "",
                duration: stringValue(item["duration"]) ?? "",
                readCount: stringValue(item["readCount"]) ?? "",
                vodStatus: stringValue(item["vodStatus"]) ?? "",
                pageURL: videoPageURL(videoNo: videoNo, request: request)
            )
        }
        return ChzzkCollectionPage(
            entries: entries,
            totalPages: totalPages,
            totalElements: totalElements
        )
    }

    static func combinedDownload(
        request: ChzzkCollectionRequest,
        profile: ChzzkCollectionProfile,
        posts: [(entry: ChzzkCollectionEntry, download: ResolvedDownload)]
    ) throws -> ResolvedDownload {
        guard !posts.isEmpty else { throw NativeDownloadError.noFiles }
        var assets: [ResolvedAsset] = []
        var fileAssetIndexes: [Int] = []
        var concatenations: [ResolvedConcatenationGroup] = []
        var muxes: [ResolvedMuxGroup] = []

        for (postIndex, post) in posts.enumerated() {
            let offset = assets.count
            let prefix = String(format: "%04d-%@", postIndex + 1, post.entry.videoNo)
            let originalAssets = post.download.assets
            let decorated = originalAssets.map { input -> ResolvedAsset in
                var asset = input
                asset.filename = prefixedFilename(input.filename, prefix: prefix)
                asset.metadata = input.metadata.merging(
                    collectionMetadata(request: request, entry: post.entry, index: postIndex)
                ) { current, _ in current }
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
                    metadata: groupMetadata(request: request, post: post, index: postIndex)
                ))
            case .mux(let videoAssets, let audioAssets, let outputFilename):
                let videoIndexes = try matchingIndexes(of: videoAssets, in: originalAssets)
                let audioIndexes = try matchingIndexes(of: audioAssets, in: originalAssets)
                muxes.append(ResolvedMuxGroup(
                    videoAssetIndexes: videoIndexes.map { offset + $0 },
                    audioAssetIndexes: audioIndexes.map { offset + $0 },
                    outputFilename: prefixedFilename(outputFilename, prefix: prefix),
                    metadata: groupMetadata(request: request, post: post, index: postIndex)
                ))
            case .grouped(let nestedFiles, let nestedConcatenations):
                fileAssetIndexes.append(contentsOf: nestedFiles.map { offset + $0 })
                concatenations.append(contentsOf: nestedConcatenations.map { group in
                    ResolvedConcatenationGroup(
                        assetIndexes: group.assetIndexes.map { offset + $0 },
                        outputFilename: prefixedFilename(group.outputFilename, prefix: prefix),
                        metadata: group.metadata.merging(
                            groupMetadata(request: request, post: post, index: postIndex)
                        ) { current, _ in current }
                    )
                })
            case .groupedMedia(let nestedFiles, let nestedConcatenations, let nestedMuxes):
                fileAssetIndexes.append(contentsOf: nestedFiles.map { offset + $0 })
                concatenations.append(contentsOf: nestedConcatenations.map { group in
                    ResolvedConcatenationGroup(
                        assetIndexes: group.assetIndexes.map { offset + $0 },
                        outputFilename: prefixedFilename(group.outputFilename, prefix: prefix),
                        metadata: group.metadata.merging(
                            groupMetadata(request: request, post: post, index: postIndex)
                        ) { current, _ in current }
                    )
                })
                muxes.append(contentsOf: nestedMuxes.map { group in
                    ResolvedMuxGroup(
                        videoAssetIndexes: group.videoAssetIndexes.map { offset + $0 },
                        audioAssetIndexes: group.audioAssetIndexes.map { offset + $0 },
                        outputFilename: prefixedFilename(group.outputFilename, prefix: prefix),
                        metadata: group.metadata.merging(
                            groupMetadata(request: request, post: post, index: postIndex)
                        ) { current, _ in current }
                    )
                })
            }
        }

        let title = "[Videos] \(profile.channelName)"
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
        let thumbnail = profile.thumbnailURL?.absoluteString ??
            posts.lazy.compactMap { $0.entry.thumbnailURL?.absoluteString }.first ??
            posts.lazy.compactMap { $0.download.metadata["thumbnail"] }.first ?? ""
        return ResolvedDownload(
            title: title,
            folderName: title.sanitizedFilename(maxLength: 120),
            assets: assets,
            packageMode: packageMode,
            metadata: DownloadMetadata.clean([
                "site": "Chzzk",
                "title": title,
                "series": title,
                "type": "collection",
                "media_type": "video",
                "category": "videos",
                "collection": "true",
                "playlist": "true",
                "collection_kind": "channel_videos",
                "channel_id": request.channelID,
                "playlist_id": request.channelID,
                "video_type": request.videoType,
                "sort_type": request.sortType,
                "artist": profile.channelName,
                "author": profile.channelName,
                "creator": profile.channelName,
                "uploader": profile.channelName,
                "channel": profile.channelName,
                "item_count": String(posts.count),
                "media_count": String(assets.count),
                "mux_count": String(muxes.count),
                "thumbnail": thumbnail,
                "url": request.sourceURL.absoluteString,
                "source_url": request.sourceURL.absoluteString,
                "page_url": request.sourceURL.absoluteString
            ])
        )
    }

    private static func groupMetadata(
        request: ChzzkCollectionRequest,
        post: (entry: ChzzkCollectionEntry, download: ResolvedDownload),
        index: Int
    ) -> [String: String] {
        post.download.metadata.merging(
            collectionMetadata(request: request, entry: post.entry, index: index)
        ) { current, _ in current }
    }

    private static func collectionMetadata(
        request: ChzzkCollectionRequest,
        entry: ChzzkCollectionEntry,
        index: Int
    ) -> [String: String] {
        DownloadMetadata.clean([
            "collection_index": String(index + 1),
            "collection_item_id": entry.videoNo,
            "collection_url": request.sourceURL.absoluteString,
            "collection_kind": "channel_videos",
            "channel_id": request.channelID,
            "video_type": request.videoType,
            "sort_type": request.sortType,
            "video_no": entry.videoNo,
            "vod_id": entry.videoNo,
            "item_title": entry.title,
            "item_thumbnail": entry.thumbnailURL?.absoluteString ?? "",
            "item_publish_date": entry.publishDate,
            "item_duration": entry.duration,
            "item_read_count": entry.readCount,
            "item_vod_status": entry.vodStatus,
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
                throw NativeDownloadError.unsupported("Invalid nested Chzzk mux plan.")
            }
            used.insert(index)
            indexes.append(index)
        }
        return indexes
    }

    private static func validateAPIResponse(_ object: [String: Any]) throws {
        if let code = integerValue(object["code"]), code != 0 && code != 200 {
            let message = stringValue(object["message"]) ?? stringValue(object["errorMessage"]) ?? "code \(code)"
            throw NativeDownloadError.unsupported("Chzzk API rejected the videos request: \(message)")
        }
    }

    private static func jsonDictionary(from data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NativeDownloadError.invalidGalleryData
        }
        return object
    }

    private static func videoPageURL(videoNo: String, request: ChzzkCollectionRequest) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = request.sourceURL.host?.hasSuffix(".test") == true
            ? "chzzk.naver.test"
            : "chzzk.naver.com"
        components.path = "/video/\(videoNo)"
        return components.url!
    }

    private static func queryValue(named name: String, in items: [URLQueryItem]) -> String? {
        items.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame })?.value?.trimmed
    }

    private static func isSafeQueryValue(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z0-9_-]*$"#, options: .regularExpression) != nil
    }

    private static func isChannelID(_ value: String) -> Bool {
        value.range(of: #"^[0-9A-Fa-f]+$"#, options: .regularExpression) != nil
    }

    private static func isChzzkHost(_ host: String) -> Bool {
        host == "chzzk.naver.com" ||
            host == "m.chzzk.naver.com" ||
            host == "chzzk.naver.test" ||
            host == "m.chzzk.naver.test"
    }

    private static func absoluteURL(_ raw: String, baseURL: URL) -> URL? {
        let value = raw.trimmed
        if value.hasPrefix("//") {
            return URL(string: "\(baseURL.scheme ?? "https"):\(value)")
        }
        return URL(string: value, relativeTo: baseURL)?.absoluteURL
    }

    private static func cleanText(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmed
    }

    private static func prefixedFilename(_ filename: String, prefix: String) -> String {
        "\(prefix)-\(filename)".sanitizedFilename(maxLength: 180)
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
