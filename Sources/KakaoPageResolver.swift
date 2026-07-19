import Foundation

struct KakaoPageEpisode: Hashable {
    var seriesID: String
    var productID: String
    var title: String
    var index: Int? = nil
}

final class KakaoPageResolver {
    private let maxEpisodePages = 500
    private let episodePageSize = 50

    func canResolve(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(),
              Self.isKakaoPageHost(host),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return false
        }

        return Self.viewerIDs(from: url) != nil || Self.seriesID(from: url) != nil
    }

    func resolve(
        _ url: URL,
        headers: HTTPRequestOptions = HTTPRequestOptions(),
        rangeExpression: String = ""
    ) async throws -> ResolvedDownload {
        let sourceURL = Self.canonicalURL(for: url) ?? url
        guard let seriesID = Self.seriesID(from: sourceURL) else {
            throw NativeDownloadError.invalidURL(url.absoluteString)
        }

        let parsed = try await loadEpisodeList(seriesID: seriesID, sourceURL: sourceURL, headers: headers)
        let itemRange = rangeExpression.trimmed
        var selectedEpisodes = Array(parsed.episodes.enumerated())
        var selectedPositions: [Int]?
        if !itemRange.isEmpty {
            let indexes = try Self.itemIndexes(for: itemRange, total: parsed.episodes.count)
            selectedEpisodes = indexes.map { (offset: $0, element: parsed.episodes[$0]) }
            selectedPositions = indexes.map { $0 + 1 }
        }

        var assets: [ResolvedAsset] = []
        var resolvedEpisodeCount = 0
        var failures: [Error] = []

        for selectedEpisode in selectedEpisodes {
            try Task.checkCancellation()
            var episode = selectedEpisode.element
            episode.index = selectedEpisode.offset + 1
            var lastError: Error?
            for _ in 0..<2 {
                do {
                    try Task.checkCancellation()
                    let data = try await postViewerInfo(for: episode, sourceURL: sourceURL, headers: headers)
                    let resolved = try Self.resolvedEpisodeDownload(
                        fromViewerData: data,
                        episode: episode,
                        sourceURL: sourceURL
                    )
                    assets.append(contentsOf: resolved.assets)
                    resolvedEpisodeCount += 1
                    lastError = nil
                    break
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    lastError = error
                }
            }
            if let lastError {
                failures.append(lastError)
            }
        }

        guard !assets.isEmpty else {
            throw failures.first ?? NativeDownloadError.noFiles
        }

        let title = (parsed.seriesTitle ?? "Series \(seriesID)").sanitizedFilename(maxLength: 120)
        var metadata = Self.kakaoPageMetadata(
            seriesTitle: title,
            seriesID: seriesID,
            productID: "",
            episodeCount: resolvedEpisodeCount,
            imageCount: assets.count
        )
        metadata["listed_episode_count"] = String(parsed.episodes.count)
        metadata["resolved_episode_count"] = String(resolvedEpisodeCount)
        metadata["resolved_media_count"] = String(assets.count)
        if !failures.isEmpty {
            metadata["skipped_count"] = String(failures.count)
        }
        if let selectedPositions {
            metadata["range"] = itemRange
            metadata["range_scope"] = "collection_items"
            metadata["range_total"] = String(parsed.episodes.count)
            metadata["range_selected"] = String(selectedPositions.count)
            metadata["range_indexes"] = selectedPositions.map(String.init).joined(separator: ",")
        }
        return ResolvedDownload(
            title: title,
            folderName: "KakaoPage \(title)".sanitizedFilename(maxLength: 120),
            assets: assets,
            metadata: metadata
        )
    }

    private func loadEpisodeList(seriesID: String, sourceURL: URL, headers: HTTPRequestOptions) async throws -> (seriesTitle: String?, episodes: [KakaoPageEpisode]) {
        var allEpisodes: [KakaoPageEpisode] = []
        var seen = Set<String>()
        var seriesTitle: String?
        var after: String?

        for _ in 0..<maxEpisodePages {
            let listData = try await postEpisodeList(seriesID: seriesID, sourceURL: sourceURL, headers: headers, after: after)
            let parsed = try Self.episodes(fromListData: listData, seriesID: seriesID)
            if seriesTitle == nil {
                seriesTitle = parsed.seriesTitle
            }

            guard !parsed.episodes.isEmpty else {
                break
            }
            let previousCount = allEpisodes.count
            for episode in parsed.episodes where !seen.contains(episode.productID) {
                seen.insert(episode.productID)
                allEpisodes.append(episode)
            }

            let next = String(allEpisodes.count)
            guard allEpisodes.count > previousCount,
                  next != after else {
                break
            }
            after = next
        }

        guard !allEpisodes.isEmpty else {
            throw NativeDownloadError.noFiles
        }
        return (seriesTitle, allEpisodes)
    }

    private func postEpisodeList(seriesID: String, sourceURL: URL, headers: HTTPRequestOptions, after: String?) async throws -> Data {
        let body = try Self.episodeListBody(seriesID: seriesID, first: episodePageSize, after: after)
        return try await HTTPClient.shared.postJSON(
            to: Self.graphQLEndpoint(for: sourceURL),
            body: body,
            referer: headers.referer ?? sourceURL.absoluteString,
            userAgent: headers.userAgent
        )
    }

    private func postViewerInfo(for episode: KakaoPageEpisode, sourceURL: URL, headers: HTTPRequestOptions) async throws -> Data {
        let body = try Self.graphQLBody(
            operationName: "viewerInfo",
            query: Self.viewerInfoQuery,
            variables: [
                "seriesId": Self.numericValue(episode.seriesID),
                "productId": Self.numericValue(episode.productID)
            ]
        )
        return try await HTTPClient.shared.postJSON(
            to: Self.graphQLEndpoint(for: sourceURL),
            body: body,
            referer: headers.referer ?? sourceURL.absoluteString,
            userAgent: headers.userAgent
        )
    }

    static func episodes(fromListData data: Data, seriesID: String) throws -> (seriesTitle: String?, episodes: [KakaoPageEpisode], hasNextPage: Bool, endCursor: String?) {
        let object = try jsonObject(from: data)
        try throwIfGraphQLErrors(in: object)

        let container = dictionary(at: ["data", "contentHomeProductList"], in: object) ??
            dictionary(at: ["contentHomeProductList"], in: object) ??
            object
        let edges = container["edges"] as? [[String: Any]] ?? []
        var episodes: [KakaoPageEpisode] = []
        var seen = Set<String>()

        for edge in edges {
            let node = edge["node"] as? [String: Any] ?? edge
            let single = node["single"] as? [String: Any] ?? node
            guard let productID = stringValue(single["productId"]) ?? stringValue(single["id"]) else {
                continue
            }
            guard !seen.contains(productID) else { continue }
            seen.insert(productID)

            let title = stringValue(single["title"]) ??
                stringValue(node["row1"]) ??
                stringValue(node["title"]) ??
                "Episode \(productID)"
            episodes.append(KakaoPageEpisode(
                seriesID: stringValue(single["seriesId"]) ?? seriesID,
                productID: productID,
                title: cleanTitle(title)
            ))
        }

        let seriesTitle = stringValue(dictionary(at: ["data", "series"], in: object)?["title"]) ??
            stringValue(dictionary(at: ["series"], in: object)?["title"])
        let pageInfo = container["pageInfo"] as? [String: Any]
        let hasNextPage = boolValue(pageInfo?["hasNextPage"]) ?? false
        let endCursor = stringValue(pageInfo?["endCursor"])
        return (seriesTitle, episodes, hasNextPage, endCursor)
    }

    static func resolvedEpisodeDownload(fromViewerData data: Data, episode: KakaoPageEpisode, sourceURL: URL) throws -> ResolvedDownload {
        let object = try jsonObject(from: data)
        try throwIfGraphQLErrors(in: object)

        let viewerInfo = dictionary(at: ["data", "viewerInfo"], in: object) ??
            dictionary(at: ["viewerInfo"], in: object) ??
            object
        let item = viewerInfo["item"] as? [String: Any]
        let viewerData = viewerInfo["viewerData"] as? [String: Any] ?? viewerInfo
        let imageData = viewerData["imageDownloadData"] as? [String: Any] ?? viewerData
        let files = imageData["files"] as? [[String: Any]] ?? []

        var assets: [ResolvedAsset] = []
        var seen = Set<String>()
        let title = cleanTitle(stringValue(item?["title"]) ?? episode.title)
        let prefix = filePrefix(for: episode, title: title)

        for file in files {
            guard let raw = stringValue(file["secureUrl"]) ?? stringValue(file["url"]) else {
                continue
            }
            guard let remote = imageURL(from: raw, sourceURL: sourceURL) else { continue }
            let normalized = URLIdentity.normalize(remote.absoluteString)
            guard !seen.contains(normalized) else { continue }
            seen.insert(normalized)

            let index = assets.count + 1
            assets.append(ResolvedAsset(
                remoteURL: remote,
                filename: filename(for: remote, prefix: prefix, index: index),
                metadata: assetMetadata(seriesTitle: title, episode: episode, remote: remote, sourceURL: sourceURL, index: index),
                referer: sourceURL.absoluteString
            ))
        }

        guard !assets.isEmpty else {
            throw NativeDownloadError.noFiles
        }

        return ResolvedDownload(
            title: title,
            folderName: "KakaoPage \(episodeOutputTitle(for: episode, title: title))".sanitizedFilename(maxLength: 120),
            assets: assets,
            metadata: kakaoPageMetadata(seriesTitle: title, seriesID: episode.seriesID, productID: episode.productID, episodeCount: 1, imageCount: assets.count)
        )
    }

    static func viewerIDs(from url: URL) -> (seriesID: String, productID: String)? {
        let path = url.path
        let patterns = [
            #"/content/([0-9]+)/viewer/([0-9]+)"#,
            #"/viewer/([0-9]+)/([0-9]+)"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(path.startIndex..<path.endIndex, in: path)
            guard let match = regex.firstMatch(in: path, range: range),
                  let first = Range(match.range(at: 1), in: path),
                  let second = Range(match.range(at: 2), in: path) else {
                continue
            }
            return (String(path[first]), String(path[second]))
        }
        return nil
    }

    static func seriesID(from url: URL) -> String? {
        if let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
           let value = items.first(where: { $0.name.lowercased() == "seriesid" })?.value,
           value.range(of: #"^[0-9]+$"#, options: .regularExpression) != nil {
            return value
        }

        let path = url.path
        guard let regex = try? NSRegularExpression(pattern: #"/content/([0-9]+)"#) else {
            return nil
        }
        let range = NSRange(path.startIndex..<path.endIndex, in: path)
        guard let match = regex.firstMatch(in: path, range: range),
              let capture = Range(match.range(at: 1), in: path) else {
            return nil
        }
        return String(path[capture])
    }

    static func canonicalURL(for url: URL) -> URL? {
        guard let host = url.host?.lowercased(),
              isKakaoPageHost(host),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }

        let canonicalHost = host.hasSuffix(".test") ? "page.kakao.test" : "page.kakao.com"
        var components = URLComponents()
        components.scheme = "https"
        components.host = canonicalHost
        if let ids = viewerIDs(from: url) {
            components.path = "/content/\(ids.seriesID)"
            return components.url
        }
        guard let seriesID = seriesID(from: url) else {
            return nil
        }
        components.path = "/content/\(seriesID)"
        return components.url
    }

    static func graphQLEndpoint(for sourceURL: URL) -> URL {
        var components = URLComponents()
        components.scheme = sourceURL.scheme ?? "https"
        components.host = sourceURL.host?.lowercased().hasSuffix(".test") == true ? "page.kakao.test" : "page.kakao.com"
        components.path = "/graphql"
        return components.url!
    }

    static func episodeListBody(seriesID: String, first: Int, after: String?) throws -> Data {
        var variables: [String: Any] = [
            "seriesId": numericValue(seriesID),
            "sortType": "asc",
            "boughtOnly": false
        ]
        if let after, !after.isEmpty {
            variables["after"] = after
        }
        return try graphQLBody(
            operationName: "contentHomeProductList",
            query: episodeListQuery,
            variables: variables
        )
    }

    static func graphQLBody(operationName: String, query: String, variables: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "operationName": operationName,
            "query": query,
            "variables": variables
        ])
    }

    private static func imageURL(from raw: String, sourceURL: URL) -> URL? {
        let trimmed = raw.trimmed
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return URL(string: trimmed)
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = sourceURL.host?.lowercased().hasSuffix(".test") == true ? "page-edge.kakao.test" : "page-edge.kakao.com"
        components.path = "/sdownload/resource"
        components.queryItems = [URLQueryItem(name: "kid", value: trimmed)]
        return components.url
    }

    private static func filename(for url: URL, prefix: String, index: Int) -> String {
        let ext = mediaFormat(for: url)
        return String(format: "%@ - %04d.%@", prefix, index, ext).sanitizedFilename(maxLength: 180)
    }

    private static func mediaFormat(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        if ext == "jpeg" {
            return "jpg"
        }
        return ext.isEmpty ? "jpg" : ext
    }

    private static func filePrefix(for episode: KakaoPageEpisode, title: String) -> String {
        episodeOutputTitle(for: episode, title: title)
    }

    private static func episodeOutputTitle(for episode: KakaoPageEpisode, title: String) -> String {
        if let index = episode.index {
            return String(format: "%04d - %@", index, title).sanitizedFilename(maxLength: 120)
        }
        return "\(episode.productID) - \(title)".sanitizedFilename(maxLength: 120)
    }

    static func kakaoPageMetadata(seriesTitle: String, seriesID: String, productID: String, episodeCount: Int?, imageCount: Int? = nil) -> [String: String] {
        DownloadMetadata.clean([
            "series": seriesTitle,
            "category": "comic",
            "type": productID.isEmpty ? "series" : "episode",
            "media_type": "image",
            "media_count": imageCount.map(String.init) ?? "",
            "image_count": imageCount.map(String.init) ?? "",
            "series_id": seriesID,
            "work_id": seriesID,
            "product_id": productID,
            "episode_id": productID,
            "chapter_id": productID,
            "gallery_id": productID.isEmpty ? seriesID : productID,
            "episode_count": episodeCount.map(String.init) ?? "",
            "slug": productID.isEmpty ? seriesID : productID,
            "site": "KakaoPage",
            "title": seriesTitle
        ])
    }

    private static func assetMetadata(seriesTitle: String, episode: KakaoPageEpisode, remote: URL, sourceURL: URL, index: Int) -> [String: String] {
        let format = mediaFormat(for: remote)
        return DownloadMetadata.clean([
            "series": seriesTitle,
            "category": "comic",
            "episode": seriesTitle,
            "chapter": seriesTitle,
            "type": "image",
            "media_type": "image",
            "series_id": episode.seriesID,
            "work_id": episode.seriesID,
            "product_id": episode.productID,
            "episode_id": episode.productID,
            "chapter_id": episode.productID,
            "gallery_id": episode.productID.isEmpty ? episode.seriesID : episode.productID,
            "id": episode.productID.isEmpty ? episode.seriesID : episode.productID,
            "page": String(index),
            "position": String(index),
            "format": format,
            "media_format": format,
            "image_url": remote.absoluteString,
            "media_url": remote.absoluteString,
            "source_url": remote.absoluteString,
            "page_url": sourceURL.absoluteString,
            "site": "KakaoPage",
            "title": seriesTitle
        ])
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
            throw NativeDownloadError.unsupported("Range did not match any KakaoPage episodes.")
        }
        return indexes
    }

    private static func itemRangeSegments(from expression: String) throws -> [ItemRangeSegment] {
        guard !expression.isEmpty else { return [] }
        let compact = expression.filter { !$0.isWhitespace }
        let pieces = compact.components(separatedBy: CharacterSet(charactersIn: ",;"))
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

    private static func jsonObject(from data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NativeDownloadError.invalidGalleryData
        }
        return object
    }

    private static func throwIfGraphQLErrors(in object: [String: Any]) throws {
        guard let errors = object["errors"] as? [[String: Any]], !errors.isEmpty else { return }
        let message = errors
            .compactMap { error -> String? in
                if let message = stringValue(error["message"]) {
                    if let extensions = error["extensions"] as? [String: Any],
                       let code = stringValue(extensions["code"]) {
                        return "\(message) (\(code))"
                    }
                    return message
                }
                return nil
            }
            .joined(separator: ", ")
        throw NativeDownloadError.unsupported(message.isEmpty ? "KakaoPage GraphQL request failed." : message)
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
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    private static func boolValue(_ value: Any?) -> Bool? {
        if let bool = value as? Bool { return bool }
        if let number = value as? NSNumber { return number.boolValue }
        if let string = value as? String {
            let lower = string.trimmed.lowercased()
            if ["true", "1", "yes", "y"].contains(lower) { return true }
            if ["false", "0", "no", "n"].contains(lower) { return false }
        }
        return nil
    }

    private static func numericValue(_ value: String) -> Any {
        if let int = Int(value) {
            return int
        }
        return value
    }

    private static func cleanTitle(_ raw: String) -> String {
        let title = raw
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmed
        return title.isEmpty ? "KakaoPage Episode" : title
    }

    private static func isKakaoPageHost(_ host: String) -> Bool {
        host == "page.kakao.com" ||
            host == "page.kakao.test"
    }

    private static let episodeListQuery = """
    query contentHomeProductList($after: String, $first: Int, $seriesId: Long!, $boughtOnly: Boolean, $sortType: String) {
      contentHomeProductList(after: $after, first: $first, seriesId: $seriesId, boughtOnly: $boughtOnly, sortType: $sortType) {
        pageInfo {
          hasNextPage
          endCursor
        }
        edges {
          node {
            row1
            single {
              productId
              seriesId
              title
            }
          }
        }
      }
    }
    """

    private static let viewerInfoQuery = """
    query viewerInfo($seriesId: Long!, $productId: Long!) {
      viewerInfo(seriesId: $seriesId, productId: $productId) {
        item {
          productId
          seriesId
          title
        }
        viewerData {
          __typename
          ... on ImageViewerData {
            imageDownloadData {
              files {
                no
                secureUrl
                width
                height
              }
            }
          }
        }
      }
    }
    """
}
