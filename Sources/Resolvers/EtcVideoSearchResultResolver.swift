import Foundation

struct EtcVideoSearchResultResolver: SearchResultResolving {
    func supports(_ baseURL: URL) -> Bool {
        guard let site = EtcVideoPageResolver.site(for: baseURL) else {
            return false
        }
        return Self.isSupportedSite(site)
    }

    static func dataAttributeLinkValue(
        in attributes: [String: String],
        baseURL: URL?
    ) -> String? {
        guard let baseURL,
              let host = baseURL.host?.lowercased(),
              let site = EtcVideoPageResolver.site(for: baseURL),
              isSupportedSite(site) else {
            return nil
        }

        switch site {
        case .streamable:
            if let id = dataAttributeID(in: attributes),
               dataAttributeLooksLikeVideoCard(attributes) {
                return "/\(id)"
            }
        case .dailymotion:
            if let id = dataAttributeID(in: attributes),
               dataAttributeLooksLikeVideoCard(attributes) {
                return isDaiLyHost(host) ? "/\(id)" : "/video/\(id)"
            }
        case .reddit:
            if let id = redditDataAttributeVideoID(in: attributes),
               redditDataAttributeLooksLikeVideoCard(attributes) {
                return "https://v.redd.it/\(id)"
            }
            if let id = redditDataAttributePostID(in: attributes),
               redditDataAttributeLooksLikePostCard(attributes) {
                if let subreddit = redditDataAttributeSubreddit(
                    in: attributes
                ),
                   let slug = redditDataAttributePostSlug(
                       in: attributes
                   ) {
                    return "/r/\(subreddit)/comments/\(id)/\(slug)/"
                }
                return "https://redd.it/\(id)"
            }
        case .rumble:
            if let id = rumbleDataAttributeID(in: attributes),
               dataAttributeLooksLikeVideoCard(attributes) {
                return "/\(id).html"
            }
        case .odysee:
            if let id = odyseeDataAttributeClaimID(in: attributes),
               let channel = odyseeDataAttributeChannel(in: attributes),
               let slug = odyseeDataAttributeSlug(in: attributes),
               odyseeDataAttributeLooksLikeClaimCard(attributes) {
                return "/@\(channel)/\(slug):\(id)"
            }
        case .bitchute:
            if let id = dataAttributeID(in: attributes),
               dataAttributeLooksLikeVideoCard(attributes) {
                return "/video/\(id)/"
            }
        case .rutube:
            if let id = dataAttributeID(in: attributes),
               dataAttributeLooksLikeVideoCard(attributes) {
                return "/video/\(id)"
            }
        case .twitcasting:
            if let id = twitCastingDataAttributeMovieID(in: attributes),
               let username = twitCastingDataAttributeUsername(
                   in: attributes
               ),
               dataAttributeLooksLikeVideoCard(attributes) {
                return "/\(username)/movie/\(id)"
            }
        case .kick:
            if let id = kickDataAttributeClipID(in: attributes),
               kickDataAttributeLooksLikeClipCard(attributes) {
                return "/?clip=\(id)"
            }
            if let id = dataAttributeID(in: attributes),
               dataAttributeLooksLikeVideoCard(attributes) {
                return "/?video=\(id)"
            }
        case .vk:
            if let external = vkDataAttributeExternalLinkValue(
                in: attributes
            ) {
                return external
            }
            if let id = vkDataAttributeVideoPathID(in: attributes),
               dataAttributeLooksLikeVideoCard(attributes) {
                return "/video\(id)"
            }
        case .okru:
            if let id = dataAttributeID(in: attributes),
               dataAttributeLooksLikeVideoCard(attributes) {
                return "/video/\(id)"
            }
        case .tver:
            if let id = tverDataAttributeEpisodeID(in: attributes),
               typeHint(
                   in: attributes,
                   containsAnyOf: ["episode", "video", "watch"]
               ) || dataAttributeLooksLikeVideoCard(attributes) {
                return "/episodes/\(id)"
            }
        default:
            return nil
        }

        return nil
    }

    func extract(from context: SearchResultResolverContext) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByKey: [String: Int] = [:]

