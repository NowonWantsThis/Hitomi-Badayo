import CryptoKit
import Foundation

enum BilibiliCollectionKind: String, Equatable {
    case space
    case season

    var category: String {
        switch self {
        case .space: return "videos"
        case .season: return "collection"
        }
    }
}

struct BilibiliCollectionRequest: Equatable {
    var kind: BilibiliCollectionKind
    var mid: String
    var seasonID: String?
    var sourceURL: URL
}

struct BilibiliCollectionEntry: Equatable {
    var id: String
    var bvid: String
    var aid: String
    var title: String
    var author: String
    var thumbnailURL: URL?
    var pageURL: URL
}

struct BilibiliCollectionPage: Equatable {
    var entries: [BilibiliCollectionEntry]
    var totalCount: Int?
    var title: String?
}

struct BilibiliWBIKeys: Equatable {
    var imageKey: String
    var subKey: String
}

final class BilibiliCollectionResolver {
    static let defaultCollectionItemLimit = 2_000
    private static let pageSize = 30
    private static let defaultUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/126.0 Safari/537.36"

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
        let itemRange = rangeExpression.trimmed
        let itemLimit = try Self.collectionItemLimit(for: itemRange)
        let profile: (name: String, thumbnail: URL?)
        let wbiKeys: BilibiliWBIKeys?
        switch request.kind {
        case .space:
            let keys = try await fetchWBIKeys(request: request, userAgent: userAgent)
            wbiKeys = keys
            profile = try await fetchProfile(request: request, keys: keys, userAgent: userAgent)
        case .season:
            wbiKeys = nil
            profile = ("Bilibili \(request.mid)", nil)
        }

        var entries: [BilibiliCollectionEntry] = []
        var seen = Set<String>()
        var collectionTitle: String?
        var declaredTotal: Int?
        var fetchedPageCount = 0
        var pageNumber = 1
        while entries.count < itemLimit {
            try Task.checkCancellation()
            let apiURL: URL
            switch request.kind {
            case .space:
                guard let wbiKeys else { throw NativeDownloadError.invalidGalleryData }
                apiURL = Self.signedAPIURL(
                    path: "/x/space/wbi/arc/search",
                    parameters: Self.webRiskParameters.merging([
                        "mid": request.mid,
                        "pn": String(pageNumber),
                        "ps": String(Self.pageSize),
                        "order": "pubdate",
                        "index": "1",
                        "order_avoided": "true",
                        "platform": "web",
                        "web_location": "333.1387"
                    ]) { current, _ in current },
                    request: request,
                    keys: wbiKeys
                )
            case .season:
                apiURL = Self.seasonPageURL(request: request, page: pageNumber)
            }
            let object = try await apiObject(
                from: apiURL,
                request: request,
                userAgent: userAgent
            )
            try Self.validateAPIResponse(object, request: request)
            let page = try Self.collectionPage(from: object, request: request)
            fetchedPageCount += 1
            if collectionTitle == nil, let title = page.title?.trimmed, !title.isEmpty {
                collectionTitle = title
            }
            if declaredTotal == nil { declaredTotal = page.totalCount }
            guard !page.entries.isEmpty else { break }
            let previousCount = entries.count
            for entry in page.entries where seen.insert(entry.id).inserted {
                entries.append(entry)
                if entries.count >= itemLimit { break }
            }
            guard entries.count > previousCount else { break }
            if let total = page.totalCount ?? declaredTotal, seen.count >= total { break }
            pageNumber += 1
        }
        guard !entries.isEmpty else { throw NativeDownloadError.noFiles }

        let listedItemCount = entries.count
        var selectedPositions: [Int]?
        if !itemRange.isEmpty {
            let indexes = try Self.itemIndexes(for: itemRange, total: entries.count)
            entries = indexes.map { entries[$0] }
            selectedPositions = indexes.map { $0 + 1 }
        }

