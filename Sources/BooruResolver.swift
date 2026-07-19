import Foundation

enum BooruProvider: String {
    case danbooru = "Danbooru"
    case gelbooru = "Gelbooru"
    case yandere = "Yande.re"
    case rule34 = "Rule34"

    static func provider(for url: URL) -> BooruProvider? {
        guard let host = url.host?.lowercased() else { return nil }
        if host == "danbooru.donmai.us" || host == "danbooru.test" {
            return .danbooru
        }
        if host == "gelbooru.com" || host == "gelbooru.test" {
            return .gelbooru
        }
        if host == "yande.re" || host == "yandere.test" {
            return .yandere
        }
        if host == "rule34.xxx" || host == "rule34.test" {
            return .rule34
        }
        return nil
    }
}

struct BooruAPIRequest {
    var url: URL
    var provider: BooruProvider
    var titleHint: String
    var pagination: BooruPaginationStyle = .none
}

enum BooruPaginationStyle: Equatable {
    case none
    case page
    case pid

    var queryName: String? {
        switch self {
        case .none: return nil
        case .page: return "page"
        case .pid: return "pid"
        }
    }

    var firstValue: Int {
        switch self {
        case .none, .page: return 1
        case .pid: return 0
        }
    }
}

final class BooruResolver {
    typealias RenderedHTMLProvider = @Sendable (URL, HTTPRequestOptions) async throws -> String

    static let defaultCollectionAssetLimit = 2_000
    private static let maximumCollectionPages = 1_000

    private let renderedHTMLProvider: RenderedHTMLProvider?

    init(renderedHTMLProvider: RenderedHTMLProvider? = nil) {
        self.renderedHTMLProvider = renderedHTMLProvider
    }

    func canResolve(_ url: URL) -> Bool {
        BooruProvider.provider(for: url) != nil
    }

    func resolve(
        _ url: URL,
        headers: HTTPRequestOptions = HTTPRequestOptions(),
        assetLimit: Int? = nil
    ) async throws -> ResolvedDownload {
        let request = try apiRequest(for: url)
        if request.pagination != .none {
            return try await resolveCollection(
                sourceURL: url,
                request: request,
                headers: headers,
                assetLimit: assetLimit
            )
        }

        let referer = headers.referer ?? url.absoluteString
        do {
            let data = try await HTTPClient.shared.data(
                from: request.url,
                referer: referer,
                userAgent: headers.userAgent
            )
            return try Self.resolvedDownload(
                from: data,
                baseURL: request.url,
                provider: request.provider,
                titleHint: request.titleHint,
                referer: url.absoluteString
            )
        } catch where request.provider == .danbooru && Self.danbooruPostID(in: url) != nil {
            return try await resolveDanbooruPostPage(
                url,
                titleHint: request.titleHint,
                headers: headers
            )
        }
    }

    private func resolveCollection(
        sourceURL: URL,
        request: BooruAPIRequest,
        headers: HTTPRequestOptions,
        assetLimit: Int?
    ) async throws -> ResolvedDownload {
        let limit = max(1, assetLimit ?? Self.defaultCollectionAssetLimit)
        let referer = headers.referer ?? sourceURL.absoluteString
        var pageValue = request.pagination.firstValue
        var posts: [[String: Any]] = []
        var seen = Set<String>()
        var nonemptyPageCount = 0
        var usedRenderedHTML = false

        while posts.count < limit && nonemptyPageCount < Self.maximumCollectionPages {
            try Task.checkCancellation()
            let pageURL = paginatedURL(for: request, pageValue: pageValue)
            let pagePosts: [[String: Any]]
            do {
                let data = try await HTTPClient.shared.data(
                    from: pageURL,
                    referer: referer,
                    userAgent: headers.userAgent
                )
                let object = try JSONSerialization.jsonObject(with: data)
                pagePosts = Self.postDictionaries(from: object)
            } catch where request.provider == .danbooru {
                pagePosts = try await renderedDanbooruPosts(
                    sourceURL: sourceURL,
                    pageValue: pageValue,
                    remaining: limit - posts.count,
                    headers: headers
                )
                usedRenderedHTML = true
            }

            guard !pagePosts.isEmpty else { break }
            nonemptyPageCount += 1
            var inserted = 0
            for post in pagePosts {
                guard let remote = Self.mediaURL(from: post, baseURL: pageURL) else { continue }
                let identity = Self.stringValue(post["id"])
                    .map { "id:\($0)" } ?? "url:\(URLIdentity.normalize(remote.absoluteString))"
                guard seen.insert(identity).inserted else { continue }
                posts.append(post)
                inserted += 1
                if posts.count == limit { break }
            }
            guard inserted > 0 else { break }
            pageValue += 1
        }

        guard !posts.isEmpty else { throw NativeDownloadError.noFiles }
        let data = try JSONSerialization.data(withJSONObject: posts)
        var resolved = try Self.resolvedDownload(
            from: data,
            baseURL: request.url,
            provider: request.provider,
            titleHint: request.titleHint,
            referer: sourceURL.absoluteString
        )
        resolved.metadata["page_count"] = String(nonemptyPageCount)
        resolved.metadata["resolver_api"] = usedRenderedHTML ? "Rendered HTML" : "JSON"
        resolved.metadata["original_contract"] = request.provider == .danbooru
            ? "danbooru-4.2-improved-clf2"
            : "booru-4.2"
        return resolved
    }