        for anchor in context.anchors {
            guard results.count < context.limit,
                  let absolute = context.resolvedURL(for: anchor),
                  let site = EtcVideoPageResolver.site(for: absolute),
                  Self.isSupportedSite(site),
                  !Self.isNavigationURL(absolute, site: site),
                  let id = EtcVideoPageResolver.contentID(from: absolute),
                  let target = Self.canonicalURL(
                      from: absolute,
                      site: site,
                      id: id
                  ) else {
                continue
            }

            let title = context.title(
                for: anchor,
                fallback: "\(site.rawValue) \(id)"
            )
            SearchResultResolverSupport.appendUniqueResult(
                title: title,
                url: target,
                id: "\(site.rawValue.lowercased())-\(id)",
                sitePrefix: site.rawValue.lowercased(),
                results: &results,
                indexByID: &indexByKey,
                metadata: metadata(
                    id: id,
                    site: site,
                    title: title,
                    anchor: anchor,
                    target: target,
                    context: context
                )
            )
        }

        return results
    }

    private func metadata(
        id: String,
        site: EtcVideoPageResolver.Site,
        title: String,
        anchor: AnchorEntry,
        target: URL,
        context: SearchResultResolverContext
    ) -> [String: String] {
        var metadata = [
            "id": id,
            "content_id": id,
            "media_id": id,
            "category": site.rawValue.lowercased(),
            "type": "video",
            "media_type": "video",
            "title": title,
            "search_title": title
        ]

        switch site {
        case .streamable:
            metadata["streamable_id"] = id
            metadata["video_id"] = id
        case .dailymotion:
            metadata["dailymotion_id"] = id
            metadata["video_id"] = id
        case .reddit:
            metadata["reddit_id"] = id
            if Self.isVRedditTarget(target) {
                metadata["video_id"] = id
            } else {
                metadata["post_id"] = id
                metadata["type"] = "post"
            }
        case .rumble:
            metadata["rumble_id"] = id
            metadata["video_id"] = id
        case .odysee:
            metadata["odysee_id"] = id
            metadata["claim_id"] = id
            metadata["video_id"] = id
            if let username = Self.odyseeChannelUsername(from: target) {
                metadata["username"] = username
                metadata["user"] = username
                metadata["channel"] = username
            }
        case .bitchute:
            metadata["bitchute_id"] = id
            metadata["video_id"] = id
        case .rutube:
            metadata["rutube_id"] = id
            metadata["video_id"] = id
        case .twitcasting:
            metadata["movie_id"] = id
            metadata["video_id"] = id
            if let username = Self.twitCastingUsername(from: target) {
                metadata["username"] = username
                metadata["user"] = username
                metadata["channel"] = username
            }
        case .kick:
            if Self.kickTargetIsClip(target) {
                metadata["clip_id"] = id
                metadata["type"] = "clip"
            } else {
                metadata["video_id"] = id
            }
        case .vk:
            metadata["vk_id"] = id
            metadata["video_id"] = id
        case .okru:
            metadata["okru_id"] = id
            metadata["video_id"] = id
        case .tver:
            metadata["episode_id"] = id
            metadata["video_id"] = id
            metadata["type"] = "episode"
        default:
            metadata["video_id"] = id
        }

        metadata.merge(context.contributorMetadata(
            for: anchor,
            fallbackName: nil,
            fallbackUsername:
                Self.odyseeChannelUsername(from: target) ??
                Self.twitCastingUsername(from: target)
        )) { current, _ in current }
        return DownloadMetadata.clean(metadata)
    }

    private static func isSupportedSite(
        _ site: EtcVideoPageResolver.Site
    ) -> Bool {
        switch site {
        case .bitchute, .dailymotion, .kick, .odysee, .okru, .reddit,
             .rumble, .rutube, .streamable, .twitcasting, .tver, .vk:
            return true
        default:
            return false
        }
    }

    private static func canonicalURL(
        from url: URL,
        site: EtcVideoPageResolver.Site,
        id: String
    ) -> URL? {
        switch site {
        case .bitchute:
            return cleanedURL(url, path: "/video/\(id)/")
        case .dailymotion:
            let host = url.host?.lowercased() ?? ""
            let path = isDaiLyHost(host) ? "/\(id)" : "/video/\(id)"
            return cleanedURL(url, path: path)
        case .kick:
            if let components = cleanedComponentsKeepingQuery(
                url,
                names: ["clip", "video", "v"]
            ),
               let target = components.url {
                return target
            }
            return cleanedURL(url)
        case .streamable:
            return cleanedURL(url, path: "/\(id)")
        case .vk:
            if url.path.lowercased().contains("video_ext.php"),
               var components = URLComponents(
                   url: url,
                   resolvingAgainstBaseURL: false
               ) {
                let items = components.queryItems ?? []
                components.queryItems = items.filter {
                    ["oid", "id"].contains($0.name.lowercased())
                }
                components.fragment = nil
                return components.url
            }
            return cleanedURL(url)
        case .reddit:
            let host = url.host?.lowercased() ?? ""
            if [
                "v.redd.it", "v.redd.test", "redd.it", "redd.test"
            ].contains(host) {
                return cleanedURL(url, path: "/\(id)")
            }
            return cleanedURL(url)
        case .odysee, .okru, .rumble, .rutube, .tver:
            return cleanedURL(url)
        default:
            return cleanedURL(url)
        }
    }

    private static func isNavigationURL(
        _ url: URL,
        site: EtcVideoPageResolver.Site
    ) -> Bool {
        let lower = url.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).lowercased() }
        let first = lower.first ?? ""

        if site == .kick,
           cleanedComponentsKeepingQuery(
               url,
               names: ["clip", "video", "v"]
           ) != nil {
            return false
        }
        if site == .vk, first == "video_ext.php" {
            return false
        }
        guard !first.isEmpty else { return true }

        let reserved: Set<String> = [
            "about", "browse", "categories", "category", "channels",
            "channel", "discover", "explore", "feed", "help", "home",
            "login", "popular", "privacy", "search", "settings",
            "signup", "tag", "tags", "terms", "trending", "user", "users"
        ]
        return reserved.contains(first)
    }

    private static func cleanedURL(
        _ url: URL,
        path: String? = nil
    ) -> URL? {
        guard var components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        ) else {
            return nil
        }
        if let path {
            components.path = path
        }
        components.queryItems = nil
        components.fragment = nil
        return components.url
    }

    private static func cleanedComponentsKeepingQuery(
        _ url: URL,
        names: Set<String>
    ) -> URLComponents? {
        guard var components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        ) else {
            return nil
        }
        let allowed = names.map { $0.lowercased() }
        let items = (components.queryItems ?? []).filter {
            allowed.contains($0.name.lowercased())
        }
        guard !items.isEmpty else { return nil }
        components.queryItems = items
        components.fragment = nil
        return components
    }

    private static func isVRedditTarget(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        return host == "v.redd.it" || host == "v.redd.test"
    }

    private static func odyseeChannelUsername(from url: URL) -> String? {
        url.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
            .first { $0.hasPrefix("@") }
            .map { String($0.dropFirst()) }
    }

    private static func twitCastingUsername(from url: URL) -> String? {
        let parts = url.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        guard parts.count >= 3,
              parts[1].lowercased() == "movie" else {
            return nil
        }
        return parts[0]
    }

    private static func kickTargetIsClip(_ url: URL) -> Bool {
        if URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        )?.queryItems?.contains(
            where: { $0.name.lowercased() == "clip" }
        ) == true {
            return true
        }
        return url.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).lowercased() }
            .contains("clip")
    }

    private static func dataAttributeID(
        in attributes: [String: String]
    ) -> String? {
        let keys = [
            "data-video-id", "data-videoid", "data-media-id",
            "data-mediaid", "data-content-id", "data-contentid",
            "data-clip-id", "data-clipid", "video-id", "clip-id"
        ]
        if let value = firstAttributeValue(
            in: attributes,
            keys: keys,
            matching: isValidPathSlug
        ) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           isValidPathSlug(id),
           typeHint(
               in: attributes,
               containsAnyOf: ["video", "watch", "clip", "episode"]
           ) {
            return id
        }
        return nil
    }

    private static func redditDataAttributeVideoID(
        in attributes: [String: String]
    ) -> String? {
        let keys = [
            "data-vreddit-id", "data-vredditid", "data-video-id",
            "data-videoid", "video-id"
        ]
        if let value = firstAttributeValue(
            in: attributes,
            keys: keys,
            matching: isValidPathSlug
        ) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           isValidPathSlug(id),
           typeHint(
               in: attributes,
               containsAnyOf: ["video", "media", "vreddit"]
           ) {
            return id
        }
        return nil
    }

    private static func redditDataAttributePostID(
        in attributes: [String: String]
    ) -> String? {
        let keys = [
            "data-post-id", "data-postid", "data-thing-id",
            "data-fullname", "post-id"
        ]
        for key in keys {
            guard let raw = attributes[key]?.trimmed else { continue }
            let value = raw.hasPrefix("t3_") ?
                String(raw.dropFirst(3)) :
                raw
            if isValidPathSlug(value) {
                return value
            }
        }
        if let id = attributes["data-id"]?.trimmed,
           isValidPathSlug(id),
           typeHint(
               in: attributes,
               containsAnyOf: ["post", "comments", "reddit"]
           ) {
            return id
        }
        return nil
    }

    private static func redditDataAttributeSubreddit(
        in attributes: [String: String]
    ) -> String? {
        firstAttributeValue(
            in: attributes,
            keys: [
                "data-subreddit", "data-subreddit-name", "subreddit"
            ],
            matching: isValidPathSlug
        )
    }

    private static func redditDataAttributePostSlug(
        in attributes: [String: String]
    ) -> String? {
        firstAttributeValue(
            in: attributes,
            keys: [
                "data-post-slug", "data-postslug",
                "data-title-slug", "data-slug"
            ],
            matching: isValidPathSlug
        )
    }

    private static func redditDataAttributeLooksLikePostCard(
        _ attributes: [String: String]
    ) -> Bool {
        let markerKeys = [
            "data-post-id", "data-postid", "data-thing-id",
            "data-fullname", "post-id"
        ]
        if markerKeys.contains(
            where: { attributes[$0]?.trimmed.isEmpty == false }
        ) {
            return true
        }
        return typeHint(
            in: attributes,
            containsAnyOf: ["post", "comments", "reddit"]
        )
    }

    private static func redditDataAttributeLooksLikeVideoCard(
        _ attributes: [String: String]
    ) -> Bool {
        let markerKeys = [
            "data-vreddit-id", "data-vredditid", "data-video-id",
            "data-videoid", "video-id"
        ]
        if markerKeys.contains(
            where: { attributes[$0]?.trimmed.isEmpty == false }
        ) {
            return true
        }
        return typeHint(
            in: attributes,
            containsAnyOf: ["video", "media", "vreddit"]
        )
    }

    private static func rumbleDataAttributeID(
        in attributes: [String: String]
    ) -> String? {
        let keys = [
            "data-rumble-id", "data-rumbleid", "data-video-id",
            "data-videoid", "video-id"
        ]
        let predicate: (String) -> Bool = { value in
            value.range(
                of: #"^v[0-9A-Za-z_-]+$"#,
                options: .regularExpression
            ) != nil
        }
        if let value = firstAttributeValue(
            in: attributes,
            keys: keys,
            matching: predicate
        ) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           predicate(id),
           typeHint(
               in: attributes,
               containsAnyOf: ["video", "rumble"]
           ) {
            return id
        }
        return nil
    }

    private static func odyseeDataAttributeClaimID(
        in attributes: [String: String]
    ) -> String? {
        firstAttributeValue(
            in: attributes,
            keys: [
                "data-claim-id", "data-claimid", "data-video-id",
                "data-videoid", "claim-id"
            ],
            matching: isValidPathSlug
        )
    }

    private static func odyseeDataAttributeChannel(
        in attributes: [String: String]
    ) -> String? {
        let keys = [
            "data-channel", "data-channel-name", "data-channel-slug",
            "data-creator", "data-uploader", "channel"
        ]
        for key in keys {
            guard let raw = attributes[key]?.trimmed else { continue }
            let value = raw.hasPrefix("@") ?
                String(raw.dropFirst()) :
                raw
            if isValidPathSlug(value) {
                return value
            }
        }
        return nil
    }

    private static func odyseeDataAttributeSlug(
        in attributes: [String: String]
    ) -> String? {
        firstAttributeValue(
            in: attributes,
            keys: [
                "data-claim-slug", "data-claimslug", "data-video-slug",
                "data-title-slug", "data-slug"
            ],
            matching: isValidPathSlug
        )
    }

    private static func odyseeDataAttributeLooksLikeClaimCard(
        _ attributes: [String: String]
    ) -> Bool {
        if [
            "data-claim-id", "data-claimid", "claim-id"
        ].contains(
            where: { attributes[$0]?.trimmed.isEmpty == false }
        ) {
            return true
        }
        return typeHint(
            in: attributes,
            containsAnyOf: ["claim", "video", "watch"]
        )
    }

    private static func twitCastingDataAttributeMovieID(
        in attributes: [String: String]
    ) -> String? {
        firstAttributeValue(
            in: attributes,
            keys: [
                "data-movie-id", "data-movieid", "data-video-id",
                "data-videoid", "movie-id"
            ],
            matching: isValidPathSlug
        )
    }

    private static func twitCastingDataAttributeUsername(
        in attributes: [String: String]
    ) -> String? {
        firstAttributeValue(
            in: attributes,
            keys: [
                "data-user", "data-user-name", "data-username",
                "data-caster", "data-screen-id", "username"
            ],
            matching: isValidPathSlug
        )
    }

    private static func kickDataAttributeClipID(
        in attributes: [String: String]
    ) -> String? {
        firstAttributeValue(
            in: attributes,
            keys: [
                "data-clip-id", "data-clipid", "data-clip-slug",
                "data-clipslug", "clip-id"
            ],
            matching: isValidPathSlug
        )
    }

    private static func kickDataAttributeLooksLikeClipCard(
        _ attributes: [String: String]
    ) -> Bool {
        if [
            "data-clip-id", "data-clipid", "data-clip-slug",
            "data-clipslug", "clip-id"
        ].contains(
            where: { attributes[$0]?.trimmed.isEmpty == false }
        ) {
            return true
        }
        return typeHint(in: attributes, containsAnyOf: ["clip"])
    }

    private static func vkDataAttributeExternalLinkValue(
        in attributes: [String: String]
    ) -> String? {
        guard let oid = firstAttributeValue(
            in: attributes,
            keys: [
                "data-oid", "data-owner-id", "data-ownerid", "oid"
            ],
            matching: isVKOwnerID
        ),
              let id = firstAttributeValue(
                  in: attributes,
                  keys: [
                      "data-vk-id", "data-video-id", "data-videoid",
                      "data-id", "vk-id"
                  ],
                  matching: isVKNumericID
              ),
              typeHint(
                  in: attributes,
                  containsAnyOf: ["video", "vk", "embed", "external"]
              ) else {
            return nil
        }
        return "/video_ext.php?oid=\(oid)&id=\(id)"
    }

    private static func vkDataAttributeVideoPathID(
        in attributes: [String: String]
    ) -> String? {
        let keys = [
            "data-vk-video-id", "data-vkvideoid", "data-video-id",
            "data-videoid", "video-id"
        ]
        let predicate: (String) -> Bool = { value in
            value.range(
                of: #"^-?[0-9]+_[0-9]+$"#,
                options: .regularExpression
            ) != nil
        }
        if let value = firstAttributeValue(
            in: attributes,
            keys: keys,
            matching: predicate
        ) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           predicate(id),
           typeHint(
               in: attributes,
               containsAnyOf: ["video", "vk"]
           ) {
            return id
        }
        return nil
    }

    private static func tverDataAttributeEpisodeID(
        in attributes: [String: String]
    ) -> String? {
        if let value = firstAttributeValue(
            in: attributes,
            keys: [
                "data-episode-id", "data-episodeid", "data-video-id",
                "data-videoid", "episode-id"
            ],
            matching: isValidPathSlug
        ) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           isValidPathSlug(id),
           typeHint(
               in: attributes,
               containsAnyOf: ["episode", "video", "tver"]
           ) {
            return id
        }
        return nil
    }

    private static func dataAttributeLooksLikeVideoCard(
        _ attributes: [String: String]
    ) -> Bool {
        let markerKeys = [
            "data-video-id", "data-videoid", "data-media-id",
            "data-mediaid", "data-content-id", "data-contentid",
            "data-clip-id", "data-clipid", "data-episode-id",
            "data-episodeid", "data-movie-id", "data-movieid",
            "video-id", "clip-id", "episode-id", "movie-id"
        ]
        if markerKeys.contains(
            where: { attributes[$0]?.trimmed.isEmpty == false }
        ) {
            return true
        }
        return typeHint(
            in: attributes,
            containsAnyOf: [
                "video", "watch", "clip", "episode", "movie"
            ]
        )
    }

    private static func firstAttributeValue(
        in attributes: [String: String],
        keys: [String],
        matching predicate: (String) -> Bool
    ) -> String? {
        for key in keys {
            if let value = attributes[key]?.trimmed,
               predicate(value) {
                return value
            }
        }
        return nil
    }

    private static func typeHint(
        in attributes: [String: String],
        containsAnyOf needles: [String]
    ) -> Bool {
        let keys = [
            "data-type", "data-kind", "data-content-type",
            "data-renderer", "class", "role"
        ]
        let values = keys.compactMap { attributes[$0]?.lowercased() }
        return values.contains { value in
            needles.contains { value.contains($0) }
        }
    }

    private static func isValidPathSlug(_ value: String) -> Bool {
        !value.isEmpty &&
            value.range(
                of: #"^[A-Za-z0-9][A-Za-z0-9_-]*$"#,
                options: .regularExpression
            ) != nil
    }

    private static func isDaiLyHost(_ host: String) -> Bool {
        [
            "dai.ly", "www.dai.ly", "dai.test", "www.dai.test"
        ].contains(host)
    }

    private static func isVKOwnerID(_ value: String) -> Bool {
        value.range(
            of: #"^-?[0-9]+$"#,
            options: .regularExpression
        ) != nil
    }

    private static func isVKNumericID(_ value: String) -> Bool {
        value.range(
            of: #"^[0-9]+$"#,
            options: .regularExpression
        ) != nil
    }
}
