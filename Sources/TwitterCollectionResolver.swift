import Foundation

enum TwitterCollectionResolverError: LocalizedError {
    case authenticationRequired

    var errorDescription: String? {
        "Twitter/X login is required. Sign in through the built-in browser to resume the download."
    }
}

enum TwitterCollectionKind: String, Equatable {
    case media
    case likes

    var titleSuffix: String {
        self == .likes ? " - Likes" : ""
    }
}

struct TwitterCollectionRequest: Equatable {
    var username: String
    var kind: TwitterCollectionKind
    var sourceURL: URL
    var profileURL: URL
}

struct TwitterCollectionEntry: Equatable {
    var tweetID: String
    var ownerUsername: String
    var pageURL: URL
    var thumbnailURL: URL?
}

struct TwitterCollectionPage: Equatable {
    var displayName: String
    var profileImageURL: URL?
    var entries: [TwitterCollectionEntry]
    var nextURL: URL?
    var requiresLogin: Bool
}

final class TwitterCollectionResolver {
    static let defaultCollectionAssetLimit = 2_000

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
        let assetRange = rangeExpression.trimmed
        let assetLimit = try Self.collectionAssetLimit(for: assetRange)

        let cookieHeader = await CookieStore.shared.cookieHeader(for: request.sourceURL)
        let hasSignedInSession = Self.hasSignedInSession(cookieHeader: cookieHeader)
        if request.kind == .likes, !hasSignedInSession {
            throw TwitterCollectionResolverError.authenticationRequired
        }

