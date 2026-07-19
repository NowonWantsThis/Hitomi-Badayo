import Foundation

enum ComicWalkerImageDecoder {
    static func decode(_ data: Data, hash: String) throws -> Data {
        let keyText = String(hash.prefix(16))
        guard keyText.count == 16, let key = UInt64(keyText, radix: 16) else {
            throw NativeDownloadError.invalidGalleryData
        }

        let filter = (0..<8)
            .map { UInt8((key >> UInt64($0 * 8)) & 0xff) }
            .reversed()
        let bytes = Array(filter)

        var output = Data()
        output.reserveCapacity(data.count)
        for (offset, byte) in data.enumerated() {
            output.append(byte ^ bytes[offset % bytes.count])
        }
        return output
    }
}

struct ComicWalkerEpisode: Equatable {
    /// Public episode code used in ComicWalker URLs and user-facing metadata.
    let id: String
    /// Internal UUID required by the current `/api/contents/viewer` endpoint.
    let viewerID: String
    let title: String
    let url: URL

    init(id: String, viewerID: String? = nil, title: String, url: URL) {
        self.id = id
        self.viewerID = viewerID?.trimmed.isEmpty == false ? viewerID! : id
        self.title = title
        self.url = url
    }
}

final class ComicWalkerResolver {
    func canResolve(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(),
              Self.isComicWalkerHost(host),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return false
        }

