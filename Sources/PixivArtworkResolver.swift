import Foundation

enum PixivArtworkResolverError: LocalizedError, Equatable {
    case authenticationRequired

    var errorDescription: String? {
        switch self {
        case .authenticationRequired:
            return "Pixiv login is required to read this artwork."
        }
    }
}

struct PixivCollectionRequest: Equatable {
    enum Kind: String {
        case userArtworks = "user_artworks"
        case bookmarks
        case tagSearch = "tag_search"
        case following
        case followingR18 = "following_r18"
    }

    var kind: Kind
    var identifier: String
    var title: String
    var queryOptions: [URLQueryItem] = []
    var userArtworkTypes: [String] = []
    var userTag: String?
}

struct PixivCollectionListing: Equatable {
    var artworkIDs: [String]
    var totalCount: Int?
    var fetchedPages: Int
}

struct PixivCollectionProgress: Equatable, Sendable {
    var processedArtworkCount: Int
    var listedArtworkCount: Int
    var assetCount: Int
}

final class PixivArtworkResolver {
    static let defaultCollectionArtworkLimit = 2_000
    static let originalBookmarkPageLimit = 48
    static let improvedBuiltinCoreConcurrency = 2
    static let effectiveOverrideCoreConcurrency = 4
    static let collectionResolutionConcurrency = effectiveOverrideCoreConcurrency
    static let collectionResolutionBatchSize = 16

    private let apiRateLimiter = PixivAPIRateLimiter()