        var graphQLAuthenticationBoundary = false
        do {
            return try await resolveGraphQLCollection(
                request: request,
                headers: headers,
                assetRange: assetRange,
                assetLimit: assetLimit
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            graphQLAuthenticationBoundary = !hasSignedInSession && Self.isAuthenticationBoundary(error)
            // X changes operation hashes regularly; retain the static/WebKit compatibility path.
        }

        var displayName = ""
        var profileImageURL: URL?
        var entries: [TwitterCollectionEntry] = []
        var seenTweetIDs = Set<String>()
        var visitedPages = Set<String>()
        var currentURL: URL? = request.sourceURL
        var sawLoginPage = false
        var collectionPageCount = 0
        let tweetResolver = TwitterResolver()
        var resolved: [(entry: TwitterCollectionEntry, download: ResolvedDownload)] = []
        var failures: [Error] = []
        var resolvedAssetCount = 0

        while resolvedAssetCount < assetLimit {
            try Task.checkCancellation()
            guard let pageURL = currentURL else { break }
            let identity = URLIdentity.normalize(pageURL.absoluteString)
            guard visitedPages.insert(identity).inserted else { break }

            let html: String
            do {
                html = try await HTTPClient.shared.string(
                    from: pageURL,
                    referer: headers.referer ?? request.profileURL.absoluteString,
                    userAgent: headers.userAgent
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if graphQLAuthenticationBoundary {
                    throw TwitterCollectionResolverError.authenticationRequired
                }
                throw error
            }
            collectionPageCount += 1
            let page = Self.collectionPage(fromHTML: html, request: request, pageURL: pageURL)
            if displayName.isEmpty, !page.displayName.isEmpty { displayName = page.displayName }
            if profileImageURL == nil { profileImageURL = page.profileImageURL }
            sawLoginPage = sawLoginPage || page.requiresLogin
            try await resolveNewEntries(
                page.entries,
                headers: headers,
                assetLimit: assetLimit,
                tweetResolver: tweetResolver,
                entries: &entries,
                seenTweetIDs: &seenTweetIDs,
                resolved: &resolved,
                failures: &failures,
                resolvedAssetCount: &resolvedAssetCount
            )
            currentURL = page.nextURL
        }

        if resolvedAssetCount < assetLimit,
           !sawLoginPage,
           Self.shouldUseBrowserRenderer(for: request.sourceURL) {
            do {
                let rendered = try await TwitterCollectionWebRenderer.render(
                    url: request.sourceURL,
                    referer: headers.referer ?? request.profileURL.absoluteString,
                    userAgent: headers.userAgent,
                    cookieHeader: cookieHeader,
                    itemLimit: Self.browserStatusLinkLimit(
                        discoveredEntryCount: entries.count,
                        resolvedAssetCount: resolvedAssetCount,
                        assetLimit: assetLimit
                    )
                )
                let page = Self.collectionPage(
                    fromHTML: rendered.html,
                    request: request,
                    pageURL: rendered.finalURL,
                    additionalLinks: rendered.statusLinks
                )
                if !page.displayName.isEmpty { displayName = page.displayName }
                if profileImageURL == nil { profileImageURL = page.profileImageURL }
                sawLoginPage = sawLoginPage || page.requiresLogin ||
                    rendered.finalURL.path.lowercased().contains("/i/flow/login")
                try await resolveNewEntries(
                    page.entries,
                    headers: headers,
                    assetLimit: assetLimit,
                    tweetResolver: tweetResolver,
                    entries: &entries,
                    seenTweetIDs: &seenTweetIDs,
                    resolved: &resolved,
                    failures: &failures,
                    resolvedAssetCount: &resolvedAssetCount
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Static links remain useful when WebKit is unavailable or X blocks rendering.
            }
        }

        guard !entries.isEmpty else {
            if sawLoginPage || graphQLAuthenticationBoundary {
                throw TwitterCollectionResolverError.authenticationRequired
            }
            throw NativeDownloadError.unsupported(
                "No Twitter/X profile media was exposed. The profile may require signed-in cookies or may not contain public media."
            )
        }

        guard !resolved.isEmpty else {
            throw failures.first ?? NativeDownloadError.noFiles
        }

        var download = Self.combinedDownload(
            request: request,
            displayName: displayName,
            profileImageURL: profileImageURL,
            posts: resolved,
            assetLimit: assetLimit
        )
        download.metadata["discovered_item_count"] = String(entries.count)
        download.metadata["resolved_item_count"] = String(resolved.count)
        download.metadata["discovered_asset_count"] = String(resolvedAssetCount)
        download.metadata["collection_pages"] = String(collectionPageCount)
        download.metadata["collection_asset_limit"] = assetLimit == Int.max ? "unbounded" : String(assetLimit)
        if !assetRange.isEmpty { download.metadata["requested_range"] = assetRange }
        if !failures.isEmpty { download.metadata["skipped_count"] = String(failures.count) }
        return download
    }

    private func resolveNewEntries(
        _ candidates: [TwitterCollectionEntry],
        headers: HTTPRequestOptions,
        assetLimit: Int,
        tweetResolver: TwitterResolver,
        entries: inout [TwitterCollectionEntry],
        seenTweetIDs: inout Set<String>,
        resolved: inout [(entry: TwitterCollectionEntry, download: ResolvedDownload)],
        failures: inout [Error],
        resolvedAssetCount: inout Int
    ) async throws {
        for entry in candidates {
            try Task.checkCancellation()
            guard resolvedAssetCount < assetLimit,
                  seenTweetIDs.insert(entry.tweetID).inserted else {
                continue
            }
            entries.append(entry)
            do {
                let download = try await tweetResolver.resolve(
                    entry.pageURL,
                    headers: headers,
                    preferGraphQL: false
                )
                resolved.append((entry, download))
                resolvedAssetCount += download.assets.count
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                failures.append(error)
            }
        }
    }

    private func resolveGraphQLCollection(
        request: TwitterCollectionRequest,
        headers: HTTPRequestOptions,
        assetRange: String,
        assetLimit: Int
    ) async throws -> ResolvedDownload {
        let api = TwitterGraphQLAPI(sourceURL: request.sourceURL, options: headers)
        let user = try await api.userByScreenName(request.username)
        let displayName = TwitterGraphQLAPI.displayName(in: user) ?? request.username
        let profileImageURL = TwitterGraphQLAPI.profileImageURL(in: user)
        var entries: [TwitterCollectionEntry] = []
        var seenTweetIDs = Set<String>()
        var seenCursors = Set<String>()
        var cursor: String?
        var pages = 0
        var resolved: [(entry: TwitterCollectionEntry, download: ResolvedDownload)] = []
        var failures: [Error] = []
        var resolvedAssetCount = 0

        while resolvedAssetCount < assetLimit {
            try Task.checkCancellation()
            let page = try await api.timelinePage(user: user, kind: request.kind, cursor: cursor)
            pages += 1

            for tweet in page.tweets {
                try Task.checkCancellation()
                guard resolvedAssetCount < assetLimit,
                      let tweetID = TwitterGraphQLAPI.tweetID(in: tweet),
                      seenTweetIDs.insert(tweetID).inserted else {
                    continue
                }

                let owner = TwitterGraphQLAPI.ownerUsername(in: tweet) ?? request.username
                var components = URLComponents()
                components.scheme = "https"
                components.host = request.sourceURL.host
                components.path = "/\(owner)/status/\(tweetID)"
                guard let pageURL = components.url else { continue }
                let payload = TwitterGraphQLAPI.mediaPayload(from: tweet)
                let thumbnailURL = TwitterResolver.mediaAssets(in: payload, sourceURL: pageURL)
                    .first(where: { $0.type == "photo" })?.remoteURL
                let entry = TwitterCollectionEntry(
                    tweetID: tweetID,
                    ownerUsername: owner,
                    pageURL: pageURL,
                    thumbnailURL: thumbnailURL
                )
                entries.append(entry)

                do {
                    var download = try TwitterResolver.resolvedDownload(
                        fromJSONObject: payload,
                        tweetID: tweetID,
                        sourceURL: pageURL
                    )
                    download.metadata["resolver_api"] = request.kind == .likes ? "Likes" : "UserMedia"
                    resolved.append((entry, download))
                    resolvedAssetCount += download.assets.count
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    failures.append(error)
                }
            }

            guard let nextCursor = page.bottomCursor,
                  !nextCursor.isEmpty,
                  seenCursors.insert(nextCursor).inserted else {
                break
            }
            cursor = nextCursor
        }

        guard !entries.isEmpty else {
            throw NativeDownloadError.unsupported(
                "Twitter/X GraphQL collection did not expose any posts."
            )
        }
        guard !resolved.isEmpty else {
            throw failures.first ?? NativeDownloadError.noFiles
        }

        var download = Self.combinedDownload(
            request: request,
            displayName: displayName,
            profileImageURL: profileImageURL,
            posts: resolved,
            assetLimit: assetLimit
        )
        download.metadata["resolver_api"] = request.kind == .likes ? "Likes" : "UserMedia"
        download.metadata["discovered_item_count"] = String(entries.count)
        download.metadata["resolved_item_count"] = String(resolved.count)
        download.metadata["discovered_asset_count"] = String(resolvedAssetCount)
        download.metadata["collection_pages"] = String(pages)
        download.metadata["collection_asset_limit"] = assetLimit == Int.max ? "unbounded" : String(assetLimit)
        if !assetRange.isEmpty { download.metadata["requested_range"] = assetRange }
        if !failures.isEmpty { download.metadata["skipped_count"] = String(failures.count) }
        return download
    }

    static func request(from url: URL) -> TwitterCollectionRequest? {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host?.lowercased(),
              isSupportedHost(host),
              TwitterResolver.tweetID(from: url) == nil,
              TwitterResolver.twitterSpaceID(from: url) == nil,
              TwitterResolver.twitterBroadcastID(from: url) == nil else {
            return nil
        }

        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        guard let rawUsername = parts.first else { return nil }
        let username = rawUsername.trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        guard isValidUsername(username), !reservedPaths.contains(username.lowercased()) else {
            return nil
        }

        let kind: TwitterCollectionKind
        if parts.count == 1 {
            kind = .media
        } else if parts.count == 2,
                  let parsed = TwitterCollectionKind(rawValue: parts[1].lowercased()) {
            kind = parsed
        } else {
            return nil
        }

        var profileComponents = URLComponents()
        profileComponents.scheme = "https"
        profileComponents.host = canonicalHost(from: host)
        profileComponents.path = "/\(username)"
        guard let profileURL = profileComponents.url else { return nil }

        var sourceComponents = profileComponents
        sourceComponents.path = "/\(username)/\(kind.rawValue)"
        guard let sourceURL = sourceComponents.url else { return nil }
        return TwitterCollectionRequest(
            username: username,
            kind: kind,
            sourceURL: sourceURL,
            profileURL: profileURL
        )
    }

    static func collectionPage(
        fromHTML html: String,
        request: TwitterCollectionRequest,
        pageURL: URL? = nil,
        additionalLinks: [String] = []
    ) -> TwitterCollectionPage {
        let baseURL = pageURL ?? request.sourceURL
        let normalizedHTML = normalizeEscapes(decodeHTML(html))
        var entries: [TwitterCollectionEntry] = []
        var seen = Set<String>()

        for anchor in captures(
            pattern: #"<a\b[^>]*\bhref\s*=\s*(?:\"[^\"]*\"|'[^']*')[^>]*>.*?</a>"#,
            in: normalizedHTML,
            group: 0
        ) {
            guard let href = attributeValue("href", in: anchor),
                  let entry = entry(
                    from: href,
                    thumbnailURL: firstImageURL(in: anchor, baseURL: baseURL),
                    request: request,
                    baseURL: baseURL
                  ),
                  seen.insert(entry.tweetID).inserted else {
                continue
            }
            entries.append(entry)
        }

        for href in captures(
            pattern: #"\bhref\s*=\s*(?:\"([^\"]+)\"|'([^']+)')"#,
            in: normalizedHTML,
            groups: [1, 2]
        ) + additionalLinks {
            if let entry = entry(
                from: href,
                thumbnailURL: nil,
                request: request,
                baseURL: baseURL
            ), seen.insert(entry.tweetID).inserted {
                entries.append(entry)
            }
        }

        return TwitterCollectionPage(
            displayName: profileDisplayName(fromHTML: normalizedHTML, request: request),
            profileImageURL: metaContent(named: "og:image", in: normalizedHTML)
                .flatMap { absoluteURL($0, baseURL: baseURL) },
            entries: entries,
            nextURL: nextPageURL(fromHTML: normalizedHTML, baseURL: baseURL),
            requiresLogin: requiresLogin(normalizedHTML)
        )
    }

    static func combinedDownload(
        request: TwitterCollectionRequest,
        displayName: String,
        profileImageURL: URL?,
        posts: [(entry: TwitterCollectionEntry, download: ResolvedDownload)],
        assetLimit: Int = Int.max
    ) -> ResolvedDownload {
        let cleanDisplayName = cleanText(displayName, fallback: request.username)
        let baseTitle = "\(cleanDisplayName) (@\(request.username))\(request.kind.titleSuffix)"
            .sanitizedFilename(maxLength: 160)
        var assets: [ResolvedAsset] = []

        postLoop: for (postIndex, post) in posts.enumerated() {
            for (assetIndex, original) in post.download.assets.enumerated() {
                if assets.count >= assetLimit { break postLoop }
                var asset = original
                let prefix = String(format: "%04d-%@", postIndex + 1, post.entry.tweetID)
                asset.filename = "\(prefix)-\(original.filename)".sanitizedFilename(maxLength: 180)
                for (key, value) in collectionMetadata(
                    request: request,
                    entry: post.entry,
                    index: postIndex,
                    assetIndex: assetIndex
                ) {
                    asset.metadata[key] = value
                }
                assets.append(asset)
            }
        }

        let firstThumbnail = profileImageURL?.absoluteString ??
            posts.lazy.compactMap { $0.entry.thumbnailURL?.absoluteString }.first ??
            posts.lazy.compactMap { $0.download.metadata["thumbnail"] }.first ?? ""
        return ResolvedDownload(
            title: baseTitle,
            folderName: baseTitle.sanitizedFilename(maxLength: 120),
            assets: assets,
            metadata: DownloadMetadata.clean([
                "site": "Twitter",
                "title": baseTitle,
                "series": cleanDisplayName,
                "artist": cleanDisplayName,
                "author": cleanDisplayName,
                "creator": cleanDisplayName,
                "uploader": request.username,
                "channel": request.username,
                "username": request.username,
                "category": "media",
                "type": "collection",
                "media_type": "mixed",
                "collection": "true",
                "collection_kind": request.kind.rawValue,
                "profile_username": request.username,
                "collection_id": request.username,
                "gallery_id": request.username,
                "item_count": String(posts.count),
                "media_count": String(assets.count),
                "thumbnail": firstThumbnail,
                "url": request.sourceURL.absoluteString,
                "source_url": request.sourceURL.absoluteString,
                "page_url": request.sourceURL.absoluteString,
                "profile_url": request.profileURL.absoluteString,
                "collection_url": request.sourceURL.absoluteString
            ])
        )
    }

    static func collectionAssetLimit(for expression: String) throws -> Int {
        let segments = try assetRangeSegments(from: expression.trimmed)
        guard !segments.isEmpty else { return defaultCollectionAssetLimit }
        if segments.contains(where: { $0.end == nil }) { return Int.max }
        return max(1, segments.compactMap(\.end).max() ?? defaultCollectionAssetLimit)
    }

    static func browserStatusLinkLimit(
        discoveredEntryCount: Int,
        resolvedAssetCount: Int,
        assetLimit: Int
    ) -> Int {
        guard assetLimit != Int.max else { return Int.max }
        let remainingAssets = max(0, assetLimit - resolvedAssetCount)
        return max(1, discoveredEntryCount + remainingAssets)
    }

    private struct AssetRangeSegment {
        var start: Int?
        var end: Int?
    }

    private static func assetRangeSegments(from expression: String) throws -> [AssetRangeSegment] {
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
            if let split = assetRangeSplit(piece) {
                let start = try positiveAssetRangeBound(split.0)
                let end = try positiveAssetRangeBound(split.1)
                guard start != nil || end != nil else {
                    throw NativeDownloadError.unsupported("Invalid range.")
                }
                if let start, let end, start > end {
                    throw NativeDownloadError.unsupported("Invalid range.")
                }
                return AssetRangeSegment(start: start, end: end)
            }
            guard let position = Int(piece), position > 0 else {
                throw NativeDownloadError.unsupported("Invalid range.")
            }
            return AssetRangeSegment(start: position, end: position)
        }
    }

    private static func assetRangeSplit(_ value: String) -> (String, String)? {
        for separator in ["...", "..", "~", "-"] {
            if let range = value.range(of: separator) {
                return (String(value[..<range.lowerBound]), String(value[range.upperBound...]))
            }
        }
        return nil
    }

    private static func positiveAssetRangeBound(_ value: String) throws -> Int? {
        guard !value.isEmpty else { return nil }
        guard let bound = Int(value), bound > 0 else {
            throw NativeDownloadError.unsupported("Invalid range.")
        }
        return bound
    }

    private static func entry(
        from rawLink: String,
        thumbnailURL: URL?,
        request: TwitterCollectionRequest,
        baseURL: URL
    ) -> TwitterCollectionEntry? {
        guard let rawURL = absoluteURL(rawLink, baseURL: baseURL),
              let tweetID = TwitterResolver.tweetID(from: rawURL) else {
            return nil
        }
        let parts = rawURL.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        let owner: String
        if parts.count >= 3,
           parts[0].lowercased() == "i",
           parts[1].lowercased() == "web",
           parts[2].lowercased() == "status" {
            owner = request.username
        } else if let statusIndex = parts.firstIndex(where: { $0.lowercased() == "status" }), statusIndex > 0 {
            owner = parts[statusIndex - 1]
        } else {
            owner = request.username
        }
        guard isValidUsername(owner) else { return nil }

        var components = URLComponents()
        components.scheme = "https"
        components.host = request.sourceURL.host
        components.path = "/\(owner)/status/\(tweetID)"
        guard let pageURL = components.url else { return nil }
        return TwitterCollectionEntry(
            tweetID: tweetID,
            ownerUsername: owner,
            pageURL: pageURL,
            thumbnailURL: thumbnailURL
        )
    }

    private static func collectionMetadata(
        request: TwitterCollectionRequest,
        entry: TwitterCollectionEntry,
        index: Int,
        assetIndex: Int
    ) -> [String: String] {
        DownloadMetadata.clean([
            "collection": "true",
            "collection_kind": request.kind.rawValue,
            "collection_id": request.username,
            "collection_index": String(index + 1),
            "collection_item_id": entry.tweetID,
            "collection_url": request.sourceURL.absoluteString,
            "profile_username": request.username,
            "profile_url": request.profileURL.absoluteString,
            "tweet_id": entry.tweetID,
            "post_id": entry.tweetID,
            "owner_username": entry.ownerUsername,
            "page": String(index + 1),
            "position": String(index + 1),
            "asset_index": String(assetIndex + 1),
            "item_page_url": entry.pageURL.absoluteString,
            "item_thumbnail": entry.thumbnailURL?.absoluteString ?? ""
        ])
    }

    private static func firstImageURL(in html: String, baseURL: URL) -> URL? {
        for attribute in ["data-src", "src"] {
            if let raw = attributeValue(attribute, in: html),
               let url = absoluteURL(raw, baseURL: baseURL) {
                return url
            }
        }
        return nil
    }

    private static func nextPageURL(fromHTML html: String, baseURL: URL) -> URL? {
        for tag in captures(pattern: #"<a\b[^>]*>"#, in: html, group: 0) {
            let rel = attributeValue("rel", in: tag)?.lowercased() ?? ""
            let cssClass = attributeValue("class", in: tag)?.lowercased() ?? ""
            guard rel.split(separator: " ").contains("next") ||
                    cssClass.contains("next") ||
                    attributeValue("data-next-page", in: tag) != nil else {
                continue
            }
            if let raw = attributeValue("href", in: tag) ?? attributeValue("data-next-page", in: tag),
               let url = absoluteURL(raw, baseURL: baseURL),
               isSupportedHost(url.host?.lowercased() ?? "") {
                return url
            }
        }
        return nil
    }

    private static func profileDisplayName(
        fromHTML html: String,
        request: TwitterCollectionRequest
    ) -> String {
        for tag in ["h1", "h2"] {
            if let raw = captures(pattern: #"<\#(tag)\b[^>]*>(.*?)</\#(tag)>"#, in: html).first {
                let value = cleanText(raw, fallback: "")
                if !value.isEmpty { return value }
            }
        }
        for name in ["og:title", "twitter:title"] {
            if let raw = metaContent(named: name, in: html), !raw.trimmed.isEmpty {
                return cleanText(raw, fallback: request.username)
            }
        }
        if let raw = captures(pattern: #"<title\b[^>]*>(.*?)</title>"#, in: html).first {
            return cleanText(raw, fallback: request.username)
        }
        return request.username
    }

    private static func requiresLogin(_ html: String) -> Bool {
        let lower = html.lowercased()
        return lower.contains("<title>log in to x") ||
            lower.contains(">sign in to x<") ||
            lower.contains("loginform") && lower.contains("redirect_after_login") ||
            lower.contains("you must be logged in to view")
    }

    static func hasSignedInSession(cookieHeader: String?) -> Bool {
        guard let cookieHeader else { return false }
        var names = Set<String>()
        for field in cookieHeader.split(separator: ";") {
            let pair = field.split(separator: "=", maxSplits: 1).map {
                String($0).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if pair.count == 2, !pair[1].isEmpty {
                names.insert(pair[0].lowercased())
            }
        }
        return names.contains("auth_token") && names.contains("ct0")
    }

    private static func isAuthenticationBoundary(_ error: Error) -> Bool {
        if let nativeError = error as? NativeDownloadError,
           case NativeDownloadError.httpStatus(let status, _) = nativeError,
           status == 401 || status == 403 || status == 404 {
            return true
        }
        if let apiError = error as? TwitterGraphQLAPIError,
           case TwitterGraphQLAPIError.authenticationRequired = apiError {
            return true
        }
        let message = error.localizedDescription.lowercased()
        return message.contains("authentication") || message.contains("authorization") ||
            message.contains("log in") || message.contains("login required")
    }

    private static func shouldUseBrowserRenderer(for url: URL) -> Bool {
        guard ProcessInfo.processInfo.environment["HITOMI_NATIVE_TWITTER_DISABLE_WEB_RENDERER"] != "1",
              let host = url.host?.lowercased() else {
            return false
        }
        return !host.hasSuffix(".test")
    }

    private static func attributeValue(_ name: String, in tag: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        return captures(
            pattern: #"\b\#(escaped)\s*=\s*(?:\"([^\"]*)\"|'([^']*)'|([^\s>\"']+))"#,
            in: tag,
            groups: [1, 2, 3]
        ).first
    }

    private static func metaContent(named name: String, in html: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        for pattern in [
            #"<meta\b[^>]*(?:property|name)\s*=\s*[\"']\#(escaped)[\"'][^>]*content\s*=\s*[\"']([^\"']+)[\"'][^>]*>"#,
            #"<meta\b[^>]*content\s*=\s*[\"']([^\"']+)[\"'][^>]*(?:property|name)\s*=\s*[\"']\#(escaped)[\"'][^>]*>"#
        ] {
            if let value = captures(pattern: pattern, in: html).first {
                return decodeHTML(value).trimmed
            }
        }
        return nil
    }

    private static func captures(
        pattern: String,
        in text: String,
        group: Int = 1
    ) -> [String] {
        captures(pattern: pattern, in: text, groups: [group])
    }

    private static func captures(
        pattern: String,
        in text: String,
        groups: [Int]
    ) -> [String] {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            for group in groups where match.numberOfRanges > group {
                if let capture = Range(match.range(at: group), in: text) {
                    return String(text[capture])
                }
            }
            return nil
        }
    }

    private static func absoluteURL(_ raw: String, baseURL: URL) -> URL? {
        var value = normalizeEscapes(decodeHTML(raw)).trimmed
        value = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        guard !value.isEmpty, !value.lowercased().hasPrefix("javascript:") else { return nil }
        if value.hasPrefix("//") { value = "\(baseURL.scheme ?? "https"):\(value)" }
        return URL(string: value, relativeTo: baseURL)?.absoluteURL
    }

    private static func normalizeEscapes(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: #"\/"#, with: "/")
            .replacingOccurrences(of: #"\\/"#, with: "/")
            .replacingOccurrences(of: #"\u002F"#, with: "/", options: .caseInsensitive)
            .replacingOccurrences(of: #"\u003A"#, with: ":", options: .caseInsensitive)
            .replacingOccurrences(of: #"\u003F"#, with: "?", options: .caseInsensitive)
            .replacingOccurrences(of: #"\u0026"#, with: "&", options: .caseInsensitive)
            .replacingOccurrences(of: #"\u003D"#, with: "=", options: .caseInsensitive)
    }

    private static func cleanText(_ raw: String, fallback: String) -> String {
        var text = decodeHTML(
            raw.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        )
        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        .trimmed
        text = text.replacingOccurrences(
            of: #"(?i)\s*\(@?[A-Za-z0-9_]{1,15}\)\s*(?:/\s*(?:X|Twitter))?.*$"#,
            with: "",
            options: .regularExpression
        ).trimmed
        text = text.replacingOccurrences(
            of: #"(?i)\s*(?:/|\||-)\s*(?:X|Twitter).*$"#,
            with: "",
            options: .regularExpression
        ).trimmed
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
    }

    private static func canonicalHost(from host: String) -> String {
        if host.hasSuffix(".test") {
            return host.contains("twitter") ? "twitter.test" : "x.test"
        }
        return "x.com"
    }

    private static func isSupportedHost(_ host: String) -> Bool {
        [
            "twitter.com", "www.twitter.com", "mobile.twitter.com",
            "x.com", "www.x.com", "mobile.x.com",
            "twitter.co", "www.twitter.co", "mobile.twitter.co",
            "x.co", "www.x.co", "mobile.x.co",
            "twitter.test", "www.twitter.test", "mobile.twitter.test",
            "x.test", "www.x.test", "mobile.x.test"
        ].contains(host)
    }

    private static func isValidUsername(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z0-9_]{1,15}$"#, options: .regularExpression) != nil
    }

    private static let reservedPaths: Set<String> = [
        "about", "compose", "explore", "hashtag", "home", "i", "intent", "login",
        "logout", "messages", "notifications", "privacy", "search", "settings",
        "share", "signup", "tos"
    ]
}
