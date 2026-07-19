import Foundation

enum NaverCafeResolverError: LocalizedError {
    case authenticationRequired(String?)

    var errorDescription: String? {
        switch self {
        case .authenticationRequired(let reason):
            let detail = reason?.trimmed ?? ""
            return detail.isEmpty ? "Naver Cafe login is required." : "Naver Cafe login is required: \(detail)"
        }
    }
}

struct NaverCafeID: Hashable {
    var cafeName: String?
    var clubID: String?
    var articleID: String
}

struct NaverCafeVideoPair: Hashable {
    var videoID: String
    var key: String
}

private struct NaverCafeVideoCandidate {
    var url: URL
    var info: [String: Any]
}

private struct NaverCafeOriginalArticle {
    var title: String
    var cafeName: String
    var clubID: String
    var articleID: String
    var contentHTML: String
}

private struct NaverCafeOriginalContext {
    var clubID: String
    var articleID: String
    var art: String?
}

final class NaverCafeResolver {
    func canResolve(_ url: URL) -> Bool {
        Self.articleID(from: url) != nil
    }

    func resolve(_ url: URL, headers: HTTPRequestOptions = HTTPRequestOptions()) async throws -> ResolvedDownload {
        guard Self.articleID(from: url) != nil else {
            throw NativeDownloadError.invalidURL(url.absoluteString)
        }

        let sourceURL = Self.originalFixedURL(for: url) ?? url
        let landingHTML = try await HTTPClient.shared.string(
            from: sourceURL,
            referer: "http://search.naver.com",
            userAgent: headers.userAgent
        )
        if Self.requiresAuthentication(fromLandingHTML: landingHTML) {
            throw NaverCafeResolverError.authenticationRequired(nil)
        }

        if let articleURL = Self.originalArticleURL(fromLandingHTML: landingHTML, sourceURL: sourceURL) {
            do {
                return try await resolveOriginal(
                    sourceURL: sourceURL,
                    articleURL: articleURL,
                    headers: headers
                )
            } catch let error as NaverCafeResolverError {
                throw error
            } catch {
                guard Self.hasArticleContainer(in: landingHTML) else {
                    throw error
                }
            }
        }

        return try await resolveModern(
            sourceURL: sourceURL,
            landingHTML: landingHTML,
            headers: headers
        )
    }

    private func resolveOriginal(
        sourceURL: URL,
        articleURL: URL,
        headers: HTTPRequestOptions
    ) async throws -> ResolvedDownload {
        let context = try Self.originalArticleContext(from: articleURL)
        let apiURL = Self.originalArticleAPIURL(context: context, sourceURL: sourceURL)
        let articleData = try await HTTPClient.shared.data(
            from: apiURL,
            referer: articleURL.absoluteString,
            userAgent: headers.userAgent
        )
        let article = try Self.originalArticle(fromAPIData: articleData, context: context)
        let id = NaverCafeID(
            cafeName: article.cafeName,
            clubID: article.clubID,
            articleID: article.articleID
        )

        var assets: [ResolvedAsset] = []
        for pair in Self.originalVideoPairs(fromContentHTML: article.contentHTML) {
            try Task.checkCancellation()
            let videoAPI = Self.videoAPIURL(for: pair, sourceURL: sourceURL)
            let data = try await HTTPClient.shared.data(
                from: videoAPI,
                userAgent: headers.userAgent
            )
            let candidate = try Self.originalVideoCandidate(fromAPIData: data, sourceURL: videoAPI)
            let position = assets.count
            assets.append(ResolvedAsset(
                remoteURL: candidate.url,
                filename: Self.originalFilename(for: candidate.url, position: position, fallbackExtension: "mp4"),
                metadata: Self.assetMetadata(
                    for: candidate.url,
                    id: id,
                    author: article.cafeName,
                    pageURL: articleURL,
                    index: position + 1,
                    mediaType: "video",
                    videoInfo: candidate.info
                ),
                referer: articleURL.absoluteString,
                userAgent: headers.userAgent
            ))
        }

        for rawSource in Self.originalImageSources(fromContentHTML: article.contentHTML) {
            try Task.checkCancellation()
            guard let joined = Self.absoluteURL(rawSource, baseURL: articleURL),
                  let remote = Self.removingOriginalTypeParameter(from: joined) else {
                continue
            }
            let position = assets.count
            assets.append(ResolvedAsset(
                remoteURL: remote,
                filename: Self.originalFilename(for: remote, position: position, fallbackExtension: "jpg"),
                metadata: Self.assetMetadata(
                    for: remote,
                    id: id,
                    author: article.cafeName,
                    pageURL: sourceURL,
                    index: position + 1,
                    mediaType: "image"
                ),
                referer: sourceURL.absoluteString,
                userAgent: headers.userAgent
            ))
        }

        guard !assets.isEmpty else {
            throw NativeDownloadError.noFiles
        }

        let title = Self.originalTitle(
            subject: article.title,
            cafeName: article.cafeName,
            articleID: article.articleID
        )
        var metadata = Self.naverCafeMetadata(
            id: id,
            author: article.cafeName,
            title: title,
            pageURL: sourceURL,
            assets: assets
        )
        metadata["article_url"] = articleURL.absoluteString
        metadata["article_api_url"] = apiURL.absoluteString
        metadata["original_contract"] = "navercafe-4.2"
        return ResolvedDownload(
            title: title,
            folderName: title,
            assets: assets,
            metadata: metadata
        )
    }