        let pageResolver = BilibiliResolver()
        var posts: [(entry: BilibiliCollectionEntry, download: ResolvedDownload)] = []
        var failures: [Error] = []
        for entry in entries {
            try Task.checkCancellation()
            do {
                let resolved = try await pageResolver.resolve(entry.pageURL, headers: headers)
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

        let entryAuthor = entries.first?.author.trimmed ?? ""
        let profileName = request.kind == .season && !entryAuthor.isEmpty
            ? entryAuthor
            : profile.name
        let title = collectionTitle ?? profileName
        var combined = try Self.combinedDownload(
            request: request,
            collectionTitle: title,
            profileName: profileName,
            profileThumbnail: profile.thumbnail,
            posts: posts
        )
        combined.metadata["listed_item_count"] = String(listedItemCount)
        combined.metadata["collection_pages"] = String(fetchedPageCount)
        if let declaredTotal {
            combined.metadata["collection_total"] = String(declaredTotal)
        }
        if let selectedPositions {
            combined.metadata["range"] = itemRange
            combined.metadata["range_scope"] = "collection_items"
            combined.metadata["range_total"] = String(declaredTotal ?? listedItemCount)
            combined.metadata["range_selected"] = String(selectedPositions.count)
            combined.metadata["range_indexes"] = selectedPositions.map(String.init).joined(separator: ",")
        }
        if !failures.isEmpty {
            combined.metadata["skipped_count"] = String(failures.count)
            combined.metadata["resolved_item_count"] = String(posts.count)
        }
        return combined
    }

    static func request(from url: URL) -> BilibiliCollectionRequest? {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host?.lowercased() else {
            return nil
        }
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        let lower = parts.map { $0.lowercased() }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []

        if isSpaceHost(host),
           let mid = parts.first,
           isNumericID(mid) {
            let seasonID = queryValue(names: ["sid", "season_id"], items: query)
                .flatMap { isNumericID($0) ? $0 : nil }
            let remainder = Array(lower.dropFirst())
            let isSeasonPath = remainder.starts(with: ["channel", "collectiondetail"])
            let isSpacePath = remainder.isEmpty ||
                remainder == ["video"] ||
                remainder == ["videos"] ||
                remainder == ["upload", "video"] ||
                remainder == ["channel", "index"]
            guard (isSeasonPath && seasonID != nil) || isSpacePath else { return nil }
            return canonicalRequest(
                mid: mid,
                seasonID: isSeasonPath ? seasonID : nil,
                testHost: host.hasSuffix(".test")
            )
        }

        if isWebHost(host),
           lower.count >= 3,
           lower[0] == "medialist",
           lower[1] == "play",
           isNumericID(parts[2]),
           let seasonID = queryValue(names: ["business_id", "sid", "season_id"], items: query),
           isNumericID(seasonID) {
            return canonicalRequest(
                mid: parts[2],
                seasonID: seasonID,
                testHost: host.hasSuffix(".test")
            )
        }
        return nil
    }

    static func wbiKeys(from object: [String: Any]) throws -> BilibiliWBIKeys {
        guard let data = object["data"] as? [String: Any],
              let images = data["wbi_img"] as? [String: Any],
              let imageURL = stringValue(images["img_url"]),
              let subURL = stringValue(images["sub_url"]),
              let imageKey = resourceKey(from: imageURL),
              let subKey = resourceKey(from: subURL) else {
            throw NativeDownloadError.invalidGalleryData
        }
        return BilibiliWBIKeys(imageKey: imageKey, subKey: subKey)
    }

    static func signedQuery(
        parameters: [String: String],
        keys: BilibiliWBIKeys,
        timestamp: Int
    ) -> String {
        var values = parameters
        values["wts"] = String(timestamp)
        let query = values.keys.sorted().map { key in
            let value = values[key, default: ""]
                .filter { !"!'()*".contains($0) }
            return "\(percentEncode(key))=\(percentEncode(value))"
        }.joined(separator: "&")
        let digest = Insecure.MD5.hash(data: Data((query + mixinKey(keys)).utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return "\(query)&w_rid=\(digest)"
    }

    static func collectionPage(
        from object: [String: Any],
        request: BilibiliCollectionRequest
    ) throws -> BilibiliCollectionPage {
        guard let data = object["data"] as? [String: Any] else {
            throw NativeDownloadError.invalidGalleryData
        }
        let rawEntries: [[String: Any]]
        let total: Int?
        let title: String?
        switch request.kind {
        case .space:
            let list = data["list"] as? [String: Any] ?? [:]
            rawEntries = list["vlist"] as? [[String: Any]] ?? []
            total = integerValue((data["page"] as? [String: Any])?["count"])
            title = nil
        case .season:
            rawEntries = data["archives"] as? [[String: Any]] ??
                data["items"] as? [[String: Any]] ?? []
            let page = data["page"] as? [String: Any]
            let meta = data["meta"] as? [String: Any]
            total = integerValue(page?["total"]) ??
                integerValue(page?["count"]) ??
                integerValue(meta?["total"]) ??
                integerValue(meta?["total_count"])
            title = stringValue(meta?["name"]) ?? stringValue(data["name"])
        }

        var entries: [BilibiliCollectionEntry] = []
        var seen = Set<String>()
        for item in rawEntries {
            let bvid = stringValue(item["bvid"])?.trimmed ?? ""
            let aid = stringValue(item["aid"])?.trimmed ??
                stringValue(item["id"])?.trimmed ?? ""
            let id: String
            let pathID: String
            if bvid.range(of: #"^BV[0-9A-Za-z]+$"#, options: [.caseInsensitive, .regularExpression]) != nil {
                id = bvid
                pathID = bvid
            } else if isNumericID(aid) {
                id = "av\(aid)"
                pathID = id
            } else {
                continue
            }
            guard seen.insert(id.lowercased()).inserted else { continue }
            let pageURL = videoPageURL(pathID: pathID, request: request)
            let thumbnail = stringValue(item["pic"]) ??
                stringValue(item["cover"])
            entries.append(BilibiliCollectionEntry(
                id: id,
                bvid: bvid,
                aid: aid,
                title: cleanText(stringValue(item["title"]) ?? id),
                author: cleanText(stringValue(item["author"]) ?? stringValue(item["name"]) ?? ""),
                thumbnailURL: thumbnail.flatMap { absoluteURL($0, baseURL: request.sourceURL) },
                pageURL: pageURL
            ))
        }
        return BilibiliCollectionPage(entries: entries, totalCount: total, title: title.map(cleanText))
    }

    static func combinedDownload(
        request: BilibiliCollectionRequest,
        collectionTitle rawCollectionTitle: String,
        profileName rawProfileName: String,
        profileThumbnail: URL?,
        posts: [(entry: BilibiliCollectionEntry, download: ResolvedDownload)]
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
                asset.metadata = input.metadata.merging(
                    collectionMetadata(
                        request: request,
                        entry: post.entry,
                        postIndex: postIndex
                    )
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
                    metadata: groupMetadata(request: request, post: post, postIndex: postIndex)
                ))
            case .mux(let videoAssets, let audioAssets, let outputFilename):
                let videoIndexes = try matchingIndexes(of: videoAssets, in: originalAssets)
                let audioIndexes = try matchingIndexes(of: audioAssets, in: originalAssets)
                muxes.append(ResolvedMuxGroup(
                    videoAssetIndexes: videoIndexes.map { offset + $0 },
                    audioAssetIndexes: audioIndexes.map { offset + $0 },
                    outputFilename: prefixedFilename(outputFilename, prefix: prefix),
                    metadata: groupMetadata(request: request, post: post, postIndex: postIndex)
                ))
            case .grouped(let nestedFiles, let nestedConcatenations):
                fileAssetIndexes.append(contentsOf: nestedFiles.map { offset + $0 })
                concatenations.append(contentsOf: nestedConcatenations.map { group in
                    ResolvedConcatenationGroup(
                        assetIndexes: group.assetIndexes.map { offset + $0 },
                        outputFilename: prefixedFilename(group.outputFilename, prefix: prefix),
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
                        outputFilename: prefixedFilename(group.outputFilename, prefix: prefix),
                        metadata: group.metadata.merging(
                            groupMetadata(request: request, post: post, postIndex: postIndex)
                        ) { current, _ in current }
                    )
                })
                muxes.append(contentsOf: nestedMuxes.map { group in
                    ResolvedMuxGroup(
                        videoAssetIndexes: group.videoAssetIndexes.map { offset + $0 },
                        audioAssetIndexes: group.audioAssetIndexes.map { offset + $0 },
                        outputFilename: prefixedFilename(group.outputFilename, prefix: prefix),
                        metadata: group.metadata.merging(
                            groupMetadata(request: request, post: post, postIndex: postIndex)
                        ) { current, _ in current }
                    )
                })
            }
        }

        let collectionTitle = cleanText(rawCollectionTitle)
        let profileName = cleanText(rawProfileName)
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
        let thumbnail = profileThumbnail?.absoluteString ??
            posts.lazy.compactMap { $0.entry.thumbnailURL?.absoluteString }.first ??
            posts.lazy.compactMap { $0.download.metadata["thumbnail"] }.first ?? ""
        return ResolvedDownload(
            title: collectionTitle,
            folderName: collectionTitle.sanitizedFilename(maxLength: 120),
            assets: assets,
            packageMode: packageMode,
            metadata: DownloadMetadata.clean([
                "site": "Bilibili",
                "title": collectionTitle,
                "series": collectionTitle,
                "type": "collection",
                "media_type": "video",
                "category": request.kind.category,
                "collection": "true",
                "playlist": "true",
                "collection_kind": request.kind.rawValue,
                "mid": request.mid,
                "user_id": request.mid,
                "channel_id": request.mid,
                "season_id": request.seasonID ?? "",
                "playlist_id": request.seasonID ?? request.mid,
                "artist": profileName,
                "author": profileName,
                "creator": profileName,
                "uploader": profileName,
                "channel": profileName,
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

    private func fetchWBIKeys(
        request: BilibiliCollectionRequest,
        userAgent: String
    ) async throws -> BilibiliWBIKeys {
        let url = Self.apiURL(path: "/x/web-interface/nav", request: request)
        let object = try await apiObject(from: url, request: request, userAgent: userAgent)
        return try Self.wbiKeys(from: object)
    }

    private func fetchProfile(
        request: BilibiliCollectionRequest,
        keys: BilibiliWBIKeys,
        userAgent: String
    ) async throws -> (name: String, thumbnail: URL?) {
        let url = Self.signedAPIURL(
            path: "/x/space/wbi/acc/info",
            parameters: Self.webRiskParameters.merging([
                "mid": request.mid,
                "platform": "web",
                "web_location": "1550101"
            ]) { current, _ in current },
            request: request,
            keys: keys
        )
        do {
            let object = try await apiObject(from: url, request: request, userAgent: userAgent)
            try Self.validateAPIResponse(object, request: request)
            return try Self.profile(fromAccountObject: object, request: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return try await fetchPublicProfileCard(request: request, userAgent: userAgent)
        }
    }

    private func fetchPublicProfileCard(
        request: BilibiliCollectionRequest,
        userAgent: String
    ) async throws -> (name: String, thumbnail: URL?) {
        let url = Self.apiURL(
            path: "/x/web-interface/card",
            queryItems: [URLQueryItem(name: "mid", value: request.mid)],
            request: request
        )
        let object = try await apiObject(from: url, request: request, userAgent: userAgent)
        try Self.validateAPIResponse(object, request: request)
        return try Self.profile(fromCardObject: object, request: request)
    }

    private func apiObject(
        from url: URL,
        request: BilibiliCollectionRequest,
        userAgent: String
    ) async throws -> [String: Any] {
        let data: Data
        if request.sourceURL.host?.hasSuffix(".test") == true {
            data = try await HTTPClient.shared.data(
                from: url,
                referer: request.sourceURL.absoluteString,
                userAgent: userAgent,
                additionalHeaders: ["Accept": "application/json, text/plain, */*"]
            )
        } else {
            // Bilibili currently rejects CFNetwork's transport fingerprint on WBI APIs.
            data = try await curlAPIData(
                from: url,
                referer: request.sourceURL,
                userAgent: userAgent
            )
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let text = String(decoding: data.prefix(2_048), as: UTF8.self)
            if text.contains("错误号: 412") || text.localizedCaseInsensitiveContains("security control") {
                throw NativeDownloadError.unsupported(
                    "Bilibili rejected this API request. Save Bilibili cookies from the login browser and retry."
                )
            }
            throw NativeDownloadError.invalidGalleryData
        }
        return object
    }

    private func curlAPIData(
        from url: URL,
        referer: URL,
        userAgent: String
    ) async throws -> Data {
        let curlURL = URL(fileURLWithPath: "/usr/bin/curl")
        guard FileManager.default.isExecutableFile(atPath: curlURL.path) else {
            throw NativeDownloadError.unsupported("macOS curl is unavailable for the Bilibili API request.")
        }

        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("HitomiBadayo-bilibili-\(UUID().uuidString)", isDirectory: true)
        let bodyURL = temporaryDirectory.appendingPathComponent("response.json")
        let logURL = temporaryDirectory.appendingPathComponent("curl.log")
        try AppPaths.ensureDirectory(temporaryDirectory)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        var arguments = [
            "--disable",
            "--silent",
            "--show-error",
            "--location",
            "--compressed",
            "--connect-timeout", "15",
            "--max-time", "30",
            "--proto", "=https",
            "--proto-redir", "=https",
            "--user-agent", userAgent,
            "--referer", referer.absoluteString,
            "--header", "Accept: application/json, text/plain, */*"
        ]
        if let proxy = NetworkSettings.load().proxyArgument(for: url) {
            arguments.append(contentsOf: ["--proxy", proxy])
        }

        if let cookieText = await CookieStore.shared.netscapeCookieFile(for: url) {
            let fileURL = temporaryDirectory.appendingPathComponent("cookies.txt")
            try cookieText.write(to: fileURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            arguments.append(contentsOf: ["--cookie", fileURL.path])
        }
        arguments.append(url.absoluteString)

        try await ExternalProcessRunner.run(
            executable: curlURL,
            arguments: arguments,
            logURL: logURL,
            stdoutURL: bodyURL,
            failureDescription: "Bilibili API request"
        )
        let data = try Data(contentsOf: bodyURL)
        guard !data.isEmpty else {
            throw NativeDownloadError.unsupported("Bilibili returned an empty API response.")
        }
        return data
    }

    private static func canonicalRequest(
        mid: String,
        seasonID: String?,
        testHost: Bool
    ) -> BilibiliCollectionRequest? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = testHost ? "space.bilibili.test" : "space.bilibili.com"
        let kind: BilibiliCollectionKind
        if let seasonID {
            kind = .season
            components.path = "/\(mid)/channel/collectiondetail"
            components.queryItems = [URLQueryItem(name: "sid", value: seasonID)]
        } else {
            kind = .space
            components.path = "/\(mid)"
        }
        guard let sourceURL = components.url else { return nil }
        return BilibiliCollectionRequest(
            kind: kind,
            mid: mid,
            seasonID: seasonID,
            sourceURL: sourceURL
        )
    }

    private static func signedAPIURL(
        path: String,
        parameters: [String: String],
        request: BilibiliCollectionRequest,
        keys: BilibiliWBIKeys,
        timestamp: Int = Int(Date().timeIntervalSince1970)
    ) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = request.sourceURL.host?.hasSuffix(".test") == true
            ? "api.bilibili.test"
            : "api.bilibili.com"
        components.path = path
        components.percentEncodedQuery = signedQuery(
            parameters: parameters,
            keys: keys,
            timestamp: timestamp
        )
        return components.url!
    }

    private static func seasonPageURL(
        request: BilibiliCollectionRequest,
        page: Int
    ) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = request.sourceURL.host?.hasSuffix(".test") == true
            ? "api.bilibili.test"
            : "api.bilibili.com"
        components.path = "/x/polymer/web-space/seasons_archives_list"
        components.queryItems = [
            URLQueryItem(name: "mid", value: request.mid),
            URLQueryItem(name: "season_id", value: request.seasonID ?? ""),
            URLQueryItem(name: "page_num", value: String(max(1, page))),
            URLQueryItem(name: "page_size", value: String(pageSize)),
            URLQueryItem(name: "sort_reverse", value: "false")
        ]
        return components.url!
    }

    private static func apiURL(
        path: String,
        queryItems: [URLQueryItem] = [],
        request: BilibiliCollectionRequest
    ) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = request.sourceURL.host?.hasSuffix(".test") == true
            ? "api.bilibili.test"
            : "api.bilibili.com"
        components.path = path
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        return components.url!
    }

    private static func profile(
        fromAccountObject object: [String: Any],
        request: BilibiliCollectionRequest
    ) throws -> (name: String, thumbnail: URL?) {
        guard let data = object["data"] as? [String: Any] else {
            throw NativeDownloadError.invalidGalleryData
        }
        return profile(name: data["name"], face: data["face"], request: request)
    }

    private static func profile(
        fromCardObject object: [String: Any],
        request: BilibiliCollectionRequest
    ) throws -> (name: String, thumbnail: URL?) {
        guard let data = object["data"] as? [String: Any],
              let card = data["card"] as? [String: Any] else {
            throw NativeDownloadError.invalidGalleryData
        }
        return profile(name: card["name"], face: card["face"], request: request)
    }

    private static func profile(
        name: Any?,
        face: Any?,
        request: BilibiliCollectionRequest
    ) -> (name: String, thumbnail: URL?) {
        let resolvedName = cleanText(stringValue(name) ?? "Bilibili \(request.mid)")
        let thumbnail = stringValue(face)
            .flatMap { absoluteURL($0, baseURL: request.sourceURL) }
        return (resolvedName, thumbnail)
    }

    private static func validateAPIResponse(
        _ object: [String: Any],
        request: BilibiliCollectionRequest
    ) throws {
        let code = integerValue(object["code"]) ?? 0
        guard code != 0 else { return }
        let message = stringValue(object["message"]) ?? "Bilibili API error \(code)"
        if [-101, -352, -412].contains(code) {
            let target = request.kind == .season ? "collection" : "space"
            throw NativeDownloadError.unsupported(
                "Bilibili \(target) access requires a valid signed-in session. Save Bilibili cookies from the login browser and retry. (\(message))"
            )
        }
        throw NativeDownloadError.unsupported("Bilibili API error \(code): \(message)")
    }

    private static func videoPageURL(
        pathID: String,
        request: BilibiliCollectionRequest
    ) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = request.sourceURL.host?.hasSuffix(".test") == true
            ? "www.bilibili.test"
            : "www.bilibili.com"
        components.path = "/video/\(pathID)"
        return components.url!
    }

    private static func groupMetadata(
        request: BilibiliCollectionRequest,
        post: (entry: BilibiliCollectionEntry, download: ResolvedDownload),
        postIndex: Int
    ) -> [String: String] {
        post.download.metadata.merging(
            collectionMetadata(request: request, entry: post.entry, postIndex: postIndex)
        ) { current, _ in current }
    }

    private static func collectionMetadata(
        request: BilibiliCollectionRequest,
        entry: BilibiliCollectionEntry,
        postIndex: Int
    ) -> [String: String] {
        DownloadMetadata.clean([
            "collection_index": String(postIndex + 1),
            "collection_item_id": entry.id,
            "collection_url": request.sourceURL.absoluteString,
            "collection_kind": request.kind.rawValue,
            "mid": request.mid,
            "season_id": request.seasonID ?? "",
            "bvid": entry.bvid,
            "aid": entry.aid,
            "item_title": entry.title,
            "item_author": entry.author,
            "item_thumbnail": entry.thumbnailURL?.absoluteString ?? "",
            "item_page_url": entry.pageURL.absoluteString
        ])
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
            throw NativeDownloadError.unsupported("Range did not match any Bilibili collection items.")
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
                throw NativeDownloadError.unsupported("Invalid nested Bilibili mux plan.")
            }
            used.insert(index)
            indexes.append(index)
        }
        return indexes
    }

    private static func mixinKey(_ keys: BilibiliWBIKeys) -> String {
        let source = Array(keys.imageKey + keys.subKey)
        return String(mixinKeyOrder.compactMap { index in
            source.indices.contains(index) ? source[index] : nil
        }.prefix(32))
    }

    private static func resourceKey(from raw: String) -> String? {
        guard let url = URL(string: raw) else { return nil }
        let value = url.deletingPathExtension().lastPathComponent.trimmed
        return value.isEmpty ? nil : value
    }

    private static func percentEncode(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private static func queryValue(
        names: [String],
        items: [URLQueryItem]
    ) -> String? {
        for name in names {
            if let value = items.first(where: { $0.name.lowercased() == name })?.value?.trimmed,
               !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func isNumericID(_ value: String) -> Bool {
        value.range(of: #"^[0-9]+$"#, options: .regularExpression) != nil
    }

    private static func isSpaceHost(_ host: String) -> Bool {
        host == "space.bilibili.com" || host == "space.bilibili.test"
    }

    private static func isWebHost(_ host: String) -> Bool {
        host == "bilibili.com" ||
            host == "www.bilibili.com" ||
            host == "bilibili.test" ||
            host == "www.bilibili.test"
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

    private static let mixinKeyOrder = [
        46, 47, 18, 2, 53, 8, 23, 32, 15, 50, 10, 31, 58, 3, 45, 35,
        27, 43, 5, 49, 33, 9, 42, 19, 29, 28, 14, 39, 12, 38, 41, 13,
        37, 48, 7, 16, 24, 55, 40, 61, 26, 17, 0, 1, 60, 51, 30, 4,
        22, 25, 54, 21, 56, 59, 6, 63, 57, 62, 11, 36, 20, 34, 44, 52
    ]

    private static let webRiskParameters = [
        "dm_img_list": "[]",
        "dm_img_str": "V2ViR0wgMS4wIChPcGVuR0wgRVMgMi4wIENocm9taXVtKQ",
        "dm_cover_img_str": "QU5HTEUgKEFwcGxlLCBBcGxlIE0xIFBybywgT3BlbkdMIDQuMSk",
        "dm_img_inter": #"{"ds":[],"wh":[0,0,0],"of":[0,0,0]}"#
    ]
}