        return Self.canResolvePath(url.path)
    }

    func resolve(
        _ url: URL,
        headers: HTTPRequestOptions = HTTPRequestOptions(),
        rangeExpression: String = ""
    ) async throws -> ResolvedDownload {
        let pageURL = Self.canonicalDetailURL(for: url) ?? Self.canonicalInputURL(for: url) ?? url
        let html = try await HTTPClient.shared.string(from: pageURL, referer: headers.referer ?? url.absoluteString, userAgent: headers.userAgent)
        let title = Self.title(fromHTML: html, pageURL: pageURL)
        let episodes = Self.episodes(fromHTML: html, pageURL: pageURL, fallbackTitle: title)
        guard !episodes.isEmpty else {
            throw NativeDownloadError.invalidURL(url.absoluteString)
        }

        let itemRange = rangeExpression.trimmed
        var selectedEpisodes = Array(episodes.enumerated())
        var selectedPositions: [Int]?
        if !itemRange.isEmpty {
            let indexes = try Self.itemIndexes(for: itemRange, total: episodes.count)
            selectedEpisodes = indexes.map { (offset: $0, element: episodes[$0]) }
            selectedPositions = indexes.map { $0 + 1 }
        }

        var downloads: [(episodeID: String, resolved: ResolvedDownload)] = []
        let duplicateTitles = Self.duplicateBaseTitles(in: episodes)
        for selectedEpisode in selectedEpisodes {
            try Task.checkCancellation()
            let episode = selectedEpisode.element
            let apiURL = try Self.viewerAPIURL(for: episode.viewerID, sourceURL: pageURL)
            let data = try await HTTPClient.shared.data(
                from: apiURL,
                referer: episode.url.absoluteString,
                userAgent: headers.userAgent
            )
            let resolved = try Self.resolvedDownload(
                from: data,
                episodeID: episode.id,
                viewerEpisodeID: episode.viewerID,
                titleHint: title,
                pageURL: episode.url,
                episodeTitle: episode.title,
                episodeIndex: selectedEpisode.offset + 1,
                forceEpisodeIndex: duplicateTitles.contains(episode.title.lowercased())
            )
            downloads.append((episode.id, resolved))
        }
        return try Self.resolvedCollectionDownload(
            title: title,
            pageURL: pageURL,
            episodeDownloads: downloads,
            listedEpisodeCount: episodes.count,
            rangeExpression: itemRange,
            selectedPositions: selectedPositions
        )
    }

    static func viewerAPIURL(for episodeID: String, sourceURL: URL) throws -> URL {
        guard var components = URLComponents(url: sourceURL, resolvingAgainstBaseURL: false) else {
            throw NativeDownloadError.invalidURL(sourceURL.absoluteString)
        }

        components.host = apiHost(for: sourceURL.host)
        components.path = "/api/contents/viewer"
        components.queryItems = [
            URLQueryItem(name: "episodeId", value: episodeID),
            URLQueryItem(name: "imageSizeType", value: "width:1284")
        ]

        guard let apiURL = components.url else {
            throw NativeDownloadError.invalidURL(sourceURL.absoluteString)
        }
        return apiURL
    }

    static func resolvedDownload(
        from data: Data,
        episodeID: String,
        viewerEpisodeID: String? = nil,
        titleHint: String,
        pageURL: URL,
        episodeTitle: String? = nil,
        episodeIndex: Int? = nil,
        forceEpisodeIndex: Bool = false
    ) throws -> ResolvedDownload {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NativeDownloadError.invalidGalleryData
        }

        let manuscripts = manuscriptDictionaries(from: object)
        var assets: [ResolvedAsset] = []
        var seen = Set<String>()
        let title = episodeOutputTitle(
            title: episodeTitle ?? titleHint,
            episodeID: episodeID,
            episodeIndex: episodeIndex,
            forceIndex: forceEpisodeIndex
        )

        for manuscript in manuscripts {
            guard let remote = imageURL(from: manuscript, baseURL: pageURL) else { continue }
            let normalized = URLIdentity.normalize(remote.absoluteString)
            guard !seen.contains(normalized) else { continue }
            seen.insert(normalized)

            let hash = stringValue(manuscript["drmHash"]) ?? stringValue(manuscript["hash"])
            let mode = (stringValue(manuscript["drmMode"]) ?? stringValue(manuscript["mode"]) ?? "").lowercased()
            if !mode.isEmpty, mode != "xor" {
                throw NativeDownloadError.unsupported("Unsupported ComicWalker DRM mode: \(mode)")
            }

            let index = assets.count + 1
            assets.append(ResolvedAsset(
                remoteURL: remote,
                filename: filename(
                    for: remote,
                    prefix: title,
                    index: index
                ),
                metadata: assetMetadata(
                    seriesTitle: titleHint,
                    episodeTitle: title,
                    episodeID: episodeID,
                    viewerEpisodeID: viewerEpisodeID,
                    pageURL: pageURL,
                    remote: remote,
                    index: index,
                    drmHash: hash,
                    drmMode: mode.isEmpty && hash != nil ? "xor" : mode
                ),
                referer: pageURL.absoluteString,
                xorKey: hash
            ))
        }

        guard !assets.isEmpty else {
            throw NativeDownloadError.noFiles
        }

        return ResolvedDownload(
            title: title,
            folderName: "ComicWalker \(title)".sanitizedFilename(maxLength: 120),
            assets: assets,
            metadata: comicWalkerMetadata(
                title: title,
                episodeID: episodeID,
                viewerEpisodeID: viewerEpisodeID,
                pageURL: pageURL,
                imageCount: assets.count
            )
        )
    }

    static func resolvedCollectionDownload(
        title: String,
        pageURL: URL,
        episodeDownloads: [(episodeID: String, resolved: ResolvedDownload)],
        listedEpisodeCount: Int? = nil,
        rangeExpression: String = "",
        selectedPositions: [Int]? = nil
    ) throws -> ResolvedDownload {
        var assets: [ResolvedAsset] = []
        var seen = Set<String>()
        let cleanTitle = title.sanitizedFilename(maxLength: 120)

        for item in episodeDownloads {
            for asset in item.resolved.assets {
                let normalized = URLIdentity.normalize(asset.remoteURL.absoluteString)
                guard !seen.contains(normalized) else { continue }
                seen.insert(normalized)
                assets.append(ResolvedAsset(
                    remoteURL: asset.remoteURL,
                    filename: asset.filename.sanitizedFilename(maxLength: 180),
                    metadata: asset.metadata,
                    referer: asset.referer,
                    userAgent: asset.userAgent,
                    additionalHeaders: asset.additionalHeaders,
                    decryption: asset.decryption,
                    xorKey: asset.xorKey,
                    pixivGridShuffle: asset.pixivGridShuffle,
                    pixivUgoiraPackage: asset.pixivUgoiraPackage,
                    lezhinImageShuffle: asset.lezhinImageShuffle,
                    pythonSegmentDecorator: asset.pythonSegmentDecorator
                ))
            }
        }

        guard !assets.isEmpty else {
            throw NativeDownloadError.noFiles
        }

        var metadata = comicWalkerCollectionMetadata(
            title: cleanTitle,
            pageURL: pageURL,
            episodeDownloads: episodeDownloads,
            imageCount: assets.count
        )
        metadata["listed_episode_count"] = String(listedEpisodeCount ?? episodeDownloads.count)
        metadata["resolved_episode_count"] = String(episodeDownloads.count)
        metadata["resolved_media_count"] = String(assets.count)
        if let selectedPositions {
            metadata["range"] = rangeExpression
            metadata["range_scope"] = "collection_items"
            metadata["range_total"] = String(listedEpisodeCount ?? episodeDownloads.count)
            metadata["range_selected"] = String(selectedPositions.count)
            metadata["range_indexes"] = selectedPositions.map(String.init).joined(separator: ",")
        }

        return ResolvedDownload(
            title: cleanTitle,
            folderName: "ComicWalker \(cleanTitle)".sanitizedFilename(maxLength: 120),
            assets: assets,
            metadata: metadata
        )
    }

    static func episodeID(from url: URL) -> String? {
        let path = url.path
        guard let regex = try? NSRegularExpression(pattern: #"/episodes/([A-Za-z0-9_]+)"#) else {
            return nil
        }
        let range = NSRange(path.startIndex..<path.endIndex, in: path)
        guard let match = regex.firstMatch(in: path, range: range),
              let capture = Range(match.range(at: 1), in: path) else {
            return nil
        }
        return String(path[capture])
    }

    static func workID(from url: URL) -> String? {
        let parts = url.path.split(separator: "/").map(String.init)
        if let detailIndex = parts.firstIndex(where: { ["detail", "contents"].contains($0.lowercased()) }) {
            let tail = parts[(detailIndex + 1)...]
            if let candidate = tail.first(where: { $0.lowercased() != "detail" && $0.lowercased() != "episodes" }) {
                return candidate.removingPercentEncoding ?? candidate
            }
        }
        return nil
    }

    static func canonicalInputURL(for url: URL) -> URL? {
        guard let host = url.host?.lowercased(),
              isComicWalkerHost(host),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              canResolvePath(url.path) else {
            return nil
        }

        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.scheme = "https"
        components.host = apiHost(for: host)
        components.port = nil
        components.fragment = nil
        return components.url
    }

    static func canonicalDetailURL(for url: URL) -> URL? {
        guard let host = url.host?.lowercased(),
              isComicWalkerHost(host),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.path.lowercased().contains("/episodes/"),
              let workID = workID(from: url) else {
            return nil
        }

        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        let lower = parts.map { $0.lowercased() }
        var canonicalPath: String?
        if let contentsIndex = lower.firstIndex(of: "contents"),
           contentsIndex + 1 < parts.count,
           lower[contentsIndex + 1] == "detail" {
            canonicalPath = "/contents/detail/\(workID)"
        } else if lower.contains("detail") {
            canonicalPath = "/detail/\(workID)"
        }

        guard let path = canonicalPath else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = apiHost(for: host)
        components.path = path
        return components.url
    }

    static func episodeID(fromHTML html: String) -> String? {
        if let fromHref = episodeIDs(fromHTML: html).first {
            return fromHref
        }

        guard let data = nextData(fromHTML: html),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }
        return firstEpisodeID(in: object)
    }

    static func viewerEpisodeID(fromHTML html: String, episodeCode: String) -> String? {
        guard let data = nextData(fromHTML: html),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }
        return episodeEntries(in: object).first {
            $0.id.caseInsensitiveCompare(episodeCode) == .orderedSame
        }?.viewerID ?? matchingEpisodeEntry(in: object, episodeCode: episodeCode)?.viewerID
    }

    static func episodeIDs(fromHTML html: String) -> [String] {
        if let data = nextData(fromHTML: html),
           let object = try? JSONSerialization.jsonObject(with: data) {
            let structuredIDs = episodeIDs(in: object)
            if !structuredIDs.isEmpty {
                return structuredIDs
            }
        }
        return uniqueStrings(captureMatches(pattern: #"/episodes/([A-Za-z0-9_]+)"#, in: html))
    }

    static func episodes(fromHTML html: String, pageURL: URL, fallbackTitle: String? = nil) -> [ComicWalkerEpisode] {
        var anchorsByID: [String: (title: String, url: URL)] = [:]
        for anchor in episodeAnchors(fromHTML: html, pageURL: pageURL) {
            anchorsByID[anchor.id] = (anchor.title, anchor.url)
        }

        var rows: [(id: String, viewerID: String, rawTitle: String, url: URL)] = []
        if let data = nextData(fromHTML: html),
           let object = try? JSONSerialization.jsonObject(with: data) {
            for entry in episodeEntries(in: object) {
                guard !entry.id.trimmed.isEmpty else { continue }
                let title = entry.title.trimmed.isEmpty ? anchorsByID[entry.id]?.title ?? "" : entry.title
                let url = anchorsByID[entry.id]?.url ?? episodeURL(for: entry.id, pageURL: pageURL)
                rows.append((entry.id, entry.viewerID, title, url))
            }

            if let requestedCode = episodeID(from: pageURL),
               !rows.contains(where: { $0.id.caseInsensitiveCompare(requestedCode) == .orderedSame }),
               let entry = matchingEpisodeEntry(in: object, episodeCode: requestedCode) {
                let title = entry.title.trimmed.isEmpty ? anchorsByID[entry.id]?.title ?? "" : entry.title
                let url = anchorsByID[entry.id]?.url ?? episodeURL(for: entry.id, pageURL: pageURL)
                rows.append((entry.id, entry.viewerID, title, url))
            }
        }

        for anchor in episodeAnchors(fromHTML: html, pageURL: pageURL) where !rows.contains(where: { $0.id == anchor.id }) {
            rows.append((anchor.id, anchor.viewerID, anchor.title, anchor.url))
        }

        let fallback = fallbackTitle?.trimmed.isEmpty == false ? fallbackTitle! : title(fromHTML: html, pageURL: pageURL)
        var output: [ComicWalkerEpisode] = []
        var seenIDs = Set<String>()
        for (offset, row) in rows.enumerated() {
            guard !seenIDs.contains(row.id) else { continue }
            seenIDs.insert(row.id)
            let base = formattedEpisodeTitle(row.rawTitle.isEmpty ? fallback : row.rawTitle, episodeID: row.id)
            let title = base.isEmpty ? episodeOutputTitle(title: fallback, episodeID: row.id, episodeIndex: offset + 1) : base
            output.append(ComicWalkerEpisode(id: row.id, viewerID: row.viewerID, title: title, url: row.url))
        }
        return output
    }

    static func title(fromHTML html: String, pageURL: URL) -> String {
        if let data = nextData(fromHTML: html),
           let object = try? JSONSerialization.jsonObject(with: data),
           let title = workTitle(in: object) {
            return title
        }

        if let title = metaContent(from: html, names: ["og:title", "twitter:title"]) ?? titleTag(from: html) {
            return cleanTitle(title)
        }

        return episodeID(from: pageURL) ?? "ComicWalker Episode"
    }

    private static func manuscriptDictionaries(from object: [String: Any]) -> [[String: Any]] {
        if let manuscripts = object["manuscripts"] as? [[String: Any]] {
            return manuscripts
        }
        if let result = object["result"] as? [String: Any],
           let manuscripts = result["manuscripts"] as? [[String: Any]] {
            return manuscripts
        }
        if let data = object["data"] as? [String: Any],
           let manuscripts = data["manuscripts"] as? [[String: Any]] {
            return manuscripts
        }
        return []
    }

    private static func imageURL(from manuscript: [String: Any], baseURL: URL) -> URL? {
        let candidates = [
            stringValue(manuscript["drmImageUrl"]),
            stringValue(manuscript["imageUrl"]),
            stringValue(manuscript["url"])
        ]

        for candidate in candidates.compactMap({ $0 }).filter({ !$0.trimmed.isEmpty }) {
            if let url = absoluteURL(candidate, baseURL: baseURL) {
                return url
            }
        }
        return nil
    }

    private static func filename(for url: URL, prefix: String, index: Int) -> String {
        let ext = url.pathExtension.trimmed.isEmpty ? "jpg" : url.pathExtension
        return String(format: "%@ - %04d.%@", prefix, index, ext).sanitizedFilename(maxLength: 180)
    }

    static func comicWalkerMetadata(
        title: String,
        episodeID: String,
        viewerEpisodeID: String? = nil,
        pageURL: URL,
        imageCount: Int? = nil
    ) -> [String: String] {
        let workID = workID(from: pageURL) ?? ""
        return DownloadMetadata.clean([
            "series": title,
            "category": "comic",
            "type": "episode",
            "media_type": "image",
            "work_id": workID,
            "episode_id": episodeID,
            "viewer_episode_id": viewerEpisodeID ?? "",
            "chapter_id": episodeID,
            "gallery_id": episodeID,
            "media_count": imageCount.map(String.init) ?? "",
            "image_count": imageCount.map(String.init) ?? "",
            "slug": episodeID,
            "site": "ComicWalker",
            "title": title
        ])
    }

    static func comicWalkerCollectionMetadata(title: String, pageURL: URL, episodeDownloads: [(episodeID: String, resolved: ResolvedDownload)], imageCount: Int? = nil) -> [String: String] {
        let workID = workID(from: pageURL) ?? ""
        let firstEpisode = episodeDownloads.first?.episodeID ?? ""
        return DownloadMetadata.clean([
            "series": title,
            "category": "comic",
            "type": "series",
            "media_type": "image",
            "work_id": workID,
            "episode_id": firstEpisode,
            "chapter_id": firstEpisode,
            "gallery_id": workID.isEmpty ? firstEpisode : workID,
            "episode_count": String(episodeDownloads.count),
            "media_count": imageCount.map(String.init) ?? "",
            "image_count": imageCount.map(String.init) ?? "",
            "slug": workID.isEmpty ? firstEpisode : workID,
            "site": "ComicWalker",
            "title": title
        ])
    }

    private static func assetMetadata(
        seriesTitle: String,
        episodeTitle: String,
        episodeID: String,
        viewerEpisodeID: String?,
        pageURL: URL,
        remote: URL,
        index: Int,
        drmHash: String?,
        drmMode: String
    ) -> [String: String] {
        let workID = workID(from: pageURL) ?? ""
        let format = mediaFormat(for: remote)
        return DownloadMetadata.clean([
            "series": seriesTitle,
            "category": "comic",
            "episode": episodeTitle,
            "chapter": episodeTitle,
            "type": "image",
            "media_type": "image",
            "work_id": workID,
            "episode_id": episodeID,
            "viewer_episode_id": viewerEpisodeID ?? "",
            "chapter_id": episodeID,
            "gallery_id": episodeID,
            "id": episodeID,
            "page": String(index),
            "position": String(index),
            "format": format,
            "media_format": format,
            "image_url": remote.absoluteString,
            "media_url": remote.absoluteString,
            "source_url": remote.absoluteString,
            "page_url": pageURL.absoluteString,
            "drm_mode": drmMode,
            "drm_hash": drmHash ?? "",
            "xor_key": drmHash ?? "",
            "site": "ComicWalker",
            "title": episodeTitle
        ])
    }

    private static func mediaFormat(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        if ext == "jpeg" {
            return "jpg"
        }
        return ext.isEmpty ? "jpg" : ext
    }

    private static func nextData(fromHTML html: String) -> Data? {
        guard let regex = try? NSRegularExpression(
            pattern: #"<script\b[^>]*\bid\s*=\s*["']__NEXT_DATA__["'][^>]*>(.*?)</script>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return nil
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, range: range),
              let capture = Range(match.range(at: 1), in: html) else {
            return nil
        }
        return decodeHTML(String(html[capture])).data(using: .utf8)
    }

    private static func firstEpisodeID(in object: Any) -> String? {
        episodeEntries(in: object).first?.id
    }

    private static func episodeIDs(in object: Any) -> [String] {
        episodeEntries(in: object).map(\.id)
    }

    private static func episodeEntries(in object: Any) -> [(id: String, viewerID: String, title: String)] {
        var output: [(id: String, viewerID: String, title: String)] = []
        if let dictionary = object as? [String: Any] {
            for key in ["firstEpisodes", "episodes", "episodeList"] {
                if let episodes = dictionary[key] as? [[String: Any]] {
                    output.append(contentsOf: episodes.compactMap(episodeEntry))
                }
            }

            if let result = dictionary["result"] as? [String: Any],
               let entry = episodeEntry(result) {
                output.append(entry)
            }
            if let result = dictionary["result"] as? [[String: Any]] {
                output.append(contentsOf: result.compactMap(episodeEntry))
            }

            for value in dictionary.values {
                output.append(contentsOf: episodeEntries(in: value))
            }
        } else if let array = object as? [Any] {
            for value in array {
                output.append(contentsOf: episodeEntries(in: value))
            }
        }
        return uniqueEpisodeEntries(output)
    }

    private static func episodeEntry(_ episode: [String: Any]) -> (id: String, viewerID: String, title: String)? {
        let viewerID = stringValue(episode["id"]) ??
            stringValue(episode["episodeId"]) ??
            stringValue(episode["code"]) ??
            stringValue(episode["episodeCode"])
        guard let viewerID, !viewerID.trimmed.isEmpty else { return nil }

        let code = stringValue(episode["code"]) ??
            stringValue(episode["episodeCode"]) ??
            viewerID
        let title = stringValue(episode["title"]) ??
            stringValue(episode["episodeTitle"]) ??
            stringValue(episode["name"]) ??
            ""
        return (code, viewerID, title)
    }

    private static func matchingEpisodeEntry(
        in object: Any,
        episodeCode: String
    ) -> (id: String, viewerID: String, title: String)? {
        if let dictionary = object as? [String: Any] {
            for value in dictionary.values {
                if let entry = matchingEpisodeEntry(in: value, episodeCode: episodeCode) {
                    return entry
                }
            }
            if let entry = episodeEntry(dictionary),
               entry.id.caseInsensitiveCompare(episodeCode) == .orderedSame {
                return entry
            }
        } else if let array = object as? [Any] {
            for value in array {
                if let entry = matchingEpisodeEntry(in: value, episodeCode: episodeCode) {
                    return entry
                }
            }
        }
        return nil
    }

    private static func episodeAnchors(fromHTML html: String, pageURL: URL) -> [ComicWalkerEpisode] {
        guard let regex = try? NSRegularExpression(
            pattern: #"<a\b([^>]*)>(.*?)</a>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return []
        }

        var output: [ComicWalkerEpisode] = []
        var seen = Set<String>()
        let expectedWorkID = workID(from: pageURL)
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        for match in regex.matches(in: html, range: range) {
            guard let attrRange = Range(match.range(at: 1), in: html),
                  let bodyRange = Range(match.range(at: 2), in: html) else {
                continue
            }
            let values = attributeValues(from: String(html[attrRange]))
            guard let href = values["href"],
                  let url = absoluteURL(href, baseURL: pageURL),
                  let id = episodeID(from: url),
                  expectedWorkID == nil || workID(from: url)?.caseInsensitiveCompare(expectedWorkID!) == .orderedSame,
                  !seen.contains(id) else {
                continue
            }
            seen.insert(id)
            let rawTitle = cleanTitle(stripTags(String(html[bodyRange])))
            output.append(ComicWalkerEpisode(id: id, title: rawTitle, url: url))
        }
        return output
    }

    private static func episodeURL(for episodeID: String, pageURL: URL) -> URL {
        if let workID = workID(from: pageURL),
           var components = URLComponents(url: pageURL, resolvingAgainstBaseURL: false) {
            let path = pageURL.path.lowercased().contains("/contents/detail/")
                ? "/contents/detail/\(workID)/episodes/\(episodeID)"
                : "/detail/\(workID)/episodes/\(episodeID)"
            components.path = path
            components.queryItems = nil
            if let url = components.url {
                return url
            }
        }
        return pageURL
    }

    private static func duplicateBaseTitles(in episodes: [ComicWalkerEpisode]) -> Set<String> {
        var counts: [String: Int] = [:]
        for episode in episodes {
            counts[episode.title.lowercased(), default: 0] += 1
        }
        return Set(counts.compactMap { $0.value > 1 ? $0.key : nil })
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
            throw NativeDownloadError.unsupported("Range did not match any ComicWalker episodes.")
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

    private static func uniqueEpisodeEntries(
        _ entries: [(id: String, viewerID: String, title: String)]
    ) -> [(id: String, viewerID: String, title: String)] {
        var output: [(id: String, viewerID: String, title: String)] = []
        var seen = Set<String>()
        for entry in entries where !seen.contains(entry.id) {
            seen.insert(entry.id)
            output.append(entry)
        }
        return output
    }

    private static func episodeOutputTitle(title: String, episodeID: String, episodeIndex: Int?, forceIndex: Bool = false) -> String {
        let base = formattedEpisodeTitle(title, episodeID: episodeID)
        if let episodeIndex, forceIndex || !isNumberedEpisodeTitle(base) {
            return String(format: "%04d - %@", episodeIndex, base).sanitizedFilename(maxLength: 120)
        }
        if base.isEmpty {
            return episodeID.sanitizedFilename(maxLength: 120)
        }
        return base.sanitizedFilename(maxLength: 120)
    }

    private static func formattedEpisodeTitle(_ raw: String, episodeID: String) -> String {
        let title = cleanTitle(raw)
        let pieces = title.split(separator: "_", maxSplits: 1, omittingEmptySubsequences: true).map(String.init)
        if pieces.count == 2, let number = Int(pieces[0].trimmed) {
            return String(format: "%04d - %@", number, pieces[1].trimmed).sanitizedFilename(maxLength: 120)
        }
        return (title.isEmpty ? episodeID : title).sanitizedFilename(maxLength: 120)
    }

    private static func isNumberedEpisodeTitle(_ title: String) -> Bool {
        let patterns = [
            #"^\d{1,4}\s*[-_.]"#,
            #"^第\s*\d+\s*話"#,
            #"^\d+\s*화"#
        ]
        return patterns.contains { pattern in
            title.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }
    }

    private static func workTitle(in object: Any) -> String? {
        if let dictionary = object as? [String: Any] {
            if let work = dictionary["work"] as? [String: Any],
               let title = stringValue(work["title"]) {
                return title
            }
            if let title = stringValue(dictionary["title"]),
               dictionary.keys.contains(where: { ["work", "workCode", "firstEpisodes", "result"].contains($0) }) {
                return title
            }
            for value in dictionary.values {
                if let title = workTitle(in: value) {
                    return title
                }
            }
        } else if let array = object as? [Any] {
            for value in array {
                if let title = workTitle(in: value) {
                    return title
                }
            }
        }
        return nil
    }

    private static func metaContent(from html: String, names: Set<String>) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"<meta\b([^>]*)>"#, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        for match in regex.matches(in: html, range: range) {
            guard let attributesRange = Range(match.range(at: 1), in: html) else { continue }
            let values = attributeValues(from: String(html[attributesRange]))
            let key = (values["property"] ?? values["name"] ?? values["itemprop"])?.lowercased()
            guard let key, names.contains(key),
                  let content = values["content"]?.trimmed,
                  !content.isEmpty else {
                continue
            }
            return content
        }
        return nil
    }

    private static func titleTag(from html: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: #"<title\b[^>]*>(.*?)</title>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return nil
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, range: range),
              let titleRange = Range(match.range(at: 1), in: html) else {
            return nil
        }
        return cleanTitle(String(html[titleRange]))
    }

    private static func cleanTitle(_ raw: String) -> String {
        var title = decodeHTML(stripTags(raw))
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmed
        for suffix in [" | ComicWalker", " - ComicWalker", " | カドコミ"] {
            if title.lowercased().hasSuffix(suffix.lowercased()) {
                title.removeLast(suffix.count)
                title = title.trimmed
            }
        }
        return title.isEmpty ? "ComicWalker Episode" : title
    }

    private static func capture(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let capture = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[capture])
    }

    private static func captureMatches(pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > 1,
                  let capture = Range(match.range(at: 1), in: text) else {
                return nil
            }
            return String(text[capture])
        }
    }

    private static func attributeValues(from attributes: String) -> [String: String] {
        guard let regex = try? NSRegularExpression(
            pattern: #"\b([A-Za-z_:][-A-Za-z0-9_:.]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>"']+))"#,
            options: [.caseInsensitive]
        ) else {
            return [:]
        }

        let range = NSRange(attributes.startIndex..<attributes.endIndex, in: attributes)
        var values: [String: String] = [:]
        for match in regex.matches(in: attributes, range: range) {
            guard let nameRange = Range(match.range(at: 1), in: attributes) else { continue }
            let name = String(attributes[nameRange]).lowercased()
            for group in 2...4 {
                guard let valueRange = Range(match.range(at: group), in: attributes) else { continue }
                values[name] = decodeHTML(String(attributes[valueRange])).trimmed
                break
            }
        }
        return values
    }

    private static func absoluteURL(_ raw: String, baseURL: URL) -> URL? {
        let value = raw.trimmed
        if value.hasPrefix("//") {
            return URL(string: "\(baseURL.scheme ?? "https"):\(value)")
        }
        return URL(string: value, relativeTo: baseURL)?.absoluteURL
    }

    private static func apiHost(for host: String?) -> String {
        host?.lowercased().hasSuffix(".test") == true ? "comic-walker.test" : "comic-walker.com"
    }

    private static func isComicWalkerHost(_ host: String) -> Bool {
        host == "comic-walker.com" ||
            host == "comic-walker.jp" ||
            host == "www.comic-walker.com" ||
            host == "www.comic-walker.jp" ||
            host == "comic-walker.test"
    }

    private static func canResolvePath(_ path: String) -> Bool {
        let lower = path.lowercased()
        return lower.contains("/episodes/") ||
            lower.contains("/contents/detail/") ||
            lower.contains("/detail/")
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        if let int = value as? Int { return String(int) }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    private static func stripTags(_ text: String) -> String {
        text
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmed
    }

    private static func decodeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }

    private static func uniqueStrings(_ values: [String]) -> [String] {
        var output: [String] = []
        var seen = Set<String>()
        for value in values {
            let trimmed = value.trimmed
            guard !trimmed.isEmpty, !seen.contains(trimmed) else { continue }
            seen.insert(trimmed)
            output.append(trimmed)
        }
        return output
    }
}