    private func resolveModern(
        sourceURL: URL,
        landingHTML: String,
        headers: HTTPRequestOptions
    ) async throws -> ResolvedDownload {
        guard let id = Self.articleID(from: sourceURL) else {
            throw NativeDownloadError.invalidURL(sourceURL.absoluteString)
        }

        let pageURL: URL
        let html: String
        if Self.hasArticleContainer(in: landingHTML) {
            pageURL = sourceURL
            html = landingHTML
        } else if let frameURL = Self.frameURL(fromHTML: landingHTML, baseURL: sourceURL) {
            pageURL = frameURL
            html = try await resolvedHTML(from: frameURL, headers: headers, depth: 1)
        } else if id.clubID != nil {
            pageURL = Self.mobileArticleURL(for: id, sourceURL: sourceURL)
            html = try await resolvedHTML(from: pageURL, headers: headers, depth: 0)
        } else {
            pageURL = sourceURL
            html = landingHTML
        }

        var resolved = try Self.resolvedDownload(fromHTML: html, pageURL: pageURL, id: id)
        let videoPairs = Self.videoPairs(fromHTML: html)
        if !videoPairs.isEmpty {
            var assets = resolved.assets
            var seen = Set(assets.map { URLIdentity.normalize($0.remoteURL.absoluteString) })
            for pair in videoPairs {
                let apiURL = Self.videoAPIURL(for: pair, sourceURL: pageURL)
                let data = try await HTTPClient.shared.data(from: apiURL, referer: pageURL.absoluteString, userAgent: headers.userAgent)
                guard let candidate = try Self.videoCandidate(fromAPIData: data, sourceURL: apiURL) else { continue }
                let remote = candidate.url
                let normalized = URLIdentity.normalize(remote.absoluteString)
                guard !seen.contains(normalized) else { continue }
                seen.insert(normalized)
                assets.append(ResolvedAsset(
                    remoteURL: remote,
                    filename: String(format: "video_%04d.%@", assets.count + 1, remote.pathExtension.trimmed.isEmpty ? "mp4" : remote.pathExtension).sanitizedFilename(maxLength: 120),
                    metadata: Self.assetMetadata(for: remote, id: id, author: resolved.metadata["author"], pageURL: pageURL, index: assets.count + 1, mediaType: "video", videoInfo: candidate.info),
                    referer: pageURL.absoluteString,
                    userAgent: headers.userAgent
                ))
            }
            resolved = ResolvedDownload(
                title: resolved.title,
                folderName: resolved.folderName,
                assets: assets,
                metadata: Self.naverCafeMetadata(id: id, author: resolved.metadata["author"], title: resolved.title, pageURL: pageURL, assets: assets)
            )
        }

        guard !resolved.assets.isEmpty else {
            throw NativeDownloadError.noFiles
        }
        return resolved
    }

    static func originalFixedURL(for url: URL) -> URL? {
        let modernGroups = captureGroups(
            pattern: #"cafe\.naver\.(?:com|test)/[^/]+/cafes/([0-9]+)/articles/([0-9]+)"#,
            in: url.absoluteString
        )
        if modernGroups.count == 2 {
            var components = URLComponents()
            components.scheme = "https"
            components.host = url.host?.lowercased().hasSuffix(".test") == true ? "cafe.naver.test" : "cafe.naver.com"
            components.path = "/ArticleRead.nhn"
            components.queryItems = [
                URLQueryItem(name: "articleid", value: modernGroups[1]),
                URLQueryItem(name: "clubid", value: modernGroups[0])
            ]
            return components.url
        }

        let groups = captureGroups(
            pattern: #"cafe\.naver\.(?:com|test)/([^/?#]+).+?articleid%3D([0-9]+)"#,
            in: url.absoluteString
        )
        guard groups.count == 2 else { return nil }

        var components = URLComponents()
        components.scheme = "https"
        components.host = url.host?.lowercased().hasSuffix(".test") == true ? "cafe.naver.test" : "cafe.naver.com"
        components.path = "/\(groups[0])/\(groups[1])"
        return components.url
    }