    private func resolveDanbooruPostPage(
        _ url: URL,
        titleHint: String,
        headers: HTTPRequestOptions
    ) async throws -> ResolvedDownload {
        let referer = headers.referer ?? url.absoluteString
        do {
            let html = try await HTTPClient.shared.string(
                from: url,
                referer: referer,
                userAgent: headers.userAgent
            )
            return try Self.resolvedDownload(
                fromHTML: html,
                pageURL: url,
                provider: .danbooru,
                titleHint: titleHint
            )
        } catch {
            let html = try await renderedHTML(for: url, headers: headers)
            var resolved = try Self.resolvedDownload(
                fromHTML: html,
                pageURL: url,
                provider: .danbooru,
                titleHint: titleHint
            )
            resolved.metadata["resolver_api"] = "Rendered HTML"
            resolved.metadata["original_contract"] = "danbooru-4.2-improved-clf2"
            return resolved
        }
    }

    private func renderedDanbooruPosts(
        sourceURL: URL,
        pageValue: Int,
        remaining: Int,
        headers: HTTPRequestOptions
    ) async throws -> [[String: Any]] {
        let listingURL = Self.danbooruHTMLPageURL(sourceURL, pageValue: pageValue)
        let listingHTML = try await renderedHTML(for: listingURL, headers: headers)
        let postURLs = Self.danbooruPostURLs(fromHTML: listingHTML, baseURL: listingURL)
        var posts: [[String: Any]] = []
        for postURL in postURLs.prefix(max(0, remaining)) {
            try Task.checkCancellation()
            let html = try await renderedHTML(for: postURL, headers: headers)
            guard let remote = Self.htmlMediaURL(fromHTML: html, pageURL: postURL) else { continue }
            posts.append(Self.htmlPostDictionary(fromHTML: html, pageURL: postURL, remote: remote))
        }
        return posts
    }

    private func renderedHTML(for url: URL, headers: HTTPRequestOptions) async throws -> String {
        if let renderedHTMLProvider {
            return try await renderedHTMLProvider(url, headers)
        }

        var requestHeaders: [String: String] = [:]
        if let referer = headers.referer?.trimmed, !referer.isEmpty {
            requestHeaders["Referer"] = referer
        }
        if let userAgent = headers.userAgent?.trimmed, !userAgent.isEmpty {
            requestHeaders["User-Agent"] = userAgent
        }
        if let cookie = await CookieStore.shared.cookieHeader(for: url) {
            requestHeaders["Cookie"] = cookie
        }
        let page = try await PythonWebRendererService.shared.renderPage(
            url: url,
            headers: requestHeaders,
            timeout: 90,
            delay: 5
        )
        if let host = url.host, !page.cookies.isEmpty {
            let cookies = page.cookies.compactMap { name, value in
                HTTPCookie(properties: [
                    .domain: host,
                    .path: "/",
                    .name: name,
                    .value: value,
                    .secure: url.scheme?.lowercased() == "https" ? "TRUE" : "FALSE"
                ])
            }
            _ = await CookieStore.shared.importHTTPCookies(cookies)
        }
        return page.html
    }

    private func paginatedURL(for request: BooruAPIRequest, pageValue: Int) -> URL {
        guard let queryName = request.pagination.queryName else { return request.url }
        return Self.replacingQueryValue(queryName, with: String(pageValue), in: request.url)
    }

    private static func danbooruHTMLPageURL(_ sourceURL: URL, pageValue: Int) -> URL {
        replacingQueryValue("page", with: String(pageValue), in: sourceURL)
    }

