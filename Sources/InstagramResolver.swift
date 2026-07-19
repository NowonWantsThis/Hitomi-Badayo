import Foundation

struct InstagramMediaAsset {
    var remoteURL: URL
    var type: String
    var width: Int
    var height: Int
    var filenameExtension: String
    var mediaID: String
}

private struct InstagramTimelinePage {
    var posts: [[String: Any]]
    var count: Int
    var hasNextPage: Bool?
    var endCursor: String?
}

private struct InstagramProfileAPIContext {
    var profile: [String: Any]
    var wwwClaim: String
}

final class InstagramResolver {
    static let defaultProfileItemLimit = 2_000

    func canResolve(_ url: URL) -> Bool {
        Self.shortcode(from: url) != nil ||
            Self.highlightID(from: url) != nil ||
            Self.storyID(from: url) != nil ||
            Self.storyCollectionUsername(from: url) != nil ||
            Self.profileUsername(from: url) != nil
    }

    func resolve(
        _ url: URL,
        headers: HTTPRequestOptions = HTTPRequestOptions(),
        includeProfileStories: Bool = false,
        rangeExpression: String = ""
    ) async throws -> ResolvedDownload {
        if let username = Self.storyCollectionUsername(from: url),
           let pageURL = Self.canonicalStoryCollectionURL(for: url) {
            return try await resolveStoryCollection(
                username: username,
                pageURL: pageURL,
                headers: headers
            )
        }

        if let username = Self.profileUsername(from: url),
           let pageURL = Self.canonicalProfileURL(for: url) {
            return try await resolveProfile(
                username: username,
                pageURL: pageURL,
                headers: headers,
                includeStories: includeProfileStories,
                rangeExpression: rangeExpression
            )
        }

        if let highlightID = Self.highlightID(from: url) {
            let apiURL = Self.reelsMediaAPIURL(reelID: "highlight:\(highlightID)", sourceURL: url)
            let data = try await HTTPClient.shared.data(
                from: apiURL,
                referer: url.absoluteString,
                userAgent: headers.userAgent,
                additionalHeaders: await Self.apiHeaders(for: apiURL)
            )
            let object = try JSONSerialization.jsonObject(with: data)
            return try Self.resolvedStoryDownload(
                fromJSONObject: object,
                storyKey: "highlight-\(highlightID)",
                titleHint: "Highlight \(highlightID)",
                pageURL: url
            )
        }

        if let storyID = Self.storyID(from: url) {
            let pageURL = Self.canonicalStoryURL(for: url) ?? url
            let username = Self.storyUsername(from: pageURL) ?? ""
            if let html = try? await HTTPClient.shared.string(
                from: pageURL,
                referer: headers.referer,
                userAgent: headers.userAgent
            ),
               let resolved = try? Self.resolvedStoryDownload(
                   fromHTML: html,
                   storyKey: storyID,
                   titleHint: "Story \(storyID)",
                   pageURL: pageURL,
                   targetStoryID: storyID,
                   usernameHint: username
               ) {
                return resolved
            }

            let apiURL = Self.mediaInfoAPIURL(mediaID: storyID, sourceURL: pageURL)
            let data = try await HTTPClient.shared.data(
                from: apiURL,
                referer: pageURL.absoluteString,
                userAgent: headers.userAgent,
                additionalHeaders: await Self.apiHeaders(for: apiURL)
            )
            let object = try JSONSerialization.jsonObject(with: data)
            return try Self.resolvedStoryDownload(
                fromJSONObject: object,
                storyKey: storyID,
                titleHint: "Story \(storyID)",
                pageURL: pageURL,
                targetStoryID: storyID,
                usernameHint: username
            )
        }

        guard let shortcode = Self.shortcode(from: url) else {
            throw NativeDownloadError.invalidURL(url.absoluteString)
        }

        let html = try await HTTPClient.shared.string(from: url, referer: headers.referer, userAgent: headers.userAgent)
        if let resolved = try? Self.resolvedDownload(fromHTML: html, pageURL: url) {
            return resolved
        }

        guard let mediaID = Self.mediaID(fromHTML: html) else {
            throw NativeDownloadError.noFiles
        }
        let apiURL = Self.mediaInfoAPIURL(mediaID: mediaID, sourceURL: url)
        let data = try await HTTPClient.shared.data(
            from: apiURL,
            referer: url.absoluteString,
            userAgent: headers.userAgent,
            additionalHeaders: await Self.apiHeaders(for: apiURL)
        )
        let object = try JSONSerialization.jsonObject(with: data)
        return try Self.resolvedDownload(fromJSONObject: object, shortcode: shortcode, pageURL: url, pageHTML: html)
    }

