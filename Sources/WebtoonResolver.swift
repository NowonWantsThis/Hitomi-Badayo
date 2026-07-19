import Foundation

final class WebtoonResolver {
    private let maxListPages = 100

    func canResolve(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(),
              Self.isWebtoonHost(host),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return false
        }

        return Self.isEpisodeURL(url) || Self.isListURL(url)
    }

    func resolve(
        _ url: URL,
        headers: HTTPRequestOptions = HTTPRequestOptions(),
        rangeExpression: String = ""
    ) async throws -> ResolvedDownload {
        let inputURL = Self.normalizedPageURL(url)
        let inputHTML = try await HTTPClient.shared.string(
            from: inputURL,
            referer: headers.referer,
            userAgent: headers.userAgent
        )

        let collectionURL: URL
        if Self.isEpisodeURL(inputURL) {
            guard let mainURL = Self.mainListURL(fromHTML: inputHTML, pageURL: inputURL) else {
                throw NativeDownloadError.unsupported("WEBTOON episode did not expose its series list URL.")
            }
            collectionURL = mainURL
        } else {
            collectionURL = inputURL
        }

        guard let firstListURL = Self.listPageURL(collectionURL, page: 1) else {
            throw NativeDownloadError.invalidURL(collectionURL.absoluteString)
        }
        let firstHTML: String
        if URLIdentity.normalize(firstListURL.absoluteString) == URLIdentity.normalize(inputURL.absoluteString) {
            firstHTML = inputHTML
        } else {
            try Task.checkCancellation()
            firstHTML = try await HTTPClient.shared.string(
                from: firstListURL,
                referer: inputURL.absoluteString,
                userAgent: headers.userAgent
            )
        }
        return try await resolveList(
            fromHTML: firstHTML,
            pageURL: firstListURL,
            headers: headers,
            rangeExpression: rangeExpression
        )
    }

    private func resolveList(
        fromHTML html: String,
        pageURL: URL,
        headers: HTTPRequestOptions,
        rangeExpression: String
    ) async throws -> ResolvedDownload {
        var discoveredEpisodes: [URL] = []
        var seenEpisodes = Set<String>()
        var listPageCount = 0

        for page in 1...maxListPages {
            try Task.checkCancellation()
            guard let listURL = Self.listPageURL(pageURL, page: page) else { break }
            let listHTML: String
            if page == 1 {
                listHTML = html
            } else {
                listHTML = try await HTTPClient.shared.string(
                    from: listURL,
                    referer: pageURL.absoluteString,
                    userAgent: headers.userAgent
                )
            }
            listPageCount += 1

            var newEpisodes: [URL] = []
            for episodeURL in Self.episodeURLs(fromHTML: listHTML, baseURL: listURL) {
                let identity = URLIdentity.normalize(episodeURL.absoluteString)
                guard seenEpisodes.insert(identity).inserted else { continue }
                newEpisodes.append(episodeURL)
            }
            guard !newEpisodes.isEmpty else { break }
            discoveredEpisodes.append(contentsOf: newEpisodes)
        }

        let episodeURLs = Array(discoveredEpisodes.reversed())
        guard !episodeURLs.isEmpty else {
            throw NativeDownloadError.noFiles
        }

        let itemRange = rangeExpression.trimmed
        var selectedEpisodes = Array(episodeURLs.enumerated())
        var selectedPositions: [Int]?
        if !itemRange.isEmpty {
            let indexes = try Self.itemIndexes(for: itemRange, total: episodeURLs.count)
            selectedEpisodes = indexes.map { (offset: $0, element: episodeURLs[$0]) }
            selectedPositions = indexes.map { $0 + 1 }
        }

        var assets: [ResolvedAsset] = []
        var seenAssets = Set<String>()
        var resolvedEpisodeCount = 0
        for selectedEpisode in selectedEpisodes {
            try Task.checkCancellation()
            let episodeURL = selectedEpisode.element
            let episodeHTML = try await HTTPClient.shared.string(
                from: episodeURL,
                referer: pageURL.absoluteString,
                userAgent: headers.userAgent
            )
            let resolved = try Self.resolvedDownload(fromHTML: episodeHTML, pageURL: episodeURL)
            resolvedEpisodeCount += 1

            for asset in resolved.assets {
                let normalized = URLIdentity.normalize(asset.remoteURL.absoluteString)
                guard !seenAssets.contains(normalized) else { continue }
                seenAssets.insert(normalized)
                var metadata = asset.metadata
                metadata["collection_position"] = String(selectedEpisode.offset + 1)
                metadata["episode_position"] = String(selectedEpisode.offset + 1)
                assets.append(ResolvedAsset(
                    remoteURL: asset.remoteURL,
                    filename: Self.combinedEpisodeFilename(
                        asset.filename,
                        episodeURL: episodeURL,
                        episodeIndex: selectedEpisode.offset + 1
                    ),
                    metadata: metadata,
                    referer: asset.referer ?? episodeURL.absoluteString
                ))
            }
        }

        guard !assets.isEmpty else {
            throw NativeDownloadError.noFiles
        }

        let title = Self.collectionTitle(fromHTML: html, pageURL: pageURL) ?? "WEBTOON Series"
        var metadata = Self.webtoonMetadata(
            series: title,
            pageURL: pageURL,
            imageCount: assets.count,
            episodeCount: resolvedEpisodeCount,
            type: "series"
        )
        metadata["listed_episode_count"] = String(episodeURLs.count)
        metadata["resolved_episode_count"] = String(resolvedEpisodeCount)
        metadata["resolved_media_count"] = String(assets.count)
        metadata["list_page_count"] = String(listPageCount)
        if let selectedPositions {
            metadata["range"] = itemRange
            metadata["range_scope"] = "collection_items"
            metadata["range_total"] = String(episodeURLs.count)
            metadata["range_selected"] = String(selectedPositions.count)
            metadata["range_indexes"] = selectedPositions.map(String.init).joined(separator: ",")
        }
        return ResolvedDownload(
            title: title.sanitizedFilename(maxLength: 120),
            folderName: "WEBTOON \(title)".sanitizedFilename(maxLength: 120),
            assets: assets,
            metadata: metadata
        )
    }

    static func resolvedDownload(fromHTML html: String, pageURL: URL) throws -> ResolvedDownload {
        let imageURLs = extractImageURLs(from: html, pageURL: pageURL)
        guard !imageURLs.isEmpty else {
            throw NativeDownloadError.noFiles
        }

        let title = episodeTitle(from: html, pageURL: pageURL).sanitizedFilename(maxLength: 120)
        let series = seriesTitle(from: html)?.sanitizedFilename(maxLength: 100)
        let assets = imageURLs.enumerated().map { offset, remote in
            let index = offset + 1
            return ResolvedAsset(
                remoteURL: remote,
                filename: filename(for: remote, index: index),
                metadata: assetMetadata(series: series, episodeTitle: title, pageURL: pageURL, remote: remote, index: index),
                referer: pageURL.absoluteString
            )
        }

        let folderTitle = [series, title].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " - ")
        return ResolvedDownload(
            title: title,
            folderName: "WEBTOON \(folderTitle.isEmpty ? title : folderTitle)".sanitizedFilename(maxLength: 120),
            assets: assets,
            metadata: webtoonMetadata(series: series, pageURL: pageURL, imageCount: assets.count, episodeCount: 1, type: "episode")
        )
    }

    static func extractImageURLs(from html: String, pageURL: URL) -> [URL] {
        let normalizedHTML = normalizeEscapes(decodeHTML(html))
        var candidates = viewerImageCandidates(from: normalizedHTML)
        candidates.append(contentsOf: scriptedImageCandidates(from: normalizedHTML))

        var urls: [URL] = []
        var seen = Set<String>()
        for candidate in candidates {
            guard let remote = absoluteURL(candidate, baseURL: pageURL),
                  isImageURL(remote) else {
                continue
            }

            let normalized = URLIdentity.normalize(remote.absoluteString)
            guard !seen.contains(normalized) else { continue }
            seen.insert(normalized)
            urls.append(remote)
        }
        return urls
    }

    private static func viewerImageCandidates(from html: String) -> [String] {
        guard let regex = try? NSRegularExpression(
            pattern: #"<img\b([^>]*)>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return []
        }

        var candidates: [String] = []
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        for match in regex.matches(in: html, range: range) {
            guard let attributesRange = Range(match.range(at: 1), in: html) else { continue }
            let attributes = String(html[attributesRange])
            let values = attributeValues(from: attributes)
            let className = values["class"]?.lowercased() ?? ""
            let isViewerImage = className.contains("_images") ||
                className.contains("viewer_img") ||
                values["data-url"] != nil ||
                values["data-original"] != nil
            guard isViewerImage else { continue }

            for key in ["data-url", "data-src", "data-original", "src"] {
                if let value = values[key]?.trimmed, !value.isEmpty {
                    candidates.append(value)
                    break
                }
            }
        }
        return candidates
    }

    private static func scriptedImageCandidates(from html: String) -> [String] {
        let patterns = [
            #""(?:viewer_img|imageUrl|image_url|dataUrl|url|src)"\s*:\s*"([^"]+\.(?:jpg|jpeg|png|webp|gif)(?:\?[^"]*)?)""#,
            #"'(?:viewer_img|imageUrl|image_url|dataUrl|url|src)'\s*:\s*'([^']+\.(?:jpg|jpeg|png|webp|gif)(?:\?[^']*)?)'"#
        ]

        return patterns.flatMap { pattern in
            captureGroupMatches(pattern: pattern, in: html)
        }
    }

    private static func episodeTitle(from html: String, pageURL: URL) -> String {
        let normalizedHTML = decodeHTML(html)
        let title = textForClass("subj_episode", in: normalizedHTML) ??
            metaContent(from: normalizedHTML, names: ["og:title", "twitter:title"]) ??
            titleTag(from: normalizedHTML) ??
            fallbackTitle(from: pageURL)
        return cleanTitle(title, pageURL: pageURL)
    }

    private static func seriesTitle(from html: String) -> String? {
        let normalizedHTML = decodeHTML(html)
        return textForClass("subj_info", in: normalizedHTML) ??
            metaContent(from: normalizedHTML, names: ["webtoon:series", "article:section"])
    }

    static func collectionTitle(fromHTML html: String, pageURL: URL) -> String? {
        let normalizedHTML = decodeHTML(html)
        let title = metaContent(from: normalizedHTML, names: ["webtoon:series", "og:title", "twitter:title"]) ??
            textForClass("subj_info", in: normalizedHTML) ??
            textForClass("subj", in: normalizedHTML) ??
            titleTag(from: normalizedHTML)
        return title.map { cleanTitle($0, pageURL: pageURL) }.flatMap { $0.isEmpty ? nil : $0 }
    }

    static func episodeURLs(fromHTML html: String, baseURL: URL) -> [URL] {
        let normalizedHTML = normalizeEscapes(decodeHTML(html))
        var output: [URL] = []

        for values in anchorAttributeValues(from: normalizedHTML) {
            if let href = values["href"],
               let url = absoluteURL(href, baseURL: baseURL),
               isEpisodeURL(url) {
                output.append(canonicalURL(url))
            }

            if let episodeNo = values["data-episode-no"]?.trimmed,
               !episodeNo.isEmpty,
               let url = episodeURL(forEpisodeNo: episodeNo, baseURL: baseURL) {
                output.append(canonicalURL(url))
            }
        }

        return uniqueURLs(output)
    }

    static func listPageURLs(fromHTML html: String, baseURL: URL) -> [URL] {
        let normalizedHTML = normalizeEscapes(decodeHTML(html))
        let current = URLIdentity.normalize(canonicalURL(baseURL).absoluteString)
        let urls = anchorAttributeValues(from: normalizedHTML).compactMap { values -> URL? in
            guard let href = values["href"],
                  let url = absoluteURL(href, baseURL: baseURL),
                  isListURL(url),
                  queryValue("page", in: url) != nil else {
                return nil
            }
            let canonical = canonicalURL(url)
            return URLIdentity.normalize(canonical.absoluteString) == current ? nil : canonical
        }
        return uniqueURLs(urls)
    }

    static func mainListURL(fromHTML html: String, pageURL: URL) -> URL? {
        let normalizedHTML = normalizeEscapes(decodeHTML(html))
        guard let regex = try? NSRegularExpression(
            pattern: #"<div\b[^>]*\bclass\s*=\s*[\"'][^\"']*subj_info[^\"']*[\"'][^>]*>(.*?)</div>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return nil
        }
        let range = NSRange(normalizedHTML.startIndex..<normalizedHTML.endIndex, in: normalizedHTML)
        guard let match = regex.firstMatch(in: normalizedHTML, range: range),
              let bodyRange = Range(match.range(at: 1), in: normalizedHTML) else {
            return nil
        }
        for values in anchorAttributeValues(from: String(normalizedHTML[bodyRange])) {
            guard let href = values["href"],
                  let candidate = absoluteURL(href, baseURL: pageURL),
                  isListURL(candidate) else {
                continue
            }
            return canonicalURL(candidate)
        }
        return nil
    }

    static func listPageURL(_ baseURL: URL, page: Int) -> URL? {
        guard page > 0,
              isListURL(baseURL),
              var components = URLComponents(url: canonicalURL(baseURL), resolvingAgainstBaseURL: false) else {
            return nil
        }
        var items = components.queryItems ?? []
        items.removeAll { $0.name.lowercased() == "page" }
        if page > 1 {
            items.append(URLQueryItem(name: "page", value: String(page)))
        }
        components.queryItems = items
        components.fragment = nil
        return components.url
    }

    static func normalizedPageURL(_ url: URL) -> URL {
        guard let host = url.host?.lowercased(),
              isWebtoonHost(host),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        components.scheme = components.scheme ?? "https"
        components.host = host.hasSuffix(".test") ? "webtoons.test" : "www.webtoons.com"
        return components.url ?? url
    }

    static func canonicalContentURL(for url: URL) -> URL? {
        guard isEpisodeURL(url) || isListURL(url) else {
            return nil
        }
        return canonicalURL(url)
    }

    private static func textForClass(_ className: String, in html: String) -> String? {
        let pattern = #"<[^>]*\bclass\s*=\s*["'][^"']*"# + NSRegularExpression.escapedPattern(for: className) + #"[^"']*["'][^>]*>(.*?)</[^>]+>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, range: range),
              let capture = Range(match.range(at: 1), in: html) else {
            return nil
        }
        let text = stripTags(String(html[capture])).trimmed
        return text.isEmpty ? nil : text
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

        let title = stripTags(String(html[titleRange])).trimmed
        return title.isEmpty ? nil : title
    }

    private static func fallbackTitle(from url: URL) -> String {
        let episode = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name.lowercased() == "episode_no" }?
            .value
        return episode.map { "Episode \($0)" } ?? "WEBTOON Episode"
    }

    private static func cleanTitle(_ raw: String, pageURL: URL) -> String {
        var title = stripTags(raw)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmed

        for suffix in [" | WEBTOON", " - WEBTOON", " | LINE WEBTOON"] {
            if title.lowercased().hasSuffix(suffix.lowercased()) {
                title.removeLast(suffix.count)
                title = title.trimmed
            }
        }

        if title.isEmpty || title.lowercased() == "webtoon" {
            return fallbackTitle(from: pageURL)
        }
        return title
    }

    private static func filename(for url: URL, index: Int) -> String {
        let ext = mediaFormat(for: url)
        return String(format: "%04d.%@", index, ext).sanitizedFilename(maxLength: 120)
    }

    private static func webtoonMetadata(series: String?, pageURL: URL? = nil, imageCount: Int? = nil, episodeCount: Int? = nil, type: String = "episode") -> [String: String] {
        let titleID = pageURL.flatMap { queryValue("title_no", in: $0) }
        let episodeID = pageURL.flatMap { queryValue("episode_no", in: $0) }
        let id = episodeID ?? titleID ?? ""
        return DownloadMetadata.clean([
            "series": series ?? "",
            "category": series ?? "",
            "channel": series ?? "",
            "uploader": series ?? "",
            "site": "WEBTOON",
            "type": type,
            "media_type": "image",
            "media_count": imageCount.map(String.init) ?? "",
            "image_count": imageCount.map(String.init) ?? "",
            "episode_count": episodeCount.map(String.init) ?? "",
            "title_id": titleID ?? "",
            "episode_id": episodeID ?? "",
            "chapter_id": episodeID ?? "",
            "gallery_id": id,
            "id": id
        ])
    }

    private static func assetMetadata(series: String?, episodeTitle: String, pageURL: URL, remote: URL, index: Int) -> [String: String] {
        let titleID = queryValue("title_no", in: pageURL) ?? ""
        let episodeID = queryValue("episode_no", in: pageURL) ?? ""
        let id = episodeID.isEmpty ? titleID : episodeID
        let format = mediaFormat(for: remote)
        return DownloadMetadata.clean([
            "series": series ?? "",
            "category": series ?? "",
            "channel": series ?? "",
            "uploader": series ?? "",
            "site": "WEBTOON",
            "title": episodeTitle,
            "episode": episodeTitle,
            "chapter": episodeTitle,
            "title_id": titleID,
            "episode_id": episodeID,
            "chapter_id": episodeID,
            "gallery_id": id,
            "id": id,
            "type": "image",
            "media_type": "image",
            "page": String(index),
            "position": String(index),
            "format": format,
            "media_format": format,
            "image_url": remote.absoluteString,
            "media_url": remote.absoluteString,
            "source_url": remote.absoluteString,
            "page_url": pageURL.absoluteString
        ])
    }

    private static func mediaFormat(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        if ext == "jpeg" {
            return "jpg"
        }
        return ext.isEmpty ? "jpg" : ext
    }

    private static func combinedEpisodeFilename(_ assetFilename: String, episodeURL: URL, episodeIndex: Int) -> String {
        let episodeID = queryValue("episode_no", in: episodeURL) ?? String(format: "%04d", episodeIndex)
        let base = (assetFilename as NSString).deletingPathExtension
        let ext = (assetFilename as NSString).pathExtension
        let stem = "episode-\(episodeID)-\(base)"
        let filename = ext.isEmpty ? stem : "\(stem).\(ext)"
        return filename.sanitizedFilename(maxLength: 180)
    }

    private static func episodeURL(forEpisodeNo episodeNo: String, baseURL: URL) -> URL? {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.fragment = nil
        components.path = components.path.replacingOccurrences(of: "/list", with: "/viewer", options: [.caseInsensitive])

        var items = components.queryItems ?? []
        items.removeAll { ["episode_no", "page"].contains($0.name.lowercased()) }
        items.append(URLQueryItem(name: "episode_no", value: episodeNo))
        components.queryItems = items
        return components.url.flatMap { isEpisodeURL($0) ? $0 : nil }
    }

    private static func sortedEpisodeURLs(_ urls: [URL]) -> [URL] {
        let keyed = urls.enumerated().map { offset, url in
            (offset: offset, url: url, episode: queryValue("episode_no", in: url).flatMap(Int.init))
        }
        guard keyed.allSatisfy({ $0.episode != nil }) else {
            return urls
        }
        return keyed.sorted {
            if $0.episode == $1.episode {
                return $0.offset < $1.offset
            }
            return ($0.episode ?? 0) < ($1.episode ?? 0)
        }.map(\.url)
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
            throw NativeDownloadError.unsupported("Range did not match any WEBTOON episodes.")
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

    private static func uniqueURLs(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        var output: [URL] = []
        for url in urls {
            let normalized = URLIdentity.normalize(url.absoluteString)
            guard !seen.contains(normalized) else { continue }
            seen.insert(normalized)
            output.append(url)
        }
        return output
    }

    private static func anchorAttributeValues(from html: String) -> [[String: String]] {
        guard let regex = try? NSRegularExpression(
            pattern: #"<a\b([^>]*)>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return []
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        return regex.matches(in: html, range: range).compactMap { match in
            guard let attributesRange = Range(match.range(at: 1), in: html) else { return nil }
            return attributeValues(from: String(html[attributesRange]))
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

    private static func captureGroupMatches(pattern: String, in text: String) -> [String] {
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

    private static func absoluteURL(_ raw: String, baseURL: URL) -> URL? {
        let value = raw.trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "\"'(),;"))
        guard !value.isEmpty else { return nil }
        if value.hasPrefix("//") {
            return URL(string: "\(baseURL.scheme ?? "https"):\(value)")
        }
        return URL(string: value, relativeTo: baseURL)?.absoluteURL
    }

    private static func isImageURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return false
        }
        return imageExtensions.contains(url.pathExtension.lowercased())
    }

    private static func isWebtoonHost(_ host: String) -> Bool {
        host == "webtoon.com" ||
            host == "www.webtoon.com" ||
            host == "webtoons.com" ||
            host == "www.webtoons.com" ||
            host == "webtoon.test" ||
            host == "webtoons.test"
    }

    private static func isEpisodeURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(),
              isWebtoonHost(host),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return false
        }
        let path = url.path.lowercased()
        return path.contains("/viewer") ||
            URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.contains { $0.name.lowercased() == "episode_no" } == true
    }

    private static func isListURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(),
              isWebtoonHost(host),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return false
        }
        let path = url.path.lowercased()
        guard path.contains("/list") else { return false }
        return queryValue("title_no", in: url) != nil || URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.isEmpty == false
    }

    private static func canonicalURL(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        components.fragment = nil
        if let host = components.host?.lowercased(), isWebtoonHost(host) {
            components.host = host.hasSuffix(".test") ? "webtoons.test" : "www.webtoons.com"
        }
        return components.url ?? url
    }

    private static func queryValue(_ name: String, in url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name.lowercased() == name.lowercased() }?
            .value
    }

    private static func normalizeEscapes(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\/", with: "/")
            .replacingOccurrences(of: "\\u002F", with: "/", options: .caseInsensitive)
            .replacingOccurrences(of: "\\u003A", with: ":", options: .caseInsensitive)
            .replacingOccurrences(of: "\\u0026", with: "&", options: .caseInsensitive)
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

    private static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "webp", "gif"
    ]
}
