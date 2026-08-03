import Foundation

struct YouTubeSearchResultResolver: SearchResultResolving {
    func supports(_ baseURL: URL) -> Bool {
        guard let host = baseURL.host?.lowercased() else { return false }
        return Self.isSupportedHost(host)
    }

    static func isSupportedHost(_ host: String) -> Bool {
        host == "youtube.com" ||
            host == "www.youtube.com" ||
            host == "m.youtube.com" ||
            host == "music.youtube.com" ||
            host == "youtu.be" ||
            host == "www.youtu.be" ||
            host == "yewtu.be" ||
            host == "youtube.test" ||
            host == "www.youtube.test" ||
            host == "m.youtube.test" ||
            host == "music.youtube.test" ||
            host == "youtu.test" ||
            host == "www.youtu.test" ||
            host == "yewtu.test" ||
            host.hasSuffix(".yewtu.be") ||
            host.hasSuffix(".yewtu.test")
    }

    static func dataAttributeLinkValue(
        in attributes: [String: String],
        baseURL: URL?
    ) -> String? {
        guard let host = baseURL?.host?.lowercased(),
              isSupportedHost(host) else {
            return nil
        }

        let shortsKeys = [
            "data-shorts-video-id", "data-short-video-id",
            "data-short-id"
        ]
        for key in shortsKeys {
            guard let id = attributes[key]?.trimmed,
                  isValidSlug(id) else {
                continue
            }
            return "/shorts/\(id)"
        }

        let videoKeys = [
            "data-video-id", "data-videoid", "video-id",
            "videoid", "data-watch-id"
        ]
        for key in videoKeys {
            guard let id = attributes[key]?.trimmed,
                  isValidSlug(id) else {
                continue
            }
            return "/watch?v=\(id)"
        }

        if let id = attributes["data-id"]?.trimmed,
           isValidSlug(id),
           typeHint(
               in: attributes,
               containsAnyOf: ["video", "short", "watch"]
           ) {
            return "/watch?v=\(id)"
        }

        let playlistKeys = [
            "data-playlist-id", "data-list-id", "data-playlistid"
        ]
        for key in playlistKeys {
            guard let id = attributes[key]?.trimmed,
                  isValidSlug(id) else {
                continue
            }
            return "/playlist?list=\(id)"
        }

        return nil
    }

    static func queueURL(from url: URL) -> URL? {
        guard let host = url.host?.lowercased(),
              isSupportedHost(host) else {
            return nil
        }

        let parts = url.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        let lower = parts.map { $0.lowercased() }
        let queryItems = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        )?.queryItems ?? []

        if isShortHost(host) {
            guard let id = parts.first, isValidSlug(id) else {
                return nil
            }
            return canonicalURL(
                path: "/watch",
                queryItems: [URLQueryItem(name: "v", value: id)]
            )
        }

        if let first = lower.first,
           ["embed", "v"].contains(first),
           parts.count >= 2,
           isValidSlug(parts[1]) {
            return canonicalURL(
                path: "/watch",
                queryItems: [
                    URLQueryItem(name: "v", value: parts[1])
                ]
            )
        }

        if isYewtuHost(host),
           parts.count == 1,
           let id = parts.first,
           isValidSlug(id),
           !isYewtuReservedPath(id) {
            return canonicalURL(
                path: "/watch",
                queryItems: [URLQueryItem(name: "v", value: id)]
            )
        }

        if lower.first == "watch",
           let id = queryValue("v", in: queryItems),
           isValidSlug(id) {
            return canonicalURL(
                path: "/watch",
                queryItems: [URLQueryItem(name: "v", value: id)]
            )
        }

        if lower.first == "shorts",
           parts.count >= 2,
           isValidSlug(parts[1]) {
            return canonicalURL(path: "/shorts/\(parts[1])")
        }

        if lower.first == "clip",
           parts.count >= 2,
           isValidSlug(parts[1]) {
            return canonicalURL(path: "/clip/\(parts[1])")
        }

        if lower.first == "live",
           parts.count >= 2,
           isValidSlug(parts[1]) {
            return canonicalURL(
                path: "/watch",
                queryItems: [
                    URLQueryItem(name: "v", value: parts[1])
                ]
            )
        }

        if lower.first == "playlist",
           let id = queryValue("list", in: queryItems),
           isValidSlug(id) {
            return canonicalURL(
                path: "/playlist",
                queryItems: [URLQueryItem(name: "list", value: id)]
            )
        }

        if let first = lower.first,
           ["channel", "user", "c"].contains(first),
           parts.count >= 2,
           isValidSlug(parts[1]) {
            return canonicalURL(
                path: channelPath(
                    prefix: parts[0],
                    slug: parts[1],
                    tail: parts.dropFirst(2).first
                )
            )
        }

        if let handle = parts.first,
           isValidHandle(handle) {
            return canonicalURL(
                path: channelPath(
                    prefix: handle,
                    slug: nil,
                    tail: parts.dropFirst().first
                )
            )
        }