    static func shortcode(from url: URL) -> String? {
        guard let host = url.host?.lowercased(),
              isSupportedHost(host),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }

        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        guard parts.count >= 2 else { return nil }
        let marker = parts[0].lowercased()
        guard ["p", "reel", "tv"].contains(marker),
              isValidShortcode(parts[1]) else {
            return nil
        }
        return parts[1]
    }

    static func canonicalURL(for url: URL) -> URL? {
        guard let shortcode = shortcode(from: url) else { return nil }
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        guard let marker = parts.first?.lowercased(),
              ["p", "reel", "tv"].contains(marker) else {
            return nil
        }
        var components = URLComponents()
        components.scheme = url.scheme ?? "https"
        components.host = url.host?.lowercased().hasSuffix(".test") == true ? "www.instagram.test" : "www.instagram.com"
        components.path = "/\(marker)/\(shortcode)/"
        return components.url
    }

    static func canonicalInputURL(for url: URL) -> URL? {
        canonicalURL(for: url) ??
            canonicalStoryURL(for: url) ??
            canonicalStoryCollectionURL(for: url) ??
            canonicalProfileURL(for: url)
    }

    static func storyCollectionUsername(from url: URL) -> String? {
        guard let host = url.host?.lowercased(),
              isSupportedHost(host),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        guard parts.count == 2,
              parts[0].lowercased() == "stories",
              parts[1].lowercased() != "highlights",
              isValidProfileUsername(parts[1]) else {
            return nil
        }
        return parts[1]
    }

    static func canonicalStoryCollectionURL(for url: URL) -> URL? {
        guard let username = storyCollectionUsername(from: url) else { return nil }
        var components = URLComponents()
        components.scheme = url.scheme ?? "https"
        components.host = url.host?.lowercased().hasSuffix(".test") == true
            ? "www.instagram.test"
            : "www.instagram.com"
        components.path = "/stories/\(username)/"
        return components.url
    }

    static func profileUsername(from url: URL) -> String? {
        guard let host = url.host?.lowercased(),
              isSupportedProfileHost(host),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        guard parts.count == 1,
              isValidProfileUsername(parts[0]),
              !isReservedProfilePath(parts[0]) else {
            return nil
        }
        return parts[0]
    }

    static func canonicalProfileURL(for url: URL) -> URL? {
        guard let username = profileUsername(from: url) else { return nil }
        return profileURL(username: username, sourceURL: url)
    }

    static func profileURL(username: String, sourceURL: URL) -> URL? {
        guard isValidProfileUsername(username),
              let host = sourceURL.host?.lowercased(),
              isSupportedHost(host) else {
            return nil
        }
        var components = URLComponents()
        components.scheme = sourceURL.scheme ?? "https"
        components.host = host.hasSuffix(".test") ? "www.instagram.test" : "www.instagram.com"
        components.path = "/\(username)/"
        return components.url
    }

    static func highlightID(from url: URL) -> String? {
        guard let host = url.host?.lowercased(),
              isSupportedHost(host),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        guard parts.count >= 3,
              parts[0].lowercased() == "stories",
              parts[1].lowercased() == "highlights",
              isValidHighlightID(parts[2]) else {
            return nil
        }
        return parts[2]
    }

    static func storyID(from url: URL) -> String? {
        guard let host = url.host?.lowercased(),
              isSupportedHost(host),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        guard parts.count >= 3,
              parts[0].lowercased() == "stories" else {
            return nil
        }
        if parts[1].lowercased() == "highlights" {
            return isValidHighlightID(parts[2]) ? parts[2] : nil
        }
        guard isValidStoryUsername(parts[1]) else { return nil }
        return isValidStoryID(parts[2]) ? parts[2] : nil
    }

    static func storyUsername(from url: URL) -> String? {
        guard storyID(from: url) != nil else { return nil }
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        guard parts.count >= 3,
              parts[0].lowercased() == "stories",
              parts[1].lowercased() != "highlights",
              isValidStoryUsername(parts[1]) else {
            return nil
        }
        return parts[1]
    }

    static func canonicalStoryURL(for url: URL) -> URL? {
        guard storyID(from: url) != nil else { return nil }
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        var components = URLComponents()
        components.scheme = url.scheme ?? "https"
        components.host = url.host?.lowercased().hasSuffix(".test") == true ? "www.instagram.test" : "www.instagram.com"
        if parts[1].lowercased() == "highlights" {
            components.path = "/stories/highlights/\(parts[2])/"
        } else {
            components.path = "/stories/\(parts[1])/\(parts[2])/"
        }
        return components.url
    }

    static func mediaInfoAPIURL(mediaID: String, sourceURL: URL) -> URL {
        var components = URLComponents()
        components.scheme = sourceURL.scheme ?? "https"
        components.host = sourceURL.host?.lowercased().hasSuffix(".test") == true ? "www.instagram.test" : "www.instagram.com"
        components.path = "/api/v1/media/\(mediaID)/info/"
        return components.url!
    }

    static func reelsMediaAPIURL(reelID: String, sourceURL: URL) -> URL {
        var components = URLComponents()
        components.scheme = sourceURL.scheme ?? "https"
        components.host = sourceURL.host?.lowercased().hasSuffix(".test") == true ? "i.instagram.test" : "i.instagram.com"
        components.path = "/api/v1/feed/reels_media/"
        let encoded = reelID
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)?
            .replacingOccurrences(of: ":", with: "%3A") ?? reelID
        components.percentEncodedQuery = "reel_ids=\(encoded)"
        return components.url!
    }

    static func webProfileInfoAPIURL(username: String, sourceURL: URL) -> URL {
        var components = URLComponents()
        components.scheme = sourceURL.scheme ?? "https"
        components.host = sourceURL.host?.lowercased().hasSuffix(".test") == true ? "www.instagram.test" : "www.instagram.com"
        components.path = "/api/v1/users/web_profile_info/"
        components.queryItems = [URLQueryItem(name: "username", value: username)]
        return components.url!
    }

    static func userFeedAPIURL(userID: String, maxID: String? = nil, sourceURL: URL) -> URL {
        var components = URLComponents()
        components.scheme = sourceURL.scheme ?? "https"
        components.host = sourceURL.host?.lowercased().hasSuffix(".test") == true ? "www.instagram.test" : "www.instagram.com"
        components.path = "/api/v1/feed/user/\(userID)/"
        var queryItems = [URLQueryItem(name: "count", value: "30")]
        if let maxID = maxID?.trimmed, !maxID.isEmpty {
            queryItems.append(URLQueryItem(name: "max_id", value: maxID))
        }
        components.queryItems = queryItems
        return components.url!
    }

    static func profileGraphQLURL(userID: String, after: String? = nil, sourceURL: URL) throws -> URL {
        var variables: [String: Any] = ["id": userID, "first": 12]
        if let after = after?.trimmed, !after.isEmpty {
            variables["after"] = after
        }
        let data = try JSONSerialization.data(withJSONObject: variables, options: [.sortedKeys])
        guard let variablesJSON = String(data: data, encoding: .utf8) else {
            throw NativeDownloadError.invalidGalleryData
        }

        var components = URLComponents()
        components.scheme = sourceURL.scheme ?? "https"
        components.host = sourceURL.host?.lowercased().hasSuffix(".test") == true ? "www.instagram.test" : "www.instagram.com"
        components.path = "/graphql/query/"
        components.queryItems = [
            URLQueryItem(name: "query_hash", value: "69cba40317214236af40e7efa697781d"),
            URLQueryItem(name: "variables", value: variablesJSON)
        ]
        guard let url = components.url else {
            throw NativeDownloadError.invalidURL(sourceURL.absoluteString)
        }
        return url
    }

    private struct ProfileRangeSegment {
        var start: Int?
        var end: Int?
    }

    static func profileItemLimit(for expression: String) throws -> Int {
        let segments = try profileRangeSegments(from: expression)
        guard !segments.isEmpty else { return defaultProfileItemLimit }
        if segments.contains(where: { $0.end == nil }) { return Int.max }
        return max(1, segments.compactMap(\.end).max() ?? defaultProfileItemLimit)
    }

    private static func profileRangeSegments(from expression: String) throws -> [ProfileRangeSegment] {
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
            if let split = profileRangeSplit(piece) {
                let start = try positiveProfileRangeBound(split.0)
                let end = try positiveProfileRangeBound(split.1)
                guard start != nil || end != nil else {
                    throw NativeDownloadError.unsupported("Invalid range.")
                }
                if let start, let end, start > end {
                    throw NativeDownloadError.unsupported("Invalid range.")
                }
                return ProfileRangeSegment(start: start, end: end)
            }
            guard let item = Int(piece), item > 0 else {
                throw NativeDownloadError.unsupported("Invalid range.")
            }
            return ProfileRangeSegment(start: item, end: item)
        }
    }

    private static func profileRangeSplit(_ value: String) -> (String, String)? {
        for separator in ["...", "..", "~", "-"] {
            if let range = value.range(of: separator) {
                return (String(value[..<range.lowerBound]), String(value[range.upperBound...]))
            }
        }
        return nil
    }

    private static func positiveProfileRangeBound(_ value: String) throws -> Int? {
        guard !value.isEmpty else { return nil }
        guard let bound = Int(value), bound > 0 else {
            throw NativeDownloadError.unsupported("Invalid range.")
        }
        return bound
    }

    private func resolveProfile(
        username: String,
        pageURL: URL,
        headers: HTTPRequestOptions,
        includeStories: Bool,
        rangeExpression: String
    ) async throws -> ResolvedDownload {
        let profileContext = try await fetchProfile(username: username, pageURL: pageURL, headers: headers)
        let profile = profileContext.profile
        let initialTimeline = Self.timelinePage(in: profile)
        let userID = Self.profileID(from: profile)
        let requestedItemLimit = try Self.profileItemLimit(for: rangeExpression)

        var stories: ResolvedDownload?
        var storyError: Error?
        if includeStories,
           let storiesURL = Self.storyCollectionURL(username: username, sourceURL: pageURL) {
            do {
                stories = try await resolveStoryCollection(
                    username: username,
                    pageURL: storiesURL,
                    profile: profile,
                    headers: headers
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                storyError = error
            }
        }

        let storyCount = stories?.assets.count ?? 0
        let profileItemLimit = requestedItemLimit == Int.max
            ? Int.max
            : max(0, requestedItemLimit - storyCount)
        var posts: [[String: Any]] = []
        var paginationError: Error?
        if !userID.isEmpty, profileItemLimit > 0 {
            do {
                posts = try await fetchProfilePosts(
                    userID: userID,
                    itemLimit: profileItemLimit,
                    pageURL: pageURL,
                    headers: headers,
                    initialWWWClaim: profileContext.wwwClaim
                )
            } catch {
                paginationError = error
            }
        }

        if posts.isEmpty, let initialTimeline,
           Self.isCompleteInitialTimeline(initialTimeline) {
            let fallbackPosts = Self.distinctProfilePosts(initialTimeline.posts)
            posts = profileItemLimit == Int.max
                ? fallbackPosts
                : Array(fallbackPosts.prefix(profileItemLimit))
        }

        if !posts.isEmpty {
            let resolvedProfile = try Self.resolvedProfileDownload(
                fromPosts: posts,
                profile: profile,
                username: username,
                pageURL: pageURL,
                declaredPostCount: initialTimeline?.count
            )
            var profileDownload = Self.profileDownload(resolvedProfile, limitedTo: profileItemLimit)
            if let stories {
                return Self.profileDownload(profileDownload, addingStories: stories)
            }
            if includeStories, let storyError {
                profileDownload.metadata["stories_requested"] = "true"
                profileDownload.metadata["stories_included"] = "false"
                profileDownload.metadata["stories_error"] = storyError.localizedDescription
            }
            return profileDownload
        }

        if let stories {
            return Self.profileDownloadFromStories(
                stories,
                declaredPostCount: initialTimeline?.count
            )
        }
        if let paginationError {
            throw paginationError
        }
        if let storyError {
            throw storyError
        }
        throw NativeDownloadError.noFiles
    }

    private func fetchProfile(
        username: String,
        pageURL: URL,
        headers: HTTPRequestOptions
    ) async throws -> InstagramProfileAPIContext {
        let html = try await HTTPClient.shared.string(
            from: pageURL,
            referer: headers.referer,
            userAgent: headers.userAgent
        )
        let embeddedProfile = Self.jsonObjects(fromHTML: html)
            .compactMap { Self.profileUser(in: $0, matching: username) }
            .first

        let apiURL = Self.webProfileInfoAPIURL(username: username, sourceURL: pageURL)
        var apiProfile: [String: Any]?
        var wwwClaim = "0"
        if let response = try? await Self.profileAPIObject(
            from: apiURL,
            sourceURL: pageURL,
            userAgent: headers.userAgent,
            wwwClaim: wwwClaim
        ) {
            apiProfile = Self.profileUser(in: response.object, matching: username)
            wwwClaim = response.wwwClaim
        }

        guard let profile = Self.mergedProfile(primary: apiProfile, fallback: embeddedProfile) else {
            throw NativeDownloadError.invalidGalleryData
        }
        return InstagramProfileAPIContext(profile: profile, wwwClaim: wwwClaim)
    }

    private func resolveStoryCollection(
        username: String,
        pageURL: URL,
        profile suppliedProfile: [String: Any]? = nil,
        headers: HTTPRequestOptions
    ) async throws -> ResolvedDownload {
        let profile: [String: Any]
        if let suppliedProfile {
            profile = suppliedProfile
        } else {
            guard let profilePageURL = Self.profileURL(username: username, sourceURL: pageURL) else {
                throw NativeDownloadError.invalidURL(pageURL.absoluteString)
            }
            do {
                profile = try await fetchProfile(
                    username: username,
                    pageURL: profilePageURL,
                    headers: headers
                ).profile
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw NativeDownloadError.unsupported(
                    "Instagram active stories require a readable profile session. Save Instagram cookies from the login browser and retry."
                )
            }
        }

        let profileID = Self.profileID(from: profile)
        guard !profileID.isEmpty else {
            throw NativeDownloadError.unsupported(
                "Instagram active stories require a readable profile ID. Save Instagram cookies from the login browser and retry."
            )
        }

        let apiURL = Self.reelsMediaAPIURL(reelID: profileID, sourceURL: pageURL)
        let data: Data
        do {
            data = try await HTTPClient.shared.data(
                from: apiURL,
                referer: pageURL.absoluteString,
                userAgent: headers.userAgent,
                additionalHeaders: await Self.apiHeaders(for: apiURL)
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw NativeDownloadError.unsupported(
                "Instagram active stories could not be read. Save Instagram cookies from the login browser and retry; the profile may also have no active stories."
            )
        }
        let object = try JSONSerialization.jsonObject(with: data)
        try Self.throwIfProfileAPIError(in: object)

        let stories: ResolvedDownload
        do {
            stories = try Self.resolvedStoryDownload(
                fromJSONObject: object,
                storyKey: "stories-\(username)",
                titleHint: "Stories",
                pageURL: pageURL,
                usernameHint: username
            )
        } catch {
            throw NativeDownloadError.unsupported(
                "No active Instagram stories were exposed. The profile may have no current stories or require signed-in cookies."
            )
        }
        return Self.storyCollectionDownload(
            stories,
            profile: profile,
            username: username,
            pageURL: pageURL
        )
    }

    static func storyCollectionURL(username: String, sourceURL: URL) -> URL? {
        guard isValidProfileUsername(username),
              let host = sourceURL.host?.lowercased(),
              isSupportedHost(host) else {
            return nil
        }
        var components = URLComponents()
        components.scheme = sourceURL.scheme ?? "https"
        components.host = host.hasSuffix(".test") ? "www.instagram.test" : "www.instagram.com"
        components.path = "/stories/\(username)/"
        return components.url
    }

    private func fetchProfilePosts(
        userID: String,
        itemLimit: Int,
        pageURL: URL,
        headers: HTTPRequestOptions,
        initialWWWClaim: String
    ) async throws -> [[String: Any]] {
        do {
            return try await fetchProfilePostsREST(
                userID: userID,
                itemLimit: itemLimit,
                pageURL: pageURL,
                headers: headers,
                initialWWWClaim: initialWWWClaim
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch let restError {
            do {
                return try await fetchProfilePostsGraphQL(
                    userID: userID,
                    itemLimit: itemLimit,
                    pageURL: pageURL,
                    headers: headers
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw restError
            }
        }
    }

    private func fetchProfilePostsREST(
        userID: String,
        itemLimit: Int,
        pageURL: URL,
        headers: HTTPRequestOptions,
        initialWWWClaim: String
    ) async throws -> [[String: Any]] {
        guard itemLimit > 0 else { return [] }
        var posts: [[String: Any]] = []
        var identities = Set<String>()
        var cursors = Set<String>()
        var cursor: String?
        var wwwClaim = initialWWWClaim

        while posts.count < itemLimit {
            let requestURL = Self.userFeedAPIURL(userID: userID, maxID: cursor, sourceURL: pageURL)
            let response = try await Self.profileAPIObject(
                from: requestURL,
                sourceURL: pageURL,
                userAgent: headers.userAgent,
                wwwClaim: wwwClaim
            )
            wwwClaim = response.wwwClaim
            guard let page = Self.restFeedPage(in: response.object) else {
                throw NativeDownloadError.invalidGalleryData
            }

            for post in page.posts {
                let identity = Self.profilePostIdentity(post)
                guard !identity.isEmpty, !identities.contains(identity) else { continue }
                identities.insert(identity)
                posts.append(post)
            }

            if posts.count >= itemLimit {
                return posts
            }
            guard page.hasNextPage == true else {
                return posts
            }
            guard let next = page.endCursor?.trimmed,
                  !next.isEmpty,
                  !cursors.contains(next) else {
                throw NativeDownloadError.invalidGalleryData
            }
            cursors.insert(next)
            cursor = next
        }
        return posts
    }

    private func fetchProfilePostsGraphQL(
        userID: String,
        itemLimit: Int,
        pageURL: URL,
        headers: HTTPRequestOptions
    ) async throws -> [[String: Any]] {
        guard itemLimit > 0 else { return [] }
        var posts: [[String: Any]] = []
        var identities = Set<String>()
        var cursors = Set<String>()
        var cursor: String?

        while posts.count < itemLimit {
            let requestURL = try Self.profileGraphQLURL(userID: userID, after: cursor, sourceURL: pageURL)
            let data = try await HTTPClient.shared.data(
                from: requestURL,
                referer: pageURL.absoluteString,
                userAgent: headers.userAgent,
                additionalHeaders: await Self.apiHeaders(for: requestURL)
            )
            let object = try JSONSerialization.jsonObject(with: data)
            try Self.throwIfProfileAPIError(in: object)
            guard let page = Self.timelinePage(in: object) else {
                throw NativeDownloadError.invalidGalleryData
            }

            for post in page.posts {
                let identity = Self.profilePostIdentity(post)
                guard !identity.isEmpty, !identities.contains(identity) else { continue }
                identities.insert(identity)
                posts.append(post)
            }

            if posts.count >= itemLimit {
                return posts
            }
            guard page.hasNextPage == true else {
                return posts
            }
            guard let next = page.endCursor?.trimmed,
                  !next.isEmpty,
                  !cursors.contains(next) else {
                throw NativeDownloadError.invalidGalleryData
            }
            cursors.insert(next)
            cursor = next
        }
        return posts
    }

    static func resolvedProfileDownload(
        fromPosts posts: [[String: Any]],
        profile: [String: Any],
        username: String,
        pageURL: URL,
        declaredPostCount: Int? = nil
    ) throws -> ResolvedDownload {
        let profileUsername = cleanTitle(stringValue(profile["username"]) ?? "")
        let cleanUsername = profileUsername.isEmpty ? cleanTitle(username) : profileUsername
        let displayName = cleanTitle(
            stringValue(profile["full_name"]) ??
                stringValue(profile["name"]) ??
                cleanUsername
        )
        let profileID = profileID(from: profile)
        var resolvedAssets: [ResolvedAsset] = []
        var seenURLs = Set<String>()
        var resolvedPostCount = 0
        var firstDate = ""

        for (postOffset, post) in distinctProfilePosts(posts).enumerated() {
            let postAssets = mediaAssets(from: post, pageURL: pageURL)
            guard !postAssets.isEmpty else { continue }
            let shortcode = mediaShortcode(from: post) ?? profilePostIdentity(post)
            guard !shortcode.isEmpty else { continue }
            let postID = mediaIdentifier(from: post).isEmpty ? shortcode : mediaIdentifier(from: post)
            let postPageURL = profilePostURL(shortcode: shortcode, sourceURL: pageURL)
            let postTitle = cleanCaption(captionText(in: post) ?? "Instagram \(shortcode)")
            let postDate = dateString(from: post["taken_at_timestamp"] ?? post["taken_at"] ?? post["device_timestamp"])
            if firstDate.isEmpty { firstDate = postDate }
            var addedPostAsset = false

            for (mediaOffset, asset) in postAssets.enumerated() {
                let normalized = URLIdentity.normalize(asset.remoteURL.absoluteString)
                guard !seenURLs.contains(normalized) else { continue }
                seenURLs.insert(normalized)
                let position = resolvedAssets.count + 1
                var assetMetadata = metadata(
                    for: asset,
                    title: postTitle,
                    username: cleanUsername,
                    displayName: displayName,
                    date: postDate,
                    shortcode: shortcode,
                    galleryID: cleanUsername,
                    index: position,
                    position: position,
                    pageURL: postPageURL,
                    containerType: postAssets.count > 1 ? "profile_sidecar" : "profile_post"
                )
                assetMetadata["post_id"] = postID
                assetMetadata["post_shortcode"] = shortcode
                assetMetadata["post_position"] = String(postOffset + 1)
                assetMetadata["post_media_position"] = String(mediaOffset + 1)
                assetMetadata["profile_id"] = profileID
                assetMetadata["profile_username"] = cleanUsername
                assetMetadata["profile_url"] = pageURL.absoluteString
                assetMetadata["uploader_id"] = profileID
                assetMetadata["channel_id"] = profileID

                resolvedAssets.append(ResolvedAsset(
                    remoteURL: asset.remoteURL,
                    filename: profileFilename(
                        for: asset,
                        shortcode: shortcode,
                        date: postDate,
                        position: position,
                        mediaPosition: mediaOffset + 1,
                        postMediaCount: postAssets.count
                    ),
                    metadata: DownloadMetadata.clean(assetMetadata),
                    referer: postPageURL.absoluteString
                ))
                addedPostAsset = true
            }
            if addedPostAsset { resolvedPostCount += 1 }
        }

        guard !resolvedAssets.isEmpty else {
            throw NativeDownloadError.noFiles
        }

        let titleBase = displayName.isEmpty ? cleanUsername : displayName
        let title = "\(titleBase) (insta_\(cleanUsername))".sanitizedFilename(maxLength: 120)
        let imageCount = resolvedAssets.filter { $0.metadata["media_type"] == "image" }.count
        let videoCount = resolvedAssets.filter { $0.metadata["media_type"] == "video" }.count
        let mediaType = imageCount > 0 && videoCount > 0 ? "mixed" : videoCount > 0 ? "video" : "image"
        let thumbnail = profileThumbnailURL(from: profile, pageURL: pageURL)?.absoluteString ?? ""
        let totalPostCount = max(declaredPostCount ?? 0, resolvedPostCount)
        let isPrivate = profile["is_private"] == nil ? "" : (boolValue(profile["is_private"]) ? "true" : "false")

        return ResolvedDownload(
            title: title,
            folderName: "Instagram \(title)".sanitizedFilename(maxLength: 120),
            assets: resolvedAssets,
            metadata: DownloadMetadata.clean([
                "site": "Instagram",
                "title": titleBase,
                "type": "profile",
                "media_type": mediaType,
                "package_mode": "files",
                "media_count": String(resolvedAssets.count),
                "image_count": imageCount > 0 ? String(imageCount) : "",
                "video_count": videoCount > 0 ? String(videoCount) : "",
                "post_count": String(resolvedPostCount),
                "profile_post_count": String(totalPostCount),
                "id": profileID.isEmpty ? cleanUsername : profileID,
                "profile_id": profileID,
                "gallery_id": cleanUsername,
                "series": cleanUsername,
                "user": cleanUsername,
                "username": cleanUsername,
                "profile_username": cleanUsername,
                "uploader_id": profileID,
                "channel_id": profileID,
                "full_name": displayName,
                "artist": displayName,
                "author": displayName,
                "creator": displayName,
                "uploader": cleanUsername,
                "channel": cleanUsername,
                "is_private": isPrivate,
                "thumbnail": thumbnail,
                "date": firstDate,
                "profile_url": pageURL.absoluteString,
                "url": pageURL.absoluteString,
                "source_url": pageURL.absoluteString,
                "page_url": pageURL.absoluteString
            ])
        )
    }

    static func profileDownload(
        _ profile: ResolvedDownload,
        limitedTo itemLimit: Int
    ) -> ResolvedDownload {
        guard itemLimit != Int.max, profile.assets.count > itemLimit else { return profile }
        let assets = Array(profile.assets.prefix(max(0, itemLimit)))
        let imageCount = assets.filter { $0.metadata["media_type"] == "image" }.count
        let videoCount = assets.filter { $0.metadata["media_type"] == "video" }.count
        let postCount = Set(assets.compactMap { $0.metadata["post_position"] }).count
        var metadata = profile.metadata
        metadata["media_count"] = String(assets.count)
        metadata["image_count"] = imageCount > 0 ? String(imageCount) : ""
        metadata["video_count"] = videoCount > 0 ? String(videoCount) : ""
        metadata["media_type"] = imageCount > 0 && videoCount > 0 ? "mixed" : videoCount > 0 ? "video" : imageCount > 0 ? "image" : ""
        metadata["post_count"] = String(postCount)
        return ResolvedDownload(
            title: profile.title,
            folderName: profile.folderName,
            assets: assets,
            packageMode: profile.packageMode,
            metadata: DownloadMetadata.clean(metadata)
        )
    }

    static func storyCollectionDownload(
        _ stories: ResolvedDownload,
        profile: [String: Any],
        username: String,
        pageURL: URL
    ) -> ResolvedDownload {
        let profileUsername = cleanTitle(stringValue(profile["username"]) ?? "")
        let cleanUsername = profileUsername.isEmpty ? cleanTitle(username) : profileUsername
        let displayName = cleanTitle(
            stringValue(profile["full_name"]) ??
                stringValue(profile["name"]) ??
                cleanUsername
        )
        let profileID = profileID(from: profile)
        let titleBase = displayName.isEmpty ? cleanUsername : displayName
        let title = "\(titleBase) (insta_\(cleanUsername))".sanitizedFilename(maxLength: 120)
        let assets = stories.assets.map { original -> ResolvedAsset in
            var asset = original
            asset.metadata["collection_kind"] = "active_stories"
            asset.metadata["profile_id"] = profileID
            asset.metadata["profile_username"] = cleanUsername
            asset.metadata["story_username"] = cleanUsername
            asset.metadata["profile_url"] = profileURL(username: cleanUsername, sourceURL: pageURL)?.absoluteString ?? ""
            asset.metadata["uploader_id"] = profileID
            asset.metadata["channel_id"] = profileID
            return asset
        }
        let imageCount = assets.filter { $0.metadata["media_type"] == "image" }.count
        let videoCount = assets.filter { $0.metadata["media_type"] == "video" }.count
        let mediaType = imageCount > 0 && videoCount > 0 ? "mixed" : videoCount > 0 ? "video" : "image"
        var metadata = stories.metadata
        metadata["title"] = titleBase
        metadata["type"] = "story_collection"
        metadata["collection_kind"] = "active_stories"
        metadata["media_type"] = mediaType
        metadata["story_count"] = String(assets.count)
        metadata["profile_id"] = profileID
        metadata["profile_username"] = cleanUsername
        metadata["story_username"] = cleanUsername
        metadata["username"] = cleanUsername
        metadata["user"] = cleanUsername
        metadata["uploader"] = cleanUsername
        metadata["channel"] = cleanUsername
        metadata["uploader_id"] = profileID
        metadata["channel_id"] = profileID
        metadata["full_name"] = displayName
        metadata["artist"] = displayName
        metadata["author"] = displayName
        metadata["creator"] = displayName
        metadata["profile_url"] = profileURL(username: cleanUsername, sourceURL: pageURL)?.absoluteString ?? ""
        metadata["url"] = pageURL.absoluteString
        metadata["source_url"] = pageURL.absoluteString
        metadata["page_url"] = pageURL.absoluteString
        return ResolvedDownload(
            title: title,
            folderName: "Instagram \(title)".sanitizedFilename(maxLength: 120),
            assets: assets,
            packageMode: stories.packageMode,
            metadata: DownloadMetadata.clean(metadata)
        )
    }

    static func profileDownload(
        _ profile: ResolvedDownload,
        addingStories stories: ResolvedDownload
    ) -> ResolvedDownload {
        let storyAssets = stories.assets.map { original -> ResolvedAsset in
            var asset = original
            asset.metadata["included_with_profile"] = "true"
            return asset
        }
        let assets = storyAssets + profile.assets
        let imageCount = assets.filter { $0.metadata["media_type"] == "image" }.count
        let videoCount = assets.filter { $0.metadata["media_type"] == "video" }.count
        var metadata = profile.metadata
        metadata["media_count"] = String(assets.count)
        metadata["image_count"] = imageCount > 0 ? String(imageCount) : ""
        metadata["video_count"] = videoCount > 0 ? String(videoCount) : ""
        metadata["media_type"] = imageCount > 0 && videoCount > 0 ? "mixed" : videoCount > 0 ? "video" : "image"
        metadata["story_count"] = String(storyAssets.count)
        metadata["stories_requested"] = "true"
        metadata["stories_included"] = "true"
        metadata["story_source_url"] = stories.metadata["source_url"] ?? ""
        return ResolvedDownload(
            title: profile.title,
            folderName: profile.folderName,
            assets: assets,
            packageMode: .files,
            metadata: DownloadMetadata.clean(metadata)
        )
    }

    static func profileDownloadFromStories(
        _ stories: ResolvedDownload,
        declaredPostCount: Int?
    ) -> ResolvedDownload {
        let storyAssets = stories.assets.map { original -> ResolvedAsset in
            var asset = original
            asset.metadata["included_with_profile"] = "true"
            return asset
        }
        var metadata = stories.metadata
        let storySourceURL = metadata["source_url"] ?? ""
        let profileSourceURL = metadata["profile_url"] ?? storySourceURL
        metadata.removeValue(forKey: "collection_kind")
        metadata["type"] = "profile"
        metadata["package_mode"] = "files"
        metadata["media_count"] = String(storyAssets.count)
        metadata["post_count"] = "0"
        metadata["profile_post_count"] = String(max(0, declaredPostCount ?? 0))
        metadata["story_count"] = String(storyAssets.count)
        metadata["stories_requested"] = "true"
        metadata["stories_included"] = "true"
        metadata["story_source_url"] = storySourceURL
        metadata["url"] = profileSourceURL
        metadata["source_url"] = profileSourceURL
        metadata["page_url"] = profileSourceURL
        return ResolvedDownload(
            title: stories.title,
            folderName: stories.folderName,
            assets: storyAssets,
            packageMode: .files,
            metadata: DownloadMetadata.clean(metadata)
        )
    }

    private static func profileUser(in value: Any, matching username: String) -> [String: Any]? {
        if let dict = value as? [String: Any] {
            let candidate = stringValue(dict["username"]) ?? stringValue(dict["user_name"])
            let hasProfileShape = timelinePage(in: dict) != nil ||
                dict["profile_pic_url"] != nil ||
                dict["profile_pic_url_hd"] != nil ||
                dict["biography"] != nil ||
                dict["is_private"] != nil ||
                dict["edge_followed_by"] != nil
            if let candidate,
               candidate.caseInsensitiveCompare(username) == .orderedSame,
               hasProfileShape {
                return dict
            }

            for key in ["data", "user", "graphql", "entry_data", "ProfilePage"] {
                if let child = dict[key],
                   let found = profileUser(in: child, matching: username) {
                    return found
                }
            }
            for child in dict.values {
                if let found = profileUser(in: child, matching: username) {
                    return found
                }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let found = profileUser(in: child, matching: username) {
                    return found
                }
            }
        }
        return nil
    }

    private static func mergedProfile(primary: [String: Any]?, fallback: [String: Any]?) -> [String: Any]? {
        guard var result = primary ?? fallback else { return nil }
        if let fallback {
            for (key, value) in fallback where result[key] == nil {
                result[key] = value
            }
        }
        return result
    }

    private static func timelinePage(in value: Any) -> InstagramTimelinePage? {
        if let dict = value as? [String: Any] {
            for key in [
                "edge_owner_to_timeline_media",
                "edge_felix_video_timeline",
                "timeline_media",
                "xdt_api__v1__feed__user_timeline_graphql_connection"
            ] {
                if let container = dict[key] as? [String: Any],
                   let page = timelinePage(fromContainer: container) {
                    return page
                }
            }
            for child in dict.values {
                if let page = timelinePage(in: child) {
                    return page
                }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let page = timelinePage(in: child) {
                    return page
                }
            }
        }
        return nil
    }

    private static func timelinePage(fromContainer container: [String: Any]) -> InstagramTimelinePage? {
        let rawItems = container["edges"] as? [Any] ?? container["items"] as? [Any] ?? []
        let posts = rawItems.compactMap { item -> [String: Any]? in
            guard let dict = item as? [String: Any] else { return nil }
            return dict["node"] as? [String: Any] ?? dict["media"] as? [String: Any] ?? dict
        }
        let pageInfo = container["page_info"] as? [String: Any] ??
            container["pageInfo"] as? [String: Any] ?? [:]
        let hasNextValue = pageInfo["has_next_page"] ?? pageInfo["hasNextPage"] ?? container["has_next_page"]
        let hasNext = hasNextValue == nil ? nil : boolValue(hasNextValue)
        let cursor = stringValue(pageInfo["end_cursor"]) ??
            stringValue(pageInfo["endCursor"]) ??
            stringValue(container["end_cursor"])
        let count = intValue(container["count"]) ?? intValue(container["total_count"]) ?? posts.count
        return InstagramTimelinePage(posts: posts, count: count, hasNextPage: hasNext, endCursor: cursor)
    }

    private static func restFeedPage(in value: Any) -> InstagramTimelinePage? {
        guard let container = value as? [String: Any],
              let rawItems = container["items"] as? [Any] else {
            return nil
        }
        let posts = rawItems.compactMap { item -> [String: Any]? in
            guard let dictionary = item as? [String: Any] else { return nil }
            return dictionary["media"] as? [String: Any] ?? dictionary
        }
        let hasNext = boolValue(container["more_available"])
        let cursor = stringValue(container["next_max_id"]) ?? stringValue(container["nextMaxId"])
        let count = intValue(container["num_results"]) ?? intValue(container["count"]) ?? posts.count
        return InstagramTimelinePage(posts: posts, count: count, hasNextPage: hasNext, endCursor: cursor)
    }

    private static func isCompleteInitialTimeline(_ page: InstagramTimelinePage) -> Bool {
        page.hasNextPage == false || (page.count > 0 && page.posts.count >= page.count)
    }

    private static func distinctProfilePosts(_ posts: [[String: Any]]) -> [[String: Any]] {
        var identities = Set<String>()
        return posts.filter { post in
            let identity = profilePostIdentity(post)
            guard !identity.isEmpty, !identities.contains(identity) else { return false }
            identities.insert(identity)
            return true
        }
    }

    private static func profilePostIdentity(_ post: [String: Any]) -> String {
        for key in ["shortcode", "code", "id", "pk", "media_id"] {
            if let value = stringValue(post[key])?.trimmed, !value.isEmpty {
                return value
            }
        }
        return ""
    }

    private static func profileID(from profile: [String: Any]) -> String {
        for key in ["id", "pk", "user_id"] {
            if let value = stringValue(profile[key])?.trimmed, !value.isEmpty {
                return value
            }
        }
        return ""
    }

    private static func profilePostURL(shortcode: String, sourceURL: URL) -> URL {
        var components = URLComponents()
        components.scheme = sourceURL.scheme ?? "https"
        components.host = sourceURL.host?.lowercased().hasSuffix(".test") == true ? "www.instagram.test" : "www.instagram.com"
        components.path = "/p/\(shortcode)/"
        return components.url ?? sourceURL
    }

    private static func profileThumbnailURL(from profile: [String: Any], pageURL: URL) -> URL? {
        for key in ["profile_pic_url_hd", "profile_pic_url", "profile_pic_url_info"] {
            if let raw = stringValue(profile[key]),
               let url = absoluteURL(raw, baseURL: pageURL) {
                return url
            }
            if let info = profile[key] as? [String: Any],
               let raw = stringValue(info["url"]),
               let url = absoluteURL(raw, baseURL: pageURL) {
                return url
            }
        }
        return nil
    }

    private static func profileFilename(
        for asset: InstagramMediaAsset,
        shortcode: String,
        date: String,
        position: Int,
        mediaPosition: Int,
        postMediaCount: Int
    ) -> String {
        let ext = asset.filenameExtension.trimmed.isEmpty ? (asset.type == "video" ? "mp4" : "jpg") : asset.filenameExtension
        let datePrefix = date.isEmpty ? "" : "\(date)-"
        let mediaSuffix = postMediaCount > 1 ? "-\(String(format: "%03d", mediaPosition))" : ""
        return "\(String(format: "%04d", position))-\(datePrefix)\(shortcode)\(mediaSuffix).\(ext)"
            .sanitizedFilename(maxLength: 180)
    }

    private static func throwIfProfileAPIError(in value: Any) throws {
        guard let dict = value as? [String: Any] else { return }
        if stringValue(dict["status"])?.lowercased() == "fail" {
            throw NativeDownloadError.unsupported(stringValue(dict["message"]) ?? "Instagram profile request failed.")
        }
        if let errors = dict["errors"] as? [Any], !errors.isEmpty {
            throw NativeDownloadError.unsupported("Instagram profile request failed.")
        }
    }

    static func mediaID(fromHTML html: String) -> String? {
        firstCapture(pattern: #"['"]media_id['"]\s*:\s*['"]([^'"]+)['"]"#, in: html)
    }

    static func resolvedDownload(fromHTML html: String, pageURL: URL) throws -> ResolvedDownload {
        guard let shortcode = shortcode(from: pageURL) else {
            throw NativeDownloadError.invalidURL(pageURL.absoluteString)
        }
        let objects = jsonObjects(fromHTML: html)
        for object in objects {
            if let media = mediaObject(in: object, shortcode: shortcode) {
                return try resolvedDownload(fromMediaObject: media, shortcode: shortcode, pageURL: pageURL, pageHTML: html)
            }
        }
        throw NativeDownloadError.noFiles
    }

    static func resolvedDownload(fromJSONObject object: Any, shortcode: String, pageURL: URL, pageHTML: String = "") throws -> ResolvedDownload {
        guard let media = mediaObject(in: object, shortcode: shortcode) else {
            throw NativeDownloadError.noFiles
        }
        return try resolvedDownload(fromMediaObject: media, shortcode: shortcode, pageURL: pageURL, pageHTML: pageHTML)
    }

    static func resolvedStoryDownload(
        fromHTML html: String,
        storyKey: String,
        titleHint: String,
        pageURL: URL,
        targetStoryID: String? = nil,
        usernameHint: String = ""
    ) throws -> ResolvedDownload {
        for object in jsonObjects(fromHTML: html) {
            if let resolved = try? resolvedStoryDownload(
                fromJSONObject: object,
                storyKey: storyKey,
                titleHint: titleHint,
                pageURL: pageURL,
                targetStoryID: targetStoryID,
                usernameHint: usernameHint
            ) {
                return resolved
            }
        }
        throw NativeDownloadError.noFiles
    }

    static func resolvedStoryDownload(
        fromJSONObject object: Any,
        storyKey: String,
        titleHint: String,
        pageURL: URL,
        targetStoryID: String? = nil,
        usernameHint: String = ""
    ) throws -> ResolvedDownload {
        let allItems = storyMediaItems(in: object)
        let items: [[String: Any]]
        if let targetStoryID = targetStoryID?.trimmed, !targetStoryID.isEmpty {
            items = allItems.filter { storyItem($0, matches: targetStoryID) }
        } else {
            items = allItems
        }
        var seen = Set<String>()
        let storyAssets: [(item: [String: Any], asset: InstagramMediaAsset)] = items.compactMap { item in
            guard let asset = mediaAsset(from: item, pageURL: pageURL) else { return nil }
            let normalized = URLIdentity.normalize(asset.remoteURL.absoluteString)
            guard !seen.contains(normalized) else { return nil }
            seen.insert(normalized)
            return (item, asset)
        }
        guard !storyAssets.isEmpty else {
            throw NativeDownloadError.noFiles
        }

        let info = storyInfo(
            from: storyAssets.map(\.item),
            titleHint: titleHint,
            storyKey: storyKey,
            usernameHint: usernameHint
        )
        let resolvedAssets = storyAssets.enumerated().map { offset, pair in
            let itemDate = dateString(from: pair.item["taken_at_timestamp"] ?? pair.item["taken_at"] ?? pair.item["device_timestamp"] ?? pair.item["imported_taken_at"])
            var assetMetadata = metadata(
                for: pair.asset,
                title: info.title,
                username: info.username,
                displayName: info.displayName,
                date: itemDate.isEmpty ? info.date : itemDate,
                shortcode: storyKey,
                galleryID: storyKey,
                index: offset + 1,
                position: offset + 1,
                pageURL: pageURL,
                containerType: "story"
            )
            if let targetStoryID = targetStoryID?.trimmed, !targetStoryID.isEmpty {
                assetMetadata["story_id"] = targetStoryID
            }
            if !usernameHint.trimmed.isEmpty {
                assetMetadata["story_username"] = usernameHint.trimmed
            }
            return ResolvedAsset(
                remoteURL: pair.asset.remoteURL,
                filename: storyFilename(for: pair.asset, item: pair.item, fallbackID: storyKey, index: offset + 1, total: storyAssets.count),
                metadata: assetMetadata,
                referer: pageURL.absoluteString
            )
        }
        let packageMode: DownloadPackageMode = storyAssets.count == 1 && storyAssets[0].asset.type == "video"
            ? .concatenate(outputFilename: resolvedAssets[0].filename)
            : .files
        let thumbnail = storyAssets.compactMap { bestImageURL(from: $0.item, pageURL: pageURL)?.url }.first
        let imageCount = storyAssets.filter { $0.asset.type == "image" }.count
        let videoCount = storyAssets.filter { $0.asset.type == "video" }.count

        return ResolvedDownload(
            title: info.displayTitle,
            folderName: "Instagram \(info.displayTitle)".sanitizedFilename(maxLength: 120),
            assets: resolvedAssets,
            packageMode: packageMode,
            metadata: DownloadMetadata.clean([
                "site": "Instagram",
                "title": info.title,
                "series": info.username,
                "artist": info.displayName,
                "author": info.displayName,
                "creator": info.displayName,
                "uploader": info.username,
                "channel": info.username,
                "user": info.username,
                "username": info.username,
                "id": storyKey,
                "story_id": targetStoryID ?? "",
                "story_username": usernameHint,
                "shortcode": storyKey,
                "media_id": storyKey,
                "gallery_id": storyKey,
                "category": storyAssets.contains(where: { $0.asset.type == "video" }) ? "video" : "image",
                "type": "story",
                "media_type": videoCount > 0 && imageCount > 0 ? "mixed" : videoCount > 0 ? "video" : "image",
                "format": storyAssets.count == 1 ? storyAssets[0].asset.filenameExtension : "",
                "media_count": String(storyAssets.count),
                "image_count": imageCount > 0 ? String(imageCount) : "",
                "video_count": videoCount > 0 ? String(videoCount) : "",
                "thumbnail": thumbnail?.absoluteString ?? "",
                "date": info.date,
                "url": pageURL.absoluteString,
                "source_url": pageURL.absoluteString,
                "page_url": pageURL.absoluteString
            ])
        )
    }

    static func mediaObject(in value: Any, shortcode: String) -> [String: Any]? {
        let candidates = mediaObjects(in: value, shortcode: shortcode)
        if let exact = candidates.first(where: { mediaShortcode(from: $0) == shortcode }) {
            return exact
        }
        return candidates.first
    }

    static func mediaAssets(from object: [String: Any], pageURL: URL) -> [InstagramMediaAsset] {
        let nodes = mediaNodes(from: object)
        var seen = Set<String>()
        return nodes.compactMap { node in
            guard let asset = mediaAsset(from: node, pageURL: pageURL) else { return nil }
            let normalized = URLIdentity.normalize(asset.remoteURL.absoluteString)
            guard !seen.contains(normalized) else { return nil }
            seen.insert(normalized)
            return asset
        }
    }

    private static func resolvedDownload(fromMediaObject object: [String: Any], shortcode: String, pageURL: URL, pageHTML: String) throws -> ResolvedDownload {
        let assets = mediaAssets(from: object, pageURL: pageURL)
        guard !assets.isEmpty else {
            throw NativeDownloadError.noFiles
        }

        let info = mediaInfo(from: object, shortcode: shortcode, pageHTML: pageHTML)
        let resolvedAssets = assets.enumerated().map { offset, asset in
            ResolvedAsset(
                remoteURL: asset.remoteURL,
                filename: filename(for: asset, title: info.title, shortcode: shortcode, index: offset + 1, total: assets.count),
                metadata: metadata(
                    for: asset,
                    title: info.title,
                    username: info.username,
                    displayName: info.displayName,
                    date: info.date,
                    shortcode: shortcode,
                    galleryID: shortcode,
                    index: offset + 1,
                    position: offset + 1,
                    pageURL: pageURL,
                    containerType: assets.count > 1 ? "sidecar" : asset.type
                ),
                referer: pageURL.absoluteString
            )
        }
        let packageMode: DownloadPackageMode = assets.count == 1 && assets[0].type == "video"
            ? .concatenate(outputFilename: resolvedAssets[0].filename)
            : .files
        let thumbnail = thumbnailURL(from: object, pageURL: pageURL)
        let imageCount = assets.filter { $0.type == "image" }.count
        let videoCount = assets.filter { $0.type == "video" }.count

        return ResolvedDownload(
            title: info.displayTitle,
            folderName: "Instagram \(info.displayTitle)".sanitizedFilename(maxLength: 120),
            assets: resolvedAssets,
            packageMode: packageMode,
            metadata: DownloadMetadata.clean([
                "site": "Instagram",
                "title": info.title,
                "series": info.username,
                "artist": info.displayName,
                "author": info.displayName,
                "creator": info.displayName,
                "uploader": info.username,
                "channel": info.username,
                "user": info.username,
                "username": info.username,
                "id": info.mediaID,
                "shortcode": shortcode,
                "media_id": info.mediaID,
                "gallery_id": shortcode,
                "category": assets.contains(where: { $0.type == "video" }) ? "video" : "image",
                "type": assets.count > 1 ? "sidecar" : assets[0].type,
                "media_type": videoCount > 0 && imageCount == 0 ? "video" : "image",
                "format": assets.count == 1 ? assets[0].filenameExtension : "",
                "media_count": String(assets.count),
                "image_count": imageCount > 0 ? String(imageCount) : "",
                "video_count": videoCount > 0 ? String(videoCount) : "",
                "thumbnail": thumbnail?.absoluteString ?? "",
                "date": info.date,
                "url": pageURL.absoluteString,
                "source_url": pageURL.absoluteString,
                "page_url": pageURL.absoluteString
            ])
        )
    }

    private static func profileAPIObject(
        from apiURL: URL,
        sourceURL: URL,
        userAgent: String?,
        wwwClaim: String
    ) async throws -> (object: Any, wwwClaim: String) {
        let (data, response) = try await HTTPClient.shared.dataResponse(
            from: apiURL,
            referer: apiRootReferer(for: sourceURL),
            userAgent: userAgent,
            additionalHeaders: await apiHeaders(for: apiURL, wwwClaim: wwwClaim)
        )
        let object = try JSONSerialization.jsonObject(with: data)
        try throwIfProfileAPIError(in: object)
        let updatedClaim = response.value(forHTTPHeaderField: "X-IG-Set-WWW-Claim")?.trimmed
        let effectiveClaim = updatedClaim?.isEmpty == false ? updatedClaim ?? wwwClaim : wwwClaim
        return (object, effectiveClaim)
    }

    private static func apiRootReferer(for sourceURL: URL) -> String {
        var components = URLComponents()
        components.scheme = sourceURL.scheme ?? "https"
        components.host = sourceURL.host?.lowercased().hasSuffix(".test") == true
            ? "www.instagram.test"
            : "www.instagram.com"
        components.path = "/"
        return components.url?.absoluteString ?? "https://www.instagram.com/"
    }

    static func apiHeaders(for apiURL: URL? = nil, wwwClaim: String = "0") async -> [String: String] {
        var headers = [
            "Accept": "*/*",
            "X-IG-App-ID": "936619743392459",
            "X-ASBD-ID": "129477",
            "X-IG-WWW-Claim": wwwClaim.trimmed.isEmpty ? "0" : wwwClaim,
            "X-Requested-With": "XMLHttpRequest",
            "Connection": "keep-alive",
            "Sec-Fetch-Dest": "empty",
            "Sec-Fetch-Mode": "cors",
            "Sec-Fetch-Site": "same-origin"
        ]
        if let apiURL,
           let csrf = await CookieStore.shared.cookieValue(named: "csrftoken", for: apiURL) {
            headers["X-CSRFToken"] = csrf
        }
        return headers
    }

    private static func metadata(
        for asset: InstagramMediaAsset,
        title: String,
        username: String,
        displayName: String,
        date: String,
        shortcode: String,
        galleryID: String,
        index: Int,
        position: Int,
        pageURL: URL,
        containerType: String
    ) -> [String: String] {
        let hasDimensions = asset.width > 0 && asset.height > 0
        let mediaID = asset.mediaID.isEmpty ? "\(galleryID)-\(index)" : asset.mediaID
        return DownloadMetadata.clean([
            "site": "Instagram",
            "title": title,
            "type": asset.type,
            "media_type": asset.type,
            "container_type": containerType,
            "category": asset.type,
            "id": mediaID,
            "shortcode": shortcode,
            "media_id": mediaID,
            "gallery_id": galleryID,
            "page": String(index),
            "position": String(position),
            "format": asset.filenameExtension,
            "media_format": asset.filenameExtension,
            "width": asset.width > 0 ? String(asset.width) : "",
            "height": asset.height > 0 ? String(asset.height) : "",
            "resolution": hasDimensions ? "\(asset.width)x\(asset.height)" : "",
            "artist": displayName,
            "author": displayName,
            "creator": displayName,
            "uploader": username,
            "channel": username,
            "user": username,
            "username": username,
            "date": date,
            "image_url": asset.type == "image" ? asset.remoteURL.absoluteString : "",
            "video_url": asset.type == "video" ? asset.remoteURL.absoluteString : "",
            "media_url": asset.remoteURL.absoluteString,
            "source_url": pageURL.absoluteString,
            "page_url": pageURL.absoluteString,
            "asset_concurrency_override": "2"
        ])
    }

    private static func mediaObjects(in value: Any, shortcode: String) -> [[String: Any]] {
        if let dict = value as? [String: Any] {
            var results: [[String: Any]] = []
            for key in ["shortcode_media", "xdt_shortcode_media", "media"] {
                if let child = dict[key] as? [String: Any],
                   isMediaObject(child, shortcode: shortcode) {
                    results.append(child)
                }
            }
            if let graphql = dict["graphql"] as? [String: Any],
               let child = graphql["shortcode_media"] as? [String: Any],
               isMediaObject(child, shortcode: shortcode) {
                results.append(child)
            }
            if let items = dict["items"] as? [[String: Any]] {
                results.append(contentsOf: items.filter { isMediaObject($0, shortcode: shortcode) })
            }
            if isMediaObject(dict, shortcode: shortcode) {
                results.append(dict)
            }
            for child in dict.values {
                results.append(contentsOf: mediaObjects(in: child, shortcode: shortcode))
            }
            return results
        }

        if let array = value as? [Any] {
            return array.flatMap { mediaObjects(in: $0, shortcode: shortcode) }
        }
        return []
    }

    private static func isMediaObject(_ object: [String: Any], shortcode: String) -> Bool {
        if let code = mediaShortcode(from: object), code == shortcode {
            return true
        }
        return object["edge_sidecar_to_children"] != nil ||
            object["carousel_media"] != nil ||
            object["display_url"] != nil ||
            object["video_url"] != nil ||
            object["video_versions"] != nil ||
            object["image_versions2"] != nil
    }

    private static func storyMediaItems(in value: Any) -> [[String: Any]] {
        if let dict = value as? [String: Any] {
            var results: [[String: Any]] = []
            if let reels = dict["reels_media"] as? [[String: Any]] {
                for reel in reels {
                    if let items = reel["items"] as? [[String: Any]] {
                        results.append(contentsOf: items.filter(isStoryMediaObject))
                    }
                }
            }
            if let reel = dict["reel"] as? [String: Any],
               let items = reel["items"] as? [[String: Any]] {
                results.append(contentsOf: items.filter(isStoryMediaObject))
            }
            if let media = dict["media"] as? [String: Any],
               let items = media["items"] as? [[String: Any]] {
                results.append(contentsOf: items.filter(isStoryMediaObject))
            }
            if let items = dict["items"] as? [[String: Any]] {
                results.append(contentsOf: items.filter(isStoryMediaObject))
            }
            if isStoryMediaObject(dict) {
                results.append(dict)
            }
            for child in dict.values {
                results.append(contentsOf: storyMediaItems(in: child))
            }
            return results
        }

        if let array = value as? [Any] {
            return array.flatMap { storyMediaItems(in: $0) }
        }
        return []
    }

    private static func storyItem(_ item: [String: Any], matches targetID: String) -> Bool {
        let targetBase = targetID.split(separator: "_", maxSplits: 1).first.map(String.init) ?? targetID
        for key in ["id", "pk", "media_id", "mediaId"] {
            guard let value = stringValue(item[key]), !value.isEmpty else { continue }
            let valueBase = value.split(separator: "_", maxSplits: 1).first.map(String.init) ?? value
            if value == targetID || valueBase == targetBase {
                return true
            }
        }
        return false
    }

    private static func isStoryMediaObject(_ object: [String: Any]) -> Bool {
        object["video_versions"] != nil ||
            object["image_versions2"] != nil ||
            object["image_versions"] != nil ||
            object["display_url"] != nil ||
            object["video_url"] != nil ||
            object["carousel_media"] != nil
    }

    private static func mediaNodes(from object: [String: Any]) -> [[String: Any]] {
        if let sidecar = object["edge_sidecar_to_children"] as? [String: Any],
           let edges = sidecar["edges"] as? [[String: Any]] {
            let nodes = edges.compactMap { edge in
                edge["node"] as? [String: Any]
            }
            if !nodes.isEmpty {
                return nodes
            }
        }
        if let carousel = object["carousel_media"] as? [[String: Any]], !carousel.isEmpty {
            return carousel
        }
        return [object]
    }

    private static func mediaAsset(from object: [String: Any], pageURL: URL) -> InstagramMediaAsset? {
        if isVideoObject(object),
           let video = bestVideoURL(from: object, pageURL: pageURL) {
            let ext = video.url.pathExtension.trimmed.isEmpty ? "mp4" : video.url.pathExtension
            return InstagramMediaAsset(
                remoteURL: video.url,
                type: "video",
                width: video.width,
                height: video.height,
                filenameExtension: ext.lowercased(),
                mediaID: mediaIdentifier(from: object)
            )
        }

        guard let image = bestImageURL(from: object, pageURL: pageURL) else {
            return nil
        }
        let ext = image.url.pathExtension.trimmed.isEmpty ? "jpg" : image.url.pathExtension
        return InstagramMediaAsset(
            remoteURL: image.url,
            type: "image",
            width: image.width,
            height: image.height,
            filenameExtension: ext.lowercased(),
            mediaID: mediaIdentifier(from: object)
        )
    }

    private static func mediaIdentifier(from object: [String: Any]) -> String {
        for key in ["id", "pk", "media_id", "code", "shortcode"] {
            if let value = stringValue(object[key]), !value.trimmed.isEmpty {
                return cleanTitle(value)
            }
        }
        return ""
    }

    private static func bestVideoURL(from object: [String: Any], pageURL: URL) -> (url: URL, width: Int, height: Int)? {
        var candidates: [(url: URL, width: Int, height: Int, score: Int)] = []
        if let raw = stringValue(object["video_url"]),
           let url = absoluteURL(raw, baseURL: pageURL) {
            candidates.append((url, intValue(object["dimensions_width"]) ?? 0, intValue(object["dimensions_height"]) ?? 0, 2_000_000))
        }
        if let versions = object["video_versions"] as? [[String: Any]] {
            for item in versions {
                guard let raw = stringValue(item["url"]),
                      let url = absoluteURL(raw, baseURL: pageURL) else {
                    continue
                }
                let width = intValue(item["width"]) ?? 0
                let height = intValue(item["height"]) ?? 0
                candidates.append((url, width, height, 1_000_000 + width * max(height, 1)))
            }
        }
        return candidates.max { lhs, rhs in lhs.score < rhs.score }.map { ($0.url, $0.width, $0.height) }
    }

    private static func bestImageURL(from object: [String: Any], pageURL: URL) -> (url: URL, width: Int, height: Int)? {
        var candidates: [(url: URL, width: Int, height: Int, score: Int)] = []
        for key in ["display_resources", "thumbnail_resources"] {
            if let resources = object[key] as? [[String: Any]] {
                for item in resources {
                    guard let raw = stringValue(item["src"]),
                          let url = absoluteURL(raw, baseURL: pageURL) else {
                        continue
                    }
                    let width = intValue(item["config_width"]) ?? intValue(item["width"]) ?? 0
                    let height = intValue(item["config_height"]) ?? intValue(item["height"]) ?? 0
                    candidates.append((url, width, height, 1_000_000 + width * max(height, 1)))
                }
            }
        }
        for key in ["image_versions2", "image_versions"] {
            if let parent = object[key] as? [String: Any],
               let items = parent["candidates"] as? [[String: Any]] {
                for item in items {
                    guard let raw = stringValue(item["url"]),
                          let url = absoluteURL(raw, baseURL: pageURL) else {
                        continue
                    }
                    let width = intValue(item["width"]) ?? 0
                    let height = intValue(item["height"]) ?? 0
                    candidates.append((url, width, height, 1_000_000 + width * max(height, 1)))
                }
            }
        }
        for key in ["display_url", "thumbnail_src", "url", "src"] {
            if let raw = stringValue(object[key]),
               let url = absoluteURL(raw, baseURL: pageURL) {
                candidates.append((url, 0, 0, key == "display_url" ? 900_000 : 100_000))
            }
        }
        return candidates.max { lhs, rhs in lhs.score < rhs.score }.map { ($0.url, $0.width, $0.height) }
    }

    private static func mediaInfo(from object: [String: Any], shortcode: String, pageHTML: String) -> (mediaID: String, title: String, displayTitle: String, username: String, displayName: String, date: String) {
        let owner = object["owner"] as? [String: Any] ??
            object["user"] as? [String: Any] ??
            object["author"] as? [String: Any]
        let username = cleanTitle(
            stringValue(owner?["username"]) ??
                stringValue(owner?["user_name"]) ??
                stringValue(owner?["pk"]) ??
                username(fromHTML: pageHTML) ??
                ""
        )
        let displayName = cleanTitle(
            stringValue(owner?["full_name"]) ??
                stringValue(owner?["name"]) ??
                username
        )
        let mediaID = stringValue(object["id"]) ??
            stringValue(object["pk"]) ??
            stringValue(object["media_id"]) ??
            mediaID(fromHTML: pageHTML) ??
            shortcode
        let title = cleanCaption(captionText(in: object) ?? titleFromHTML(pageHTML) ?? "Instagram \(shortcode)")
        let displayTitle = username.isEmpty ? title : "@\(username) - \(title)"
        let date = dateString(from: object["taken_at_timestamp"] ?? object["taken_at"] ?? object["device_timestamp"])
        return (mediaID, title, displayTitle.sanitizedFilename(maxLength: 120), username, displayName, date)
    }

    private static func captionText(in object: [String: Any]) -> String? {
        if let edge = object["edge_media_to_caption"] as? [String: Any],
           let edges = edge["edges"] as? [[String: Any]] {
            for item in edges {
                if let node = item["node"] as? [String: Any],
                   let text = stringValue(node["text"]) {
                    return text
                }
            }
        }
        if let caption = object["caption"] as? [String: Any],
           let text = stringValue(caption["text"]) {
            return text
        }
        if let caption = stringValue(object["caption"]) {
            return caption
        }
        return stringValue(object["accessibility_caption"]) ??
            stringValue(object["title"]) ??
            stringValue(object["description"])
    }

    private static func thumbnailURL(from object: [String: Any], pageURL: URL) -> URL? {
        if let raw = stringValue(object["display_url"]) ?? stringValue(object["thumbnail_src"]) {
            return absoluteURL(raw, baseURL: pageURL)
        }
        return mediaNodes(from: object).compactMap { node in
            bestImageURL(from: node, pageURL: pageURL)?.url
        }.first
    }

    private static func storyInfo(
        from items: [[String: Any]],
        titleHint: String,
        storyKey: String,
        usernameHint: String = ""
    ) -> (title: String, displayTitle: String, username: String, displayName: String, date: String) {
        let first = items.first ?? [:]
        let owner = first["user"] as? [String: Any] ??
            first["owner"] as? [String: Any] ??
            first["author"] as? [String: Any]
        let username = cleanTitle(
            stringValue(owner?["username"]) ??
                stringValue(owner?["user_name"]) ??
                stringValue(owner?["pk"]) ??
                usernameHint
        )
        let displayName = cleanTitle(
            stringValue(owner?["full_name"]) ??
                stringValue(owner?["name"]) ??
                username
        )
        let title = cleanCaption(captionText(in: first) ?? titleHint)
        let displayTitle = username.isEmpty ? title : "@\(username) - \(title)"
        let date = dateString(from: first["taken_at_timestamp"] ?? first["taken_at"] ?? first["device_timestamp"] ?? first["imported_taken_at"])
        return (title.isEmpty ? storyKey : title, displayTitle.sanitizedFilename(maxLength: 120), username, displayName, date)
    }

    private static func storyFilename(for asset: InstagramMediaAsset, item: [String: Any], fallbackID: String, index: Int, total: Int) -> String {
        let ext = asset.filenameExtension.trimmed.isEmpty ? (asset.type == "video" ? "mp4" : "jpg") : asset.filenameExtension
        let rawID = stringValue(item["id"]) ??
            stringValue(item["pk"]) ??
            stringValue(item["media_id"]) ??
            fallbackID
        let itemID = cleanTitle(rawID).isEmpty ? fallbackID : cleanTitle(rawID)
        let base = "stories_\(itemID)"
        if total == 1 {
            return "\(base).\(ext)".sanitizedFilename(maxLength: 180)
        }
        return "\(String(format: "%04d", index))-\(base).\(ext)".sanitizedFilename(maxLength: 180)
    }

    private static func filename(for asset: InstagramMediaAsset, title: String, shortcode: String, index: Int, total: Int) -> String {
        let ext = asset.filenameExtension.trimmed.isEmpty ? (asset.type == "video" ? "mp4" : "jpg") : asset.filenameExtension
        if total == 1 {
            return "\(title)-\(shortcode).\(ext)".sanitizedFilename(maxLength: 180)
        }
        return "\(title)-\(shortcode)-\(String(format: "%03d", index)).\(ext)".sanitizedFilename(maxLength: 180)
    }

    static func jsonObjects(fromHTML html: String) -> [Any] {
        var payloads: [String] = []
        payloads.append(contentsOf: [
            balancedValue(afterPattern: #"window\._sharedData\s*="#, in: html),
            balancedValue(afterPattern: #"window\.__additionalDataLoaded\s*\("#, in: html),
            balancedValue(afterPattern: #"window\.__initialData\s*="#, in: html),
            balancedValue(afterPattern: #"window\.__INITIAL_DATA__\s*="#, in: html)
        ].compactMap { $0 })
        payloads.append(contentsOf: scriptJSONPayloads(fromHTML: html))
        return payloads.compactMap { payload in
            guard let data = jsonData(from: payload) else { return nil }
            return try? JSONSerialization.jsonObject(with: data)
        }
    }

    private static func scriptJSONPayloads(fromHTML html: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"<script\b[^>]*>(.*?)</script>"#, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        return regex.matches(in: html, range: range).compactMap { match in
            guard let capture = Range(match.range(at: 1), in: html) else { return nil }
            let raw = String(html[capture]).trimmed
            guard raw.hasPrefix("{") || raw.hasPrefix("[") else { return nil }
            return raw
        }
    }

    private static func jsonData(from raw: String) -> Data? {
        let decoded = decodeHTML(normalizeEscapes(raw)).trimmed
        guard decoded.hasPrefix("{") || decoded.hasPrefix("[") else { return nil }
        return decoded.data(using: .utf8)
    }

    private static func balancedValue(afterPattern pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
              let matchRange = Range(match.range, in: text) else {
            return nil
        }
        var index = matchRange.upperBound
        while index < text.endIndex, text[index] != "{" && text[index] != "[" {
            index = text.index(after: index)
        }
        guard index < text.endIndex else { return nil }

        let opener = text[index]
        let closer: Character = opener == "{" ? "}" : "]"
        var depth = 0
        var inString: Character?
        var escaped = false
        var cursor = index
        while cursor < text.endIndex {
            let char = text[cursor]
            if let quote = inString {
                if escaped {
                    escaped = false
                } else if char == "\\" {
                    escaped = true
                } else if char == quote {
                    inString = nil
                }
                cursor = text.index(after: cursor)
                continue
            }
            if char == "\"" || char == "'" {
                inString = char
            } else if char == opener {
                depth += 1
            } else if char == closer {
                depth -= 1
                if depth == 0 {
                    return String(text[index...cursor])
                }
            }
            cursor = text.index(after: cursor)
        }
        return nil
    }

    private static func isVideoObject(_ object: [String: Any]) -> Bool {
        boolValue(object["is_video"]) ||
            stringValue(object["__typename"])?.lowercased().contains("video") == true ||
            object["video_url"] != nil ||
            object["video_versions"] != nil ||
            intValue(object["media_type"]) == 2
    }

    private static func mediaShortcode(from object: [String: Any]) -> String? {
        for key in ["shortcode", "code"] {
            if let value = stringValue(object[key]), isValidShortcode(value) {
                return value
            }
        }
        return nil
    }

    private static func username(fromHTML html: String) -> String? {
        firstCapture(pattern: #""username"\s*:\s*"([\w.]+)""#, in: html) ??
            firstCapture(pattern: #"instagram\.com/([\w.]+)/"#, in: html)
    }

    private static func titleFromHTML(_ html: String) -> String? {
        if let title = metaContent(from: html, names: ["og:title", "twitter:title"]) {
            return title
        }
        guard let raw = firstCapture(pattern: #"<title\b[^>]*>(.*?)</title>"#, in: html) else {
            return nil
        }
        return stripTags(raw)
    }

    private static func metaContent(from html: String, names: [String]) -> String? {
        for name in names {
            let patterns = [
                #"<meta\b[^>]*(?:property|name)\s*=\s*["']\#(name)["'][^>]*content\s*=\s*["']([^"']+)["'][^>]*>"#,
                #"<meta\b[^>]*content\s*=\s*["']([^"']+)["'][^>]*(?:property|name)\s*=\s*["']\#(name)["'][^>]*>"#
            ]
            for pattern in patterns {
                if let value = firstCapture(pattern: pattern, in: html) {
                    return decodeHTML(value)
                }
            }
        }
        return nil
    }

    private static func firstCapture(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[range])
    }

    private static func absoluteURL(_ raw: String, baseURL: URL) -> URL? {
        var value = decodeHTML(normalizeEscapes(raw))
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'").union(.whitespacesAndNewlines))
        guard !value.isEmpty else { return nil }
        if value.hasPrefix("//") {
            value = "\(baseURL.scheme ?? "https"):\(value)"
        }
        return URL(string: value, relativeTo: baseURL)?.absoluteURL
    }

    private static func isSupportedHost(_ host: String) -> Bool {
        host == "instagram.com" ||
            host == "www.instagram.com" ||
            host == "m.instagram.com" ||
            host.hasSuffix(".instagram.com") ||
            host == "instagram.co" ||
            host == "www.instagram.co" ||
            host.hasSuffix(".instagram.co") ||
            host == "instagram.test" ||
            host == "www.instagram.test" ||
            host.hasSuffix(".instagram.test")
    }

    private static func isSupportedProfileHost(_ host: String) -> Bool {
        [
            "instagram.com",
            "www.instagram.com",
            "m.instagram.com",
            "instagram.co",
            "www.instagram.co",
            "m.instagram.co",
            "instagram.test",
            "www.instagram.test",
            "m.instagram.test"
        ].contains(host)
    }

    private static func isValidProfileUsername(_ value: String) -> Bool {
        isValidStoryUsername(value) && !value.contains("..")
    }

    private static func isReservedProfilePath(_ value: String) -> Bool {
        [
            "about", "accounts", "ads", "api", "challenge", "developer", "developers",
            "direct", "directory", "emails", "explore", "graphql", "legal", "oauth", "p",
            "privacy", "reel", "reels", "static", "stories", "terms", "tv", "web"
        ].contains(value.lowercased())
    }

    private static func isValidShortcode(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z0-9_-]{2,}$"#, options: .regularExpression) != nil
    }

    private static func isValidStoryID(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil
    }

    private static func isValidStoryUsername(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z0-9._]{1,30}$"#, options: .regularExpression) != nil &&
            !value.hasPrefix(".") &&
            !value.hasSuffix(".")
    }

    private static func isValidHighlightID(_ value: String) -> Bool {
        value.range(of: #"^[0-9]+$"#, options: .regularExpression) != nil
    }

    private static func cleanCaption(_ raw: String) -> String {
        let decoded = decodeHTML(stripTags(raw))
        let firstLine = decoded
            .components(separatedBy: .newlines)
            .first?
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmed ?? ""
        return cleanTitle(firstLine.isEmpty ? decoded : firstLine)
    }

    private static func cleanTitle(_ raw: String) -> String {
        decodeHTML(stripTags(raw))
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmed
            .sanitizedFilename(maxLength: 120)
    }

    private static func stripTags(_ raw: String) -> String {
        raw.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
    }

    private static func normalizeEscapes(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\/", with: "/")
            .replacingOccurrences(of: "\\u0026", with: "&", options: .caseInsensitive)
            .replacingOccurrences(of: "\\u003d", with: "=", options: .caseInsensitive)
            .replacingOccurrences(of: "\\u003f", with: "?", options: .caseInsensitive)
            .replacingOccurrences(of: "\\u002F", with: "/", options: .caseInsensitive)
            .replacingOccurrences(of: "\\u003A", with: ":", options: .caseInsensitive)
    }

    private static func decodeHTML(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#34;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
    }

    private static func stringValue(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            return string.trimmed.isEmpty ? nil : string
        case let number as NSNumber:
            return number.stringValue
        default:
            return nil
        }
    }

    private static func intValue(_ value: Any?) -> Int? {
        switch value {
        case let int as Int:
            return int
        case let number as NSNumber:
            return number.intValue
        case let string as String:
            return Int(string)
        default:
            return nil
        }
    }

    private static func boolValue(_ value: Any?) -> Bool {
        switch value {
        case let bool as Bool:
            return bool
        case let number as NSNumber:
            return number.boolValue
        case let string as String:
            return ["1", "true", "yes", "y"].contains(string.lowercased())
        default:
            return false
        }
    }

    private static func dateString(from value: Any?) -> String {
        guard let seconds = intValue(value), seconds > 0 else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(seconds)))
    }
}