    static func requiresAuthentication(fromLandingHTML html: String) -> Bool {
        html.contains(#""cafe_cautionpage""#)
    }

    static func originalArticleURL(fromLandingHTML html: String, sourceURL: URL) -> URL? {
        guard let raw = captureMatches(
            pattern: #"(//cafe\.naver\.(?:com|test)/ArticleRead\.nhn\?[^'\"]*articleid=[0-9]+[^'\"]*)"#,
            in: html
        ).first else {
            return nil
        }
        return absoluteURL(raw, baseURL: sourceURL)
    }

    private static func originalArticleContext(from articleURL: URL) throws -> NaverCafeOriginalContext {
        let raw = articleURL.absoluteString
        guard let articleID = firstCapture(patterns: [#"articleid=([0-9]+)"#], in: raw),
              let clubID = firstCapture(patterns: [#"clubid(?:=|%3D)([0-9]+)"#], in: raw) else {
            throw NativeDownloadError.invalidGalleryData
        }
        let art = firstCapture(patterns: [#"art=(.+?)&"#], in: raw)
        return NaverCafeOriginalContext(clubID: clubID, articleID: articleID, art: art)
    }

    private static func originalArticleAPIURL(context: NaverCafeOriginalContext, sourceURL: URL) -> URL {
        var components = URLComponents()
        components.scheme = sourceURL.scheme ?? "https"
        components.host = sourceURL.host?.lowercased().hasSuffix(".test") == true ? "apis.naver.test" : "apis.naver.com"
        components.path = "/cafe-web/cafe-articleapi/v2.1/cafes/\(context.clubID)/articles/\(context.articleID)"
        if let art = context.art, !art.isEmpty {
            components.percentEncodedQuery = "art=\(art)&useCafeId=true&requestFrom=A"
        } else {
            components.percentEncodedQuery = "query=&useCafeId=true&requestFrom=A"
        }
        return components.url!
    }

    private static func originalArticle(
        fromAPIData data: Data,
        context: NaverCafeOriginalContext
    ) throws -> NaverCafeOriginalArticle {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = root["result"] as? [String: Any] else {
            throw NativeDownloadError.invalidGalleryData
        }
        if isPythonTruthy(result["errorCode"]) {
            throw NaverCafeResolverError.authenticationRequired(stringValue(result["reason"]))
        }
        guard let article = result["article"] as? [String: Any],
              let cafe = result["cafe"] as? [String: Any],
              let subject = stringValue(article["subject"]),
              let cafeName = stringValue(cafe["url"]),
              let contentHTML = stringValue(article["contentHtml"]) else {
            throw NativeDownloadError.invalidGalleryData
        }
        return NaverCafeOriginalArticle(
            title: subject,
            cafeName: cafeName,
            clubID: context.clubID,
            articleID: context.articleID,
            contentHTML: contentHTML
        )
    }

    static func originalVideoPairs(fromContentHTML html: String) -> [NaverCafeVideoPair] {
        var pairs: [NaverCafeVideoPair] = []
        for tag in captureFullMatches(pattern: #"<span\b[^>]*>"#, in: html) {
            let values = attributeValues(from: tag)
            let classes = Set((values["class"] ?? "").split(whereSeparator: \Character.isWhitespace).map(String.init))
            guard classes.contains("_naverVideo"),
                  let videoID = values["vid"],
                  let key = values["key"] else {
                continue
            }
            pairs.append(NaverCafeVideoPair(videoID: videoID, key: key))
        }

        for tag in captureFullMatches(pattern: #"<script\b[^>]*>"#, in: html) {
            let values = attributeValues(from: tag)
            let classes = Set((values["class"] ?? "").split(whereSeparator: \Character.isWhitespace).map(String.init))
            guard classes.contains("__se_module_data"),
                  let module = values["data-module"] ?? values["data-module-v2"],
                  let object = try? JSONSerialization.jsonObject(with: Data(module.utf8)) as? [String: Any],
                  let data = object["data"] as? [String: Any],
                  let videoID = stringValue(data["vid"]),
                  let key = stringValue(data["inkey"]),
                  !videoID.isEmpty else {
                continue
            }
            pairs.append(NaverCafeVideoPair(videoID: videoID, key: key))
        }
        return pairs
    }

    static func originalImageSources(fromContentHTML html: String) -> [String] {
        captureFullMatches(pattern: #"<img\b[^>]*>"#, in: html).compactMap { tag in
            attributeValues(from: tag)["src"]
        }
    }

    private static func originalVideoCandidate(fromAPIData data: Data, sourceURL: URL) throws -> NaverCafeVideoCandidate {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let videos = object["videos"] as? [String: Any],
              let list = videos["list"] as? [[String: Any]],
              !list.isEmpty else {
            throw NativeDownloadError.invalidGalleryData
        }

        var best: [String: Any]?
        var bestSize = Int.min
        for candidate in list {
            guard let size = intValue(candidate["size"]) else {
                throw NativeDownloadError.invalidGalleryData
            }
            if best == nil || size > bestSize {
                best = candidate
                bestSize = size
            }
        }
        guard let best,
              let raw = stringValue(best["source"]),
              let remote = absoluteURL(raw, baseURL: sourceURL) else {
            throw NativeDownloadError.invalidGalleryData
        }
        return NaverCafeVideoCandidate(url: remote, info: best)
    }

    private static func removingOriginalTypeParameter(from url: URL) -> URL? {
        let cleaned = url.absoluteString.replacingOccurrences(
            of: #"[?&]type=[wh0-9]+"#,
            with: "",
            options: .regularExpression
        )
        return URL(string: cleaned)
    }

    private static func originalFilename(for url: URL, position: Int, fallbackExtension: String) -> String {
        let ext = url.pathExtension.trimmed.isEmpty ? fallbackExtension : url.pathExtension
        return String(format: "%04d.%@", position, ext).sanitizedFilename(maxLength: 120)
    }

    private static func originalTitle(subject: String, cafeName: String, articleID: String) -> String {
        let tail = " (\(cafeName)_\(articleID))"
        let cleanSubject = decodeHTML(stripTags(subject))
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmed
        let subjectLimit = max(1, 255 - tail.count)
        return "\(String(cleanSubject.prefix(subjectLimit)))\(tail)".sanitizedFilename(maxLength: 255)
    }

    private static func isPythonTruthy(_ value: Any?) -> Bool {
        switch value {
        case nil, is NSNull:
            return false
        case let value as Bool:
            return value
        case let value as NSNumber:
            return value.doubleValue != 0
        case let value as String:
            return !value.isEmpty
        case let value as [Any]:
            return !value.isEmpty
        case let value as [String: Any]:
            return !value.isEmpty
        default:
            return true
        }
    }

    private func resolvedHTML(from url: URL, headers: HTTPRequestOptions, depth: Int) async throws -> String {
        guard depth <= 8 else {
            throw NativeDownloadError.unsupported("Naver Cafe frame nesting is too deep.")
        }

        let html = try await HTTPClient.shared.string(from: url, referer: headers.referer, userAgent: headers.userAgent)
        if Self.hasArticleContainer(in: html) {
            return html
        }
        if let frameURL = Self.frameURL(fromHTML: html, baseURL: url) {
            return try await resolvedHTML(from: frameURL, headers: headers, depth: depth + 1)
        }
        return html
    }

    static func resolvedDownload(fromHTML html: String, pageURL: URL, id: NaverCafeID? = nil) throws -> ResolvedDownload {
        let article = id ?? articleID(from: pageURL) ?? NaverCafeID(cafeName: nil, clubID: nil, articleID: fallbackArticleID(from: pageURL))
        let body = articleBodyHTML(fromHTML: html) ?? html
        let imageURLs = imageURLs(fromHTML: body, pageURL: pageURL)

        let combinedHTML = html + "\n" + body
        let title = articleTitle(fromHTML: combinedHTML, fallback: article.articleID)
        let author = articleAuthor(fromHTML: combinedHTML)
        let assets = imageURLs.enumerated().map { offset, remote in
            ResolvedAsset(
                remoteURL: remote,
                filename: filename(for: remote, index: offset + 1),
                metadata: assetMetadata(for: remote, id: article, author: author, pageURL: pageURL, index: offset + 1, mediaType: "image"),
                referer: pageURL.absoluteString
            )
        }

        let label = cafeLabel(for: article)
        let folderTitle = label.isEmpty ? title : "[\(label)] \(title)"
        return ResolvedDownload(
            title: folderTitle.sanitizedFilename(maxLength: 120),
            folderName: "Naver Cafe \(folderTitle)".sanitizedFilename(maxLength: 120),
            assets: assets,
            metadata: naverCafeMetadata(id: article, author: author, title: folderTitle, pageURL: pageURL, assets: assets)
        )
    }

    static func imageURLs(fromHTML html: String, pageURL: URL) -> [URL] {
        let normalizedHTML = normalizeEscapes(html)
        var candidates = mediaTagCandidates(fromHTML: normalizedHTML)
        candidates.append(contentsOf: scriptImageCandidates(fromHTML: normalizedHTML))

        var output: [URL] = []
        var seen = Set<String>()
        for candidate in candidates {
            guard let remote = absoluteURL(candidate, baseURL: pageURL),
                  shouldDownload(remote) else {
                continue
            }
            let normalized = URLIdentity.normalize(remote.absoluteString)
            guard !seen.contains(normalized) else { continue }
            seen.insert(normalized)
            output.append(remote)
        }
        return output
    }

    static func videoPairs(fromHTML html: String) -> [NaverCafeVideoPair] {
        let normalized = normalizeEscapes(decodeHTML(html))
        var pairs: [NaverCafeVideoPair] = []
        var seen = Set<NaverCafeVideoPair>()

        let objectPattern = #"\{[^{}]*(?:"vid"|"videoId"|'vid'|'videoId')[^{}]*(?:"inkey"|"key"|'inkey'|'key')[^{}]*\}"#
        for object in captureFullMatches(pattern: objectPattern, in: normalized) {
            let videoID = firstCapture(patterns: [
                #""vid"\s*:\s*"([^"]+)""#,
                #""videoId"\s*:\s*"([^"]+)""#,
                #"'vid'\s*:\s*'([^']+)'"#,
                #"'videoId'\s*:\s*'([^']+)'"#
            ], in: object)
            let key = firstCapture(patterns: [
                #""inkey"\s*:\s*"([^"]+)""#,
                #""key"\s*:\s*"([^"]+)""#,
                #"'inkey'\s*:\s*'([^']+)'"#,
                #"'key'\s*:\s*'([^']+)'"#
            ], in: object)
            guard let videoID, let key else { continue }
            let pair = NaverCafeVideoPair(videoID: videoID, key: key)
            if seen.insert(pair).inserted {
                pairs.append(pair)
            }
        }

        let looseVideoIDs = captureMatches(pattern: #"(?:vid|videoId)\s*[:=]\s*["']([^"']+)["']"#, in: normalized)
        let looseKeys = captureMatches(pattern: #"(?:inkey|key)\s*[:=]\s*["']([^"']+)["']"#, in: normalized)
        for (videoID, key) in zip(looseVideoIDs, looseKeys) {
            let pair = NaverCafeVideoPair(videoID: videoID, key: key)
            if seen.insert(pair).inserted {
                pairs.append(pair)
            }
        }

        return pairs
    }

    static func videoAPIURL(for pair: NaverCafeVideoPair, sourceURL: URL) -> URL {
        var components = URLComponents()
        components.scheme = sourceURL.scheme ?? "https"
        components.host = sourceURL.host?.lowercased().hasSuffix(".test") == true ? "apis.naver.test" : "apis.naver.com"
        components.path = "/rmcnmv/rmcnmv/vod/play/v2.0/\(pair.videoID)"
        components.queryItems = [URLQueryItem(name: "key", value: pair.key)]
        return components.url!
    }

    static func videoURL(fromAPIData data: Data, sourceURL: URL) throws -> URL? {
        try videoCandidate(fromAPIData: data, sourceURL: sourceURL)?.url
    }

    private static func videoCandidate(fromAPIData data: Data, sourceURL: URL) throws -> NaverCafeVideoCandidate? {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NativeDownloadError.invalidGalleryData
        }
        let videos = videoDictionaries(in: object)
        let best = videos.max { lhs, rhs in
            (intValue(lhs["size"]) ?? intValue(lhs["bitrate"]) ?? 0) < (intValue(rhs["size"]) ?? intValue(rhs["bitrate"]) ?? 0)
        }
        guard let raw = stringValue(best?["source"]) ?? stringValue(best?["url"]) else {
            return nil
        }
        guard let remote = absoluteURL(raw, baseURL: sourceURL) else {
            return nil
        }
        return NaverCafeVideoCandidate(url: remote, info: best ?? [:])
    }

    static func articleID(from url: URL) -> NaverCafeID? {
        guard let host = url.host?.lowercased(),
              isNaverCafeHost(host),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let items = components?.queryItems ?? []
        let clubID = queryValue(["clubid", "clubId", "cafeId"], in: items)
        let articleID = queryValue(["articleid", "articleId"], in: items)
        if let articleID, !articleID.isEmpty {
            return NaverCafeID(cafeName: nil, clubID: clubID, articleID: articleID)
        }

        let parts = url.path.split(separator: "/").map { String($0).removingPercentEncoding ?? String($0) }
        if let cafesIndex = parts.firstIndex(where: { $0.lowercased() == "cafes" }),
           cafesIndex + 3 < parts.count,
           parts[cafesIndex + 2].lowercased() == "articles" {
            let club = parts[cafesIndex + 1]
            let article = parts[cafesIndex + 3]
            if isNumeric(article) {
                return NaverCafeID(cafeName: nil, clubID: club, articleID: article)
            }
        }

        if let cafeName = parts.first,
           !reservedCafePath(cafeName),
           let articleID = encodedArticleID(in: url) {
            return NaverCafeID(cafeName: cafeName, clubID: nil, articleID: articleID)
        }

        if parts.count >= 2,
           isNumeric(parts[1]),
           !reservedCafePath(parts[0]) {
            return NaverCafeID(cafeName: parts[0], clubID: nil, articleID: parts[1])
        }

        return nil
    }

    private static func encodedArticleID(in url: URL) -> String? {
        let raw = url.absoluteString
        let decoded = raw.removingPercentEncoding ?? raw
        for text in [raw, decoded] {
            if let value = firstCapture(patterns: [#"(?i)articleid(?:=|%3d)([0-9]+)"#], in: text) {
                return value
            }
        }
        return nil
    }

    static func mobileArticleURL(for id: NaverCafeID, sourceURL: URL) -> URL {
        var components = URLComponents()
        components.scheme = sourceURL.scheme ?? "https"
        components.host = sourceURL.host?.lowercased().hasSuffix(".test") == true ? "m.cafe.naver.test" : "m.cafe.naver.com"
        if let clubID = id.clubID, !clubID.isEmpty {
            components.path = "/ca-fe/web/cafes/\(clubID)/articles/\(id.articleID)"
        } else if let cafeName = id.cafeName, !cafeName.isEmpty {
            components.path = "/\(cafeName)/\(id.articleID)"
        } else {
            components.path = "/ArticleRead.nhn"
            components.queryItems = [URLQueryItem(name: "articleid", value: id.articleID)]
        }
        return components.url!
    }

    static func canonicalInputURL(for url: URL) -> URL? {
        guard articleID(from: url) != nil else { return nil }
        return originalFixedURL(for: url) ?? url
    }

    private static func articleBodyHTML(fromHTML html: String) -> String? {
        let patterns = [
            #"<div\b[^>]*\bclass\s*=\s*["'][^"']*se-main-container[^"']*["'][^>]*>(.*?)</div>\s*</div>"#,
            #"<div\b[^>]*\bid\s*=\s*["']tbody["'][^>]*>(.*?)</div>"#,
            #"<div\b[^>]*\bclass\s*=\s*["'][^"']*article_container[^"']*["'][^>]*>(.*?)</div>\s*</div>"#,
            #"<div\b[^>]*\bclass\s*=\s*["'][^"']*ContentRenderer[^"']*["'][^>]*>(.*?)</div>\s*</div>"#
        ]
        for pattern in patterns {
            if let body = captureMatches(pattern: pattern, in: html).first {
                return body
            }
        }
        return nil
    }

    private static func hasArticleContainer(in html: String) -> Bool {
        html.range(of: #"se-main-container|id\s*=\s*["']tbody["']|article_container|ContentRenderer"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func frameURL(fromHTML html: String, baseURL: URL) -> URL? {
        let frameTags = captureFullMatches(pattern: #"<(?:frame|iframe)\b[^>]*>"#, in: html)
        for tag in frameTags {
            let values = attributeValues(from: tag)
            guard let raw = values["src"],
                  raw.lowercased().contains("article"),
                  let url = absoluteURL(raw, baseURL: baseURL) else {
                continue
            }
            return url
        }
        return nil
    }

    private static func mediaTagCandidates(fromHTML html: String) -> [String] {
        let tags = captureFullMatches(pattern: #"<(?:span|img|video|source)\b[^>]*>"#, in: html)
        var candidates: [String] = []
        for tag in tags {
            let values = attributeValues(from: tag)
            let className = values["class"]?.lowercased() ?? ""
            let isLikelyArticleMedia = className.contains("se-image") ||
                className.contains("_img") ||
                values["data-gif-url"] != nil ||
                values["data-lazy-src"] != nil ||
                values["data-src"] != nil ||
                values["data-original"] != nil ||
                values["src"] != nil
            guard isLikelyArticleMedia else { continue }

            for key in ["data-gif-url", "data-lazy-src", "data-src", "data-original", "data-url", "src"] {
                if let value = values[key]?.trimmed, !value.isEmpty {
                    candidates.append(value)
                    break
                }
            }
        }
        return candidates
    }

    private static func scriptImageCandidates(fromHTML html: String) -> [String] {
        let patterns = [
            #""(?:url|src|originalUrl|imageUrl)"\s*:\s*"([^"]+\.(?:jpg|jpeg|png|gif|webp)(?:\?[^"]*)?)""#,
            #"'(?:url|src|originalUrl|imageUrl)'\s*:\s*'([^']+\.(?:jpg|jpeg|png|gif|webp)(?:\?[^']*)?)'"#
        ]
        return patterns.flatMap { captureMatches(pattern: $0, in: html) }
    }

    private static func shouldDownload(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        if host == "ssl.pstatic.net" || host == "static.naver.net" || host.contains("sprite") {
            return false
        }

        let ext = url.pathExtension.lowercased()
        if ["jpg", "jpeg", "png", "gif", "webp"].contains(ext) {
            return true
        }
        return host.contains("pstatic") || host.contains("cafefiles")
    }

    private static func articleTitle(fromHTML html: String, fallback: String) -> String {
        let title = textForClass("title_text", in: html) ??
            textForClass("tit", in: html) ??
            metaContent(from: html, names: ["og:title", "twitter:title"]) ??
            titleTag(fromHTML: html) ??
            fallback
        return cleanTitle(title, fallback: fallback)
    }

    private static func articleAuthor(fromHTML html: String) -> String? {
        textForClass("nickname", in: html) ??
            textForClass("nick", in: html) ??
            textForClass("profile_name", in: html) ??
            metaContent(from: html, names: ["article:author", "author"])
    }

    private static func cafeLabel(for id: NaverCafeID) -> String {
        id.cafeName ?? id.clubID ?? ""
    }

    private static func naverCafeMetadata(id: NaverCafeID, author: String?, title: String = "", pageURL: URL? = nil, assets: [ResolvedAsset] = []) -> [String: String] {
        let label = cafeLabel(for: id)
        let imageCount = assets.filter { ($0.metadata["media_type"] ?? $0.metadata["type"]) == "image" }.count
        let videoCount = assets.filter { ($0.metadata["media_type"] ?? $0.metadata["type"]) == "video" }.count
        return DownloadMetadata.clean([
            "id": id.articleID,
            "title": title,
            "artist": author ?? label,
            "author": author ?? label,
            "creator": author ?? label,
            "user": author ?? "",
            "username": author ?? "",
            "uploader": author ?? "",
            "channel": label,
            "channel_id": id.clubID ?? id.cafeName ?? "",
            "club_id": id.clubID ?? "",
            "cafe_name": id.cafeName ?? "",
            "article_id": id.articleID,
            "post_id": id.articleID,
            "gallery_id": id.articleID,
            "media_id": id.articleID,
            "type": "article",
            "media_type": videoCount > 0 && imageCount == 0 ? "video" : "image",
            "media_count": assets.isEmpty ? "" : String(assets.count),
            "image_count": imageCount > 0 ? String(imageCount) : "",
            "video_count": videoCount > 0 ? String(videoCount) : "",
            "source_url": pageURL?.absoluteString ?? "",
            "page_url": pageURL?.absoluteString ?? "",
            "site": "Naver Cafe"
        ])
    }

    private static func assetMetadata(for url: URL, id: NaverCafeID, author: String?, pageURL: URL, index: Int, mediaType: String, videoInfo: [String: Any] = [:]) -> [String: String] {
        let format = url.pathExtension.trimmed.isEmpty ? (mediaType == "video" ? "mp4" : "jpg") : url.pathExtension.lowercased()
        let width = stringValue(videoInfo["width"]) ?? stringValue(videoInfo["w"]) ?? ""
        let height = stringValue(videoInfo["height"]) ?? stringValue(videoInfo["h"]) ?? ""
        let quality = stringValue(videoInfo["quality"]) ?? stringValue(videoInfo["label"]) ?? (height.isEmpty ? "" : "\(height)p")
        var metadata = DownloadMetadata.clean([
            "site": "Naver Cafe",
            "type": mediaType,
            "media_type": mediaType,
            "id": id.articleID,
            "article_id": id.articleID,
            "post_id": id.articleID,
            "gallery_id": id.articleID,
            "media_id": "\(id.articleID)-\(index)",
            "page": String(index),
            "position": String(index),
            "format": format,
            "media_format": format,
            "width": width,
            "height": height,
            "resolution": height.isEmpty ? "" : "\(height)p",
            "quality": quality,
            "byte_count": stringValue(videoInfo["size"]) ?? stringValue(videoInfo["filesize"]) ?? "",
            "media_url": url.absoluteString,
            "source_url": pageURL.absoluteString,
            "page_url": pageURL.absoluteString,
            "club_id": id.clubID ?? "",
            "cafe_name": id.cafeName ?? "",
            "artist": author ?? cafeLabel(for: id),
            "author": author ?? cafeLabel(for: id),
            "creator": author ?? cafeLabel(for: id)
        ])
        if mediaType == "video" {
            metadata["video_url"] = url.absoluteString
        } else {
            metadata["image_url"] = url.absoluteString
        }
        return metadata
    }

    private static func videoDictionaries(in object: Any) -> [[String: Any]] {
        if let dict = object as? [String: Any] {
            if let videos = dict["videos"] as? [String: Any],
               let list = videos["list"] as? [[String: Any]] {
                return list
            }
            if let list = dict["list"] as? [[String: Any]] {
                return list
            }
            for value in dict.values {
                let found = videoDictionaries(in: value)
                if !found.isEmpty { return found }
            }
        } else if let list = object as? [[String: Any]] {
            return list
        } else if let array = object as? [Any] {
            for value in array {
                let found = videoDictionaries(in: value)
                if !found.isEmpty { return found }
            }
        }
        return []
    }

    private static func filename(for url: URL, index: Int) -> String {
        let ext = url.pathExtension.trimmed.isEmpty ? "jpg" : url.pathExtension
        return String(format: "%04d.%@", index, ext).sanitizedFilename(maxLength: 120)
    }

    private static func fallbackArticleID(from url: URL) -> String {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name.lowercased() == "articleid" }?
            .value ?? url.lastPathComponent
    }

    private static func isNaverCafeHost(_ host: String) -> Bool {
        host == "cafe.naver.com" ||
            host == "m.cafe.naver.com" ||
            host == "cafe.naver.test" ||
            host == "m.cafe.naver.test"
    }

    private static func reservedCafePath(_ value: String) -> Bool {
        ["articlelist", "articleread.nhn", "cafes", "ca-fe", "member", "mycafeintro.nhn", "search"].contains(value.lowercased())
    }

    private static func queryValue(_ names: [String], in items: [URLQueryItem]) -> String? {
        for name in names {
            if let value = items.first(where: { $0.name.lowercased() == name.lowercased() })?.value,
               !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func textForClass(_ className: String, in html: String) -> String? {
        let pattern = #"<[^>]+\bclass\s*=\s*["'][^"']*"# +
            NSRegularExpression.escapedPattern(for: className) +
            #"[^"']*["'][^>]*>(.*?)</[^>]+>"#
        return captureMatches(pattern: pattern, in: html).first.map(stripTags)
    }

    private static func metaContent(from html: String, names: Set<String>) -> String? {
        let metas = captureFullMatches(pattern: #"<meta\b[^>]*>"#, in: html)
        for tag in metas {
            let values = attributeValues(from: tag)
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

    private static func titleTag(fromHTML html: String) -> String? {
        captureMatches(pattern: #"<title\b[^>]*>(.*?)</title>"#, in: html).first
    }

    private static func cleanTitle(_ raw: String, fallback: String) -> String {
        var title = decodeHTML(stripTags(raw))
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmed
        for suffix in [" : 네이버 카페", " | 네이버 카페", " - 네이버 카페", " : Naver Cafe", " | Naver Cafe", " - Naver Cafe"] {
            if title.lowercased().hasSuffix(suffix.lowercased()) {
                title.removeLast(suffix.count)
                title = title.trimmed
            }
        }
        return title.isEmpty ? fallback : title
    }

    private static func attributeValues(from text: String) -> [String: String] {
        guard let regex = try? NSRegularExpression(
            pattern: #"\b([A-Za-z_:][-A-Za-z0-9_:.]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>"']+))"#,
            options: [.caseInsensitive]
        ) else {
            return [:]
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        var values: [String: String] = [:]
        for match in regex.matches(in: text, range: range) {
            guard let nameRange = Range(match.range(at: 1), in: text) else { continue }
            let name = String(text[nameRange]).lowercased()
            for group in 2...4 {
                guard let valueRange = Range(match.range(at: group), in: text) else { continue }
                values[name] = normalizeEscapes(decodeHTML(String(text[valueRange]))).trimmed
                break
            }
        }
        return values
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
            return normalizeEscapes(String(text[capture]))
        }
    }

    private static func captureGroups(pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1 else {
            return []
        }
        return (1..<match.numberOfRanges).compactMap { index in
            guard let capture = Range(match.range(at: index), in: text) else { return nil }
            return normalizeEscapes(String(text[capture]))
        }
    }

    private static func captureFullMatches(pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let capture = Range(match.range(at: 0), in: text) else { return nil }
            return String(text[capture])
        }
    }

    private static func firstCapture(patterns: [String], in text: String) -> String? {
        for pattern in patterns {
            if let value = captureMatches(pattern: pattern, in: text).first {
                return value
            }
        }
        return nil
    }

    private static func absoluteURL(_ raw: String, baseURL: URL) -> URL? {
        let value = normalizeEscapes(decodeHTML(raw)).trimmed
        if value.hasPrefix("//") {
            return URL(string: "\(baseURL.scheme ?? "https"):\(value)")
        }
        return URL(string: value, relativeTo: baseURL)?.absoluteURL
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) }
        return nil
    }

    private static func isNumeric(_ text: String) -> Bool {
        !text.isEmpty && text.allSatisfy { $0 >= "0" && $0 <= "9" }
    }

    private static func normalizeEscapes(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"\\u002F"#, with: "/", options: .caseInsensitive)
            .replacingOccurrences(of: #"\/"#, with: "/")
            .replacingOccurrences(of: #"\\/"#, with: "/")
            .replacingOccurrences(of: #"\\u0026"#, with: "&", options: .caseInsensitive)
            .replacingOccurrences(of: #"\""#, with: "\"")
    }

    private static func stripTags(_ text: String) -> String {
        decodeHTML(text)
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
            .replacingOccurrences(of: "&nbsp;", with: " ")
    }
}