    private static func replacingQueryValue(_ name: String, with value: String, in url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        var items = components.queryItems ?? []
        items.removeAll { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        items.append(URLQueryItem(name: name, value: value))
        components.queryItems = items
        return components.url ?? url
    }

    static func danbooruPostURLs(fromHTML html: String, baseURL: URL) -> [URL] {
        var output: [URL] = []
        var seen = Set<String>()
        let articles = regexSnippets(#"<article\b[^>]*>.*?</article>"#, in: html)
        for article in articles {
            var candidate: URL?
            if let id = firstCapture(#"\bdata-id\s*=\s*(?:\"([0-9]+)\"|'([0-9]+)'|([0-9]+))"#, in: article),
               var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) {
                components.path = "/posts/\(id)"
                components.query = nil
                components.fragment = nil
                candidate = components.url
            }
            if candidate == nil {
                for href in attributeValues(named: ["href"], in: article) {
                    guard href.range(of: #"/posts/[0-9]+"#, options: .regularExpression) != nil,
                          let url = absoluteURL(htmlDecoded(href), baseURL: baseURL) else { continue }
                    candidate = url
                    break
                }
            }
            guard let candidate else { continue }
            let identity = URLIdentity.normalize(candidate.absoluteString)
            if seen.insert(identity).inserted {
                output.append(candidate)
            }
        }
        return output
    }

    func apiRequest(for url: URL) throws -> BooruAPIRequest {
        guard let provider = BooruProvider.provider(for: url) else {
            throw NativeDownloadError.unsupported("Unsupported booru host.")
        }

        switch provider {
        case .danbooru:
            return try danbooruAPIRequest(for: url, provider: provider)
        case .gelbooru, .rule34:
            return try dapiAPIRequest(for: url, provider: provider)
        case .yandere:
            return try yandereAPIRequest(for: url, provider: provider)
        }
    }

    static func resolvedDownload(from data: Data, baseURL: URL, provider: BooruProvider, titleHint: String, referer: String) throws -> ResolvedDownload {
        let object = try JSONSerialization.jsonObject(with: data)
        let posts = postDictionaries(from: object)
        var assets: [ResolvedAsset] = []
        var metadata = DownloadMetadata.clean(["search": titleHint])

        for (offset, post) in posts.enumerated() {
            guard let remote = mediaURL(from: post, baseURL: baseURL) else { continue }
            let id = stringValue(post["id"]) ?? String(offset + 1)
            let fallback = remote.lastPathComponent.isEmpty ? "\(id).jpg" : remote.lastPathComponent
            let filename = "\(id)-\(fallback)".sanitizedFilename(maxLength: 180)
            assets.append(ResolvedAsset(
                remoteURL: remote,
                filename: filename,
                metadata: assetMetadata(from: post, provider: provider, remote: remote, referer: referer, index: assets.count + 1),
                referer: referer
            ))
            metadata = metadata.merging(postMetadata(from: post)) { current, _ in current }
        }

        guard !assets.isEmpty else {
            throw NativeDownloadError.noFiles
        }

        let title = titleHint.sanitizedFilename(maxLength: 120)
        if metadata["tag"] == nil {
            metadata["tag"] = titleHint
        }
        if metadata["tags"] == nil {
            metadata["tags"] = titleHint
        }
        if metadata["category"] == nil {
            metadata["category"] = titleHint
        }
        let imageCount = assets.filter { isImage($0.remoteURL) }.count
        let videoCount = assets.filter { isVideo($0.remoteURL) }.count
        metadata["type"] = metadata["type"] ?? "post"
        metadata["media_type"] = mediaType(imageCount: imageCount, videoCount: videoCount)
        metadata["media_count"] = String(assets.count)
        if imageCount > 0 {
            metadata["image_count"] = String(imageCount)
        }
        if videoCount > 0 {
            metadata["video_count"] = String(videoCount)
        }
        metadata["site"] = provider.rawValue
        metadata["provider"] = provider.rawValue
        metadata["api_url"] = baseURL.absoluteString
        metadata["url"] = referer
        metadata["source_url"] = referer
        metadata["page_url"] = referer
        metadata["title"] = title
        return ResolvedDownload(
            title: title,
            folderName: "\(provider.rawValue) \(title)".sanitizedFilename(maxLength: 120),
            assets: assets,
            metadata: metadata
        )
    }

    static func resolvedDownload(fromHTML html: String, pageURL: URL, provider: BooruProvider, titleHint: String) throws -> ResolvedDownload {
        guard let remote = htmlMediaURL(fromHTML: html, pageURL: pageURL) else {
            throw NativeDownloadError.noFiles
        }

        let post = htmlPostDictionary(fromHTML: html, pageURL: pageURL, remote: remote)
        let id = stringValue(post["id"]) ?? "1"
        let fallback = remote.lastPathComponent.isEmpty ? "\(id).\(mediaExtension(for: remote))" : remote.lastPathComponent
        let filename = "\(id)-\(fallback)".sanitizedFilename(maxLength: 180)
        let asset = ResolvedAsset(
            remoteURL: remote,
            filename: filename,
            metadata: assetMetadata(from: post, provider: provider, remote: remote, referer: pageURL.absoluteString, index: 1),
            referer: pageURL.absoluteString
        )

        let title = titleHint.sanitizedFilename(maxLength: 120)
        let imageCount = isImage(remote) ? 1 : 0
        let videoCount = isVideo(remote) ? 1 : 0
        var metadata = DownloadMetadata.clean(["search": titleHint])
            .merging(postMetadata(from: post)) { current, _ in current }
        if metadata["tag"] == nil {
            metadata["tag"] = titleHint
        }
        if metadata["tags"] == nil {
            metadata["tags"] = titleHint
        }
        if metadata["category"] == nil {
            metadata["category"] = titleHint
        }
        metadata["type"] = metadata["type"] ?? "post"
        metadata["media_type"] = mediaType(imageCount: imageCount, videoCount: videoCount)
        metadata["media_count"] = "1"
        if imageCount > 0 {
            metadata["image_count"] = "1"
        }
        if videoCount > 0 {
            metadata["video_count"] = "1"
        }
        metadata["site"] = provider.rawValue
        metadata["provider"] = provider.rawValue
        metadata["url"] = pageURL.absoluteString
        metadata["source_url"] = pageURL.absoluteString
        metadata["page_url"] = pageURL.absoluteString
        metadata["title"] = title

        return ResolvedDownload(
            title: title,
            folderName: "\(provider.rawValue) \(title)".sanitizedFilename(maxLength: 120),
            assets: [asset],
            metadata: DownloadMetadata.clean(metadata)
        )
    }

    private func danbooruAPIRequest(for url: URL, provider: BooruProvider) throws -> BooruAPIRequest {
        if isDanbooruFavoritesURL(url) {
            guard let userID = favoriteUserID(in: url) else {
                throw NativeDownloadError.unsupported("Danbooru favorites require user_id.")
            }
            let apiURL = try url.replacingPath("/posts.json", queryItems: [
                URLQueryItem(name: "tags", value: "ordfav:\(userID)"),
                URLQueryItem(name: "limit", value: "100")
            ])
            return BooruAPIRequest(url: apiURL, provider: provider, titleHint: "fav_\(userID)", pagination: .page)
        }

        if isDanbooruPopularURL(url) {
            let apiURL = try url.replacingPath("/explore/posts/popular.json", queryItems: preservedQueryItems(["date", "scale", "page", "limit"], in: url))
            return BooruAPIRequest(url: apiURL, provider: provider, titleHint: "Danbooru popular", pagination: .page)
        }

        if let id = postID(in: url, patterns: [#"/posts/([0-9]+)"#]) ?? queryValue("id", in: url) {
            let apiURL = try url.replacingPath("/posts/\(id).json", queryItems: [])
            return BooruAPIRequest(url: apiURL, provider: provider, titleHint: "\(provider.rawValue) \(id)")
        }

        let tags = queryValue("tags", in: url) ?? ""
        let apiURL = try url.replacingPath("/posts.json", queryItems: [
            URLQueryItem(name: "tags", value: tags),
            URLQueryItem(name: "limit", value: "100")
        ])
        let title = tags.trimmed.isEmpty ? "\(provider.rawValue) posts" : tags
        return BooruAPIRequest(url: apiURL, provider: provider, titleHint: title, pagination: .page)
    }

    private func yandereAPIRequest(for url: URL, provider: BooruProvider) throws -> BooruAPIRequest {
        if let poolID = yanderePoolID(in: url) {
            let apiURL = try url.replacingPath("/post.json", queryItems: [
                URLQueryItem(name: "tags", value: "pool:\(poolID)"),
                URLQueryItem(name: "limit", value: "100")
            ])
            return BooruAPIRequest(url: apiURL, provider: provider, titleHint: "pool_\(poolID)", pagination: .page)
        }

        let id = postID(in: url, patterns: [#"/post/show/([0-9]+)"#]) ?? queryValue("id", in: url)
        let tags = id.map { "id:\($0)" } ?? queryValue("tags", in: url) ?? ""
        let apiURL = try url.replacingPath("/post.json", queryItems: [
            URLQueryItem(name: "tags", value: tags),
            URLQueryItem(name: "limit", value: "100")
        ])
        let title = id.map { "\(provider.rawValue) \($0)" } ?? (tags.trimmed.isEmpty ? "\(provider.rawValue) posts" : tags)
        return BooruAPIRequest(
            url: apiURL,
            provider: provider,
            titleHint: title,
            pagination: id == nil ? .page : .none
        )
    }

    private func dapiAPIRequest(for url: URL, provider: BooruProvider) throws -> BooruAPIRequest {
        if (provider == .gelbooru || provider == .rule34),
           isDapiFavoritesURL(url) {
            guard let userID = favoriteUserID(in: url) else {
                throw NativeDownloadError.unsupported("\(provider.rawValue) favorites require id or user_id.")
            }
            var favoriteItems = [
                URLQueryItem(name: "page", value: "dapi"),
                URLQueryItem(name: "s", value: "post"),
                URLQueryItem(name: "q", value: "index"),
                URLQueryItem(name: "json", value: "1"),
                URLQueryItem(name: "tags", value: "fav:\(userID)"),
                URLQueryItem(name: "limit", value: queryValue("limit", in: url)?.trimmed.isEmpty == false ? queryValue("limit", in: url) : "100")
            ]
            if let pid = queryValue("pid", in: url), !pid.trimmed.isEmpty {
                favoriteItems.append(URLQueryItem(name: "pid", value: pid))
            }
            if provider == .gelbooru {
                favoriteItems.append(URLQueryItem(name: "blacklist", value: "0"))
            } else if let blacklist = queryValue("blacklist", in: url), !blacklist.trimmed.isEmpty {
                favoriteItems.append(URLQueryItem(name: "blacklist", value: blacklist))
            }
            let apiURL = try url.replacingPath("/index.php", queryItems: favoriteItems)
            return BooruAPIRequest(url: apiURL, provider: provider, titleHint: "fav_\(userID)", pagination: .pid)
        }

        let id = queryValue("id", in: url)
        let tags = queryValue("tags", in: url) ?? ""
        var queryItems = [
            URLQueryItem(name: "page", value: "dapi"),
            URLQueryItem(name: "s", value: "post"),
            URLQueryItem(name: "q", value: "index"),
            URLQueryItem(name: "json", value: "1")
        ]

        if let id, !id.isEmpty {
            queryItems.append(URLQueryItem(name: "id", value: id))
        } else {
            let limit = queryValue("limit", in: url)?.trimmed
            queryItems.append(URLQueryItem(name: "tags", value: tags))
            queryItems.append(URLQueryItem(name: "limit", value: limit?.isEmpty == false ? limit : "100"))
            if let pid = queryValue("pid", in: url), !pid.trimmed.isEmpty {
                queryItems.append(URLQueryItem(name: "pid", value: pid))
            }
        }

        if provider == .gelbooru {
            queryItems.append(URLQueryItem(name: "blacklist", value: "0"))
        } else if let blacklist = queryValue("blacklist", in: url), !blacklist.trimmed.isEmpty {
            queryItems.append(URLQueryItem(name: "blacklist", value: blacklist))
        }

        let apiURL = try url.replacingPath("/index.php", queryItems: queryItems)
        let title = id.map { "\(provider.rawValue) \($0)" } ?? (tags.trimmed.isEmpty ? "\(provider.rawValue) posts" : tags)
        return BooruAPIRequest(
            url: apiURL,
            provider: provider,
            titleHint: title,
            pagination: id == nil ? .pid : .none
        )
    }

    private func isDanbooruFavoritesURL(_ url: URL) -> Bool {
        url.path.lowercased().contains("/favorites")
    }

    private func isDanbooruPopularURL(_ url: URL) -> Bool {
        url.path.lowercased().contains("/explore/posts/popular")
    }

    private func isDapiFavoritesURL(_ url: URL) -> Bool {
        let path = url.path.lowercased()
        if path.contains("/favorites") {
            return true
        }
        return queryValue("page", in: url)?.lowercased() == "favorites"
    }

    private func favoriteUserID(in url: URL) -> String? {
        for key in ["user_id", "search[user_id]", "search[id]", "user", "id"] {
            if let value = queryValue(key, in: url)?.trimmed, !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private func yanderePoolID(in url: URL) -> String? {
        let path = url.path
        if let id = postID(in: url, patterns: [#"/pool/show/([0-9]+)"#, #"/pool/([0-9]+)"#]) {
            return id
        }
        guard path.lowercased().contains("/pool") else { return nil }
        if let poolID = queryValue("pool_id", in: url)?.trimmed, !poolID.isEmpty {
            return poolID
        }
        if let id = queryValue("id", in: url)?.trimmed, !id.isEmpty {
            return id
        }
        return nil
    }

    private func postID(in url: URL, patterns: [String]) -> String? {
        let path = url.path
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(path.startIndex..<path.endIndex, in: path)
            guard let match = regex.firstMatch(in: path, range: range),
                  match.numberOfRanges > 1,
                  let capture = Range(match.range(at: 1), in: path) else {
                continue
            }
            return String(path[capture])
        }
        return nil
    }

    private func queryValue(_ name: String, in url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name.lowercased() == name.lowercased() }?
            .value
    }

    private func preservedQueryItems(_ names: [String], in url: URL) -> [URLQueryItem] {
        let allowed = Set(names.map { $0.lowercased() })
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .filter { allowed.contains($0.name.lowercased()) && ($0.value?.trimmed.isEmpty == false) } ?? []
    }

    private static func postDictionaries(from object: Any) -> [[String: Any]] {
        if let array = object as? [[String: Any]] {
            return array
        }

        if let dictionary = object as? [String: Any] {
            if let posts = dictionary["post"] as? [[String: Any]] {
                return posts
            }
            if let post = dictionary["post"] as? [String: Any] {
                return [post]
            }
            if let posts = dictionary["posts"] as? [[String: Any]] {
                return posts
            }
            if let posts = dictionary["results"] as? [[String: Any]] {
                return posts
            }
            if dictionary.keys.contains(where: { ["file_url", "large_file_url", "jpeg_url", "sample_url", "media_asset", "mediaAsset"].contains($0) }) {
                return [dictionary]
            }
        }

        return []
    }

    private static func mediaURL(from post: [String: Any], baseURL: URL) -> URL? {
        let candidates = [
            stringValue(post["file_url"]),
            stringValue(post["large_file_url"]),
            stringValue(post["jpeg_url"]),
            stringValue(post["sample_url"]),
            stringValue(post["animated_gif_url"]),
            stringValue(post["video_url"]),
            stringValue(post["mp4_url"]),
            stringValue(post["source"])
        ]

        for candidate in candidates.compactMap({ $0 }).filter({ !$0.trimmed.isEmpty }) {
            if let url = absoluteURL(candidate, baseURL: baseURL) {
                return url
            }
        }

        if let url = mediaAssetURL(from: post, baseURL: baseURL) {
            return url
        }

        if let directory = stringValue(post["directory"]),
           let image = stringValue(post["image"]),
           !directory.isEmpty,
           !image.isEmpty {
            return absoluteURL("/images/\(directory)/\(image)", baseURL: baseURL)
        }

        return nil
    }

    private static func mediaAssetURL(from post: [String: Any], baseURL: URL) -> URL? {
        let containers = [
            post["media_asset"],
            post["mediaAsset"],
            post["media"],
            post["asset"]
        ]

        var scored: [(score: Int, url: URL)] = []
        for container in containers {
            scored.append(contentsOf: mediaAssetCandidates(from: container, baseURL: baseURL, depth: 0))
        }

        return scored.max { lhs, rhs in
            lhs.score < rhs.score
        }?.url
    }

    private static func mediaAssetCandidates(from value: Any?, baseURL: URL, depth: Int) -> [(score: Int, url: URL)] {
        guard depth < 4 else { return [] }

        if let array = value as? [Any] {
            return array.flatMap { mediaAssetCandidates(from: $0, baseURL: baseURL, depth: depth + 1) }
        }

        guard let dictionary = value as? [String: Any] else {
            if let raw = stringValue(value),
               let url = absoluteURL(raw, baseURL: baseURL) {
                return [(mediaAssetScore(type: nil, url: raw, dictionary: [:]), url)]
            }
            return []
        }

        let urlKeys = [
            "url",
            "file_url",
            "fileUrl",
            "large_file_url",
            "largeFileUrl",
            "original_url",
            "originalUrl",
            "source_url",
            "sourceUrl",
            "download_url",
            "downloadUrl"
        ]
        let type = stringValue(dictionary["type"]) ??
            stringValue(dictionary["name"]) ??
            stringValue(dictionary["variant"]) ??
            stringValue(dictionary["format"])
        var results: [(score: Int, url: URL)] = []

        for key in urlKeys {
            guard let raw = stringValue(dictionary[key]),
                  !raw.trimmed.isEmpty,
                  let url = absoluteURL(raw, baseURL: baseURL) else {
                continue
            }
            results.append((mediaAssetScore(type: type ?? key, url: raw, dictionary: dictionary), url))
        }

        let nestedKeys = [
            "variants",
            "variant",
            "files",
            "file",
            "samples",
            "sample",
            "original",
            "large",
            "media_asset",
            "mediaAsset"
        ]
        for key in nestedKeys {
            results.append(contentsOf: mediaAssetCandidates(from: dictionary[key], baseURL: baseURL, depth: depth + 1))
        }

        return results
    }

    private static func mediaAssetScore(type: String?, url: String, dictionary: [String: Any]) -> Int {
        let marker = "\(type ?? "") \(url)".lowercased()
        var score = 0

        if marker.contains("original") || marker.contains("source") || marker.contains("full") {
            score += 1_000
        } else if marker.contains("large") || marker.contains("file") || marker.contains("highres") {
            score += 800
        } else if marker.contains("sample") {
            score += 500
        } else if marker.contains("preview") || marker.contains("thumb") || marker.contains("180x180") {
            score -= 400
        }

        if marker.contains("/original/") || marker.contains("/data/") {
            score += 200
        }
        if marker.contains("/sample/") {
            score += 50
        }
        if marker.contains("/preview/") || marker.contains("/thumbnail/") || marker.contains("/360x360/") || marker.contains("/180x180/") {
            score -= 150
        }

        let width = intValue(dictionary["width"]) ?? intValue(dictionary["image_width"]) ?? 0
        let height = intValue(dictionary["height"]) ?? intValue(dictionary["image_height"]) ?? 0
        if width > 0 && height > 0 {
            score += min(width * height / 10_000, 300)
        }

        return score
    }

    private static func htmlMediaURL(fromHTML html: String, pageURL: URL) -> URL? {
        htmlMediaCandidates(fromHTML: html)
            .compactMap { candidate -> (score: Int, url: URL)? in
                let raw = htmlDecoded(candidate.raw)
                guard let url = absoluteURL(raw, baseURL: pageURL),
                      isHTMLMediaURL(url, raw: raw) else {
                    return nil
                }
                return (htmlMediaScore(raw: raw, context: candidate.context), url)
            }
            .max { lhs, rhs in lhs.score < rhs.score }?
            .url
    }

    private static func htmlMediaCandidates(fromHTML html: String) -> [(raw: String, context: String)] {
        var results: [(raw: String, context: String)] = []
        let anchorTags = regexSnippets(#"<a\b[^>]*>.*?</a>"#, in: html)
        for tag in anchorTags {
            for href in attributeValues(named: ["href"], in: tag) {
                results.append((raw: href, context: tag))
            }
        }

        let mediaTags = regexSnippets(#"<(?:img|source|video)\b[^>]*>"#, in: html)
        let mediaAttributes = [
            "src",
            "data-src",
            "data-file-url",
            "data-large-file-url",
            "data-original",
            "data-url",
            "data-full",
            "data-original-url"
        ]
        for tag in mediaTags {
            for value in attributeValues(named: mediaAttributes, in: tag) {
                results.append((raw: value, context: tag))
            }
        }

        let richTags = regexSnippets(#"<[^>]+>"#, in: html)
        let richAttributes = [
            "data-file-url",
            "data-large-file-url",
            "data-original",
            "data-original-url",
            "data-source",
            "data-url"
        ]
        for tag in richTags where tag.lowercased().contains("data-") {
            for value in attributeValues(named: richAttributes, in: tag) {
                results.append((raw: value, context: tag))
            }
        }
        return results
    }

    private static func htmlMediaScore(raw: String, context: String) -> Int {
        let marker = "\(context) \(raw)".lowercased()
        var score = 0
        if marker.contains("post-option-view-original") || marker.contains("view-original") || marker.contains("view original") {
            score += 1_200
        }
        if marker.contains("/data/original/") || marker.contains("/original/") {
            score += 900
        }
        if marker.contains("original") || marker.contains("source") || marker.contains("full") {
            score += 700
        }
        if marker.contains("download") || marker.contains("large") || marker.contains("file") {
            score += 350
        }
        if marker.contains("sample") {
            score += 100
        }
        if marker.contains("preview") || marker.contains("thumb") || marker.contains("360x360") || marker.contains("180x180") {
            score -= 500
        }
        if hasRecognizedMediaExtension(raw) {
            score += 100
        }
        return score
    }

    private static func isHTMLMediaURL(_ url: URL, raw: String) -> Bool {
        if hasRecognizedMediaExtension(url.absoluteString) || hasRecognizedMediaExtension(raw) {
            return true
        }
        let marker = "\(url.absoluteString) \(raw)".lowercased()
        return marker.contains("/data/original/") || marker.contains("/original/")
    }

    private static func htmlPostDictionary(fromHTML html: String, pageURL: URL, remote: URL) -> [String: Any] {
        var post: [String: Any] = [
            "id": htmlPostID(fromHTML: html, pageURL: pageURL) ?? "1",
            "file_url": remote.absoluteString
        ]

        if let dimensions = htmlDimensions(fromHTML: html) {
            post["width"] = dimensions.width
            post["height"] = dimensions.height
            post["image_width"] = dimensions.width
            post["image_height"] = dimensions.height
        }
        if let source = htmlSourceValue(fromHTML: html, pageURL: pageURL) {
            post["source"] = source
        }
        for (key, value) in htmlTagMetadataGroups(fromHTML: html, pageURL: pageURL) {
            post[key] = value
        }
        return post
    }

    private static func htmlTagMetadataGroups(fromHTML html: String, pageURL: URL) -> [String: String] {
        var artists: [String] = []
        var copyrights: [String] = []
        var characters: [String] = []
        var generals: [String] = []

        for tag in regexSnippets(#"<a\b[^>]*>.*?</a>"#, in: html) {
            guard let href = attributeValues(named: ["href"], in: tag).first,
                  let queryTag = htmlTagQueryValue(from: href, pageURL: pageURL) else {
                continue
            }
            let lower = queryTag.lowercased()
            let label = textContent(ofHTML: tag)
            let fallbackName: String
            if let separator = queryTag.firstIndex(of: ":") {
                fallbackName = String(queryTag[queryTag.index(after: separator)...])
            } else {
                fallbackName = queryTag
            }
            let value = (label.isEmpty ? fallbackName : label)
                .replacingOccurrences(of: "_", with: " ")
                .trimmed
            guard !value.isEmpty else { continue }

            if lower.hasPrefix("artist:") {
                appendUnique(value, to: &artists)
            } else if lower.hasPrefix("copyright:") {
                appendUnique(value, to: &copyrights)
            } else if lower.hasPrefix("character:") {
                appendUnique(value, to: &characters)
            } else if !lower.contains(":") {
                appendUnique(value, to: &generals)
            }
        }

        return DownloadMetadata.clean([
            "tag_string_artist": artists.joined(separator: " "),
            "tag_string_copyright": copyrights.joined(separator: " "),
            "tag_string_character": characters.joined(separator: " "),
            "tag_string_general": generals.joined(separator: " ")
        ])
    }

    private static func htmlTagQueryValue(from href: String, pageURL: URL) -> String? {
        guard let url = absoluteURL(htmlDecoded(href), baseURL: pageURL) else { return nil }
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name.lowercased() == "tags" }?
            .value?
            .trimmed
    }

    private static func htmlSourceValue(fromHTML html: String, pageURL: URL) -> String? {
        for tag in regexSnippets(#"<[^>]*(?:post-info-source|source)[^>]*>.*?</[^>]+>"#, in: html) {
            guard tag.lowercased().contains("post-info-source"),
                  let href = attributeValues(named: ["href"], in: tag).first,
                  let url = absoluteURL(htmlDecoded(href), baseURL: pageURL),
                  !isHTMLMediaURL(url, raw: href) else {
                continue
            }
            return url.absoluteString
        }
        return nil
    }

    private static func htmlDimensions(fromHTML html: String) -> (width: Int, height: Int)? {
        for snippet in regexSnippets(#"<[^>]*(?:post-info-size|image-resize-link)[^>]*>.*?</[^>]+>"#, in: html) {
            if let dimensions = firstDimensions(in: snippet) {
                return dimensions
            }
        }
        return firstDimensions(in: html)
    }

    private static func firstDimensions(in text: String) -> (width: Int, height: Int)? {
        guard let regex = try? NSRegularExpression(pattern: #"([0-9]{2,6})\s*[x×]\s*([0-9]{2,6})"#, options: .caseInsensitive) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 2,
              let widthRange = Range(match.range(at: 1), in: text),
              let heightRange = Range(match.range(at: 2), in: text),
              let width = Int(text[widthRange]),
              let height = Int(text[heightRange]) else {
            return nil
        }
        return (width, height)
    }

    private static func htmlPostID(fromHTML html: String, pageURL: URL) -> String? {
        if let id = danbooruPostID(in: pageURL) {
            return id
        }
        return firstCapture(#"\bdata-id\s*=\s*(?:"([0-9]+)"|'([0-9]+)'|([0-9]+))"#, in: html) ??
            firstCapture(#"\bpost_id\b\s*[:=]\s*(?:"([0-9]+)"|'([0-9]+)'|([0-9]+))"#, in: html)
    }

    private static func danbooruPostID(in url: URL) -> String? {
        firstCapture(#"/posts/([0-9]+)"#, in: url.path)
    }

    private static func attributeValues(named names: [String], in tag: String) -> [String] {
        var values: [String] = []
        for name in names {
            let escapedName = NSRegularExpression.escapedPattern(for: name)
            let pattern = "\\b\(escapedName)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s>]+))"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            let range = NSRange(tag.startIndex..<tag.endIndex, in: tag)
            for match in regex.matches(in: tag, range: range) {
                for group in 1..<match.numberOfRanges {
                    let captureRange = match.range(at: group)
                    guard captureRange.location != NSNotFound,
                          let valueRange = Range(captureRange, in: tag) else {
                        continue
                    }
                    values.append(htmlDecoded(String(tag[valueRange])))
                    break
                }
            }
        }
        return values
    }

    private static func regexSnippets(_ pattern: String, in text: String, options: NSRegularExpression.Options = [.caseInsensitive, .dotMatchesLineSeparators]) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let snippetRange = Range(match.range, in: text) else { return nil }
            return String(text[snippetRange])
        }
    }

    private static func firstCapture(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        for group in 1..<match.numberOfRanges {
            let captureRange = match.range(at: group)
            guard captureRange.location != NSNotFound,
                  let valueRange = Range(captureRange, in: text) else {
                continue
            }
            return String(text[valueRange])
        }
        return nil
    }

    private static func textContent(ofHTML html: String) -> String {
        let withoutTags: String
        if let regex = try? NSRegularExpression(pattern: #"<[^>]+>"#) {
            let range = NSRange(html.startIndex..<html.endIndex, in: html)
            withoutTags = regex.stringByReplacingMatches(in: html, range: range, withTemplate: " ")
        } else {
            withoutTags = html
        }
        return htmlDecoded(withoutTags)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmed
    }

    private static func htmlDecoded(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&#38;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#34;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }

    private static func hasRecognizedMediaExtension(_ raw: String) -> Bool {
        let lower = raw.lowercased()
        for ext in ["jpg", "jpeg", "png", "gif", "webp", "mp4", "webm"] {
            if lower.range(of: #"\.\#(ext)(?:[?#]|$)"#, options: .regularExpression) != nil {
                return true
            }
        }
        return false
    }

    private static func appendUnique(_ value: String, to values: inout [String]) {
        if !values.contains(value) {
            values.append(value)
        }
    }

    private static func postMetadata(from post: [String: Any]) -> [String: String] {
        let id = stringValue(post["id"]) ?? stringValue(post["post_id"])
        let artist = stringValue(post["tag_string_artist"]) ??
            stringValue(post["artist"]) ??
            stringValue(post["artist_name"])
        let copyright = stringValue(post["tag_string_copyright"]) ??
            stringValue(post["copyright"])
        let character = stringValue(post["tag_string_character"]) ??
            stringValue(post["character"])
        let general = stringValue(post["tag_string_general"]) ??
            stringValue(post["tags"]) ??
            stringValue(post["tag_string"])
        let date = normalizedDate(
            stringValue(post["created_at"]) ??
                stringValue(post["updated_at"]) ??
                stringValue(post["createdAt"]) ??
                stringValue(post["date"])
        ) ?? ""
        return DownloadMetadata.clean([
            "id": id ?? "",
            "post_id": id ?? "",
            "gallery_id": id ?? "",
            "media_id": id ?? "",
            "artist": artist ?? "",
            "author": artist ?? "",
            "creator": artist ?? "",
            "uploader": artist ?? "",
            "channel": artist ?? "",
            "series": copyright ?? "",
            "parody": copyright ?? "",
            "character": character ?? "",
            "tag": general ?? "",
            "tags": general ?? "",
            "category": general ?? "",
            "date": date,
            "published_date": date,
            "rating": stringValue(post["rating"]) ?? "",
            "score": stringValue(post["score"]) ?? "",
            "source": stringValue(post["source"]) ?? ""
        ])
    }

    private static func assetMetadata(from post: [String: Any], provider: BooruProvider, remote: URL, referer: String, index: Int) -> [String: String] {
        let id = stringValue(post["id"]) ?? stringValue(post["post_id"]) ?? String(index)
        let base = postMetadata(from: post)
        let type = isVideo(remote) ? "video" : "image"
        let format = mediaExtension(for: remote)
        let width = intValue(post["image_width"]) ?? intValue(post["width"]) ?? intValue(post["file_width"]) ?? 0
        let height = intValue(post["image_height"]) ?? intValue(post["height"]) ?? intValue(post["file_height"]) ?? 0
        var metadata = base
        metadata.merge(DownloadMetadata.clean([
            "series": base["series"] ?? provider.rawValue,
            "category": base["category"] ?? provider.rawValue,
            "site": provider.rawValue,
            "provider": provider.rawValue,
            "type": type,
            "media_type": type,
            "post_id": id,
            "gallery_id": id,
            "media_id": id,
            "id": id,
            "page": String(index),
            "position": String(index),
            "width": width > 0 ? String(width) : "",
            "height": height > 0 ? String(height) : "",
            "resolution": width > 0 && height > 0 ? "\(width)x\(height)" : "",
            "format": format,
            "media_format": format,
            "image_url": type == "image" ? remote.absoluteString : "",
            "video_url": type == "video" ? remote.absoluteString : "",
            "media_url": remote.absoluteString,
            "source_url": remote.absoluteString,
            "page_url": referer,
            "title": id
        ])) { _, new in new }
        return DownloadMetadata.clean(metadata)
    }

    private static func mediaExtension(for url: URL) -> String {
        let absolute = url.absoluteString.lowercased()
        for ext in ["jpg", "jpeg", "png", "gif", "webp", "mp4", "webm"] {
            if absolute.range(of: #"\.\#(ext)(?:[?#]|$)"#, options: .regularExpression) != nil {
                return ext == "jpeg" ? "jpg" : ext
            }
        }
        let ext = url.pathExtension.lowercased()
        return ext == "jpeg" ? "jpg" : (ext.isEmpty ? "jpg" : ext)
    }

    private static func isImage(_ url: URL) -> Bool {
        ["jpg", "jpeg", "png", "gif", "webp"].contains(mediaExtension(for: url))
    }

    private static func isVideo(_ url: URL) -> Bool {
        ["mp4", "webm"].contains(mediaExtension(for: url))
    }

    private static func mediaType(imageCount: Int, videoCount: Int) -> String {
        if imageCount > 0, videoCount > 0 {
            return "mixed"
        }
        if videoCount > 0 {
            return "video"
        }
        return "image"
    }

    private static func normalizedDate(_ raw: String?) -> String? {
        guard let value = raw?.trimmed, !value.isEmpty else { return nil }
        if let match = value.range(of: #"[0-9]{4}-[0-9]{2}-[0-9]{2}"#, options: .regularExpression) {
            return String(value[match])
        }
        if value.range(of: #"^[0-9]{8}$"#, options: .regularExpression) != nil {
            let monthStart = value.index(value.startIndex, offsetBy: 4)
            let dayStart = value.index(value.startIndex, offsetBy: 6)
            return "\(value.prefix(4))-\(value[monthStart..<dayStart])-\(value[dayStart..<value.endIndex])"
        }
        return nil
    }

    private static func absoluteURL(_ raw: String, baseURL: URL) -> URL? {
        let trimmed = raw.trimmed
        if trimmed.hasPrefix("//") {
            return URL(string: "\(baseURL.scheme ?? "https"):\(trimmed)")
        }
        return URL(string: trimmed, relativeTo: baseURL)?.absoluteURL
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        if let int = value as? Int { return String(int) }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) }
        return nil
    }
}

private extension URL {
    func replacingPath(_ path: String, queryItems: [URLQueryItem]) throws -> URL {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
            throw NativeDownloadError.invalidURL(absoluteString)
        }
        components.path = path
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else {
            throw NativeDownloadError.invalidURL(absoluteString)
        }
        return url
    }
}
