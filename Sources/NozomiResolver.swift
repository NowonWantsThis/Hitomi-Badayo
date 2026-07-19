import Foundation

struct NozomiIndexRequest {
    var url: URL
    var tag: String
    var isNegative: Bool
    var isPopular: Bool = false
}

final class NozomiResolver {
    func canResolve(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(),
              isNozomiHost(host),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return false
        }

        if postID(from: url) != nil {
            return true
        }
        return ((try? indexRequests(for: url)) ?? []).isEmpty == false
    }

    func resolve(
        _ url: URL,
        headers: HTTPRequestOptions = HTTPRequestOptions(),
        rangeExpression: String = ""
    ) async throws -> ResolvedDownload {
        let sourceURL = Self.fragmentStrippedURL(url)
        if let id = postID(from: sourceURL) {
            let postURL = try Self.postJSONURL(for: id, sourceURL: sourceURL)
            let data = try await HTTPClient.shared.data(from: postURL, referer: headers.referer ?? sourceURL.absoluteString, userAgent: headers.userAgent)
            return try Self.resolvedDownload(fromPosts: [data], titleHint: "Nozomi \(id)", sourceURL: sourceURL)
        }

        let queryRequests = try indexRequests(for: sourceURL)
        guard !queryRequests.isEmpty else {
            throw NativeDownloadError.invalidURL(url.absoluteString)
        }

        var requests = queryRequests
        if !requests.contains(where: { !$0.isNegative }) {
            requests.insert(
                try indexRequest(sourceURL: sourceURL, isPopular: isPopularURL(sourceURL)),
                at: 0
            )
        }

        var positiveIDs: [Int]?
        var negativeIDSets: [Set<Int>] = []

        for request in requests {
            try Task.checkCancellation()
            let data = try await HTTPClient.shared.data(from: request.url, referer: headers.referer ?? sourceURL.absoluteString, userAgent: headers.userAgent)
            let ids = Self.uniqueIDs(Self.parseIndexIDs(from: data))
            if request.isNegative {
                negativeIDSets.append(Set(ids))
            } else if let current = positiveIDs {
                let allowed = Set(ids)
                positiveIDs = current.filter(allowed.contains)
            } else {
                positiveIDs = ids
            }
        }

        let excluded = negativeIDSets.reduce(into: Set<Int>()) { result, ids in
            result.formUnion(ids)
        }
        let listedIDs = (positiveIDs ?? []).filter { !excluded.contains($0) }
        let itemRange = rangeExpression.trimmed
        let selectedIndexes = itemRange.isEmpty
            ? Array(listedIDs.indices)
            : try Self.itemIndexes(for: itemRange, total: listedIDs.count)
        let ids = selectedIndexes.map { listedIDs[$0] }
        guard !ids.isEmpty else {
            throw NativeDownloadError.noFiles
        }

        var posts: [Data] = []
        var failures: [Error] = []
        for id in ids {
            try Task.checkCancellation()
            do {
                let postURL = try Self.postJSONURL(for: String(id), sourceURL: sourceURL)
                let data = try await HTTPClient.shared.data(from: postURL, referer: headers.referer ?? sourceURL.absoluteString, userAgent: headers.userAgent)
                posts.append(data)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                failures.append(error)
            }
        }

        guard !posts.isEmpty else {
            throw failures.first ?? NativeDownloadError.noFiles
        }
        let title = titleHint(for: queryRequests)
        var resolved = try Self.resolvedDownload(fromPosts: posts, titleHint: title, sourceURL: sourceURL)
        resolved.metadata["listed_post_count"] = String(listedIDs.count)
        resolved.metadata["selected_post_count"] = String(ids.count)
        if !itemRange.isEmpty {
            resolved.metadata["range"] = itemRange
            resolved.metadata["range_scope"] = "collection_items"
            resolved.metadata["range_total"] = String(listedIDs.count)
            resolved.metadata["range_selected"] = String(selectedIndexes.count)
            resolved.metadata["range_indexes"] = selectedIndexes.map { String($0 + 1) }.joined(separator: ",")
        }
        if !failures.isEmpty {
            resolved.metadata["skipped_count"] = String(failures.count)
            resolved.metadata["resolved_item_count"] = String(posts.count)
        }
        return resolved
    }

    static func canonicalInputURL(for url: URL) -> URL? {
        let canonical = fragmentStrippedURL(url)
        guard NozomiResolver().canResolve(canonical) else {
            return nil
        }
        return canonical
    }

    func indexRequests(for url: URL) throws -> [NozomiIndexRequest] {
        let popular = isPopularURL(url)
        if isIndexURL(url) {
            return [try indexRequest(sourceURL: url, isPopular: popular)]
        }

        if let tag = tagSlug(from: url) {
            return [try indexRequest(for: tag, sourceURL: url, isNegative: false, isPopular: popular)]
        }

        guard isSearchURL(url),
              let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                  .queryItems?
                  .first(where: { $0.name.lowercased() == "q" || $0.name.lowercased() == "query" })?
                  .value else {
            return []
        }

        let terms = query
            .split(whereSeparator: { $0.isWhitespace || $0 == "," })
            .map(String.init)
            .filter { !$0.trimmed.isEmpty }

        return try terms.map { term in
            let isNegative = term.hasPrefix("-")
            let tag = isNegative ? String(term.dropFirst()) : term
            return try indexRequest(for: tag, sourceURL: url, isNegative: isNegative, isPopular: popular)
        }
    }

    func indexRequest(sourceURL: URL, isPopular: Bool) throws -> NozomiIndexRequest {
        guard var components = URLComponents(url: sourceURL, resolvingAgainstBaseURL: false) else {
            throw NativeDownloadError.invalidURL(sourceURL.absoluteString)
        }
        components.host = Self.jsonHost(for: sourceURL.host)
        components.path = isPopular ? "/index-Popular.nozomi" : "/index.nozomi"
        components.queryItems = nil
        components.fragment = nil
        guard let indexURL = components.url else {
            throw NativeDownloadError.invalidURL(sourceURL.absoluteString)
        }

        return NozomiIndexRequest(
            url: indexURL,
            tag: isPopular ? "Popular" : "Nozomi",
            isNegative: false,
            isPopular: isPopular
        )
    }

    func indexRequest(for tag: String, sourceURL: URL, isNegative: Bool, isPopular: Bool = false) throws -> NozomiIndexRequest {
        let cleaned = Self.normalizedIndexTag(tag)
        guard !cleaned.isEmpty,
              var components = URLComponents(url: sourceURL, resolvingAgainstBaseURL: false) else {
            throw NativeDownloadError.invalidURL(sourceURL.absoluteString)
        }

        let encoded = cleaned.addingPercentEncoding(withAllowedCharacters: Self.nozomiPathSegmentAllowedCharacters) ?? cleaned
        components.host = Self.jsonHost(for: sourceURL.host)
        components.path = isPopular ? "/nozomi/popular/\(encoded)-Popular.nozomi" : "/nozomi/\(encoded).nozomi"
        components.queryItems = nil
        components.fragment = nil
        guard let indexURL = components.url else {
            throw NativeDownloadError.invalidURL(sourceURL.absoluteString)
        }

        return NozomiIndexRequest(url: indexURL, tag: cleaned, isNegative: isNegative, isPopular: isPopular)
    }

    static func normalizedIndexTag(_ raw: String) -> String {
        raw
            .trimmed
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "")
            .replacingOccurrences(of: ".html", with: "")
            .replacingOccurrences(of: "-Popular", with: "", options: [.caseInsensitive])
    }

    static func resolvedDownload(fromPosts posts: [Data], titleHint: String, sourceURL: URL) throws -> ResolvedDownload {
        var assets: [ResolvedAsset] = []
        var seen = Set<String>()
        var postIDs: [String] = []

        for data in posts {
            guard let post = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            let postID = stringValue(post["postid"]) ?? stringValue(post["id"]) ?? stringValue(post["dataid"]) ?? "post"
            if !postIDs.contains(postID) {
                postIDs.append(postID)
            }
            let referer = postReferer(for: postID, sourceURL: sourceURL)

            for (imageIndex, image) in imageDictionaries(from: post).enumerated() {
                guard let dataID = stringValue(image["dataid"]) ?? stringValue(image["id"]),
                      let remote = mediaURL(for: image, dataID: dataID, sourceURL: sourceURL) else {
                    continue
                }

                let normalized = URLIdentity.normalize(remote.absoluteString)
                guard !seen.contains(normalized) else { continue }
                seen.insert(normalized)

                let filename = outputFilename(postID: postID, dataID: dataID, remoteURL: remote, index: assets.count + 1)
                assets.append(
                    ResolvedAsset(
                        remoteURL: remote,
                        filename: filename,
                        metadata: assetMetadata(
                            titleHint: titleHint,
                            postID: postID,
                            dataID: dataID,
                            remoteURL: remote,
                            referer: referer,
                            page: imageIndex + 1,
                            position: assets.count + 1
                        ),
                        referer: referer
                    )
                )
            }
        }

        guard !assets.isEmpty else {
            throw NativeDownloadError.noFiles
        }

        let title = titleHint.sanitizedFilename(maxLength: 120)
        return ResolvedDownload(
            title: title,
            folderName: "Nozomi \(title)".sanitizedFilename(maxLength: 120),
            assets: assets,
            metadata: nozomiMetadata(titleHint: titleHint, assets: assets, postIDs: postIDs)
        )
    }

    static func postJSONURL(for id: String, sourceURL: URL) throws -> URL {
        let postID = id.trimmed
        guard postID.count >= 3,
              var components = URLComponents(url: sourceURL, resolvingAgainstBaseURL: false) else {
            throw NativeDownloadError.invalidURL(id)
        }

        let last = String(postID.suffix(1))
        let middle = String(postID.dropLast().suffix(2))
        components.host = jsonHost(for: sourceURL.host)
        components.path = "/post/\(last)/\(middle)/\(postID).json"
        components.queryItems = nil
        components.fragment = nil
        guard let url = components.url else {
            throw NativeDownloadError.invalidURL(id)
        }
        return url
    }

    static func parseIndexIDs(from data: Data) -> [Int] {
        guard data.count >= 4 else { return [] }
        var ids: [Int] = []
        var offset = 0
        while offset + 4 <= data.count {
            let value = data[offset..<offset + 4].reduce(UInt32(0)) { partial, byte in
                (partial << 8) | UInt32(byte)
            }
            ids.append(Int(value))
            offset += 4
        }
        return ids
    }

    static func itemIndexes(for expression: String, total: Int) throws -> [Int] {
        let segments = try itemRangeSegments(from: expression)
        guard !segments.isEmpty else { return Array(0..<max(0, total)) }
        guard total > 0 else { return [] }

        var indexes: [Int] = []
        for position in 1...total {
            if segments.contains(where: { segment in
                let start = max(1, segment.start ?? 1)
                let end = min(total, segment.end ?? total)
                return start <= position && position <= end
            }) {
                indexes.append(position - 1)
            }
        }
        guard !indexes.isEmpty else {
            throw NativeDownloadError.unsupported("Range did not match any Nozomi posts.")
        }
        return indexes
    }

    private func postID(from url: URL) -> String? {
        let path = url.path
        guard let regex = try? NSRegularExpression(pattern: #"/post/([0-9]+)(?:\.html)?$"#) else {
            return nil
        }
        let range = NSRange(path.startIndex..<path.endIndex, in: path)
        guard let match = regex.firstMatch(in: path, range: range),
              let capture = Range(match.range(at: 1), in: path) else {
            return nil
        }
        return String(path[capture])
    }

    private static func fragmentStrippedURL(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        components.fragment = nil
        return components.url ?? url
    }

    private struct ItemRangeSegment {
        var start: Int?
        var end: Int?
    }

    private static func itemRangeSegments(from expression: String) throws -> [ItemRangeSegment] {
        let trimmed = expression.trimmed
        guard !trimmed.isEmpty else { return [] }
        let compact = trimmed.filter { !$0.isWhitespace }
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

    private static func uniqueIDs(_ ids: [Int]) -> [Int] {
        var seen = Set<Int>()
        return ids.filter { seen.insert($0).inserted }
    }

    private func tagSlug(from url: URL) -> String? {
        let parts = url.path.split(separator: "/").map(String.init)
        guard parts.count >= 2, parts[0].lowercased() == "tag" else {
            return nil
        }
        let tag = (parts[1] as NSString).deletingPathExtension.trimmed
        return tag.isEmpty ? nil : tag
    }

    private func titleHint(for requests: [NozomiIndexRequest]) -> String {
        let positives = requests.filter { !$0.isNegative }.map(\.tag)
        let negatives = requests.filter(\.isNegative).map { "-\($0.tag)" }
        let title = (positives + negatives).joined(separator: " ")
        guard !title.isEmpty else {
            return requests.contains(where: \.isPopular) ? "Popular" : "Nozomi"
        }
        return requests.contains(where: \.isPopular) && title.lowercased() != "popular" ? "\(title) Popular" : title
    }

    private func isIndexURL(_ url: URL) -> Bool {
        let path = url.path.lowercased()
        return path.isEmpty ||
            path == "/" ||
            path == "/index.html" ||
            path == "/popular" ||
            path == "/popular.html"
    }

    private func isPopularURL(_ url: URL) -> Bool {
        let path = url.path.lowercased()
        if path.contains("popular") {
            return true
        }

        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        for item in items {
            let name = item.name.lowercased()
            let value = item.value?.trimmed.lowercased() ?? ""
            if name == "popular" {
                return value.isEmpty || ["1", "true", "yes", "y"].contains(value)
            }
            if ["sort", "order", "type"].contains(name), value.contains("popular") {
                return true
            }
        }
        return false
    }

    private func isSearchURL(_ url: URL) -> Bool {
        let path = url.path.lowercased()
        return path == "/search.html" || path == "/search-popular.html"
    }

    private static func nozomiMetadata(titleHint: String, assets: [ResolvedAsset] = [], postIDs: [String] = []) -> [String: String] {
        let imageCount = assets.filter { mediaType(for: $0.remoteURL) == "image" }.count
        let videoCount = assets.filter { mediaType(for: $0.remoteURL) == "video" }.count
        let mediaType = mediaType(forImageCount: imageCount, videoCount: videoCount)
        return DownloadMetadata.clean([
            "tag": titleHint,
            "tags": titleHint,
            "category": titleHint,
            "search": titleHint,
            "site": "Nozomi.la",
            "title": titleHint,
            "type": titleHint.lowercased().hasPrefix("nozomi ") ? "post" : "collection",
            "media_type": mediaType,
            "media_count": assets.isEmpty ? "" : String(assets.count),
            "image_count": assets.isEmpty ? "" : String(imageCount),
            "video_count": assets.isEmpty ? "" : String(videoCount),
            "post_count": postIDs.isEmpty ? "" : String(postIDs.count),
            "post_id": postIDs.count == 1 ? postIDs[0] : "",
            "gallery_id": postIDs.count == 1 ? postIDs[0] : "",
            "id": postIDs.count == 1 ? postIDs[0] : ""
        ])
    }

    private static func assetMetadata(
        titleHint: String,
        postID: String,
        dataID: String,
        remoteURL: URL,
        referer: String,
        page: Int,
        position: Int
    ) -> [String: String] {
        let format = mediaFormat(for: remoteURL)
        let mediaType = mediaType(for: remoteURL)
        return DownloadMetadata.clean([
            "tag": titleHint,
            "tags": titleHint,
            "category": titleHint,
            "search": titleHint,
            "site": "Nozomi.la",
            "title": titleHint,
            "post_id": postID,
            "gallery_id": postID,
            "id": postID,
            "data_id": dataID,
            "media_id": dataID,
            "type": mediaType,
            "media_type": mediaType,
            "page": String(page),
            "position": String(position),
            "format": format,
            "media_format": format,
            "image_url": mediaType == "image" ? remoteURL.absoluteString : "",
            "video_url": mediaType == "video" ? remoteURL.absoluteString : "",
            "media_url": remoteURL.absoluteString,
            "source_url": remoteURL.absoluteString,
            "page_url": referer
        ])
    }

    private func isNozomiHost(_ host: String) -> Bool {
        host == "nozomi.la" ||
            host == "www.nozomi.la" ||
            host == "j.nozomi.la" ||
            host == "nozomi.test" ||
            host == "j.nozomi.test"
    }

    private static func mediaURL(for image: [String: Any], dataID: String, sourceURL: URL) -> URL? {
        if let direct = stringValue(image["url"]) ?? stringValue(image["imageurl"]) ?? stringValue(image["image_url"]),
           let url = absoluteURL(direct, baseURL: sourceURL) {
            return url
        }

        let type = (stringValue(image["type"]) ?? stringValue(image["ext"]) ?? "jpg")
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let isVideo = boolValue(image["is_video"]) || ["mp4", "webm"].contains(type)
        let hostPrefix: String
        let ext: String
        if isVideo {
            hostPrefix = "v"
            ext = type.isEmpty || type == "jpg" ? "mp4" : type
        } else if type == "gif" {
            hostPrefix = "g"
            ext = "gif"
        } else {
            hostPrefix = "w"
            ext = "webp"
        }

        guard dataID.count >= 3 else { return nil }
        let last = String(dataID.suffix(1))
        let middle = String(dataID.dropLast().suffix(2))
        let host = mediaHost(prefix: hostPrefix, sourceHost: sourceURL.host)
        return URL(string: "\(sourceURL.scheme ?? "https")://\(host)/\(last)/\(middle)/\(dataID).\(ext)")
    }

    private static func imageDictionaries(from post: [String: Any]) -> [[String: Any]] {
        if let images = post["imageurls"] as? [[String: Any]] {
            return images
        }
        if let images = post["images"] as? [[String: Any]] {
            return images
        }
        if post.keys.contains(where: { ["dataid", "imageurl", "image_url", "url"].contains($0.lowercased()) }) {
            return [post]
        }
        return []
    }

    private static func outputFilename(postID: String, dataID: String, remoteURL: URL, index: Int) -> String {
        let ext = mediaFormat(for: remoteURL)
        return String(format: "%04d-%@-%@.%@", index, postID, dataID, ext).sanitizedFilename(maxLength: 180)
    }

    private static func mediaFormat(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        if ext == "jpeg" {
            return "jpg"
        }
        return ext.isEmpty ? "bin" : ext
    }

    private static func mediaType(for url: URL) -> String {
        ["mp4", "webm", "mov", "m4v"].contains(mediaFormat(for: url)) ? "video" : "image"
    }

    private static func mediaType(forImageCount imageCount: Int, videoCount: Int) -> String {
        if imageCount > 0 && videoCount > 0 {
            return "mixed"
        }
        if videoCount > 0 {
            return "video"
        }
        return "image"
    }

    private static func postReferer(for postID: String, sourceURL: URL) -> String {
        let host = sourceURL.host?.lowercased().hasSuffix(".test") == true ? "nozomi.test" : "nozomi.la"
        return "\(sourceURL.scheme ?? "https")://\(host)/post/\(postID).html"
    }

    private static func absoluteURL(_ raw: String, baseURL: URL) -> URL? {
        let trimmed = raw.trimmed
        if trimmed.hasPrefix("//") {
            return URL(string: "\(baseURL.scheme ?? "https"):\(trimmed)")
        }
        return URL(string: trimmed, relativeTo: baseURL)?.absoluteURL
    }

    private static func jsonHost(for host: String?) -> String {
        host?.lowercased().hasSuffix(".test") == true
            ? "j.gold-usergeneratedcontent.test"
            : "j.gold-usergeneratedcontent.net"
    }

    private static func mediaHost(prefix: String, sourceHost: String?) -> String {
        sourceHost?.lowercased().hasSuffix(".test") == true
            ? "\(prefix).gold-usergeneratedcontent.test"
            : "\(prefix).gold-usergeneratedcontent.net"
    }

    private static let nozomiPathSegmentAllowedCharacters: CharacterSet = {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        return allowed
    }()

    private static func stringValue(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        if let int = value as? Int { return String(int) }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    private static func boolValue(_ value: Any?) -> Bool {
        if let bool = value as? Bool { return bool }
        if let number = value as? NSNumber { return number.boolValue }
        if let string = value as? String {
            return ["1", "true", "yes", "y"].contains(string.trimmed.lowercased())
        }
        return false
    }
}
