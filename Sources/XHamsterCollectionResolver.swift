import Foundation

enum XHamsterCollectionKind: Equatable {
    case users
    case creators(prefix: String?)

    var category: String {
        switch self {
        case .users:
            return "users"
        case .creators:
            return "creators"
        }
    }
}

struct XHamsterCollectionRequest: Equatable {
    var username: String
    var kind: XHamsterCollectionKind
    var sourceURL: URL
}

struct XHamsterCollectionPage: Equatable {
    var title: String?
    var videoURLs: [URL]
    var cardCount: Int
}

final class XHamsterCollectionResolver {
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
        var collectionTitle: String?
        var videoURLs: [URL] = []
        var seen = Set<String>()
        var pageCount = 0
        for page in 1...Self.maximumPageCount {
            try Task.checkCancellation()
            let pageURL = Self.pageURL(for: request, page: page)
            let html = try await HTTPClient.shared.string(
                from: pageURL,
                referer: page == 1 ? request.sourceURL.absoluteString : Self.pageURL(for: request, page: page - 1).absoluteString,
                userAgent: headers.userAgent
            )
            let parsed = Self.collectionPage(fromHTML: html, pageURL: pageURL)
            pageCount += 1
            if collectionTitle == nil {
                collectionTitle = parsed.title
            }
            guard parsed.cardCount > 0 else { break }
            for videoURL in parsed.videoURLs where seen.insert(videoURL.absoluteString).inserted {
                videoURLs.append(videoURL)
            }
        }
        guard !videoURLs.isEmpty else {
            throw NativeDownloadError.noFiles
        }

        let selectedIndexes = try Self.collectionItemIndexes(
            for: itemRange,
            total: videoURLs.count
        )
        let selectedVideoURLs = selectedIndexes.map { videoURLs[$0] }