        return nil
    }

    func extract(from context: SearchResultResolverContext) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByKey: [String: Int] = [:]

        for anchor in context.anchors {
            guard results.count < context.limit,
                  let absolute = context.resolvedURL(for: anchor),
                  let target = Self.queueURL(from: absolute),
                  let key = Self.resultKey(for: target) else {
                continue
            }

            let title = context.title(for: anchor, fallbackURL: target)
            SearchResultResolverSupport.appendUniqueResult(
                title: title,
                url: target,
                id: key,
                sitePrefix: "youtube",
                results: &results,
                indexByID: &indexByKey,
                metadata: metadata(
                    key: key,
                    title: title,
                    target: target,
                    contributorMetadata: context.contributorMetadata(
                        for: anchor
                    )
                )
            )
        }

        return results
    }

    private func metadata(
        key: String,
        title: String,
        target: URL,
        contributorMetadata: [String: String]
    ) -> [String: String] {
        var metadata = [
            "id": key,
            "category": "youtube",
            "title": title,
            "search_title": title
        ]
        let components = URLComponents(
            url: target,
            resolvingAgainstBaseURL: false
        )
        let queryItems = components?.queryItems ?? []
        let parts = target.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        let lower = parts.map { $0.lowercased() }
        if lower.first == "watch",
           let videoID = Self.queryValue("v", in: queryItems) {
            metadata["id"] = videoID
            metadata["video_id"] = videoID
            metadata["media_id"] = videoID
            metadata["type"] = "video"
            metadata["media_type"] = "video"
        } else if lower.first == "shorts", parts.count >= 2 {
            metadata["id"] = parts[1]
            metadata["video_id"] = parts[1]
            metadata["media_id"] = parts[1]
            metadata["type"] = "short"
            metadata["media_type"] = "video"
        } else if lower.first == "clip", parts.count >= 2 {
            metadata["id"] = parts[1]
            metadata["clip_id"] = parts[1]
            metadata["media_id"] = parts[1]
            metadata["type"] = "clip"
            metadata["media_type"] = "video"
        } else if lower.first == "playlist",
                  let playlistID = Self.queryValue(
                      "list",
                      in: queryItems
                  ) {
            metadata["id"] = playlistID
            metadata["playlist_id"] = playlistID
            metadata["gallery_id"] = playlistID
            metadata["series"] = playlistID
            metadata["type"] = "playlist"
        } else if let first = parts.first,
                  first.hasPrefix("@") {
            let handle = first.trimmingCharacters(
                in: CharacterSet(charactersIn: "@")
            )
            metadata["id"] = handle
            metadata["handle"] = first
            metadata["username"] = first
            metadata["user"] = first
            metadata["channel"] = first
            metadata["type"] = "channel"
        } else if let first = lower.first,
                  ["channel", "user", "c"].contains(first),
                  parts.count >= 2 {
            metadata["id"] = parts[1]
            if first == "channel" {
                metadata["channel_id"] = parts[1]
            } else {
                metadata["username"] = parts[1]
            }
            metadata["user"] = parts[1]
            metadata["channel"] = parts[1]
            metadata["type"] = "channel"
        }
        metadata.merge(contributorMetadata) { current, _ in current }
        return DownloadMetadata.clean(metadata)
    }

    private static func resultKey(for url: URL) -> String? {
        guard let components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        ) else {
            return nil
        }
        let queryItems = components.queryItems ?? []
        let parts = url.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        let lower = parts.map { $0.lowercased() }

        if lower.first == "watch",
           let id = queryValue("v", in: queryItems) {
            return "video-\(id)"
        }
        if lower.first == "shorts", parts.count >= 2 {
            return "video-\(parts[1])"
        }
        if lower.first == "clip", parts.count >= 2 {
            return "clip-\(parts[1])"
        }
        if lower.first == "playlist",
           let id = queryValue("list", in: queryItems) {
            return "playlist-\(id)"
        }
        if let first = parts.first, first.hasPrefix("@") {
            return "channel-\(url.path.lowercased())"
        }
        if let first = lower.first,
           ["channel", "user", "c"].contains(first) {
            return "channel-\(url.path.lowercased())"
        }
        return nil
    }

    private static func channelPath(
        prefix: String,
        slug: String?,
        tail: String?
    ) -> String {
        var parts = slug == nil ? [prefix] : [prefix, slug!]
        if let tail, isChannelTab(tail) {
            parts.append(tail)
        }
        return "/" + parts.joined(separator: "/")
    }

    private static func canonicalURL(
        path: String,
        queryItems: [URLQueryItem]? = nil
    ) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.youtube.com"
        components.path = path
        components.queryItems = queryItems
        return components.url
    }

    private static func isShortHost(_ host: String) -> Bool {
        host == "youtu.be" ||
            host == "www.youtu.be" ||
            host == "youtu.test" ||
            host == "www.youtu.test"
    }

    private static func isYewtuHost(_ host: String) -> Bool {
        host == "yewtu.be" ||
            host == "yewtu.test" ||
            host.hasSuffix(".yewtu.be") ||
            host.hasSuffix(".yewtu.test")
    }

    private static func isValidSlug(_ value: String) -> Bool {
        !value.isEmpty &&
            value.range(
                of: #"^[A-Za-z0-9][A-Za-z0-9._-]*$"#,
                options: .regularExpression
            ) != nil
    }

    private static func isValidHandle(_ value: String) -> Bool {
        value.range(
            of: #"^@[A-Za-z0-9][A-Za-z0-9._-]*$"#,
            options: .regularExpression
        ) != nil
    }

    private static func isChannelTab(_ value: String) -> Bool {
        [
            "featured", "videos", "shorts", "streams", "live",
            "playlists", "community", "releases", "podcasts"
        ].contains(value.lowercased())
    }

    private static func isYewtuReservedPath(_ value: String) -> Bool {
        [
            "channel", "c", "clip", "embed", "feed", "hashtag",
            "live", "playlist", "playlists", "redirect", "results",
            "shorts", "user", "watch"
        ].contains(value.lowercased()) || value.hasPrefix("@")
    }

    private static func queryValue(
        _ name: String,
        in items: [URLQueryItem]
    ) -> String? {
        items.first {
            $0.name.lowercased() == name.lowercased()
        }?.value
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
}