    func canResolve(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(),
              Self.isPixivArtworkHost(host),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return false
        }
        return Self.artworkID(from: url) != nil ||
            Self.collectionRequest(from: url) != nil ||
            Self.isPixivVanityProfileURL(url)
    }

    func resolve(
        _ url: URL,
        headers: HTTPRequestOptions = HTTPRequestOptions(),
        ugoiraFileFormat: PixivUgoiraFileFormat = .ugoira,
        ugoiraDither: Bool = true,
        ugoiraQuality: Int = 90,
        rangeExpression: String = "",
        progress: (@Sendable (PixivCollectionProgress) async -> Void)? = nil
    ) async throws -> ResolvedDownload {
        let apiHeaderFields = try await Self.apiHeaders(for: url)
        if let artworkID = Self.artworkID(from: url) {
            return try await resolveArtwork(
                artworkID: artworkID,
                sourceURL: url,
                headers: headers,
                apiHeaderFields: apiHeaderFields,
                ugoiraFileFormat: ugoiraFileFormat,
                ugoiraDither: ugoiraDither,
                ugoiraQuality: ugoiraQuality
            )
        }

        if let request = Self.collectionRequest(from: url) {
            return try await resolveCollection(
                request,
                sourceURL: url,
                headers: headers,
                apiHeaderFields: apiHeaderFields,
                ugoiraFileFormat: ugoiraFileFormat,
                ugoiraDither: ugoiraDither,
                ugoiraQuality: ugoiraQuality,
                rangeExpression: rangeExpression,
                progress: progress
            )
        }

        if Self.isPixivVanityProfileURL(url) {
            let profileURL = try await resolvedVanityProfileURL(url, headers: headers)
            return try await resolve(
                profileURL,
                headers: headers,
                ugoiraFileFormat: ugoiraFileFormat,
                ugoiraDither: ugoiraDither,
                ugoiraQuality: ugoiraQuality,
                rangeExpression: rangeExpression,
                progress: progress
            )
        }

        throw NativeDownloadError.invalidURL(url.absoluteString)
    }

    private func resolveArtwork(
        artworkID: String,
        sourceURL url: URL,
        headers: HTTPRequestOptions,
        apiHeaderFields: [String: String],
        ugoiraFileFormat: PixivUgoiraFileFormat,
        ugoiraDither: Bool,
        ugoiraQuality: Int
    ) async throws -> ResolvedDownload {
        let referer = Self.artworkURL(for: artworkID, sourceURL: url).absoluteString
        let (detailData, _) = try await apiDataResponse(
            from: Self.detailAPIURL(for: artworkID, sourceURL: url),
            referer: headers.referer ?? referer,
            userAgent: headers.userAgent,
            additionalHeaders: apiHeaderFields
        )
        let detail = try Self.detail(from: detailData, artworkID: artworkID)

        if detail.isUgoira {
            let (metaData, response) = try await apiDataResponse(
                from: Self.ugoiraAPIURL(for: artworkID, sourceURL: url),
                referer: headers.referer ?? referer,
                userAgent: headers.userAgent,
                additionalHeaders: apiHeaderFields,
                acceptedStatusCodes: [401, 403, 404]
            )
            guard response.statusCode == 200 else {
                throw PixivArtworkResolverError.authenticationRequired
            }
            return try Self.ugoiraDownload(
                from: metaData,
                detail: detail,
                pageURL: URL(string: referer)!,
                fileFormat: ugoiraFileFormat,
                dither: ugoiraDither,
                quality: ugoiraQuality
            )
        }

        let (pagesData, response) = try await apiDataResponse(
            from: Self.pagesAPIURL(for: artworkID, sourceURL: url),
            referer: headers.referer ?? referer,
            userAgent: headers.userAgent,
            additionalHeaders: apiHeaderFields,
            acceptedStatusCodes: [401, 403, 404]
        )
        if response.statusCode == 200,
           let resolved = try? Self.pagesDownload(from: pagesData, detail: detail, pageURL: URL(string: referer)!) {
            return resolved
        }

        if detail.originalURL != nil {
            return try Self.singleImageDownload(from: detail, pageURL: URL(string: referer)!)
        }
        if [401, 403, 404].contains(response.statusCode) {
            throw PixivArtworkResolverError.authenticationRequired
        }
        throw NativeDownloadError.noFiles
    }

    private func resolveCollection(
        _ request: PixivCollectionRequest,
        sourceURL url: URL,
        headers: HTTPRequestOptions,
        apiHeaderFields: [String: String],
        ugoiraFileFormat: PixivUgoiraFileFormat,
        ugoiraDither: Bool,
        ugoiraQuality: Int,
        rangeExpression: String,
        progress: (@Sendable (PixivCollectionProgress) async -> Void)?
    ) async throws -> ResolvedDownload {
        let range = rangeExpression.trimmed
        let maximumRequestedAsset = try Self.maximumRequestedAssetIndex(in: range)
        let needsDetailTagFiltering = request.kind == .userArtworks && request.userTag?.isEmpty == false
        let artworkLimit = needsDetailTagFiltering
            ? max(Self.defaultCollectionArtworkLimit, maximumRequestedAsset ?? 1)
            : max(1, maximumRequestedAsset ?? Self.defaultCollectionArtworkLimit)
        let listing = try await collectionListing(
            for: request,
            sourceURL: url,
            headers: headers,
            apiHeaderFields: apiHeaderFields,
            limit: artworkLimit
        )
        guard !listing.artworkIDs.isEmpty else {
            throw NativeDownloadError.noFiles
        }

        var assets: [ResolvedAsset] = []
        var firstMetadata: [String: String] = [:]
        var resolvedArtworkCount = 0
        var failureCount = 0
        var filteredArtworkCount = 0
        for batchStart in stride(from: 0, to: listing.artworkIDs.count, by: Self.collectionResolutionBatchSize) {
            try Task.checkCancellation()
            let batchEnd = min(listing.artworkIDs.count, batchStart + Self.collectionResolutionBatchSize)
            let gate = PixivResolutionSemaphore(value: Self.collectionResolutionConcurrency)
            var batchResults: [Int: ResolvedDownload] = [:]
            var batchFailureCount = 0

            try await withThrowingTaskGroup(of: PixivCollectionArtworkResult.self) { group in
                for offset in batchStart..<batchEnd {
                    let artworkID = listing.artworkIDs[offset]
                    group.addTask {
                        try await gate.withPermit {
                            do {
                                let resolved = try await self.resolveArtwork(
                                    artworkID: artworkID,
                                    sourceURL: url,
                                    headers: headers,
                                    apiHeaderFields: apiHeaderFields,
                                    ugoiraFileFormat: ugoiraFileFormat,
                                    ugoiraDither: ugoiraDither,
                                    ugoiraQuality: ugoiraQuality
                                )
                                guard Self.collectionArtwork(
                                    resolved,
                                    matchesRequestedTag: request.userTag
                                ) else {
                                    return .filtered(offset: offset)
                                }
                                return .resolved(offset: offset, download: resolved)
                            } catch is CancellationError {
                                throw CancellationError()
                            } catch let error as PixivArtworkResolverError {
                                throw error
                            } catch {
                                return .failed(offset: offset)
                            }
                        }
                    }
                }

                for try await result in group {
                    switch result {
                    case .resolved(let offset, let download):
                        batchResults[offset] = download
                    case .failed:
                        batchFailureCount += 1
                    case .filtered:
                        filteredArtworkCount += 1
                    }
                }
            }

            failureCount += batchFailureCount
            for offset in batchStart..<batchEnd {
                guard let resolved = batchResults[offset] else { continue }
                resolvedArtworkCount += 1
                if firstMetadata.isEmpty {
                    firstMetadata = resolved.metadata
                }
                assets.append(contentsOf: resolved.assets)
                if let maximumRequestedAsset, assets.count >= maximumRequestedAsset {
                    break
                }
            }
            await progress?(PixivCollectionProgress(
                processedArtworkCount: batchEnd,
                listedArtworkCount: listing.artworkIDs.count,
                assetCount: assets.count
            ))
            if let maximumRequestedAsset, assets.count >= maximumRequestedAsset { break }
        }

        guard !assets.isEmpty else {
            throw NativeDownloadError.noFiles
        }

        let collectionTitle = try await originalStyleCollectionTitle(
            request,
            sourceURL: url,
            headers: headers,
            apiHeaderFields: apiHeaderFields
        )
        let title = collectionTitle.sanitizedFilename(maxLength: 120)
        var metadata = firstMetadata
        metadata["site"] = "Pixiv"
        metadata["type"] = "collection"
        metadata["collection"] = collectionTitle
        metadata["collection_type"] = request.kind.rawValue
        metadata["collection_id"] = request.identifier
        metadata["gallery_id"] = request.identifier
        metadata["item_count"] = String(assets.count)
        metadata["artwork_count"] = String(resolvedArtworkCount)
        metadata["listed_artwork_count"] = String(listing.artworkIDs.count)
        metadata["collection_pages"] = String(listing.fetchedPages)
        if let totalCount = listing.totalCount {
            metadata["collection_total"] = String(totalCount)
        }
        if failureCount > 0 {
            metadata["skipped_count"] = String(failureCount)
        }
        if filteredArtworkCount > 0 {
            metadata["filtered_count"] = String(filteredArtworkCount)
        }
        if let maximumRequestedAsset {
            metadata["range_resolution_limit"] = String(maximumRequestedAsset)
        }
        return ResolvedDownload(
            title: title,
            folderName: title,
            assets: assets,
            metadata: DownloadMetadata.clean(metadata)
        )
    }

    private func originalStyleCollectionTitle(
        _ request: PixivCollectionRequest,
        sourceURL: URL,
        headers: HTTPRequestOptions,
        apiHeaderFields: [String: String]
    ) async throws -> String {
        if request.kind == .tagSearch {
            let token = request.identifier.replacingOccurrences(of: " ", with: "+")
            return "\(request.identifier) (pixiv_search_\(token))"
        }

        let userID: String?
        switch request.kind {
        case .userArtworks, .bookmarks:
            userID = request.identifier == "me" ? apiHeaderFields["X-User-Id"] : request.identifier
        case .following, .followingR18:
            userID = apiHeaderFields["X-User-Id"]
        case .tagSearch:
            userID = nil
        }
        guard let userID, !userID.isEmpty else {
            return "Pixiv \(request.title)"
        }

        let artist: String
        do {
            let (data, _) = try await apiDataResponse(
                from: Self.profileTopAPIURL(for: userID, sourceURL: sourceURL),
                referer: headers.referer ?? sourceURL.absoluteString,
                userAgent: headers.userAgent,
                additionalHeaders: apiHeaderFields
            )
            artist = try Self.profileArtist(from: data) ?? "Pixiv User \(userID)"
        } catch let error as PixivArtworkResolverError {
            throw error
        } catch {
            artist = "Pixiv User \(userID)"
        }

        switch request.kind {
        case .userArtworks:
            return "\(artist) (pixiv_\(userID))"
        case .bookmarks:
            return "\(artist) (pixiv_bmk_\(userID))"
        case .following:
            return "\(artist) (pixiv_following_\(userID))"
        case .followingR18:
            return "\(artist) (pixiv_following_r18_\(userID))"
        case .tagSearch:
            return request.title
        }
    }

    private static func profileArtist(from data: Data) throws -> String? {
        let object = try jsonObject(from: data)
        let body = dictionary(at: ["body"], in: object) ?? object
        if let extraData = body["extraData"] as? [String: Any],
           let meta = extraData["meta"] as? [String: Any],
           let ogp = meta["ogp"] as? [String: Any],
           let title = stringValue(ogp["title"])?.trimmed,
           !title.isEmpty {
            return cleanTitle(title)
        }
        for key in ["userName", "name", "title"] {
            if let value = stringValue(body[key])?.trimmed, !value.isEmpty {
                return cleanTitle(value)
            }
        }
        return nil
    }

    func collectionListing(
        for request: PixivCollectionRequest,
        sourceURL: URL,
        headers: HTTPRequestOptions = HTTPRequestOptions(),
        limit: Int
    ) async throws -> PixivCollectionListing {
        let apiHeaderFields = try await Self.apiHeaders(for: sourceURL)
        return try await collectionListing(
            for: request,
            sourceURL: sourceURL,
            headers: headers,
            apiHeaderFields: apiHeaderFields,
            limit: limit
        )
    }

    private func collectionListing(
        for originalRequest: PixivCollectionRequest,
        sourceURL: URL,
        headers: HTTPRequestOptions,
        apiHeaderFields: [String: String],
        limit: Int
    ) async throws -> PixivCollectionListing {
        let request = try Self.requestByResolvingCurrentUser(originalRequest, apiHeaderFields: apiHeaderFields)
        let effectiveLimit = max(1, limit)
        let referer = headers.referer ?? sourceURL.absoluteString
        if request.kind == .userArtworks {
            let (data, _) = try await apiDataResponse(
                from: Self.collectionAPIURL(for: request, sourceURL: sourceURL),
                referer: referer,
                userAgent: headers.userAgent,
                additionalHeaders: apiHeaderFields
            )
            let allIDs = try Self.artworkIDs(fromCollectionData: data, request: request)
            return PixivCollectionListing(
                artworkIDs: Array(allIDs.prefix(effectiveLimit)),
                totalCount: allIDs.count,
                fetchedPages: 1
            )
        }

        let bookmarkLimit = Self.bookmarkPageLimit(for: request)
        let bookmarkStartOffset = Self.queryInteger("offset", in: request.queryOptions) ?? 0
        let rests = Self.bookmarkRestValues(for: request, apiHeaderFields: apiHeaderFields)
        var artworkIDs: [String] = []
        var seen = Set<String>()
        var totalCount: Int?
        var fetchedPages = 0
        for rest in rests {
            var page = 1
            while artworkIDs.count < effectiveLimit {
                try Task.checkCancellation()
                let offset = bookmarkStartOffset + ((page - 1) * bookmarkLimit)
                let apiURL = Self.collectionAPIURL(
                    for: request,
                    sourceURL: sourceURL,
                    page: page,
                    bookmarkOffset: offset,
                    bookmarkRest: rest
                )
                let (data, _) = try await apiDataResponse(
                    from: apiURL,
                    referer: referer,
                    userAgent: headers.userAgent,
                    additionalHeaders: apiHeaderFields
                )
                let pageIDs = try Self.artworkIDs(fromCollectionData: data, request: request)
                let pageTotal = try Self.collectionTotal(from: data, request: request)
                if request.kind == .bookmarks {
                    if page == 1, let pageTotal {
                        totalCount = (totalCount ?? 0) + pageTotal
                    }
                } else {
                    totalCount = pageTotal ?? totalCount
                }
                fetchedPages += 1
                let previousCount = artworkIDs.count
                for id in pageIDs where seen.insert(id).inserted {
                    artworkIDs.append(id)
                    if artworkIDs.count >= effectiveLimit { break }
                }
                if artworkIDs.count >= effectiveLimit || artworkIDs.count == previousCount {
                    break
                }
                if let pageTotal {
                    let consumed = request.kind == .bookmarks
                        ? offset + pageIDs.count
                        : artworkIDs.count
                    if consumed >= pageTotal { break }
                }
                guard !pageIDs.isEmpty else { break }
                guard page < Int.max else { break }
                page += 1
            }
            if request.kind != .bookmarks || artworkIDs.count >= effectiveLimit { break }
        }
        return PixivCollectionListing(
            artworkIDs: artworkIDs,
            totalCount: totalCount,
            fetchedPages: fetchedPages
        )
    }

    static func artworkID(from url: URL) -> String? {
        let parts = url.path.split(separator: "/").map(String.init)
        for (index, part) in parts.enumerated() where part.lowercased() == "artworks" && index + 1 < parts.count {
            let candidate = parts[index + 1]
            if candidate.range(of: #"^[0-9]+$"#, options: .regularExpression) != nil {
                return candidate
            }
        }

        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return items.first { $0.name.lowercased() == "illust_id" }?.value.flatMap { value in
            value.range(of: #"^[0-9]+$"#, options: .regularExpression) != nil ? value : nil
        }
    }

    static func detailAPIURL(for artworkID: String, sourceURL: URL) -> URL {
        apiURL(path: "/ajax/illust/\(artworkID)", sourceURL: sourceURL)
    }

    static func pagesAPIURL(for artworkID: String, sourceURL: URL) -> URL {
        apiURL(path: "/ajax/illust/\(artworkID)/pages", sourceURL: sourceURL)
    }

    static func ugoiraAPIURL(for artworkID: String, sourceURL: URL) -> URL {
        apiURL(path: "/ajax/illust/\(artworkID)/ugoira_meta", sourceURL: sourceURL)
    }

    static func profileTopAPIURL(for userID: String, sourceURL: URL) -> URL {
        apiURL(path: "/ajax/user/\(userID)/profile/top", sourceURL: sourceURL)
    }

    static func collectionRequest(from url: URL) -> PixivCollectionRequest? {
        guard let host = url.host?.lowercased(),
              isPixivArtworkHost(host) else {
            return nil
        }

        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true).map { String($0).removingPercentEncoding ?? String($0) }
        let lowered = parts.map { $0.lowercased() }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []

        if lowered.first == "bookmark.php" {
            let userID = items.first(where: { $0.name.lowercased() == "id" })?.value?.trimmed
            guard userID == nil || isNumericID(userID ?? "") else { return nil }
            let identifier = userID?.isEmpty == false ? userID! : "me"
            return PixivCollectionRequest(
                kind: .bookmarks,
                identifier: identifier,
                title: identifier == "me" ? "My Bookmarks" : "Bookmarks \(identifier)",
                queryOptions: selectedQueryItems(from: items, names: bookmarkOptionNames)
            )
        }

        if lowered.first == "bookmark_new_illust_r18.php" {
            return PixivCollectionRequest(
                kind: .followingR18,
                identifier: "following_r18",
                title: "Following R18",
                queryOptions: selectedQueryItems(from: items, names: followingOptionNames)
            )
        }

        if lowered.first == "bookmark_new_illust.php" {
            return PixivCollectionRequest(
                kind: .following,
                identifier: "following",
                title: "Following",
                queryOptions: selectedQueryItems(from: items, names: followingOptionNames)
            )
        }

        if let tagIndex = lowered.firstIndex(of: "tags"),
           tagIndex + 1 < parts.count,
           lowered.contains("artworks") {
            let tag = parts[tagIndex + 1].trimmed
            guard !tag.isEmpty else { return nil }
            return PixivCollectionRequest(
                kind: .tagSearch,
                identifier: tag,
                title: "Tag \(tag)",
                queryOptions: selectedQueryItems(from: items, names: searchOptionNames)
            )
        }

        if lowered.first == "search.php",
           let word = items.first(where: { $0.name.lowercased() == "word" })?.value?.trimmed,
           !word.isEmpty {
            return PixivCollectionRequest(
                kind: .tagSearch,
                identifier: word,
                title: "Search \(word)",
                queryOptions: selectedQueryItems(from: items, names: searchOptionNames)
            )
        }

        if let usersIndex = lowered.firstIndex(of: "users"),
           usersIndex + 1 < parts.count,
           isNumericID(parts[usersIndex + 1]) {
            let userID = parts[usersIndex + 1]
            if usersIndex + 2 < lowered.count,
               lowered[usersIndex + 2] == "following" {
                return PixivCollectionRequest(
                    kind: .following,
                    identifier: userID,
                    title: "Following \(userID)",
                    queryOptions: selectedQueryItems(from: items, names: followingOptionNames)
                )
            }
            if lowered.contains("bookmarks") {
                return PixivCollectionRequest(
                    kind: .bookmarks,
                    identifier: userID,
                    title: "Bookmarks \(userID)",
                    queryOptions: selectedQueryItems(from: items, names: bookmarkOptionNames)
                )
            }
            if lowered.count == usersIndex + 2 ||
                lowered.contains("artworks") ||
                lowered.contains("illustrations") ||
                lowered.contains("illusts") ||
                lowered.contains("manga") {
                let filters = userArtworkFilters(parts: parts, lowered: lowered, usersIndex: usersIndex)
                let titleSuffix = [filters.types.joined(separator: "+"), filters.tag].filter { !$0.isEmpty }.joined(separator: " ")
                return PixivCollectionRequest(
                    kind: .userArtworks,
                    identifier: userID,
                    title: titleSuffix.isEmpty ? "User \(userID)" : "User \(userID) \(titleSuffix)",
                    userArtworkTypes: filters.types,
                    userTag: filters.tag.isEmpty ? nil : filters.tag
                )
            }
        }

        if lowered.first == "member.php",
           let userID = items.first(where: { $0.name.lowercased() == "id" })?.value,
           isNumericID(userID) {
            return PixivCollectionRequest(kind: .userArtworks, identifier: userID, title: "User \(userID)")
        }

        return nil
    }

    static func collectionAPIURL(for request: PixivCollectionRequest, sourceURL: URL) -> URL {
        collectionAPIURL(
            for: request,
            sourceURL: sourceURL,
            page: 1,
            bookmarkOffset: queryInteger("offset", in: request.queryOptions) ?? 0,
            bookmarkRest: nil
        )
    }

    static func collectionAPIURL(
        for request: PixivCollectionRequest,
        sourceURL: URL,
        page: Int,
        bookmarkOffset: Int,
        bookmarkRest: String? = nil
    ) -> URL {
        let page = max(1, page)
        switch request.kind {
        case .userArtworks:
            return apiURL(path: "/ajax/user/\(request.identifier)/profile/all", sourceURL: sourceURL)
        case .bookmarks:
            let options = request.queryOptions.filter {
                !["offset", "limit"].contains($0.name.lowercased())
            }
            return apiURL(
                path: "/ajax/user/\(request.identifier)/illusts/bookmarks",
                sourceURL: sourceURL,
                queryItems: mergedQueryItems(defaults: [
                    URLQueryItem(name: "tag", value: ""),
                    URLQueryItem(name: "offset", value: String(max(0, bookmarkOffset))),
                    URLQueryItem(name: "limit", value: String(bookmarkPageLimit(for: request))),
                    URLQueryItem(name: "rest", value: bookmarkRest ?? "show")
                ], options: options)
            )
        case .tagSearch:
            let options = request.queryOptions.filter { $0.name.lowercased() != "p" }
            return apiURL(
                path: "/ajax/search/artworks/\(request.identifier)",
                sourceURL: sourceURL,
                queryItems: mergedQueryItems(defaults: [
                    URLQueryItem(name: "word", value: request.identifier),
                    URLQueryItem(name: "order", value: "date_d"),
                    URLQueryItem(name: "mode", value: "all"),
                    URLQueryItem(name: "p", value: String(page)),
                    URLQueryItem(name: "s_mode", value: "s_tag_full"),
                    URLQueryItem(name: "type", value: "all")
                ], options: options)
            )
        case .following:
            let options = request.queryOptions.filter { $0.name.lowercased() != "p" }
            return apiURL(
                path: "/ajax/follow_latest/illust",
                sourceURL: sourceURL,
                queryItems: mergedQueryItems(defaults: [
                    URLQueryItem(name: "p", value: String(page)),
                    URLQueryItem(name: "mode", value: "all")
                ], options: options)
            )
        case .followingR18:
            let options = request.queryOptions.filter { $0.name.lowercased() != "p" }
            return apiURL(
                path: "/ajax/follow_latest/illust",
                sourceURL: sourceURL,
                queryItems: mergedQueryItems(defaults: [
                    URLQueryItem(name: "p", value: String(page)),
                    URLQueryItem(name: "mode", value: "r18")
                ], options: options)
            )
        }
    }

    static func collectionTotal(from data: Data, request: PixivCollectionRequest) throws -> Int? {
        let object = try jsonObject(from: data)
        let body = object["body"] as? [String: Any] ?? object
        switch request.kind {
        case .userArtworks:
            return try artworkIDs(fromCollectionData: data, request: request).count
        case .bookmarks:
            return intValue(body["total"]) ??
                (body["works"] as? [Any]).map(\.count)
        case .tagSearch:
            let illustManga = body["illustManga"] as? [String: Any]
            return intValue(illustManga?["total"]) ?? intValue(body["total"])
        case .following, .followingR18:
            let page = body["page"] as? [String: Any]
            return intValue(body["total"]) ?? intValue(page?["total"])
        }
    }

    static func artworkIDs(fromCollectionData data: Data) throws -> [String] {
        let object = try jsonObject(from: data)
        var ids: [String] = []
        collectArtworkIDs(in: object, output: &ids)
        var seen = Set<String>()
        return ids.filter { id in
            guard !seen.contains(id) else { return false }
            seen.insert(id)
            return true
        }
    }

    static func artworkIDs(fromCollectionData data: Data, request: PixivCollectionRequest) throws -> [String] {
        let object = try jsonObject(from: data)
        guard request.kind == .userArtworks else {
            var ids: [String] = []
            collectArtworkIDs(in: object, output: &ids)
            return uniqueIDs(ids)
        }

        let roots = collectionBodyRoots(from: object)
        let typeNames = request.userArtworkTypes.isEmpty ? ["illusts", "manga"] : request.userArtworkTypes
        var ids: [String] = []
        for root in roots {
            for typeName in typeNames {
                guard let table = root[typeName] else { continue }
                collectUserArtworkIDs(in: table, tag: nil, output: &ids)
            }
        }
        return uniqueIDs(ids).sorted { (Int($0) ?? 0) > (Int($1) ?? 0) }
    }

    private static func collectionArtwork(
        _ resolved: ResolvedDownload,
        matchesRequestedTag requestedTag: String?
    ) -> Bool {
        guard let requestedTag = requestedTag?.trimmed, !requestedTag.isEmpty else {
            return true
        }
        let expected = originalStyleTag(requestedTag)
        let rawTags = resolved.metadata["tags"] ?? resolved.assets.first?.metadata["tags"] ?? ""
        return rawTags
            .split(separator: ",", omittingEmptySubsequences: true)
            .map { originalStyleTag(String($0)) }
            .contains(expected)
    }

    private static func originalStyleTag(_ raw: String) -> String {
        raw.filter { !$0.isWhitespace }.lowercased()
    }

    static func artworkURL(for artworkID: String, sourceURL: URL) -> URL {
        var components = URLComponents(url: sourceURL, resolvingAgainstBaseURL: false)
        components?.scheme = "https"
        components?.host = sourceURL.host?.lowercased().hasSuffix(".test") == true ? "www.pixiv.test" : "www.pixiv.net"
        components?.path = "/artworks/\(artworkID)"
        components?.queryItems = nil
        components?.fragment = nil
        return components?.url ?? URL(string: "https://www.pixiv.net/artworks/\(artworkID)")!
    }

    static func canonicalInputURL(for url: URL) -> URL? {
        canonicalInputURL(for: url, redirectsFollowed: 0)
    }

    private static func canonicalInputURL(for url: URL, redirectsFollowed: Int) -> URL? {
        guard let host = url.host?.lowercased(),
              isPixivArtworkHost(host) else {
            return nil
        }

        if redirectsFollowed < 3,
           let redirectURL = returnToURL(from: url),
           redirectURL.absoluteString != url.absoluteString,
           let canonical = canonicalInputURL(for: redirectURL, redirectsFollowed: redirectsFollowed + 1) {
            return canonical
        }

        if let artworkID = artworkID(from: url) {
            return artworkURL(for: artworkID, sourceURL: url)
        }

        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true).map { String($0).removingPercentEncoding ?? String($0) }
        let lowered = parts.map { $0.lowercased() }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if lowered.first == "search_user.php",
           let nickname = items.first(where: { $0.name.lowercased() == "nick" })?.value?.trimmed,
           !nickname.isEmpty {
            var components = URLComponents()
            components.scheme = "https"
            components.host = "pixiv.me"
            components.path = "/\(nickname)"
            return components.url
        }

        if isPixivVanityProfileURL(url) {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.scheme = "https"
            components?.queryItems = nil
            components?.fragment = nil
            return components?.url
        }

        if lowered.first == "member.php",
           let userID = items.first(where: { $0.name.lowercased() == "id" })?.value,
           isNumericID(userID) {
            return userURL(for: userID, sourceURL: url)
        }

        if let request = collectionRequest(from: url) {
            return collectionURL(for: request, sourceURL: url)
        }

        return nil
    }

    private static func returnToURL(from url: URL) -> URL? {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard let value = items.first(where: { $0.name.lowercased() == "return_to" })?.value?.trimmed,
              !value.isEmpty else {
            return nil
        }
        if let absolute = URL(string: value),
           absolute.scheme != nil {
            return absolute
        }
        return URL(string: value, relativeTo: url)?.absoluteURL
    }

    static func userURL(for userID: String, sourceURL: URL) -> URL {
        var components = URLComponents(url: sourceURL, resolvingAgainstBaseURL: false)
        components?.scheme = "https"
        components?.host = sourceURL.host?.lowercased().hasSuffix(".test") == true ? "www.pixiv.test" : "www.pixiv.net"
        components?.path = "/users/\(userID)"
        components?.queryItems = nil
        components?.fragment = nil
        return components?.url ?? URL(string: "https://www.pixiv.net/users/\(userID)")!
    }

    static func collectionURL(for request: PixivCollectionRequest, sourceURL: URL) -> URL {
        var components = URLComponents(url: sourceURL, resolvingAgainstBaseURL: false)
        components?.scheme = "https"
        components?.host = sourceURL.host?.lowercased().hasSuffix(".test") == true ? "www.pixiv.test" : "www.pixiv.net"
        switch request.kind {
        case .userArtworks:
            var pathParts = ["users", request.identifier]
            if let type = request.userArtworkTypes.first {
                pathParts.append(type)
            }
            if let tag = request.userTag, !tag.isEmpty {
                if pathParts.count == 2 {
                    pathParts.append("illusts")
                }
                pathParts.append(tag)
            }
            components?.path = "/" + pathParts.joined(separator: "/")
        case .bookmarks:
            components?.path = "/users/\(request.identifier)/bookmarks/artworks"
        case .tagSearch:
            components?.path = "/en/tags/\(request.identifier)/artworks"
        case .following:
            components?.path = isNumericID(request.identifier) ? "/users/\(request.identifier)/following" : "/bookmark_new_illust.php"
        case .followingR18:
            components?.path = "/bookmark_new_illust_r18.php"
        }
        let canonicalOptions = request.queryOptions.filter { $0.name.lowercased() != "p" }
        components?.queryItems = canonicalOptions.isEmpty ? nil : canonicalOptions
        components?.fragment = nil
        return components?.url ?? URL(string: "https://www.pixiv.net/")!
    }

    private static let searchOptionNames = [
        "p", "order", "mode", "s_mode", "scd", "ecd", "type",
        "wlt", "wgt", "hlt", "hgt", "blt", "bgt", "ratio", "tool"
    ]
    private static let bookmarkOptionNames = ["tag", "offset", "limit", "rest"]
    private static let followingOptionNames = ["p"]

    private static func queryInteger(_ name: String, in items: [URLQueryItem]) -> Int? {
        guard let value = items.first(where: { $0.name.lowercased() == name.lowercased() })?
            .value?
            .trimmed else {
            return nil
        }
        return Int(value)
    }

    private static func bookmarkPageLimit(for request: PixivCollectionRequest) -> Int {
        min(max(1, queryInteger("limit", in: request.queryOptions) ?? originalBookmarkPageLimit), 100)
    }

    private static func userArtworkFilters(parts: [String], lowered: [String], usersIndex: Int) -> (types: [String], tag: String) {
        var types: [String] = []
        var tag = ""
        let afterUser = Array(lowered.dropFirst(usersIndex + 2))
        let originalAfterUser = Array(parts.dropFirst(usersIndex + 2))
        for (index, part) in afterUser.enumerated() {
            switch part {
            case "artworks":
                continue
            case "illustrations", "illusts":
                if !types.contains("illusts") { types.append("illusts") }
            case "manga":
                if !types.contains("manga") { types.append("manga") }
            default:
                if tag.isEmpty, !part.isEmpty {
                    tag = originalAfterUser[index].trimmed
                }
            }
        }
        return (types, tag)
    }

    private static func selectedQueryItems(from items: [URLQueryItem], names: [String]) -> [URLQueryItem] {
        let allowed = Set(names.map { $0.lowercased() })
        var output: [URLQueryItem] = []
        var seen = Set<String>()
        for item in items {
            let key = item.name.lowercased()
            guard allowed.contains(key),
                  !seen.contains(key) else {
                continue
            }
            let value = item.value?.trimmed ?? ""
            guard !value.isEmpty else { continue }
            output.append(URLQueryItem(name: item.name, value: value))
            seen.insert(key)
        }
        return output
    }

    private static func mergedQueryItems(defaults: [URLQueryItem], options: [URLQueryItem]) -> [URLQueryItem] {
        var output = defaults
        for option in options {
            let key = option.name.lowercased()
            if let index = output.firstIndex(where: { $0.name.lowercased() == key }) {
                output[index] = option
            } else {
                output.append(option)
            }
        }
        return output
    }

    private struct RangeSegment {
        var start: Int?
        var end: Int?
    }

    static func maximumRequestedAssetIndex(in expression: String) throws -> Int? {
        let segments = try rangeSegments(from: expression)
        guard !segments.isEmpty else { return nil }
        if segments.contains(where: { $0.end == nil }) { return nil }
        return segments.compactMap(\.end).max()
    }

    private static func rangeSegments(from expression: String) throws -> [RangeSegment] {
        guard !expression.isEmpty else { return [] }
        let compact = expression.filter { !$0.isWhitespace }
        let pieces = compact.components(separatedBy: CharacterSet(charactersIn: ",;"))
            .filter { !$0.isEmpty }
        guard !pieces.isEmpty else {
            throw NativeDownloadError.unsupported("Invalid range.")
        }
        return try pieces.map { piece in
            if let split = rangeSplit(piece) {
                let start = try positiveRangeBound(split.0)
                let end = try positiveRangeBound(split.1)
                guard start != nil || end != nil else {
                    throw NativeDownloadError.unsupported("Invalid range.")
                }
                if let start, let end, start > end {
                    throw NativeDownloadError.unsupported("Invalid range.")
                }
                return RangeSegment(start: start, end: end)
            }
            guard let index = Int(piece), index > 0 else {
                throw NativeDownloadError.unsupported("Invalid range.")
            }
            return RangeSegment(start: index, end: index)
        }
    }

    private static func rangeSplit(_ value: String) -> (String, String)? {
        for separator in ["...", "..", "~", "-"] {
            if let range = value.range(of: separator) {
                return (String(value[..<range.lowerBound]), String(value[range.upperBound...]))
            }
        }
        return nil
    }

    private static func positiveRangeBound(_ value: String) throws -> Int? {
        guard !value.isEmpty else { return nil }
        guard let bound = Int(value), bound > 0 else {
            throw NativeDownloadError.unsupported("Invalid range.")
        }
        return bound
    }

    private static func uniqueIDs(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { id in
            guard !seen.contains(id) else { return false }
            seen.insert(id)
            return true
        }
    }

    private static func collectionBodyRoots(from object: Any) -> [[String: Any]] {
        var roots: [[String: Any]] = []
        if let dict = object as? [String: Any] {
            roots.append(dict)
            if let body = dict["body"] as? [String: Any] {
                roots.append(body)
            }
        }
        return roots
    }

    private static func collectUserArtworkIDs(in value: Any, tag: String?, output: inout [String]) {
        if let table = value as? [String: Any] {
            let orderedKeys = table.keys
                .filter(isNumericID)
                .sorted { (Int($0) ?? 0) > (Int($1) ?? 0) }
            for key in orderedKeys {
                let child = table[key]
                if tagMatches(child, tag: tag) {
                    output.append(key)
                }
            }
            for (key, child) in table where !isNumericID(key) {
                collectUserArtworkIDs(in: child, tag: tag, output: &output)
            }
            return
        }

        if let array = value as? [Any] {
            for item in array {
                if let dict = item as? [String: Any],
                   let id = stringValue(dict["id"]) ?? stringValue(dict["illustId"]) ?? stringValue(dict["illustID"]) ?? stringValue(dict["illust_id"]),
                   isNumericID(id),
                   tagMatches(dict, tag: tag) {
                    output.append(id)
                } else {
                    collectUserArtworkIDs(in: item, tag: tag, output: &output)
                }
            }
        }
    }

    private static func tagMatches(_ value: Any?, tag: String?) -> Bool {
        guard let tag, !tag.isEmpty else { return true }
        let normalizedTag = normalizedTagLabel(tag)
        return tagLabels(in: value).contains(normalizedTag)
    }

    private static func tagLabels(in value: Any?) -> Set<String> {
        var output = Set<String>()
        collectTagLabels(in: value, output: &output)
        return output
    }

    private static func collectTagLabels(in value: Any?, output: inout Set<String>) {
        if let string = stringValue(value) {
            let normalized = normalizedTagLabel(string)
            if !normalized.isEmpty {
                output.insert(normalized)
            }
            return
        }

        if let array = value as? [Any] {
            for item in array {
                collectTagLabels(in: item, output: &output)
            }
            return
        }

        guard let dict = value as? [String: Any] else { return }
        for key in ["tags", "tag", "tagList", "tag_list", "userTags", "user_tags"] {
            collectTagLabels(in: dict[key], output: &output)
        }
        for key in ["name", "tag", "romaji", "translation", "translated_name"] {
            if let raw = stringValue(dict[key]) {
                let normalized = normalizedTagLabel(raw)
                if !normalized.isEmpty {
                    output.insert(normalized)
                }
            }
        }
    }

    private static func normalizedTagLabel(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "+", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    static func detail(from data: Data, artworkID: String) throws -> PixivArtworkDetail {
        let object = try jsonObject(from: data)
        let body = dictionary(at: ["body"], in: object) ?? object
        if body["noLoginData"] != nil {
            throw PixivArtworkResolverError.authenticationRequired
        }
        let id = stringValue(body["id"]) ?? artworkID
        let title = cleanTitle(stringValue(body["title"]) ?? stringValue(body["illustTitle"]) ?? "Pixiv \(id)")
        let userName = cleanTitle(stringValue(body["userName"]) ?? stringValue(body["user_name"]) ?? stringValue(body["userAccount"]) ?? "")
        let userID = stringValue(body["userId"]) ??
            stringValue(body["user_id"]) ??
            stringValue(body["userID"]) ??
            stringValue(body["user"])
        let type = intValue(body["illustType"]) ?? intValue(body["illust_type"]) ?? 0
        let original = (body["urls"] as? [String: Any]).flatMap { stringValue($0["original"]) }
        let createDateRaw = stringValue(body["createDate"]) ?? stringValue(body["create_date"]) ?? ""
        let createDate = parsePixivDate(createDateRaw)
        let tags = pixivTags(from: body["tags"])
        return PixivArtworkDetail(
            id: id,
            title: title,
            userName: userName,
            userID: userID ?? "",
            isUgoira: type == 2,
            originalURL: original,
            createDateRaw: createDateRaw,
            createDate: createDate,
            tags: tags
        )
    }

    static func pagesDownload(from data: Data, detail: PixivArtworkDetail, pageURL: URL) throws -> ResolvedDownload {
        let object = try jsonObject(from: data)
        let pages = object["body"] as? [[String: Any]] ?? object["pages"] as? [[String: Any]] ?? []
        var assets: [ResolvedAsset] = []
        var seen = Set<String>()

        for page in pages {
            let urls = page["urls"] as? [String: Any] ?? page
            guard let raw = stringValue(urls["original"]) ?? stringValue(urls["regular"]),
                  let remote = normalizedURL(raw, baseURL: pageURL) else {
                continue
            }
            let normalized = URLIdentity.normalize(remote.absoluteString)
            guard !seen.contains(normalized) else { continue }
            seen.insert(normalized)
            let index = assets.count
            assets.append(ResolvedAsset(
                remoteURL: remote,
                filename: imageFilename(for: remote, detail: detail, index: index),
                metadata: imageAssetMetadata(for: remote, detail: detail, pageURL: pageURL, index: index),
                referer: pageURL.absoluteString
            ))
        }

        guard !assets.isEmpty else {
            throw NativeDownloadError.noFiles
        }
        return resolvedDownload(detail: detail, assets: assets)
    }

    static func singleImageDownload(from detail: PixivArtworkDetail, pageURL: URL) throws -> ResolvedDownload {
        guard let raw = detail.originalURL,
              let remote = normalizedURL(raw, baseURL: pageURL) else {
            throw NativeDownloadError.noFiles
        }
        return resolvedDownload(detail: detail, assets: [
            ResolvedAsset(
                remoteURL: remote,
                filename: imageFilename(for: remote, detail: detail, index: 0),
                metadata: imageAssetMetadata(for: remote, detail: detail, pageURL: pageURL, index: 0),
                referer: pageURL.absoluteString
            )
        ])
    }

    static func ugoiraDownload(
        from data: Data,
        detail: PixivArtworkDetail,
        pageURL: URL,
        fileFormat: PixivUgoiraFileFormat = .ugoira,
        dither: Bool = true,
        quality: Int = 90
    ) throws -> ResolvedDownload {
        let object = try jsonObject(from: data)
        let body = dictionary(at: ["body"], in: object) ?? object
        let raw = stringValue(body["originalSrc"]) ??
            stringValue(body["original_src"]) ??
            stringValue(body["src"])
        guard let raw, let remote = normalizedURL(raw, baseURL: pageURL) else {
            throw NativeDownloadError.noFiles
        }

        let frames = ugoiraFrames(from: body["frames"])
        var asset = ResolvedAsset(
            remoteURL: remote,
            filename: ugoiraFilename(for: detail, fileFormat: fileFormat),
            metadata: ugoiraAssetMetadata(for: remote, detail: detail, pageURL: pageURL, fileFormat: fileFormat, frameCount: frames.count),
            referer: pageURL.absoluteString
        )
        if fileFormat != .zip, !frames.isEmpty {
            asset.pixivUgoiraPackage = PixivUgoiraPackage(
                frames: frames,
                artworkURL: pageURL.absoluteString,
                outputFormat: fileFormat,
                dither: dither,
                quality: min(max(1, quality), 100)
            )
        }

        var resolved = resolvedDownload(detail: detail, assets: [
            asset
        ])
        resolved.metadata["type"] = "ugoira"
        resolved.metadata["media_type"] = "ugoira"
        resolved.metadata["format"] = fileFormat.rawValue
        resolved.metadata["media_format"] = fileFormat.rawValue
        if !frames.isEmpty {
            resolved.metadata["frame_count"] = String(frames.count)
        }
        resolved.metadata["ugoira_source_zip"] = remote.absoluteString
        return resolved
    }

    private static func ugoiraFrames(from value: Any?) -> [PixivUgoiraFrame] {
        guard let array = value as? [Any] else { return [] }
        return array.compactMap { item in
            guard let dictionary = item as? [String: Any],
                  let file = stringValue(dictionary["file"])?.trimmed,
                  !file.isEmpty else {
                return nil
            }
            let delay = intValue(dictionary["delay"]) ?? 0
            return PixivUgoiraFrame(file: file, delay: max(0, delay))
        }
    }

    static func rawUgoiraZipDownload(from data: Data, detail: PixivArtworkDetail, pageURL: URL) throws -> ResolvedDownload {
        let object = try jsonObject(from: data)
        let body = dictionary(at: ["body"], in: object) ?? object
        let raw = stringValue(body["originalSrc"]) ??
            stringValue(body["original_src"]) ??
            stringValue(body["src"])
        guard let raw, let remote = normalizedURL(raw, baseURL: pageURL) else {
            throw NativeDownloadError.noFiles
        }
        var resolved = resolvedDownload(detail: detail, assets: [
            ResolvedAsset(
                remoteURL: remote,
                filename: ugoiraFilename(for: detail, fileFormat: .zip),
                metadata: ugoiraAssetMetadata(for: remote, detail: detail, pageURL: pageURL, fileFormat: .zip, frameCount: 0),
                referer: pageURL.absoluteString
            )
        ])
        resolved.metadata["type"] = "ugoira"
        resolved.metadata["media_type"] = "ugoira"
        resolved.metadata["format"] = "zip"
        resolved.metadata["media_format"] = "zip"
        resolved.metadata["ugoira_source_zip"] = remote.absoluteString
        return resolved
    }

    static func ugoiraFilename(for detail: PixivArtworkDetail, fileFormat: PixivUgoiraFileFormat) -> String {
        "\(detail.id)-ugoira.\(fileFormat.rawValue)".sanitizedFilename(maxLength: 180)
    }

    private static func resolvedDownload(detail: PixivArtworkDetail, assets: [ResolvedAsset]) -> ResolvedDownload {
        let display = "\(detail.title) (pixiv_illust_\(detail.id))"
        let imageCount = assets.filter { ($0.metadata["media_type"] ?? $0.metadata["type"]) == "image" }.count
        let ugoiraCount = assets.filter { ($0.metadata["media_type"] ?? $0.metadata["type"]) == "ugoira" }.count
        let primaryType = ugoiraCount > 0 && imageCount == 0 ? "ugoira" : "image"
        return ResolvedDownload(
            title: display.sanitizedFilename(maxLength: 120),
            folderName: display.sanitizedFilename(maxLength: 120),
            assets: assets,
            metadata: DownloadMetadata.clean([
                "id": detail.id,
                "post_id": detail.id,
                "media_id": detail.id,
                "gallery_id": detail.id,
                "site": "Pixiv",
                "title": detail.title,
                "type": primaryType,
                "media_type": primaryType,
                "media_count": String(assets.count),
                "image_count": imageCount > 0 ? String(imageCount) : "",
                "ugoira_count": ugoiraCount > 0 ? String(ugoiraCount) : "",
                "artist": detail.userName,
                "author": detail.userName,
                "creator": detail.userName,
                "username": detail.userName,
                "user": detail.userName,
                "artistid": detail.userID,
                "artist_id": detail.userID,
                "user_id": detail.userID,
                "uid": detail.userID,
                "uploader_id": detail.userID,
                "channel_id": detail.userID,
                "date": pixivDateTimestamp(detail),
                "created_at": detail.createDateRaw,
                "tags": detail.tags.joined(separator: ", ")
            ])
        )
    }

    private static func imageAssetMetadata(for url: URL, detail: PixivArtworkDetail, pageURL: URL, index: Int) -> [String: String] {
        let format = mediaFormat(for: url)
        return DownloadMetadata.clean([
            "site": "Pixiv",
            "title": detail.title,
            "type": "image",
            "media_type": "image",
            "id": detail.id,
            "post_id": detail.id,
            "illust_id": detail.id,
            "artwork_id": detail.id,
            "gallery_id": detail.id,
            "media_id": "\(detail.id)_p\(index)",
            "page": String(index + 1),
            "position": String(index + 1),
            "page_index": String(index),
            "format": format,
            "media_format": format,
            "image_url": url.absoluteString,
            "media_url": url.absoluteString,
            "source_url": url.absoluteString,
            "page_url": pageURL.absoluteString,
            "artist": detail.userName,
            "author": detail.userName,
            "creator": detail.userName,
            "username": detail.userName,
            "user": detail.userName,
            "artistid": detail.userID,
            "artist_id": detail.userID,
            "user_id": detail.userID,
            "uid": detail.userID,
            "uploader_id": detail.userID,
            "channel_id": detail.userID,
            "date": pixivDateTimestamp(detail),
            "created_at": detail.createDateRaw,
            "original_modification_time": pixivDateTimestamp(detail),
            "tags": detail.tags.joined(separator: ", ")
        ])
    }

    private static func ugoiraAssetMetadata(for url: URL, detail: PixivArtworkDetail, pageURL: URL, fileFormat: PixivUgoiraFileFormat, frameCount: Int) -> [String: String] {
        DownloadMetadata.clean([
            "site": "Pixiv",
            "title": detail.title,
            "type": "ugoira",
            "media_type": "ugoira",
            "id": detail.id,
            "post_id": detail.id,
            "illust_id": detail.id,
            "artwork_id": detail.id,
            "gallery_id": detail.id,
            "media_id": "\(detail.id)-ugoira",
            "page": "1",
            "position": "1",
            "format": fileFormat.rawValue,
            "media_format": fileFormat.rawValue,
            "media_url": url.absoluteString,
            "source_url": url.absoluteString,
            "ugoira_source_zip": url.absoluteString,
            "page_url": pageURL.absoluteString,
            "frame_count": frameCount > 0 ? String(frameCount) : "",
            "artist": detail.userName,
            "author": detail.userName,
            "creator": detail.userName,
            "username": detail.userName,
            "user": detail.userName,
            "artistid": detail.userID,
            "artist_id": detail.userID,
            "user_id": detail.userID,
            "uid": detail.userID,
            "uploader_id": detail.userID,
            "channel_id": detail.userID,
            "date": pixivDateTimestamp(detail),
            "created_at": detail.createDateRaw,
            "original_modification_time": pixivDateTimestamp(detail),
            "tags": detail.tags.joined(separator: ", ")
        ])
    }

    private static func imageFilename(for url: URL, detail: PixivArtworkDetail, index: Int) -> String {
        let ext = url.pathExtension.trimmed.isEmpty ? "jpg" : url.pathExtension
        return "\(detail.id)_p\(index).\(ext)".sanitizedFilename(maxLength: 180)
    }

    private static func mediaFormat(for url: URL) -> String {
        let ext = url.pathExtension.trimmed.lowercased()
        return ext.isEmpty ? "jpg" : ext
    }

    private static func pixivDateTimestamp(_ detail: PixivArtworkDetail) -> String {
        if let createDate = detail.createDate {
            return String(Int(createDate.timeIntervalSince1970))
        }
        return detail.createDateRaw
    }

    private static func parsePixivDate(_ value: String) -> Date? {
        let value = value.trimmed
        guard !value.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    private static func pixivTags(from value: Any?) -> [String] {
        let raw: [Any]
        if let dictionary = value as? [String: Any],
           let tags = dictionary["tags"] as? [Any] {
            raw = tags
        } else if let tags = value as? [Any] {
            raw = tags
        } else {
            return []
        }

        var seen = Set<String>()
        return raw.compactMap { item in
            let tag: String?
            if let dictionary = item as? [String: Any] {
                tag = stringValue(dictionary["tag"]) ?? stringValue(dictionary["name"])
            } else {
                tag = stringValue(item)
            }
            guard let tag = tag?.trimmed,
                  !tag.isEmpty,
                  seen.insert(tag.lowercased()).inserted else {
                return nil
            }
            return tag
        }
    }

    private static func apiURL(path: String, sourceURL: URL, queryItems: [URLQueryItem]? = nil) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = sourceURL.host?.lowercased().hasSuffix(".test") == true ? "www.pixiv.test" : "www.pixiv.net"
        components.path = path
        components.queryItems = queryItems
        return components.url!
    }

    private func apiDataResponse(
        from url: URL,
        referer: String?,
        userAgent: String?,
        additionalHeaders: [String: String],
        acceptedStatusCodes: Set<Int> = []
    ) async throws -> (Data, HTTPURLResponse) {
        try await apiRateLimiter.waitIfNeeded(for: url)
        return try await HTTPClient.shared.dataResponse(
            from: url,
            referer: referer,
            userAgent: userAgent,
            additionalHeaders: additionalHeaders,
            acceptedStatusCodes: acceptedStatusCodes
        )
    }

    private func resolvedVanityProfileURL(_ url: URL, headers: HTTPRequestOptions) async throws -> URL {
        let (data, response) = try await HTTPClient.shared.dataResponse(
            from: url,
            referer: headers.referer ?? "https://www.pixiv.net/",
            userAgent: headers.userAgent
        )
        if let finalURL = response.url,
           !Self.isPixivVanityProfileURL(finalURL),
           Self.collectionRequest(from: finalURL) != nil {
            return finalURL
        }

        let html = String(decoding: data, as: UTF8.self)
        if let range = html.range(of: #"(?:www\.)?pixiv\.net/(?:en/)?users/([0-9]+)"#, options: .regularExpression) {
            let match = String(html[range])
            if let idRange = match.range(of: #"[0-9]+$"#, options: .regularExpression) {
                return Self.userURL(for: String(match[idRange]), sourceURL: url)
            }
        }
        throw NativeDownloadError.unsupported("Pixiv profile could not be resolved: \(url.absoluteString)")
    }

    static func pixivUserID(fromSessionValue value: String?) -> String? {
        guard let value = value?.trimmed,
              let range = value.range(of: #"^[0-9]+"#, options: .regularExpression) else {
            return nil
        }
        return String(value[range])
    }

    static func apiHeaders(sessionValue: String?) -> [String: String] {
        var fields = [
            "Accept": "application/json",
            "Accept-Encoding": "gzip, deflate",
            "Accept-Language": "en-US,en;q=0.9,ko-KR;q=0.8,ko;q=0.7,ja;q=0.6",
            "Cache-Control": "no-cache",
            "Pragma": "no-cache",
            "Referer": "https://www.pixiv.net/",
            "X-Requested-With": "XMLHttpRequest"
        ]
        if let userID = pixivUserID(fromSessionValue: sessionValue) {
            fields["X-User-Id"] = userID
        }
        return fields
    }

    private static func apiHeaders(for sourceURL: URL) async throws -> [String: String] {
        if sourceURL.host?.lowercased().hasSuffix(".test") == true {
            return apiHeaders(sessionValue: nil)
        }
        let cookieURL = URL(string: "https://www.pixiv.net/")!
        let sessionValue = await CookieStore.shared.cookieValue(named: "PHPSESSID", for: cookieURL)
        guard pixivUserID(fromSessionValue: sessionValue) != nil else {
            throw PixivArtworkResolverError.authenticationRequired
        }
        return apiHeaders(sessionValue: sessionValue)
    }

    private static func requestByResolvingCurrentUser(
        _ request: PixivCollectionRequest,
        apiHeaderFields: [String: String]
    ) throws -> PixivCollectionRequest {
        guard request.identifier == "me" else { return request }
        guard let userID = apiHeaderFields["X-User-Id"] else {
            throw PixivArtworkResolverError.authenticationRequired
        }
        var resolved = request
        resolved.identifier = userID
        resolved.title = "My Bookmarks"
        return resolved
    }

    private static func bookmarkRestValues(
        for request: PixivCollectionRequest,
        apiHeaderFields: [String: String]
    ) -> [String?] {
        guard request.kind == .bookmarks else { return [nil] }
        if let explicit = request.queryOptions.first(where: { $0.name.lowercased() == "rest" })?.value?.trimmed,
           !explicit.isEmpty {
            return [explicit]
        }
        if request.identifier == apiHeaderFields["X-User-Id"] {
            return ["show", "hide"]
        }
        return ["show"]
    }

    private static func normalizedURL(_ raw: String, baseURL: URL) -> URL? {
        let value = raw.trimmed
        guard !value.isEmpty else { return nil }
        if value.hasPrefix("//") {
            return URL(string: "\(baseURL.scheme ?? "https"):\(value)")
        }
        return URL(string: value, relativeTo: baseURL)?.absoluteURL
    }

    private static func jsonObject(from data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NativeDownloadError.invalidGalleryData
        }
        if apiErrorMessage(in: object) != nil {
            throw PixivArtworkResolverError.authenticationRequired
        }
        return object
    }

    private static func apiErrorMessage(in object: [String: Any]) -> String? {
        guard boolValue(object["error"]) == true else { return nil }
        let message = firstMessage(in: object)
        if let message, !message.isEmpty {
            return "Pixiv API error: \(message)"
        }
        return "Pixiv API returned an error."
    }

    private static func firstMessage(in object: [String: Any]) -> String? {
        for key in ["message", "errorMessage", "error_message", "msg", "reason", "description"] {
            if let message = stringValue(object[key])?.trimmed, !message.isEmpty {
                return message
            }
        }
        if let body = object["body"] as? [String: Any] {
            return firstMessage(in: body)
        }
        if let errors = object["errors"] as? [String: Any] {
            return firstMessage(in: errors)
        }
        return nil
    }

    private static func dictionary(at path: [String], in object: [String: Any]) -> [String: Any]? {
        var current: Any = object
        for key in path {
            guard let dictionary = current as? [String: Any],
                  let next = dictionary[key] else {
                return nil
            }
            current = next
        }
        return current as? [String: Any]
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        if let int = value as? Int { return String(int) }
        if let double = value as? Double { return String(Int(double)) }
        return nil
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let string = value as? String { return Int(string) }
        if let double = value as? Double { return Int(double) }
        return nil
    }

    private static func boolValue(_ value: Any?) -> Bool? {
        if let bool = value as? Bool { return bool }
        if let int = value as? Int { return int != 0 }
        if let string = value as? String {
            switch string.trimmed.lowercased() {
            case "true", "yes", "1": return true
            case "false", "no", "0": return false
            default: return nil
            }
        }
        return nil
    }

    private static func collectArtworkIDs(in value: Any, output: inout [String]) {
        if let array = value as? [Any] {
            for item in array {
                if let raw = stringValue(item), isNumericID(raw) {
                    output.append(raw)
                    continue
                }
                collectArtworkIDs(in: item, output: &output)
            }
            return
        }

        guard let dictionary = value as? [String: Any] else {
            return
        }

        appendArtworkIDFields(in: dictionary, output: &output)

        for key in ["illusts", "manga"] {
            guard let table = dictionary[key] else { continue }
            if let table = table as? [String: Any] {
                let ids = table.keys
                    .filter(isNumericID)
                    .sorted { (Int($0) ?? 0) > (Int($1) ?? 0) }
                output.append(contentsOf: ids)
                for child in table.values {
                    collectArtworkIDs(in: child, output: &output)
                }
            } else {
                collectArtworkIDs(in: table, output: &output)
            }
        }

        for key in ["body", "works", "data", "illustManga", "thumbnails", "illust", "items", "contents"] {
            if let child = dictionary[key] {
                collectArtworkIDs(in: child, output: &output)
            }
        }
    }

    private static func appendArtworkIDFields(in dictionary: [String: Any], output: inout [String]) {
        for key in ["id", "illustId", "illustID", "illust_id"] {
            if let id = stringValue(dictionary[key]), isNumericID(id) {
                output.append(id)
            }
        }
    }

    private static func isNumericID(_ value: String) -> Bool {
        value.range(of: #"^[0-9]+$"#, options: .regularExpression) != nil
    }

    private static func cleanTitle(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmed
            .sanitizedFilename(maxLength: 120)
    }

    private static func isPixivArtworkHost(_ host: String) -> Bool {
        host == "pixiv.net" ||
            host == "www.pixiv.net" ||
            host == "pixiv.com" ||
            host == "www.pixiv.com" ||
            host == "pixiv.co" ||
            host == "www.pixiv.co" ||
            host == "pixiv.me" ||
            host.hasSuffix(".pixiv.me") ||
            host == "pixiv.test" ||
            host == "www.pixiv.test"
    }

    private static func isPixivVanityProfileURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(),
              host == "pixiv.me" || host.hasSuffix(".pixiv.me") else {
            return false
        }
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true)
        return parts.count == 1 && !parts[0].isEmpty
    }
}