        var posts: [(url: URL, download: ResolvedDownload)] = []
        var failures: [Error] = []
        let resolver = EtcVideoPageResolver()
        for videoURL in selectedVideoURLs {
            try Task.checkCancellation()
            do {
                let resolved = try await resolver.resolve(videoURL, headers: headers)
                posts.append((videoURL, resolved))
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
            title: collectionTitle ?? request.username,
            posts: posts
        )
        combined.metadata["listed_item_count"] = String(videoURLs.count)
        combined.metadata["discovered_item_count"] = String(videoURLs.count)
        combined.metadata["selected_item_count"] = String(selectedVideoURLs.count)
        combined.metadata["resolved_item_count"] = String(posts.count)
        combined.metadata["resolved_media_count"] = String(combined.assets.count)
        combined.metadata["collection_pages"] = String(pageCount)
        combined.metadata["collection_item_limit"] = itemLimit == Int.max
            ? "unbounded"
            : String(itemLimit)
        if !itemRange.isEmpty {
            combined.metadata["range"] = itemRange
            combined.metadata["range_scope"] = "collection_items"
            combined.metadata["range_total"] = String(videoURLs.count)
            combined.metadata["range_selected"] = String(selectedVideoURLs.count)
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
            throw NativeDownloadError.unsupported("Range did not match any xHamster videos.")
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

    static func request(from url: URL) -> XHamsterCollectionRequest? {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              EtcVideoPageResolver.site(for: url) == .xhamster else {
            return nil
        }

        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        let lower = parts.map { $0.lowercased() }
        let username: String
        let kind: XHamsterCollectionKind
        let canonicalPath: String

        if let usersIndex = lower.firstIndex(of: "users"), usersIndex == 0,
           usersIndex + 1 < parts.count {
            username = parts[usersIndex + 1].trimmed
            let remainder = Array(lower.dropFirst(usersIndex + 2))
            guard remainder.isEmpty ||
                    remainder == ["videos"] ||
                    (remainder.count == 2 && remainder[0] == "videos" && isPageNumber(remainder[1])) else {
                return nil
            }
            kind = .users
            canonicalPath = "/users/\(username)/videos"
        } else if let creatorsIndex = lower.firstIndex(of: "creators"),
                  creatorsIndex <= 1,
                  creatorsIndex + 1 < parts.count {
            let prefix: String?
            if creatorsIndex == 1 {
                guard lower[0] == "shemale" else { return nil }
                prefix = parts[0]
            } else {
                prefix = nil
            }
            username = parts[creatorsIndex + 1].trimmed
            let remainder = Array(lower.dropFirst(creatorsIndex + 2))
            guard remainder.isEmpty ||
                    remainder == ["exclusive"] ||
                    (remainder.count == 2 && remainder[0] == "exclusive" && isPageNumber(remainder[1])) else {
                return nil
            }
            kind = .creators(prefix: prefix)
            canonicalPath = "/" + [prefix, "creators", username].compactMap { $0 }.joined(separator: "/")
        } else {
            return nil
        }

        guard username.range(of: #"^[A-Za-z0-9][A-Za-z0-9_-]*$"#, options: .regularExpression) != nil else {
            return nil
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = url.host?.lowercased().hasSuffix(".test") == true ? "xhamster.test" : "xhamster.com"
        components.path = canonicalPath
        guard let sourceURL = components.url else { return nil }
        return XHamsterCollectionRequest(username: username, kind: kind, sourceURL: sourceURL)
    }

    static func pageURL(for request: XHamsterCollectionRequest, page: Int) -> URL {
        let normalizedPage = max(1, page)
        var components = URLComponents(url: request.sourceURL, resolvingAgainstBaseURL: false)!
        switch request.kind {
        case .users:
            components.path = "/users/\(request.username)/videos/\(normalizedPage)"
        case .creators(let prefix):
            components.path = "/" + [prefix, "creators", request.username, "exclusive", String(normalizedPage)]
                .compactMap { $0 }
                .joined(separator: "/")
        }
        components.queryItems = nil
        components.fragment = nil
        return components.url!
    }

    static func collectionPage(fromHTML html: String, pageURL: URL) -> XHamsterCollectionPage {
        let title = channelTitle(fromHTML: html)
        let cardRanges = cardStartRanges(in: html)
        guard !cardRanges.isEmpty else {
            return XHamsterCollectionPage(title: title, videoURLs: [], cardCount: 0)
        }

        let source = html as NSString
        var urls: [URL] = []
        var seen = Set<String>()
        for (index, startRange) in cardRanges.enumerated() {
            let end = index + 1 < cardRanges.count ? cardRanges[index + 1].location : source.length
            let scope = source.substring(with: NSRange(location: startRange.location, length: end - startRange.location))
            if scope.range(of: "thumb-image-container__status-text", options: .caseInsensitive) != nil {
                continue
            }
            guard let rawHref = firstCapture(
                pattern: #"<a\b[^>]*\bhref\s*=\s*[\"']([^\"']+)[\"']"#,
                in: scope
            ),
                  let absolute = absoluteURL(decodeHTML(rawHref), baseURL: pageURL),
                  let canonical = canonicalVideoURL(for: absolute, collectionPageURL: pageURL),
                  seen.insert(canonical.absoluteString).inserted else {
                continue
            }
            urls.append(canonical)
        }
        return XHamsterCollectionPage(title: title, videoURLs: urls, cardCount: cardRanges.count)
    }

    static func combinedDownload(
        request: XHamsterCollectionRequest,
        title rawTitle: String,
        posts: [(url: URL, download: ResolvedDownload)]
    ) throws -> ResolvedDownload {
        guard !posts.isEmpty else { throw NativeDownloadError.noFiles }

        var assets: [ResolvedAsset] = []
        var fileAssetIndexes: [Int] = []
        var concatenations: [ResolvedConcatenationGroup] = []
        var muxes: [ResolvedMuxGroup] = []
        for (postIndex, post) in posts.enumerated() {
            let offset = assets.count
            let itemID = EtcVideoPageResolver.contentID(from: post.url) ?? String(postIndex + 1)
            let prefix = String(format: "%04d-%@", postIndex + 1, itemID)
            let originalAssets = post.download.assets
            let decorated = originalAssets.map { input -> ResolvedAsset in
                var asset = input
                asset.filename = prefixedFilename(input.filename, prefix: prefix)
                asset.metadata["collection_index"] = String(postIndex + 1)
                asset.metadata["collection_item_id"] = itemID
                asset.metadata["profile_username"] = request.username
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
                    metadata: groupMetadata(post: post, postIndex: postIndex, request: request, itemID: itemID)
                ))
            case .grouped(let nestedFileIndexes, let nestedConcatenations):
                fileAssetIndexes.append(contentsOf: nestedFileIndexes.map { offset + $0 })
                concatenations.append(contentsOf: nestedConcatenations.map { group in
                    ResolvedConcatenationGroup(
                        assetIndexes: group.assetIndexes.map { offset + $0 },
                        outputFilename: prefixedFilename(group.outputFilename, prefix: prefix),
                        metadata: group.metadata.merging(
                            groupMetadata(post: post, postIndex: postIndex, request: request, itemID: itemID)
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
                    metadata: groupMetadata(post: post, postIndex: postIndex, request: request, itemID: itemID)
                ))
            case .groupedMedia(let nestedFileIndexes, let nestedConcatenations, let nestedMuxes):
                fileAssetIndexes.append(contentsOf: nestedFileIndexes.map { offset + $0 })
                concatenations.append(contentsOf: nestedConcatenations.map { group in
                    ResolvedConcatenationGroup(
                        assetIndexes: group.assetIndexes.map { offset + $0 },
                        outputFilename: prefixedFilename(group.outputFilename, prefix: prefix),
                        metadata: group.metadata.merging(
                            groupMetadata(post: post, postIndex: postIndex, request: request, itemID: itemID)
                        ) { current, _ in current }
                    )
                })
                muxes.append(contentsOf: nestedMuxes.map { group in
                    ResolvedMuxGroup(
                        videoAssetIndexes: group.videoAssetIndexes.map { offset + $0 },
                        audioAssetIndexes: group.audioAssetIndexes.map { offset + $0 },
                        outputFilename: prefixedFilename(group.outputFilename, prefix: prefix),
                        metadata: group.metadata.merging(
                            groupMetadata(post: post, postIndex: postIndex, request: request, itemID: itemID)
                        ) { current, _ in current }
                    )
                })
            }
        }

        let title = "[Channel] \(cleanText(rawTitle, fallback: request.username))"
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
                "site": "xHamster",
                "title": title,
                "series": title,
                "category": "videos",
                "type": "collection",
                "media_type": "video",
                "collection": "true",
                "playlist": "true",
                "collection_kind": request.kind.category,
                "profile_username": request.username,
                "artist": cleanText(rawTitle, fallback: request.username),
                "author": cleanText(rawTitle, fallback: request.username),
                "creator": cleanText(rawTitle, fallback: request.username),
                "uploader": cleanText(rawTitle, fallback: request.username),
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

    private static func cardStartRanges(in html: String) -> [NSRange] {
        guard let regex = try? NSRegularExpression(
            pattern: #"<div\b[^>]*\bclass\s*=\s*[\"'][^\"']*\bthumb-list__item\b[^\"']*[\"'][^>]*>"#,
            options: [.caseInsensitive]
        ) else { return [] }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        return regex.matches(in: html, range: range).map(\.range)
    }

    private static func channelTitle(fromHTML html: String) -> String? {
        let raw = firstCapture(
            pattern: #"<div\b[^>]*\bclass\s*=\s*[\"'][^\"']*\buser-name\b[^\"']*[\"'][^>]*>(.*?)</div>"#,
            in: html
        ) ?? firstCapture(pattern: #"<h1\b[^>]*>(.*?)</h1>"#, in: html)
        guard let raw else { return nil }
        let value = cleanText(raw, fallback: "")
        return value.isEmpty ? nil : value
    }

    private static func firstCapture(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[captureRange])
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

    private static func canonicalVideoURL(for url: URL, collectionPageURL: URL) -> URL? {
        guard let canonical = EtcVideoPageResolver.canonicalXHamsterURL(for: url),
              var components = URLComponents(url: canonical, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.scheme = "https"
        components.host = collectionPageURL.host?.lowercased().hasSuffix(".test") == true
            ? "xhamster.test"
            : "xhamster.com"
        return components.url
    }

    private static func decodeHTML(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }

    private static func cleanText(_ raw: String, fallback: String) -> String {
        let value = decodeHTML(
            raw.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        )
        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        .trimmed
        return value.isEmpty ? fallback : value
    }

    private static func isPageNumber(_ value: String) -> Bool {
        guard let page = Int(value) else { return false }
        return page > 0
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
                throw NativeDownloadError.unsupported("Invalid nested xHamster mux plan.")
            }
            used.insert(index)
            indexes.append(index)
        }
        return indexes
    }

    private static func groupMetadata(
        post: (url: URL, download: ResolvedDownload),
        postIndex: Int,
        request: XHamsterCollectionRequest,
        itemID: String
    ) -> [String: String] {
        post.download.metadata.merging(DownloadMetadata.clean([
            "collection_index": String(postIndex + 1),
            "collection_item_id": itemID,
            "profile_username": request.username,
            "collection_url": request.sourceURL.absoluteString
        ])) { current, _ in current }
    }
}
