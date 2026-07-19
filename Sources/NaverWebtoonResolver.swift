import Foundation

struct NaverWebtoonEpisode: Equatable {
    var number: Int
    var subtitle: String
    var thumbnailURL: URL?
    var charge: Bool
    var locked: Bool
}

struct NaverWebtoonArticlePage: Equatable {
    var episodes: [NaverWebtoonEpisode]
    var totalCount: Int
    var page: Int
    var totalPages: Int
    var nextPage: Int?
}

struct NaverWebtoonSeriesInfo: Equatable {
    var title: String
    var author: String
    var thumbnailURL: URL?
}

final class NaverWebtoonResolver {
    static let maximumListPageNumber = 99

    func canResolve(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(),
              Self.isNaverComicHost(host),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return false
        }

        return Self.isDetailURL(url) || Self.isListURL(url)
    }

    func resolve(
        _ url: URL,
        headers: HTTPRequestOptions = HTTPRequestOptions(),
        rangeExpression: String = ""
    ) async throws -> ResolvedDownload {
        let sourceURL: URL
        if Self.isDetailURL(url) {
            sourceURL = Self.canonicalDetailURL(url) ?? url
        } else {
            sourceURL = Self.canonicalListURL(url) ?? url
        }

        let html = try await HTTPClient.shared.string(from: sourceURL, referer: headers.referer, userAgent: headers.userAgent)
        if Self.isDetailURL(sourceURL) {
            return try await Self.resolvedEpisodeDownload(fromHTML: html, pageURL: sourceURL, headers: headers)
        }
        return try await resolvedCollectionDownload(
            fromFirstHTML: html,
            listURL: sourceURL,
            headers: headers,
            rangeExpression: rangeExpression
        )
    }

    private static func resolvedEpisodeDownload(fromHTML html: String, pageURL: URL, headers: HTTPRequestOptions) async throws -> ResolvedDownload {
        let documentCandidates = await effecttoonDocumentImageCandidates(fromHTML: html, pageURL: pageURL, headers: headers)
        return try resolvedDownload(fromHTML: html, pageURL: pageURL, additionalImageCandidates: documentCandidates)
    }

    static func resolvedDownload(fromHTML html: String, pageURL: URL, additionalImageCandidates: [String] = []) throws -> ResolvedDownload {
        let imageURLs = extractImageURLs(from: html, pageURL: pageURL, additionalImageCandidates: additionalImageCandidates)
        guard !imageURLs.isEmpty else {
            throw NativeDownloadError.noFiles
        }

        let title = episodeTitle(from: html, pageURL: pageURL).sanitizedFilename(maxLength: 120)
        let series = seriesTitle(from: html, pageURL: pageURL)?.sanitizedFilename(maxLength: 100)
        let author = authorName(fromHTML: html)
        let assets = imageURLs.enumerated().map { offset, remote in
            let index = offset + 1
            return ResolvedAsset(
                remoteURL: remote,
                filename: filename(for: remote, index: index),
                metadata: assetMetadata(series: series, author: author, episodeTitle: title, pageURL: pageURL, remote: remote, index: index),
                referer: pageURL.absoluteString
            )
        }

        let folderTitle: String
        if let series, !series.isEmpty, !title.lowercased().hasPrefix(series.lowercased()) {
            folderTitle = "\(series) - \(title)"
        } else {
            folderTitle = title
        }
        return ResolvedDownload(
            title: title,
            folderName: "Naver Webtoon \(folderTitle.isEmpty ? title : folderTitle)".sanitizedFilename(maxLength: 120),
            assets: assets,
            metadata: naverWebtoonMetadata(series: series, author: author, pageURL: pageURL, imageCount: assets.count, episodeCount: 1, type: "episode")
        )
    }

    static func extractImageURLs(from html: String, pageURL: URL, additionalImageCandidates: [String] = []) -> [URL] {
        let normalizedHTML = normalizeEscapes(decodeHTML(html))
        var candidates: [String]
        if webtoonType(from: normalizedHTML) == "EFFECTTOON", !additionalImageCandidates.isEmpty {
            candidates = additionalImageCandidates
        } else {
            candidates = imageTagCandidates(from: normalizedHTML)
            candidates.append(contentsOf: scriptImageCandidates(from: normalizedHTML))
            candidates.append(contentsOf: additionalImageCandidates)
        }

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

    static func episodePageURLs(fromHTML html: String, baseURL: URL) -> [URL] {
        var urls: [URL] = []
        for href in anchorHREFs(fromHTML: html) {
            guard let url = linkURL(href, baseURL: baseURL),
                  isDetailURL(url),
                  sameTitleID(url, baseURL),
                  let canonical = canonicalDetailURL(url) else {
                continue
            }
            urls.append(canonical)
        }
        return uniqueURLs(urls)
    }

    static func listPageURLs(fromHTML html: String, baseURL: URL) -> [URL] {
        var urls: [URL] = []
        for href in anchorHREFs(fromHTML: html) {
            guard let url = linkURL(href, baseURL: baseURL),
                  isListURL(url),
                  sameTitleID(url, baseURL),
                  let canonical = legacyListPageURL(url) else {
                continue
            }
            urls.append(canonical)
        }
        return uniqueURLs(urls)
    }

    static func isDetailURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(), isNaverComicHost(host) else { return false }
        let path = url.path.lowercased()
        guard path.contains("/webtoon/detail") || path.hasSuffix("/detail.nhn") || path.contains("/detail") else {
            return false
        }
        return titleID(from: url) != nil && episodeNo(from: url) != nil
    }

    static func isListURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(), isNaverComicHost(host) else { return false }
        let path = url.path.lowercased()
        guard path.contains("/webtoon/list") || path.hasSuffix("/list.nhn") || path.contains("/list") else {
            return false
        }
        return titleID(from: url) != nil
    }

    static func titleID(from url: URL) -> String? {
        queryValue("titleId", from: url)
    }

    static func episodeNo(from url: URL) -> String? {
        queryValue("no", from: url)
    }

    static func canonicalContentURL(for url: URL) -> URL? {
        if isDetailURL(url) {
            return canonicalDetailURL(url)
        }
        if isListURL(url) {
            return canonicalListURL(url)
        }
        return nil
    }

    private struct CollectionCatalog {
        var episodes: [NaverWebtoonEpisode]
        var totalCount: Int
        var seriesInfo: NaverWebtoonSeriesInfo?
        var source: String
    }

    private func resolvedCollectionDownload(
        fromFirstHTML firstHTML: String,
        listURL: URL,
        headers: HTTPRequestOptions,
        rangeExpression: String
    ) async throws -> ResolvedDownload {
        let firstURL = Self.canonicalListURL(listURL) ?? listURL
        let itemRange = rangeExpression.trimmed
        let requestedLimit = try Self.maximumRequestedItem(in: itemRange)
        var currentAPIError: Error?
        let currentCatalog: CollectionCatalog?
        do {
            currentCatalog = try await currentCollectionCatalog(
                listURL: firstURL,
                headers: headers,
                requestedLimit: requestedLimit
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            currentCatalog = nil
            currentAPIError = error
        }

        let catalog: CollectionCatalog
        if let currentCatalog, !currentCatalog.episodes.isEmpty {
            catalog = currentCatalog
        } else {
            let legacyEpisodes = try await legacyCollectionEpisodes(
                fromFirstHTML: firstHTML,
                listURL: firstURL,
                headers: headers
            )
            guard !legacyEpisodes.isEmpty else {
                throw currentAPIError ?? NativeDownloadError.noFiles
            }
            catalog = CollectionCatalog(
                episodes: legacyEpisodes,
                totalCount: legacyEpisodes.count,
                seriesInfo: nil,
                source: "legacy-html"
            )
        }

        let listedEpisodeCount = max(catalog.totalCount, catalog.episodes.count)
        var selectedEpisodes = catalog.episodes
        var selectedPositions: [Int]?
        if !itemRange.isEmpty {
            let indexes = try Self.itemIndexes(for: itemRange, total: catalog.episodes.count)
            selectedEpisodes = indexes.map { catalog.episodes[$0] }
            selectedPositions = indexes.map { $0 + 1 }
        }

        guard !selectedEpisodes.isEmpty else { throw NativeDownloadError.noFiles }
        var assets: [ResolvedAsset] = []
        var seenAssets = Set<String>()
        var failures: [Error] = []
        var resolvedEpisodeCount = 0
        var skippedLockedCount = 0

        guard let titleID = Self.titleID(from: firstURL) else {
            throw NativeDownloadError.invalidURL(firstURL.absoluteString)
        }
        for (selectedIndex, episode) in selectedEpisodes.enumerated() {
            try Task.checkCancellation()
            if episode.locked {
                skippedLockedCount += 1
                continue
            }
            guard let episodeURL = Self.detailURL(
                titleID: titleID,
                episodeNumber: episode.number,
                relativeTo: firstURL
            ) else {
                continue
            }
            do {
                let html = try await HTTPClient.shared.string(
                    from: episodeURL,
                    referer: firstURL.absoluteString,
                    userAgent: headers.userAgent
                )
                let resolved = try await Self.resolvedEpisodeDownload(
                    fromHTML: html,
                    pageURL: episodeURL,
                    headers: headers
                )
                resolvedEpisodeCount += 1
                let collectionPosition = Self.collectionPosition(
                    of: episode,
                    in: catalog.episodes,
                    fallback: selectedIndex + 1
                )
                for asset in resolved.assets {
                    let normalized = URLIdentity.normalize(asset.remoteURL.absoluteString)
                    guard seenAssets.insert(normalized).inserted else { continue }
                    var metadata = asset.metadata
                    metadata["collection_position"] = String(collectionPosition)
                    metadata["episode_position"] = String(collectionPosition)
                    metadata["episode_number"] = String(episode.number)
                    metadata["episode_title"] = episode.subtitle
                    if let thumbnailURL = episode.thumbnailURL {
                        metadata["episode_thumbnail"] = thumbnailURL.absoluteString
                    }
                    assets.append(ResolvedAsset(
                        remoteURL: asset.remoteURL,
                        filename: Self.combinedEpisodeFilename(
                            asset.filename,
                            episodeNumber: episode.number,
                            fallbackIndex: collectionPosition
                        ),
                        metadata: metadata,
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
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                failures.append(error)
            }
        }

        guard !assets.isEmpty else {
            if skippedLockedCount == selectedEpisodes.count {
                throw NativeDownloadError.unsupported(
                    "Selected Naver Webtoon episodes require login, a pass, or purchase."
                )
            }
            throw failures.first ?? NativeDownloadError.noFiles
        }

        let title = Self.nonEmpty(catalog.seriesInfo?.title) ?? Self.collectionTitle(fromHTML: firstHTML, pageURL: firstURL)
        let author = Self.nonEmpty(catalog.seriesInfo?.author) ?? Self.authorName(fromHTML: firstHTML)
        var metadata = Self.naverWebtoonMetadata(
            series: title,
            author: author,
            pageURL: firstURL,
            imageCount: assets.count,
            episodeCount: resolvedEpisodeCount,
            type: "series",
            thumbnail: catalog.seriesInfo?.thumbnailURL
        )
        metadata["collection_api"] = catalog.source
        metadata["listed_episode_count"] = String(listedEpisodeCount)
        metadata["fetched_episode_count"] = String(catalog.episodes.count)
        metadata["resolved_episode_count"] = String(resolvedEpisodeCount)
        let lockedEpisodeCount = catalog.episodes.filter(\.locked).count
        if lockedEpisodeCount > 0 {
            metadata["locked_episode_count"] = String(lockedEpisodeCount)
        }
        if skippedLockedCount > 0 {
            metadata["skipped_locked_count"] = String(skippedLockedCount)
        }
        let skippedCount = skippedLockedCount + failures.count
        if skippedCount > 0 {
            metadata["skipped_count"] = String(skippedCount)
        }
        if let selectedPositions {
            metadata["range"] = itemRange
            metadata["range_scope"] = "collection_items"
            metadata["range_total"] = String(listedEpisodeCount)
            metadata["range_selected"] = String(selectedPositions.count)
            metadata["range_indexes"] = selectedPositions.map(String.init).joined(separator: ",")
        }

        return ResolvedDownload(
            title: title,
            folderName: "Naver Webtoon \(title)".sanitizedFilename(maxLength: 120),
            assets: assets,
            metadata: metadata
        )
    }

    private func currentCollectionCatalog(
        listURL: URL,
        headers: HTTPRequestOptions,
        requestedLimit: Int?
    ) async throws -> CollectionCatalog {
        guard let infoURL = Self.articleInfoAPIURL(for: listURL) else {
            throw NativeDownloadError.invalidURL(listURL.absoluteString)
        }
        let jsonHeaders = ["Accept": "application/json, text/plain, */*"]
        var seriesInfo: NaverWebtoonSeriesInfo?
        do {
            let data = try await HTTPClient.shared.data(
                from: infoURL,
                referer: listURL.absoluteString,
                userAgent: headers.userAgent,
                additionalHeaders: jsonHeaders
            )
            seriesInfo = try Self.seriesInfo(from: data)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            seriesInfo = nil
        }

        let effectiveLimit = max(1, requestedLimit ?? Int.max)
        var episodes: [NaverWebtoonEpisode] = []
        var seenNumbers = Set<Int>()
        var totalCount = 0
        var pageNumber = 1
        while pageNumber <= Self.maximumListPageNumber {
            try Task.checkCancellation()
            guard let pageURL = Self.articleListAPIURL(for: listURL, page: pageNumber) else {
                throw NativeDownloadError.invalidURL(listURL.absoluteString)
            }
            let data = try await HTTPClient.shared.data(
                from: pageURL,
                referer: listURL.absoluteString,
                userAgent: headers.userAgent,
                additionalHeaders: jsonHeaders
            )
            let page = try Self.articlePage(from: data)
            totalCount = max(totalCount, page.totalCount)
            let previousCount = episodes.count
            for episode in page.episodes where seenNumbers.insert(episode.number).inserted {
                episodes.append(episode)
                if episodes.count >= effectiveLimit { break }
            }
            if episodes.count >= effectiveLimit { break }
            guard episodes.count > previousCount,
                  let nextPage = page.nextPage,
                  nextPage > pageNumber else {
                break
            }
            pageNumber = nextPage
        }
        episodes.sort { $0.number < $1.number }
        guard !episodes.isEmpty else { throw NativeDownloadError.noFiles }
        return CollectionCatalog(
            episodes: episodes,
            totalCount: max(totalCount, episodes.count),
            seriesInfo: seriesInfo,
            source: "article-list"
        )
    }

    private func legacyCollectionEpisodes(
        fromFirstHTML firstHTML: String,
        listURL: URL,
        headers: HTTPRequestOptions
    ) async throws -> [NaverWebtoonEpisode] {
        let firstURL = Self.canonicalListURL(listURL) ?? listURL
        var pageQueue = [firstURL]
        var seenPages: Set<String> = [URLIdentity.normalize(firstURL.absoluteString)]
        var episodeURLs: [URL] = []
        var pageHTMLCache: [String: String] = [URLIdentity.normalize(firstURL.absoluteString): firstHTML]

        var index = 0
        while index < pageQueue.count && index < Self.maximumListPageNumber {
            let pageURL = pageQueue[index]
            index += 1
            let pageKey = URLIdentity.normalize(pageURL.absoluteString)
            let html: String
            if let cached = pageHTMLCache[pageKey] {
                html = cached
            } else {
                html = try await HTTPClient.shared.string(from: pageURL, referer: listURL.absoluteString, userAgent: headers.userAgent)
                pageHTMLCache[pageKey] = html
            }

            episodeURLs.append(contentsOf: Self.episodePageURLs(fromHTML: html, baseURL: pageURL))
            for next in Self.listPageURLs(fromHTML: html, baseURL: pageURL) {
                let normalized = URLIdentity.normalize(next.absoluteString)
                guard !seenPages.contains(normalized) else { continue }
                seenPages.insert(normalized)
                pageQueue.append(next)
            }
        }

        return Self.uniqueURLs(episodeURLs).compactMap { episodeURL in
            guard let rawNumber = Self.episodeNo(from: episodeURL),
                  let number = Int(rawNumber),
                  number > 0 else {
                return nil
            }
            return NaverWebtoonEpisode(
                number: number,
                subtitle: "Episode \(number)",
                thumbnailURL: nil,
                charge: false,
                locked: false
            )
        }.sorted { $0.number < $1.number }
    }

    private struct HTMLTagContext {
        let name: String
        let className: String
        let id: String
        let excluded: Bool
    }

    private static func imageTagCandidates(from html: String) -> [String] {
        guard let regex = htmlTagRegex() else {
            return []
        }

        let type = webtoonType(from: html)
        let hasDefaultViewer = htmlContainsClass("toon_view_lst", in: html)
        let hasCuttoonViewer = htmlContainsClass("swiper-wrapper", in: html)
        if type == "CUTTOON", hasCuttoonViewer {
            return cuttoonImageTagCandidates(from: html)
        }

        var candidates: [String] = []
        var stack: [HTMLTagContext] = []
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        for match in regex.matches(in: html, range: range) {
            guard let closingRange = Range(match.range(at: 1), in: html),
                  let nameRange = Range(match.range(at: 2), in: html),
                  let attributesRange = Range(match.range(at: 3), in: html) else {
                continue
            }

            let name = String(html[nameRange]).lowercased()
            if !String(html[closingRange]).isEmpty {
                if let index = stack.lastIndex(where: { $0.name == name }) {
                    stack.removeSubrange(index..<stack.endIndex)
                }
                continue
            }

            let attributes = String(html[attributesRange])
            let values = attributeValues(from: attributes)
            let className = values["class"]?.lowercased() ?? ""
            let id = values["id"]?.lowercased() ?? ""
            let excluded = stack.last?.excluded == true || isExcludedViewerClass(className)

            if name == "img",
               !excluded,
               isViewerImageTag(values: values, className: className, stack: stack, type: type, hasDefaultViewer: hasDefaultViewer, hasCuttoonViewer: hasCuttoonViewer) {
                if let value = firstImageSource(in: values) {
                    candidates.append(value)
                }
            }

            if !isVoidHTMLElement(name) && !attributes.trimmed.hasSuffix("/") {
                stack.append(HTMLTagContext(name: name, className: className, id: id, excluded: excluded))
            }
        }
        return candidates
    }

    private static func cuttoonImageTagCandidates(from html: String) -> [String] {
        guard let regex = htmlTagRegex() else {
            return []
        }

        var candidates: [String] = []
        var stack: [HTMLTagContext] = []
        var activeSlideDepth: Int?
        var activeSlideCandidates: [String] = []
        var activeSlideExcluded = false
        let range = NSRange(html.startIndex..<html.endIndex, in: html)

        for match in regex.matches(in: html, range: range) {
            guard let closingRange = Range(match.range(at: 1), in: html),
                  let nameRange = Range(match.range(at: 2), in: html),
                  let attributesRange = Range(match.range(at: 3), in: html) else {
                continue
            }

            let name = String(html[nameRange]).lowercased()
            if !String(html[closingRange]).isEmpty {
                if let popIndex = stack.lastIndex(where: { $0.name == name }) {
                    if let slideDepth = activeSlideDepth, popIndex == slideDepth {
                        if !activeSlideExcluded, let first = activeSlideCandidates.first {
                            candidates.append(first)
                        }
                        activeSlideDepth = nil
                        activeSlideCandidates = []
                        activeSlideExcluded = false
                    }
                    stack.removeSubrange(popIndex..<stack.endIndex)
                }
                continue
            }

            let attributes = String(html[attributesRange])
            let values = attributeValues(from: attributes)
            let className = values["class"]?.lowercased() ?? ""
            let id = values["id"]?.lowercased() ?? ""
            let excludedClass = isExcludedViewerClass(className)

            if activeSlideDepth != nil, excludedClass {
                activeSlideExcluded = true
            }
            if name == "img", activeSlideDepth != nil, let value = firstImageSource(in: values) {
                activeSlideCandidates.append(value)
            }

            guard !isVoidHTMLElement(name), !attributes.trimmed.hasSuffix("/") else {
                continue
            }

            let excluded = stack.last?.excluded == true || excludedClass
            let isDirectCuttoonSlide = activeSlideDepth == nil &&
                classList(className, contains: "swiper-slide") &&
                stack.contains { classList($0.className, contains: "swiper-wrapper") }
            stack.append(HTMLTagContext(name: name, className: className, id: id, excluded: excluded))
            if isDirectCuttoonSlide {
                activeSlideDepth = stack.count - 1
                activeSlideCandidates = []
                activeSlideExcluded = excludedClass
            }
        }

        if activeSlideDepth != nil, !activeSlideExcluded, let first = activeSlideCandidates.first {
            candidates.append(first)
        }
        return candidates
    }

    private static func htmlTagRegex() -> NSRegularExpression? {
        try? NSRegularExpression(
            pattern: #"<\s*(/?)\s*([A-Za-z][A-Za-z0-9]*)\b([^>]*)>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        )
    }

    private static func firstImageSource(in values: [String: String]) -> String? {
        for key in ["data-src", "data-url", "data-original", "src"] {
            if let value = values[key]?.trimmed, !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func isViewerImageTag(values: [String: String], className: String, stack: [HTMLTagContext], type: String?, hasDefaultViewer: Bool, hasCuttoonViewer: Bool) -> Bool {
        if type == "DEFAULT", hasDefaultViewer {
            return stack.contains { classList($0.className, contains: "toon_view_lst") }
        }
        if type == "CUTTOON", hasCuttoonViewer {
            return stack.contains { classList($0.className, contains: "swiper-wrapper") } &&
                stack.contains { classList($0.className, contains: "swiper-slide") }
        }

        let inViewerContainer = stack.contains { context in
            classList(context.className, contains: "toon_view_lst") ||
                classList(context.className, contains: "swiper-wrapper") ||
                classList(context.className, contains: "swiper-slide") ||
                context.id == "toon_view_area" ||
                context.id == "comic_view_area"
        }
        return inViewerContainer ||
            className.contains("toon") ||
            className.contains("swiper-slide") ||
            values["data-src"] != nil ||
            values["data-url"] != nil ||
            values["data-original"] != nil
    }

    private static func webtoonType(from html: String) -> String? {
        captureGroupMatches(pattern: #"webtoonType\s*:\s*['"]([^'"]+)['"]"#, in: html)
            .first?
            .uppercased()
    }

    private static func htmlContainsClass(_ className: String, in html: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: className)
        let pattern = #"\bclass\s*=\s*["'][^"']*"# + escaped + #"[^"']*["']"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return false
        }
        return regex.firstMatch(in: html, range: NSRange(html.startIndex..<html.endIndex, in: html)) != nil
    }

    private static func classList(_ className: String, contains needle: String) -> Bool {
        className.split(whereSeparator: { $0.isWhitespace }).contains { $0 == needle }
    }

    private static func isExcludedViewerClass(_ className: String) -> Bool {
        classList(className, contains: "cut_viewer_last") ||
            classList(className, contains: "cut_viewer_recomm")
    }

    private static func isVoidHTMLElement(_ name: String) -> Bool {
        ["area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source", "track", "wbr"].contains(name)
    }

    private static func scriptImageCandidates(from html: String) -> [String] {
        let patterns = [
            #"(?:imageUrl|sImageUrl|documentUrl)\s*:\s*['"]([^'"]+\.(?:jpg|jpeg|png|webp|gif)(?:\?[^'"]*)?)['"]"#,
            #""(?:imageUrl|sImageUrl|documentUrl)"\s*:\s*"([^"]+\.(?:jpg|jpeg|png|webp|gif)(?:\?[^"]*)?)""#
        ]

        return patterns.flatMap { pattern in
            captureGroupMatches(pattern: pattern, in: html)
        }
    }

    private static func effecttoonDocumentImageCandidates(fromHTML html: String, pageURL: URL, headers: HTTPRequestOptions) async -> [String] {
        let normalizedHTML = normalizeEscapes(decodeHTML(html))
        guard webtoonType(from: normalizedHTML) == "EFFECTTOON",
              let documentRaw = captureGroupMatches(pattern: #"documentUrl\s*:\s*['"]([^'"]+)['"]"#, in: normalizedHTML).first,
              let documentURL = absoluteURL(documentRaw, baseURL: pageURL) else {
            return []
        }

        let imageBaseRaw = captureGroupMatches(pattern: #"imageUrl\s*:\s*['"]([^'"]+)['"]"#, in: normalizedHTML).first
        let baseURL: URL
        if let imageBaseRaw,
           let remote = absoluteURL(imageBaseRaw.hasSuffix("/") ? imageBaseRaw : "\(imageBaseRaw)/", baseURL: pageURL) {
            baseURL = remote
        } else {
            baseURL = pageURL
        }

        guard let json = try? await HTTPClient.shared.string(from: documentURL, referer: pageURL.absoluteString, userAgent: headers.userAgent) else {
            return []
        }
        return stillcutImageCandidates(fromJSON: json).compactMap { candidate in
            absoluteURL(candidate, baseURL: baseURL)?.absoluteString
        }
    }

    private static func stillcutImageCandidates(fromJSON json: String) -> [String] {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any],
              let assets = dictionary["assets"] as? [String: Any],
              let stillcut = assets["stillcut"] else {
            return []
        }
        return stringLeaves(inJSONValue: stillcut)
    }

    private static func stringLeaves(inJSONValue value: Any) -> [String] {
        if let string = value as? String {
            return [string]
        }
        if let array = value as? [Any] {
            return array.flatMap { stringLeaves(inJSONValue: $0) }
        }
        if let dictionary = value as? [String: Any] {
            return sortedJSONKeys(Array(dictionary.keys)).flatMap { key in
                dictionary[key].map { stringLeaves(inJSONValue: $0) } ?? []
            }
        }
        return []
    }

    private static func sortedJSONKeys(_ keys: [String]) -> [String] {
        keys.sorted { left, right in
            if let leftNumber = Int(left), let rightNumber = Int(right), leftNumber != rightNumber {
                return leftNumber < rightNumber
            }
            return left.localizedStandardCompare(right) == .orderedAscending
        }
    }

    private static func episodeTitle(from html: String, pageURL: URL) -> String {
        let normalizedHTML = decodeHTML(html)
        let title = metaContent(from: normalizedHTML, names: ["og:title", "twitter:title"]) ??
            textForClass("subj_episode", in: normalizedHTML) ??
            titleTag(from: normalizedHTML) ??
            fallbackTitle(from: pageURL)
        return cleanTitle(title, pageURL: pageURL)
    }

    private static func seriesTitle(from html: String, pageURL: URL) -> String? {
        let normalizedHTML = decodeHTML(html)
        if let explicit = metaContent(from: normalizedHTML, names: ["webtoon:series", "article:section", "naver:webtoon"]) ??
            textForClass("comicinfo", in: normalizedHTML) {
            return cleanSeriesTitle(explicit)
        }

        guard let rawTitle = metaContent(from: normalizedHTML, names: ["og:title", "twitter:title"]) ??
            titleTag(from: normalizedHTML) else {
            return nil
        }
        let clean = cleanTitle(rawTitle, pageURL: pageURL)
        let separators = [" - ", " | ", " :: "]
        for separator in separators {
            if let range = clean.range(of: separator) {
                let value = String(clean[..<range.lowerBound]).trimmed
                if !value.isEmpty {
                    return cleanSeriesTitle(value)
                }
            }
        }
        return nil
    }

    private static func authorName(fromHTML html: String) -> String? {
        let normalizedHTML = normalizeEscapes(decodeHTML(html))
        let candidates = [
            textForClass("author", in: normalizedHTML),
            textForClass("artist", in: normalizedHTML),
            metaContent(from: normalizedHTML, names: ["article:author", "author", "artist", "webtoon:author"]),
            scriptTextCandidate(names: ["author", "artist", "writer", "painter", "creator"], in: normalizedHTML)
        ]

        for candidate in candidates {
            let clean = candidate.map(cleanAuthor) ?? ""
            if !clean.isEmpty {
                return clean
            }
        }
        return nil
    }

    private static func collectionTitle(fromHTML html: String, pageURL: URL) -> String {
        let normalizedHTML = decodeHTML(html)
        let fallback = titleID(from: pageURL).map { value in
            "Webtoon \(value)"
        } ?? "Naver Webtoon"
        let title = seriesTitle(from: normalizedHTML, pageURL: pageURL) ??
            metaContent(from: normalizedHTML, names: ["og:title", "twitter:title"]) ??
            textForClass("subj", in: normalizedHTML) ??
            textForClass("title", in: normalizedHTML) ??
            titleTag(from: normalizedHTML) ??
            fallback
        return cleanSeriesTitle(cleanTitle(title, pageURL: pageURL))
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
            .first { $0.name.lowercased() == "no" }?
            .value
        return episode.map { "Episode \($0)" } ?? "Naver Webtoon Episode"
    }

    private static func cleanTitle(_ raw: String, pageURL: URL) -> String {
        var title = stripTags(raw)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmed

        for suffix in [" :: 네이버 웹툰", " - 네이버 웹툰", " | 네이버 웹툰", " :: Naver Webtoon", " - Naver Webtoon"] {
            if title.lowercased().hasSuffix(suffix.lowercased()) {
                title.removeLast(suffix.count)
                title = title.trimmed
            }
        }

        if title.isEmpty {
            return fallbackTitle(from: pageURL)
        }
        return title
    }

    private static func cleanSeriesTitle(_ raw: String) -> String {
        stripTags(raw)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmed
    }

    private static func filename(for url: URL, index: Int) -> String {
        let ext = mediaFormat(for: url)
        return String(format: "%04d.%@", index, ext).sanitizedFilename(maxLength: 120)
    }

    private static func combinedEpisodeFilename(_ filename: String, episodeNumber: Int, fallbackIndex: Int) -> String {
        let number = episodeNumber > 0 ? episodeNumber : max(1, fallbackIndex)
        return "\(String(format: "%04d", number))-\(number)-\(filename)".sanitizedFilename(maxLength: 180)
    }

    private static func naverWebtoonMetadata(
        series: String?,
        author: String?,
        pageURL: URL? = nil,
        imageCount: Int? = nil,
        episodeCount: Int? = nil,
        type: String = "episode",
        thumbnail: URL? = nil
    ) -> [String: String] {
        let titleID = pageURL.flatMap { titleID(from: $0) }
        let episodeID = pageURL.flatMap { episodeNo(from: $0) }
        let id = episodeID ?? titleID ?? ""
        return DownloadMetadata.clean([
            "series": series ?? "",
            "category": series ?? "",
            "channel": series ?? "",
            "artist": author ?? "",
            "author": author ?? "",
            "creator": author ?? "",
            "uploader": author ?? series ?? "",
            "site": "Naver Webtoon",
            "type": type,
            "media_type": "image",
            "media_count": imageCount.map(String.init) ?? "",
            "image_count": imageCount.map(String.init) ?? "",
            "episode_count": episodeCount.map(String.init) ?? "",
            "title_id": titleID ?? "",
            "episode_id": episodeID ?? "",
            "chapter_id": episodeID ?? "",
            "gallery_id": id,
            "id": id,
            "source_url": pageURL?.absoluteString ?? "",
            "page_url": pageURL?.absoluteString ?? "",
            "thumbnail": thumbnail?.absoluteString ?? ""
        ])
    }

    private static func assetMetadata(series: String?, author: String?, episodeTitle: String, pageURL: URL, remote: URL, index: Int) -> [String: String] {
        let titleID = titleID(from: pageURL) ?? ""
        let episodeID = episodeNo(from: pageURL) ?? ""
        let id = episodeID.isEmpty ? titleID : episodeID
        let format = mediaFormat(for: remote)
        return DownloadMetadata.clean([
            "series": series ?? "",
            "category": series ?? "",
            "channel": series ?? "",
            "artist": author ?? "",
            "author": author ?? "",
            "creator": author ?? "",
            "uploader": author ?? series ?? "",
            "site": "Naver Webtoon",
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

    private static func scriptTextCandidate(names: Set<String>, in html: String) -> String? {
        let namePattern = names.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        let patterns = [
            #"(?:["'])("# + namePattern + #")(?:["'])\s*:\s*(?:["'])([^"']{1,160})(?:["'])"#,
            #"\b("# + namePattern + #")\s*:\s*(?:["'])([^"']{1,160})(?:["'])"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
                continue
            }
            let range = NSRange(html.startIndex..<html.endIndex, in: html)
            for match in regex.matches(in: html, range: range) {
                guard let capture = Range(match.range(at: 2), in: html) else { continue }
                let value = normalizeEscapes(decodeHTML(String(html[capture]))).trimmed
                if !value.isEmpty {
                    return value
                }
            }
        }
        return nil
    }

    private static func cleanAuthor(_ raw: String) -> String {
        var author = stripTags(raw)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmed
        let prefixes = [
            #"(?i)^(?:author|artist|creator|by)\s*[:：]\s*"#,
            #"^(?:글\s*/\s*그림|글|그림|작가)\s*[:：]?\s*"#
        ]
        for prefix in prefixes {
            author = author.replacingOccurrences(of: prefix, with: "", options: .regularExpression).trimmed
        }
        return author
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

    private static func anchorHREFs(fromHTML html: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"<a\b([^>]*)>"#, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        return regex.matches(in: html, range: range).compactMap { match in
            guard let attributesRange = Range(match.range(at: 1), in: html) else { return nil }
            return attributeValues(from: String(html[attributesRange]))["href"]
        }
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

    private static func linkURL(_ raw: String, baseURL: URL) -> URL? {
        let value = raw.trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "\"'(),;"))
        guard !value.isEmpty else { return nil }
        if value.hasPrefix("?"),
           var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false),
           let query = URLComponents(string: "https://example.test/\(value)")?.queryItems {
            var items = components.queryItems ?? []
            for item in query {
                items.removeAll { $0.name.lowercased() == item.name.lowercased() }
                items.append(item)
            }
            components.queryItems = items
            components.fragment = nil
            return components.url
        }
        return absoluteURL(value, baseURL: baseURL)
    }

    private static func isImageURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return false
        }
        return imageExtensions.contains(url.pathExtension.lowercased())
    }

    private static func isNaverComicHost(_ host: String) -> Bool {
        host == "comic.naver.com" ||
            host == "m.comic.naver.com" ||
            host == "comic.naver.test" ||
            host == "m.comic.naver.test"
    }

    private static func apiHost(for host: String?) -> String {
        host?.lowercased().hasSuffix(".test") == true ? "comic.naver.test" : "comic.naver.com"
    }

    static func articleInfoAPIURL(for listURL: URL) -> URL? {
        guard let titleID = titleID(from: listURL),
              var components = URLComponents(url: listURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.scheme = "https"
        components.host = apiHost(for: listURL.host)
        components.path = "/api/article/list/info"
        components.queryItems = [URLQueryItem(name: "titleId", value: titleID)]
        components.fragment = nil
        return components.url
    }

    static func articleListAPIURL(for listURL: URL, page: Int) -> URL? {
        guard let titleID = titleID(from: listURL),
              page > 0,
              var components = URLComponents(url: listURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.scheme = "https"
        components.host = apiHost(for: listURL.host)
        components.path = "/api/article/list"
        components.queryItems = [
            URLQueryItem(name: "titleId", value: titleID),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "sort", value: "ASC")
        ]
        components.fragment = nil
        return components.url
    }

    static func articlePage(from data: Data) throws -> NaverWebtoonArticlePage {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawEpisodes = root["articleList"] as? [[String: Any]] else {
            throw NativeDownloadError.unsupported("Invalid Naver Webtoon article list response.")
        }
        let episodes = rawEpisodes.compactMap { value -> NaverWebtoonEpisode? in
            guard let number = jsonInt(value["no"]), number > 0 else { return nil }
            let subtitle = nonEmpty(jsonString(value["subtitle"])) ?? "Episode \(number)"
            let thumbnailURL = nonEmpty(jsonString(value["thumbnailUrl"])).flatMap(URL.init(string:))
            return NaverWebtoonEpisode(
                number: number,
                subtitle: subtitle,
                thumbnailURL: thumbnailURL,
                charge: jsonBool(value["charge"]) ?? false,
                locked: jsonBool(value["thumbnailLock"]) ?? false
            )
        }
        let pageInfo = root["pageInfo"] as? [String: Any] ?? [:]
        let totalCount = max(episodes.count, jsonInt(root["totalCount"]) ?? jsonInt(pageInfo["totalRows"]) ?? episodes.count)
        let page = max(1, jsonInt(pageInfo["page"]) ?? jsonInt(pageInfo["rawPage"]) ?? 1)
        let pageSize = max(1, jsonInt(pageInfo["pageSize"]) ?? max(1, episodes.count))
        let calculatedPages = max(1, (totalCount + pageSize - 1) / pageSize)
        let totalPages = max(page, jsonInt(pageInfo["totalPages"]) ?? calculatedPages)
        let explicitNext = jsonInt(pageInfo["nextPage"]).flatMap { $0 > 0 ? $0 : nil }
        let nextPage = explicitNext ?? (page < totalPages ? page + 1 : nil)
        return NaverWebtoonArticlePage(
            episodes: episodes,
            totalCount: totalCount,
            page: page,
            totalPages: totalPages,
            nextPage: nextPage
        )
    }

    static func seriesInfo(from data: Data) throws -> NaverWebtoonSeriesInfo {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let title = nonEmpty(jsonString(root["titleName"])) else {
            throw NativeDownloadError.unsupported("Invalid Naver Webtoon series info response.")
        }
        var authors: [String] = []
        var seenAuthors = Set<String>()
        for artist in root["communityArtists"] as? [[String: Any]] ?? [] {
            guard let name = nonEmpty(jsonString(artist["name"])),
                  seenAuthors.insert(name).inserted else {
                continue
            }
            authors.append(name)
        }
        if authors.isEmpty,
           let ad = root["gfpAdCustomParam"] as? [String: Any],
           let displayAuthor = nonEmpty(jsonString(ad["displayAuthor"])) {
            authors.append(displayAuthor)
        }
        if authors.isEmpty,
           let displayAuthor = nonEmpty(jsonString(root["displayAuthor"])) {
            authors.append(displayAuthor)
        }
        let thumbnailURL = ["sharedThumbnailUrl", "thumbnailUrl", "posterThumbnailUrl"]
            .compactMap { nonEmpty(jsonString(root[$0])).flatMap(URL.init(string:)) }
            .first
        return NaverWebtoonSeriesInfo(
            title: title,
            author: authors.joined(separator: ", "),
            thumbnailURL: thumbnailURL
        )
    }

    private static func detailURL(titleID: String, episodeNumber: Int, relativeTo baseURL: URL) -> URL? {
        guard episodeNumber > 0,
              var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.scheme = "https"
        components.host = apiHost(for: baseURL.host)
        components.path = "/webtoon/detail"
        components.queryItems = [
            URLQueryItem(name: "titleId", value: titleID),
            URLQueryItem(name: "no", value: String(episodeNumber))
        ]
        components.fragment = nil
        return components.url
    }

    private static func queryValue(_ name: String, from url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name.lowercased() == name.lowercased() }?
            .value?
            .trimmed
    }

    private static func sameTitleID(_ lhs: URL, _ rhs: URL) -> Bool {
        guard let left = titleID(from: lhs), let right = titleID(from: rhs) else {
            return true
        }
        return left == right
    }

    private static func canonicalDetailURL(_ url: URL) -> URL? {
        guard let titleID = titleID(from: url),
              let no = episodeNo(from: url),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.scheme = "https"
        components.host = apiHost(for: url.host)
        components.path = "/webtoon/detail"
        components.queryItems = [
            URLQueryItem(name: "titleId", value: titleID),
            URLQueryItem(name: "no", value: no)
        ]
        components.fragment = nil
        return components.url
    }

    private static func canonicalListURL(_ url: URL) -> URL? {
        guard let titleID = titleID(from: url),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.scheme = "https"
        components.host = apiHost(for: url.host)
        components.path = "/webtoon/list"
        components.queryItems = [URLQueryItem(name: "titleId", value: titleID)]
        components.fragment = nil
        return components.url
    }

    private static func legacyListPageURL(_ url: URL) -> URL? {
        guard let titleID = titleID(from: url),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        let page = queryValue("page", from: url).flatMap(Int.init)
        components.scheme = "https"
        components.host = apiHost(for: url.host)
        components.path = "/webtoon/list"
        components.queryItems = [URLQueryItem(name: "titleId", value: titleID)]
        if let page, page > 1 {
            components.queryItems?.append(URLQueryItem(name: "page", value: String(page)))
        }
        components.fragment = nil
        return components.url
    }

    private static func collectionPosition(
        of episode: NaverWebtoonEpisode,
        in episodes: [NaverWebtoonEpisode],
        fallback: Int
    ) -> Int {
        episodes.firstIndex(where: { $0.number == episode.number }).map { $0 + 1 } ?? max(1, fallback)
    }

    private struct ItemRangeSegment {
        var start: Int?
        var end: Int?
    }

    private static func maximumRequestedItem(in expression: String) throws -> Int? {
        let segments = try itemRangeSegments(from: expression)
        guard !segments.isEmpty else { return nil }
        if segments.contains(where: { $0.end == nil }) { return nil }
        return segments.compactMap(\.end).max()
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
            throw NativeDownloadError.unsupported("Range did not match any Naver Webtoon episodes.")
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

    private static func jsonString(_ value: Any?) -> String? {
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return nil
    }

    private static func jsonInt(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }

    private static func jsonBool(_ value: Any?) -> Bool? {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        if let value = value as? String {
            switch value.lowercased() {
            case "true", "yes", "1": return true
            case "false", "no", "0": return false
            default: return nil
            }
        }
        return nil
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmed, !value.isEmpty else { return nil }
        return value
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

    private static func uniqueURLs(_ urls: [URL]) -> [URL] {
        var output: [URL] = []
        var seen = Set<String>()
        for url in urls {
            let normalized = URLIdentity.normalize(url.absoluteString)
            guard !seen.contains(normalized) else { continue }
            seen.insert(normalized)
            output.append(url)
        }
        return output
    }
}