struct PixivArtworkDetail {
    var id: String
    var title: String
    var userName: String
    var userID: String
    var isUgoira: Bool
    var originalURL: String?
    var createDateRaw: String
    var createDate: Date?
    var tags: [String]
}

private enum PixivCollectionArtworkResult {
    case resolved(offset: Int, download: ResolvedDownload)
    case failed(offset: Int)
    case filtered(offset: Int)
}

private actor PixivResolutionSemaphore {
    private var value: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(value: Int) {
        self.value = max(1, value)
    }

    func wait() async {
        if value > 0 {
            value -= 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func signal() {
        if waiters.isEmpty {
            value += 1
        } else {
            waiters.removeFirst().resume()
        }
    }

    func withPermit<T: Sendable>(
        _ operation: @Sendable () async throws -> T
    ) async throws -> T {
        await wait()
        do {
            try Task.checkCancellation()
            let result = try await operation()
            signal()
            return result
        } catch {
            signal()
            throw error
        }
    }
}

private actor PixivAPIRateLimiter {
    private let maximumCalls = 2
    private let interval: TimeInterval = 3
    private var requestTimes: [Date] = []

    func waitIfNeeded(for url: URL) async throws {
        if url.host?.lowercased().hasSuffix(".test") == true { return }
        while true {
            try Task.checkCancellation()
            let now = Date()
            requestTimes.removeAll { now.timeIntervalSince($0) >= interval }
            if requestTimes.count < maximumCalls {
                requestTimes.append(now)
                return
            }
            let delay = max(0.01, interval - now.timeIntervalSince(requestTimes[0]))
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
    }
}
