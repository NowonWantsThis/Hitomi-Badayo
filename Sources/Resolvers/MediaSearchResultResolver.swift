import Foundation

struct MediaSearchResultResolver: SearchResultResolving {
    private enum Site {
        case coub
        case vimeo
        case soundCloud
    }

    func supports(_ baseURL: URL) -> Bool {
        site(for: baseURL) != nil
    }

    static func dataAttributeLinkValue(
        in attributes: [String: String],
        baseURL: URL?
    ) -> String? {
        guard let host = baseURL?.host?.lowercased() else {
            return nil
        }

        if isCoubHost(host),
           let id = coubDataAttributeID(in: attributes),
           coubDataAttributeLooksLikeClipCard(attributes) {
            return "/view/\(id)"
        }

        if isVimeoHost(host),
           let id = vimeoDataAttributeVideoID(in: attributes),
           vimeoDataAttributeLooksLikeVideoCard(attributes) {
            return "/\(id)"
        }

        if isSoundCloudHost(host),
           let path = soundCloudDataAttributeTrackPath(in: attributes),
           soundCloudDataAttributeLooksLikeTrackCard(attributes) {
            return path
        }

        return nil
    }

    func extract(from context: SearchResultResolverContext) -> [SearchResultLink] {
        guard let site = site(for: context.baseURL) else { return [] }

        switch site {
        case .coub:
            return extractCoub(from: context)
        case .vimeo:
            return extractVimeo(from: context)
        case .soundCloud:
            return extractSoundCloud(from: context)
        }
    }

    private func extractCoub(from context: SearchResultResolverContext) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByID: [String: Int] = [:]

        for anchor in context.anchors {
            guard results.count < context.limit,
                  let absolute = context.resolvedURL(for: anchor),
                  let id = CoubResolver.coubID(from: absolute),
                  let target = CoubResolver.canonicalViewURL(id: id, sourceURL: absolute) else {
                continue
            }

            let title = context.title(for: anchor, fallback: "Coub \(id)")
            SearchResultResolverSupport.appendUniqueResult(
                title: title,
                url: target,
                id: id,
                sitePrefix: "coub",
                results: &results,
                indexByID: &indexByID,
                metadata: mediaMetadata(
                    id: id,
                    category: "coub",
                    type: "video",
                    title: title,
                    contributorMetadata: context.contributorMetadata(for: anchor),
                    additional: [
                        "coub_id": id,
                        "video_id": id
                    ]
                )
            )
        }

