import Foundation

enum PornhubCollectionKind: String, CaseIterable, Equatable {
    case users
    case pornstar
    case model
    case channels
    case playlist

    var titleHeader: String {
        self == .playlist ? "Playlist" : "Channel"
    }
}

struct PornhubCollectionRequest: Equatable {
    var kind: PornhubCollectionKind
    var identifier: String
    var sourceURL: URL
}

struct PornhubCollectionEntry: Equatable {
    var videoID: String
    var title: String
    var thumbnailURL: URL?
    var pageURL: URL
}

struct PornhubCollectionPage: Equatable {
    var entries: [PornhubCollectionEntry]
    var isNotFound: Bool
}

struct PornhubCollectionProfile: Equatable {
    var title: String
    var thumbnailURL: URL?
    var token: String?
    var usesFreePornstarPages: Bool
}

final class PornhubCollectionResolver {
    private static let maximumPageCount = 100
    static let defaultCollectionItemLimit = 2_000

    func canResolve(_ url: URL) -> Bool {
        Self.request(from: url) != nil
    }

    func resolve(
        _ url: URL,
        headers: HTTPRequestOptions = HTTPRequestOptions(),
        rangeExpression: String = "",
        preferredResolution: String = ""
    ) async throws -> ResolvedDownload {
        guard let request = Self.request(from: url) else {
            throw NativeDownloadError.invalidURL(url.absoluteString)
        }
        try await PornhubMediaResolver.requirePremiumLoginIfNeeded(
            for: request.sourceURL,
            headers: headers
        )

        let itemRange = rangeExpression.trimmed
        let itemLimit = try Self.collectionItemLimit(for: itemRange)

        let initialHTML = try await Self.fetchHTML(
            from: request.sourceURL,
            method: .get,
            request: request,
            headers: headers,
            referer: headers.referer
        )
        let profile = Self.profile(fromHTML: initialHTML, request: request)
        if request.kind == .playlist, profile.token?.trimmed.isEmpty != false {
            throw NativeDownloadError.unsupported("Pornhub playlist token was not present in the page.")
        }

        var entries: [PornhubCollectionEntry] = []
        var seen = Set<String>()
        var consecutiveFailures = 0
        var pageCount = 0
        for pageNumber in 1...Self.maximumPageCount {
            try Task.checkCancellation()
            let pageRequest = Self.pageRequest(
                request: request,
                profile: profile,
                page: pageNumber
            )
            let html: String
            do {
                html = try await Self.fetchHTML(
                    from: pageRequest.url,
                    method: pageRequest.method,
                    request: request,
                    headers: headers,
                    referer: request.sourceURL.absoluteString
                )
                consecutiveFailures = 0
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                consecutiveFailures += 1
                if consecutiveFailures < 2 { continue }
                break
            }

            let page = Self.collectionPage(fromHTML: html, request: request)
            pageCount += 1
            if page.isNotFound || page.entries.isEmpty { break }
            for entry in page.entries where seen.insert(entry.videoID).inserted {
                entries.append(entry)
            }
            if entries.count >= itemLimit { break }
        }
        guard !entries.isEmpty else { throw NativeDownloadError.noFiles }

        let selectedIndexes = try Self.collectionItemIndexes(
            for: itemRange,
            total: entries.count
        )
        let selectedEntries = selectedIndexes.map { entries[$0] }

        let pageResolver = PornhubMediaResolver()
        var posts: [(entry: PornhubCollectionEntry, download: ResolvedDownload)] = []
        var failures: [Error] = []
        for entry in selectedEntries {
            try Task.checkCancellation()
            do {
                let download = try await pageResolver.resolve(
                    entry.pageURL,
                    headers: headers,
                    preferredResolution: preferredResolution,
                    verifyPremiumLogin: false
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
        combined.metadata["listed_item_count"] = String(entries.count)
        combined.metadata["discovered_item_count"] = String(entries.count)
        combined.metadata["selected_item_count"] = String(selectedEntries.count)
        combined.metadata["resolved_item_count"] = String(posts.count)
        combined.metadata["collection_pages"] = String(pageCount)
        combined.metadata["collection_item_limit"] = itemLimit == Int.max
            ? "unbounded"
            : String(itemLimit)
        if !itemRange.isEmpty {
            combined.metadata["range"] = itemRange
            combined.metadata["range_scope"] = "collection_items"
            combined.metadata["range_total"] = String(entries.count)
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
            throw NativeDownloadError.unsupported("Range did not match any Pornhub videos.")
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

    static func request(from url: URL) -> PornhubCollectionRequest? {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host?.lowercased(),
              isSupportedHost(host) else {
            return nil
        }
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        guard parts.count >= 2,
              let kind = PornhubCollectionKind(rawValue: parts[0].lowercased()),
              isValidIdentifier(parts[1]) else {
            return nil
        }

        let remainder = parts.dropFirst(2).map { $0.lowercased() }
        if kind == .playlist {
            guard remainder.isEmpty else { return nil }
        } else if let first = remainder.first {
            guard first == "videos" else { return nil }
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = canonicalHost(from: host)
        components.path = "/\(kind.rawValue)/\(parts[1])"
        guard let sourceURL = components.url else { return nil }
        return PornhubCollectionRequest(
            kind: kind,
            identifier: parts[1],
            sourceURL: sourceURL
        )
    }

    static func profile(
        fromHTML html: String,
        request: PornhubCollectionRequest
    ) -> PornhubCollectionProfile {
        let titleCandidates: [String?]
        if request.kind == .playlist {
            titleCandidates = [
                elementText(withID: "watchPlaylist", in: html),
                elementText(tag: "h1", attribute: nil, value: nil, in: html),
                metaContent(named: "og:title", in: html),
                elementText(tag: "title", attribute: nil, value: nil, in: html)
            ]
        } else {
            titleCandidates = [
                elementText(tag: "h1", attribute: "itemprop", value: "name", in: html),
                elementText(inClass: "profileUserName", preferredTag: "a", in: html),
                elementText(inClass: "titleWrapper", preferredTag: "h1", in: html),
                elementText(inClass: "withBio", preferredTag: "h1", in: html),
                elementText(tag: "h1", attribute: nil, value: nil, in: html),
                metaContent(named: "og:title", in: html),
                elementText(tag: "title", attribute: nil, value: nil, in: html)
            ]
        }
        let rawTitle = titleCandidates.compactMap { $0?.trimmed }.first(where: { !$0.isEmpty }) ?? request.identifier
        let cleanedTitle = cleanText(rawTitle, fallback: request.identifier)
        let title = "[\(request.kind.titleHeader)] \(cleanedTitle)"
        let rawThumbnail = metaContent(named: "og:image", in: html) ??
            firstCapture(
                pattern: #"<img\b[^>]*(?:class\s*=\s*[\"'][^\"']*(?:avatar|profile)[^\"']*[\"'][^>]*)?(?:data-src|src)\s*=\s*[\"']([^\"']+)[\"']"#,
                in: html
            )
        let token = firstCapture(
            pattern: #"(?:var\s+)?token\s*=\s*[\"']([^\"']+)[\"']"#,
            in: html
        )
        let uploadPath = "/pornstar/\(request.identifier)/videos/upload".lowercased()
        let usesFreePages = request.kind == .pornstar && html.lowercased().contains(uploadPath)
        return PornhubCollectionProfile(
            title: title,
            thumbnailURL: rawThumbnail.flatMap { absoluteURL($0, baseURL: request.sourceURL) },
            token: token,
            usesFreePornstarPages: usesFreePages
        )
    }

    static func collectionPage(
        fromHTML html: String,
        request: PornhubCollectionRequest
    ) -> PornhubCollectionPage {
        let decoded = decodeHTML(html)
        let notFound = decoded.range(
            of: #"<title\b[^>]*>\s*Page Not Found\s*</title>"#,
            options: [.caseInsensitive, .regularExpression]
        ) != nil
        guard !notFound else {
            return PornhubCollectionPage(entries: [], isNotFound: true)
        }

        let scope = pageScope(in: decoded, kind: request.kind)
        var tags = allCaptures(
            pattern: #"<li\b[^>]*class\s*=\s*[\"'][^\"']*(?:videoblock|pcVideoListItem|videoBox)[^\"']*[\"'][^>]*>.*?</li>"#,
            in: scope,
            group: 0
        )
        if tags.isEmpty { tags = [scope] }

        var entries: [PornhubCollectionEntry] = []
        var seen = Set<String>()
        for tag in tags {
            for anchor in allCaptures(
                pattern: #"<a\b[^>]*href\s*=\s*[\"']([^\"']*(?:view_video\.php\?[^\"']*\bviewkey=|/embed/)[^\"']+)[\"'][^>]*>"#,
                in: tag,
                group: 0
            ) {
                guard let rawHref = attributeValue("href", in: anchor),
                      let rawURL = absoluteURL(rawHref, baseURL: request.sourceURL),
                      let mediaRequest = PornhubMediaResolver.request(from: rawURL),
                      mediaRequest.kind == .video,
                      seen.insert(mediaRequest.id).inserted,
                      let pageURL = PornhubMediaResolver.canonicalURL(
                        kind: .video,
                        id: mediaRequest.id,
                        sourceURL: request.sourceURL
                      ) else {
                    continue
                }
                let rawTitle = attributeValue("title", in: anchor) ??
                    firstCapture(
                        pattern: #"<span\b[^>]*class\s*=\s*[\"'][^\"']*title[^\"']*[\"'][^>]*>(.*?)</span>"#,
                        in: tag
                    ) ?? mediaRequest.id
                let rawThumbnail = attributeValue("data-thumb_url", in: tag) ??
                    attributeValue("data-mediumthumb", in: tag) ??
                    firstCapture(
                        pattern: #"<img\b[^>]*(?:data-src|data-original|src)\s*=\s*[\"']([^\"']+)[\"']"#,
                        in: tag
                    )
                entries.append(PornhubCollectionEntry(
                    videoID: mediaRequest.id,
                    title: cleanText(rawTitle, fallback: mediaRequest.id),
                    thumbnailURL: rawThumbnail.flatMap { absoluteURL($0, baseURL: request.sourceURL) },
                    pageURL: pageURL
                ))
            }
        }

        if entries.isEmpty {
            for rawHref in allCaptures(
                pattern: #"href\s*=\s*[\"']([^\"']*view_video\.php\?[^\"']*\bviewkey=[^\"']+)[\"']"#,
                in: scope
            ) {
                guard let rawURL = absoluteURL(rawHref, baseURL: request.sourceURL),
                      let mediaRequest = PornhubMediaResolver.request(from: rawURL),
                      mediaRequest.kind == .video,
                      seen.insert(mediaRequest.id).inserted,
                      let pageURL = PornhubMediaResolver.canonicalURL(
                        kind: .video,
                        id: mediaRequest.id,
                        sourceURL: request.sourceURL
                      ) else {
                    continue
                }
                entries.append(PornhubCollectionEntry(
                    videoID: mediaRequest.id,
                    title: mediaRequest.id,
                    thumbnailURL: nil,
                    pageURL: pageURL
                ))
            }
        }
        return PornhubCollectionPage(entries: entries, isNotFound: false)
    }

    static func combinedDownload(
        request: PornhubCollectionRequest,
        profile: PornhubCollectionProfile,
        posts: [(entry: PornhubCollectionEntry, download: ResolvedDownload)]
    ) throws -> ResolvedDownload {
        guard !posts.isEmpty else { throw NativeDownloadError.noFiles }
        var assets: [ResolvedAsset] = []
        var fileAssetIndexes: [Int] = []
        var concatenations: [ResolvedConcatenationGroup] = []
        var muxes: [ResolvedMuxGroup] = []

        for (postIndex, post) in posts.enumerated() {
            let offset = assets.count
            let prefix = String(format: "%04d-%@", postIndex + 1, post.entry.videoID)
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
            title: profile.title,
            folderName: profile.title.sanitizedFilename(maxLength: 120),
            assets: assets,
            packageMode: packageMode,
            metadata: DownloadMetadata.clean([
                "site": "Pornhub",
                "title": profile.title,
                "series": profile.title,
                "type": "collection",
                "media_type": "video",
                "category": "videos",
                "collection": "true",
                "playlist": "true",
                "collection_kind": request.kind.rawValue,
                "collection_id": request.identifier,
                "playlist_id": request.kind == .playlist ? request.identifier : "",
                "profile_id": request.kind == .playlist ? "" : request.identifier,
                "channel_id": request.kind == .channels ? request.identifier : "",
                "artist": request.kind == .playlist ? "" : request.identifier,
                "author": request.kind == .playlist ? "" : request.identifier,
                "creator": request.kind == .playlist ? "" : request.identifier,
                "uploader": request.kind == .playlist ? "" : request.identifier,
                "channel": request.kind == .playlist ? "" : request.identifier,
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

    private enum RequestMethod: Equatable {
        case get
        case post
    }

    private static func pageRequest(
        request: PornhubCollectionRequest,
        profile: PornhubCollectionProfile,
        page: Int
    ) -> (url: URL, method: RequestMethod) {
        var components = URLComponents()
        components.scheme = "https"
        components.host = request.sourceURL.host
        switch request.kind {
        case .users:
            components.path = "/users/\(request.identifier)/videos/public/ajax"
            components.queryItems = [
                URLQueryItem(name: "o", value: "mr"),
                URLQueryItem(name: "page", value: String(page))
            ]
            return (components.url!, .post)
        case .model:
            components.path = "/model/\(request.identifier)/videos/upload/ajax"
            components.queryItems = [
                URLQueryItem(name: "o", value: "mr"),
                URLQueryItem(name: "page", value: String(page))
            ]
            return (components.url!, .post)
        case .pornstar:
            components.path = profile.usesFreePornstarPages
                ? "/pornstar/\(request.identifier)/videos/upload"
                : "/pornstar/\(request.identifier)"
            components.queryItems = [URLQueryItem(name: "page", value: String(page))]
            return (components.url!, .get)
        case .channels:
            components.path = "/channels/\(request.identifier)/videos"
            components.queryItems = [URLQueryItem(name: "page", value: String(page))]
            return (components.url!, .get)
        case .playlist:
            components.path = "/playlist/viewChunked"
            components.queryItems = [
                URLQueryItem(name: "id", value: request.identifier),
                URLQueryItem(name: "token", value: profile.token ?? ""),
                URLQueryItem(name: "page", value: String(page))
            ]
            return (components.url!, .get)
        }
    }

    private static func fetchHTML(
        from url: URL,
        method: RequestMethod,
        request: PornhubCollectionRequest,
        headers: HTTPRequestOptions,
        referer: String?
    ) async throws -> String {
        let additionalHeaders = await pageHeaders(for: url, ajax: method == .post)
        let data: Data
        switch method {
        case .get:
            data = try await HTTPClient.shared.data(
                from: url,
                referer: referer ?? request.sourceURL.absoluteString,
                userAgent: headers.userAgent,
                additionalHeaders: additionalHeaders
            )
        case .post:
            data = try await HTTPClient.shared.postForm(
                to: url,
                fields: [:],
                referer: referer ?? request.sourceURL.absoluteString,
                userAgent: headers.userAgent,
                additionalHeaders: additionalHeaders
            )
        }
        if let text = String(data: data, encoding: .utf8) { return text }
        if let text = String(data: data, encoding: .isoLatin1) { return text }
        return String(decoding: data, as: UTF8.self)
    }

    static func pageHeaders(for url: URL, ajax: Bool) async -> [String: String] {
        let ageCookieNames = Set([
            "age_verified", "accessagedisclaimerph", "accessagedisclaimeruk", "accessph"
        ])
        let existing = await CookieStore.shared.cookieHeader(for: url) ?? ""
        var cookies = existing.split(separator: ";").map { String($0).trimmed }.filter { value in
            let name = value.split(separator: "=", maxSplits: 1).first.map(String.init)?.lowercased() ?? ""
            return !ageCookieNames.contains(name)
        }
        cookies.append(contentsOf: [
            "age_verified=1",
            "accessAgeDisclaimerPH=1",
            "accessAgeDisclaimerUK=1",
            "accessPH=1"
        ])
        var result = [
            "Accept": ajax ? "text/html, */*; q=0.01" : "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Cookie": cookies.joined(separator: "; ")
        ]
        if ajax { result["X-Requested-With"] = "XMLHttpRequest" }
        return result
    }

    private static func groupMetadata(
        request: PornhubCollectionRequest,
        post: (entry: PornhubCollectionEntry, download: ResolvedDownload),
        index: Int
    ) -> [String: String] {
        post.download.metadata.merging(
            collectionMetadata(request: request, entry: post.entry, index: index)
        ) { current, _ in current }
    }

    private static func collectionMetadata(
        request: PornhubCollectionRequest,
        entry: PornhubCollectionEntry,
        index: Int
    ) -> [String: String] {
        DownloadMetadata.clean([
            "collection_index": String(index + 1),
            "collection_item_id": entry.videoID,
            "collection_url": request.sourceURL.absoluteString,
            "collection_kind": request.kind.rawValue,
            "collection_id": request.identifier,
            "playlist_id": request.kind == .playlist ? request.identifier : "",
            "profile_id": request.kind == .playlist ? "" : request.identifier,
            "video_id": entry.videoID,
            "item_title": entry.title,
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
                throw NativeDownloadError.unsupported("Invalid nested Pornhub mux plan.")
            }
            used.insert(index)
            indexes.append(index)
        }
        return indexes
    }

    private static func pageScope(in html: String, kind: PornhubCollectionKind) -> String {
        let markers: [String]
        switch kind {
        case .pornstar:
            markers = ["videoUList", "pornstarsVideos"]
        case .channels:
            markers = ["channelsBody", "rightSide"]
        default:
            markers = ["container"]
        }
        for marker in markers {
            if let range = html.range(of: marker, options: .caseInsensitive) {
                return String(html[range.lowerBound...])
            }
        }
        return html
    }

    private static func elementText(withID id: String, in html: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: id)
        return firstCapture(
            pattern: #"<[^>]+\bid\s*=\s*[\"']\#(escaped)[\"'][^>]*>(.*?)</[^>]+>"#,
            in: html
        ).map { cleanText($0, fallback: "") }
    }

    private static func elementText(
        tag: String,
        attribute: String?,
        value: String?,
        in html: String
    ) -> String? {
        let escapedTag = NSRegularExpression.escapedPattern(for: tag)
        let attributePattern: String
        if let attribute, let value {
            attributePattern = #"(?=[^>]*\b\#(NSRegularExpression.escapedPattern(for: attribute))\s*=\s*[\"']\#(NSRegularExpression.escapedPattern(for: value))[\"'])"#
        } else {
            attributePattern = ""
        }
        return firstCapture(
            pattern: #"<\#(escapedTag)\b\#(attributePattern)[^>]*>(.*?)</\#(escapedTag)>"#,
            in: html
        ).map { cleanText($0, fallback: "") }
    }

    private static func elementText(
        inClass className: String,
        preferredTag: String,
        in html: String
    ) -> String? {
        let escapedClass = NSRegularExpression.escapedPattern(for: className)
        let escapedTag = NSRegularExpression.escapedPattern(for: preferredTag)
        let scope = firstCapture(
            pattern: #"<[^>]+class\s*=\s*[\"'][^\"']*\#(escapedClass)[^\"']*[\"'][^>]*>(.*?)</(?:div|section|header)>"#,
            in: html
        )
        guard let scope else { return nil }
        return firstCapture(
            pattern: #"<\#(escapedTag)\b[^>]*>(.*?)</\#(escapedTag)>"#,
            in: scope
        ).map { cleanText($0, fallback: "") }
    }

    private static func metaContent(named name: String, in html: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        for pattern in [
            #"<meta\b[^>]*(?:property|name)\s*=\s*[\"']\#(escaped)[\"'][^>]*content\s*=\s*[\"']([^\"']+)[\"'][^>]*>"#,
            #"<meta\b[^>]*content\s*=\s*[\"']([^\"']+)[\"'][^>]*(?:property|name)\s*=\s*[\"']\#(escaped)[\"'][^>]*>"#
        ] {
            if let value = firstCapture(pattern: pattern, in: html) {
                return decodeHTML(value).trimmed
            }
        }
        return nil
    }

    private static func attributeValue(_ name: String, in tag: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        return firstCapture(
            pattern: #"\b\#(escaped)\s*=\s*(?:\"([^\"]*)\"|'([^']*)'|([^\s>\"']+))"#,
            in: tag,
            groups: [1, 2, 3]
        )
    }

    private static func firstCapture(pattern: String, in text: String) -> String? {
        firstCapture(pattern: pattern, in: text, groups: [1])
    }

    private static func firstCapture(pattern: String, in text: String, groups: [Int]) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        for group in groups where match.numberOfRanges > group {
            if let capture = Range(match.range(at: group), in: text) {
                return String(text[capture])
            }
        }
        return nil
    }

    private static func allCaptures(
        pattern: String,
        in text: String,
        group: Int = 1
    ) -> [String] {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > group,
                  let capture = Range(match.range(at: group), in: text) else {
                return nil
            }
            return String(text[capture])
        }
    }

    private static func absoluteURL(_ raw: String, baseURL: URL) -> URL? {
        var value = decodeHTML(raw).trimmed
        guard !value.isEmpty,
              !value.lowercased().hasPrefix("javascript:") else {
            return nil
        }
        if value.hasPrefix("//") {
            value = "\(baseURL.scheme ?? "https"):\(value)"
        }
        return URL(string: value, relativeTo: baseURL)?.absoluteURL
    }

    private static func cleanText(_ raw: String, fallback: String) -> String {
        let text = decodeHTML(
            raw.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        )
        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        .trimmed
        return (text.isEmpty ? fallback : text).sanitizedFilename(maxLength: 120)
    }

    private static func decodeHTML(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#34;", with: "\"")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: #"\/"#, with: "/")
    }

    private static func prefixedFilename(_ filename: String, prefix: String) -> String {
        "\(prefix)-\(filename)".sanitizedFilename(maxLength: 180)
    }

    private static func isSupportedHost(_ host: String) -> Bool {
        host == "pornhub.test" || host == "www.pornhub.test" ||
            host == "pornhubthbh7ap3u.onion" || host == "www.pornhubthbh7ap3u.onion" ||
            host == "pornhubvybmsymdol4iibwgwtkpwmeyd6luq2gxajgjzfjvotyt5zhyd.onion" ||
            host == "pornhub.com" || host.hasSuffix(".pornhub.com") ||
            host == "pornhub.net" || host.hasSuffix(".pornhub.net") ||
            host == "pornhub.org" || host.hasSuffix(".pornhub.org") ||
            host == "pornhubpremium.com" || host.hasSuffix(".pornhubpremium.com") ||
            host == "pornhubpremium.net" || host.hasSuffix(".pornhubpremium.net") ||
            host == "pornhubpremium.org" || host.hasSuffix(".pornhubpremium.org")
    }

    private static func canonicalHost(from host: String) -> String {
        if host.hasSuffix(".test") { return "www.pornhub.test" }
        if host.contains("pornhubpremium") { return "www.pornhubpremium.com" }
        return "www.pornhub.com"
    }

    private static func isValidIdentifier(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil
    }
}