        return results
    }

    private func extractVimeo(from context: SearchResultResolverContext) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByID: [String: Int] = [:]

        for anchor in context.anchors {
            guard results.count < context.limit,
                  let absolute = context.resolvedURL(for: anchor),
                  let id = VimeoResolver.videoID(from: absolute),
                  let target = vimeoVideoURL(id: id, sourceURL: absolute) else {
                continue
            }

            let title = context.title(for: anchor, fallback: "Vimeo \(id)")
            SearchResultResolverSupport.appendUniqueResult(
                title: title,
                url: target,
                id: id,
                sitePrefix: "vimeo",
                results: &results,
                indexByID: &indexByID,
                metadata: mediaMetadata(
                    id: id,
                    category: "vimeo",
                    type: "video",
                    title: title,
                    contributorMetadata: context.contributorMetadata(for: anchor),
                    additional: ["video_id": id]
                )
            )
        }

        return results
    }

    private func extractSoundCloud(from context: SearchResultResolverContext) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByTrack: [String: Int] = [:]

        for anchor in context.anchors {
            guard results.count < context.limit,
                  let absolute = context.resolvedURL(for: anchor),
                  let target = soundCloudTrackURL(from: absolute) else {
                continue
            }

            let title = context.title(for: anchor, fallbackURL: target)
            let trackKey = soundCloudTrackKey(for: target)
            let parts = target.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
            let username = parts.first
            let slug = parts.dropFirst().first
            let contributorMetadata = context.contributorMetadata(
                for: anchor,
                fallbackName: username,
                fallbackUsername: username
            )
            var additional = ["track_id": trackKey]
            if let slug {
                additional["slug"] = slug
            }
            SearchResultResolverSupport.appendUniqueResult(
                title: title,
                url: target,
                id: trackKey,
                sitePrefix: "soundcloud",
                results: &results,
                indexByID: &indexByTrack,
                metadata: mediaMetadata(
                    id: trackKey,
                    category: "soundcloud",
                    type: "track",
                    title: title,
                    contributorMetadata: contributorMetadata,
                    additional: additional,
                    mediaType: "audio"
                )
            )
        }

        return results
    }

    private func mediaMetadata(
        id: String,
        category: String,
        type: String,
        title: String,
        contributorMetadata: [String: String],
        additional: [String: String] = [:],
        mediaType: String = "video"
    ) -> [String: String] {
        var metadata = [
            "id": id,
            "media_id": id,
            "category": category,
            "type": type,
            "media_type": mediaType,
            "title": title,
            "search_title": title
        ]
        metadata.merge(additional) { current, _ in current }
        metadata.merge(contributorMetadata) { current, _ in current }
        return DownloadMetadata.clean(metadata)
    }

    private func site(for url: URL) -> Site? {
        guard let host = url.host?.lowercased() else { return nil }
        if Self.isCoubHost(host) {
            return .coub
        }
        if Self.isVimeoHost(host) {
            return .vimeo
        }
        if Self.isSoundCloudHost(host) {
            return .soundCloud
        }
        return nil
    }

    private func vimeoVideoURL(id: String, sourceURL: URL) -> URL? {
        var components = URLComponents()
        components.scheme = sourceURL.scheme ?? "https"
        components.host = sourceURL.host?.lowercased().contains("test") == true
            ? "vimeo.test"
            : "vimeo.com"
        components.path = "/\(id)"
        return components.url
    }

    private func soundCloudTrackURL(from url: URL) -> URL? {
        guard let host = url.host?.lowercased(), Self.isSoundCloudHost(host) else { return nil }
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 2 else { return nil }

        let first = parts[0].lowercased()
        let second = parts[1].lowercased()
        guard !["discover", "search", "you", "stream", "charts", "stations", "upload", "pages"].contains(first),
              !["sets", "albums", "tracks", "likes", "reposts", "popular-tracks"].contains(second),
              !parts[0].isEmpty,
              !parts[1].isEmpty else {
            return nil
        }

        return cleanedURL(url, path: "/\(parts[0])/\(parts[1])")
    }

    private func soundCloudTrackKey(for url: URL) -> String {
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 2 else {
            return URLIdentity.normalize(url.absoluteString)
        }
        return "\(parts[0])/\(parts[1])"
    }

    private func cleanedURL(_ url: URL, path: String) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.path = path
        components.queryItems = nil
        components.fragment = nil
        return components.url
    }

    static func isCoubHost(_ host: String) -> Bool {
        host == "coub.com" ||
            host == "www.coub.com" ||
            host == "coub.test" ||
            host == "www.coub.test" ||
            host.hasSuffix(".coub.com") ||
            host.hasSuffix(".coub.test") ||
            CoubResolver.isImagizerHost(host)
    }

    static func isVimeoHost(_ host: String) -> Bool {
        host == "vimeo.com" ||
            host == "www.vimeo.com" ||
            host == "player.vimeo.com" ||
            host == "vimeo.test" ||
            host == "www.vimeo.test" ||
            host == "player.vimeo.test"
    }

    static func isSoundCloudHost(_ host: String) -> Bool {
        host == "soundcloud.com" ||
            host == "www.soundcloud.com" ||
            host == "soundcloud.test" ||
            host == "www.soundcloud.test" ||
            host.hasSuffix(".soundcloud.com") ||
            host.hasSuffix(".soundcloud.test")
    }

    private static func coubDataAttributeID(
        in attributes: [String: String]
    ) -> String? {
        let keys = [
            "data-coub-id", "data-coubid", "data-clip-id",
            "data-clipid", "data-video-id", "data-videoid",
            "data-media-id", "coub-id", "clip-id"
        ]
        for key in keys {
            if let value = attributes[key]?.trimmed,
               value.range(
                   of: #"^[0-9A-Za-z]+$"#,
                   options: .regularExpression
               ) != nil {
                return value
            }
        }
        if let id = attributes["data-id"]?.trimmed,
           id.range(
               of: #"^[0-9A-Za-z]+$"#,
               options: .regularExpression
           ) != nil,
           typeHint(
               in: attributes,
               containsAnyOf: ["coub", "clip", "video"]
           ) {
            return id
        }
        return nil
    }

    private static func coubDataAttributeLooksLikeClipCard(
        _ attributes: [String: String]
    ) -> Bool {
        let keys = [
            "data-coub-id", "data-coubid", "data-clip-id",
            "data-clipid", "data-video-id", "data-videoid",
            "data-media-id", "coub-id", "clip-id"
        ]
        if keys.contains(where: {
            attributes[$0]?.trimmed.isEmpty == false
        }) {
            return true
        }
        return typeHint(
            in: attributes,
            containsAnyOf: ["coub", "clip", "video"]
        )
    }

    private static func vimeoDataAttributeVideoID(
        in attributes: [String: String]
    ) -> String? {
        let keys = [
            "data-vimeo-id", "data-vimeoid", "data-video-id",
            "data-videoid", "data-clip-id", "data-clipid",
            "video-id", "clip-id"
        ]
        for key in keys {
            if let value = attributes[key]?.trimmed,
               value.range(
                   of: #"^[0-9]{4,}$"#,
                   options: .regularExpression
               ) != nil {
                return value
            }
        }
        if let id = attributes["data-id"]?.trimmed,
           id.range(
               of: #"^[0-9]{4,}$"#,
               options: .regularExpression
           ) != nil,
           typeHint(
               in: attributes,
               containsAnyOf: ["vimeo", "video", "clip"]
           ) {
            return id
        }
        return nil
    }

    private static func vimeoDataAttributeLooksLikeVideoCard(
        _ attributes: [String: String]
    ) -> Bool {
        let keys = [
            "data-vimeo-id", "data-vimeoid", "data-video-id",
            "data-videoid", "data-clip-id", "data-clipid",
            "video-id", "clip-id"
        ]
        if keys.contains(where: {
            attributes[$0]?.trimmed.isEmpty == false
        }) {
            return true
        }
        return typeHint(
            in: attributes,
            containsAnyOf: ["vimeo", "video", "clip"]
        )
    }

    private static func soundCloudDataAttributeTrackPath(
        in attributes: [String: String]
    ) -> String? {
        let pathKeys = [
            "data-permalink-path", "data-permalinkpath",
            "data-track-path", "data-trackpath", "permalink-path"
        ]
        for key in pathKeys {
            if let path = soundCloudTrackPath(from: attributes[key]) {
                return path
            }
        }
        if let path = soundCloudTrackPath(from: attributes["data-id"]),
           typeHint(
               in: attributes,
               containsAnyOf: ["soundcloud", "track", "audio"]
           ) {
            return path
        }

        let usernameKeys = [
            "data-username", "data-user-username", "data-user-permalink",
            "data-user-permalink-name", "data-artist-username"
        ]
        let slugKeys = [
            "data-track-slug", "data-track-permalink", "data-permalink",
            "data-slug", "data-title-slug"
        ]
        guard let username = firstValidPathSlug(
            in: attributes,
            keys: usernameKeys
        ),
              let slug = firstValidPathSlug(
                  in: attributes,
                  keys: slugKeys
              ) else {
            return nil
        }
        return "/\(username)/\(slug)"
    }

    private static func soundCloudTrackPath(
        from value: String?
    ) -> String? {
        guard let value = value?.trimmed, !value.isEmpty else {
            return nil
        }
        let trimmed = value.hasPrefix("/")
            ? String(value.dropFirst())
            : value
        let parts = trimmed
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        guard parts.count >= 2,
              isValidPathSlug(parts[0]),
              isValidPathSlug(parts[1]) else {
            return nil
        }
        let second = parts[1].lowercased()
        guard ![
            "sets", "albums", "tracks", "likes", "reposts",
            "popular-tracks"
        ].contains(second) else {
            return nil
        }
        return "/\(parts[0])/\(parts[1])"
    }

    private static func soundCloudDataAttributeLooksLikeTrackCard(
        _ attributes: [String: String]
    ) -> Bool {
        let keys = [
            "data-permalink-path", "data-permalinkpath",
            "data-track-path", "data-trackpath", "permalink-path",
            "data-track-slug", "data-track-permalink"
        ]
        if keys.contains(where: {
            attributes[$0]?.trimmed.isEmpty == false
        }) {
            return true
        }
        return typeHint(
            in: attributes,
            containsAnyOf: ["soundcloud", "track", "audio"]
        )
    }

    private static func firstValidPathSlug(
        in attributes: [String: String],
        keys: [String]
    ) -> String? {
        for key in keys {
            if let value = attributes[key]?.trimmed,
               isValidPathSlug(value) {
                return value
            }
        }
        return nil
    }

    private static func isValidPathSlug(_ value: String) -> Bool {
        !value.isEmpty &&
            value.range(
                of: #"^[A-Za-z0-9][A-Za-z0-9_-]*$"#,
                options: .regularExpression
            ) != nil
    }

    private static func typeHint(
        in attributes: [String: String],
        containsAnyOf needles: [String]
    ) -> Bool {
        let keys = [
            "data-type", "data-kind", "data-content-type",
            "data-renderer", "class", "role"
        ]
        let values = keys.compactMap {
            attributes[$0]?.lowercased()
        }
        return values.contains { value in
            needles.contains { value.contains($0) }
        }
    }
}
