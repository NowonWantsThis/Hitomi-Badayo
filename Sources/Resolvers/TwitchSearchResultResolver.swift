import Foundation

struct TwitchSearchResultResolver: SearchResultResolving {
    func supports(_ baseURL: URL) -> Bool {
        guard let host = baseURL.host?.lowercased() else { return false }
        return Self.isSupportedHost(host)
    }

    static func isSupportedHost(_ host: String) -> Bool {
        host == "twitch.tv" ||
            host == "www.twitch.tv" ||
            host == "m.twitch.tv" ||
            host == "clips.twitch.tv" ||
            host == "twitch.test" ||
            host == "www.twitch.test" ||
            host == "m.twitch.test" ||
            host == "clips.twitch.test"
    }

    static func dataAttributeLinkValue(
        in attributes: [String: String],
        baseURL: URL?
    ) -> String? {
        guard let host = baseURL?.host?.lowercased(),
              isSupportedHost(host) else {
            return nil
        }

        if let id = dataAttributeVODID(in: attributes),
           dataAttributeLooksLikeVODCard(attributes) {
            return "/videos/\(id)"
        }
        if let slug = dataAttributeClipSlug(in: attributes),
           dataAttributeLooksLikeClipCard(attributes) {
            if let username = dataAttributeUsername(in: attributes) {
                return "/\(username)/clip/\(slug)"
            }
            return "https://\(clipsHost(for: host))/\(slug)"
        }
        return nil
    }

    static func mediaURL(from url: URL) -> URL? {
        let host = url.host?.lowercased() ?? ""
        let parts = url.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        let lower = parts.map { $0.lowercased() }

        if host == "clips.twitch.tv" || host == "clips.twitch.test" {
            return parts.isEmpty ? nil : url
        }
        if lower.first == "videos", parts.count >= 2 {
            return url
        }
        if let marker = lower.firstIndex(of: "clip"),
           marker + 1 < parts.count {
            return url
        }
        return nil
    }

    func extract(from context: SearchResultResolverContext) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByID: [String: Int] = [:]

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
                sitePrefix: "twitch",
                results: &results,
                indexByID: &indexByID,
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
            "category": "twitch",
            "title": title,
            "search_title": title
        ]
        if let vodID = TwitchVODResolver.vodID(from: target) {
            metadata["id"] = vodID
            metadata["vod_id"] = vodID
            metadata["video_id"] = vodID
            metadata["media_id"] = vodID
            metadata["type"] = "vod"
            metadata["media_type"] = "video"
        } else if let clipID = Self.clipSlug(from: target) {
            metadata["id"] = clipID
            metadata["clip_id"] = clipID
            metadata["media_id"] = clipID
            metadata["type"] = "clip"
            metadata["media_type"] = "video"
            if let username = Self.clipUsername(from: target) {
                metadata["username"] = username
                metadata["user"] = username
            }
        }
        metadata.merge(contributorMetadata) { current, _ in current }
        return DownloadMetadata.clean(metadata)
    }

    private static func queueURL(from url: URL) -> URL? {
        if let vodID = TwitchVODResolver.vodID(from: url) {
            return TwitchVODResolver.canonicalURL(
                vodID: vodID,
                sourceURL: url
            )
        }
        guard let host = url.host?.lowercased(),
              isSupportedHost(host),
              var components = URLComponents(
                  url: url,
                  resolvingAgainstBaseURL: false
              ) else {
            return nil
        }
        components.queryItems = nil
        components.fragment = nil
        if host == "m.twitch.tv" {
            components.scheme = "https"
            components.host = "www.twitch.tv"
        } else if host == "m.twitch.test" {
            components.scheme = "https"
            components.host = "www.twitch.test"
        }
        guard let clean = components.url,
              clipSlug(from: clean) != nil else {
            return nil
        }
        return clean
    }

    private static func resultKey(for url: URL) -> String? {
        if let vodID = TwitchVODResolver.vodID(from: url) {
            return "vod-\(vodID)"
        }
        if let slug = clipSlug(from: url) {
            return "clip-\(slug.lowercased())"
        }
        return nil
    }

    private static func clipSlug(from url: URL) -> String? {
        guard let host = url.host?.lowercased(),
              isSupportedHost(host) else {
            return nil
        }
        let parts = url.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        let lower = parts.map { $0.lowercased() }

        if host == "clips.twitch.tv" || host == "clips.twitch.test" {
            guard let slug = parts.first,
                  isValidSlug(slug) else {
                return nil
            }
            return slug
        }

        if let marker = lower.firstIndex(of: "clip"),
           marker + 1 < parts.count,
           isValidSlug(parts[marker + 1]) {
            return parts[marker + 1]
        }
        return nil
    }

    private static func clipUsername(from url: URL) -> String? {
        let parts = url.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        guard parts.count >= 3,
              parts[1].lowercased() == "clip" else {
            return nil
        }
        return parts[0]
    }

    private static func dataAttributeVODID(
        in attributes: [String: String]
    ) -> String? {
        let keys = [
            "data-vod-id", "data-vodid", "data-video-id",
            "data-videoid", "vod-id", "video-id"
        ]
        if let value = firstAttributeValue(
            in: attributes,
            keys: keys,
            matching: isNumericID
        ) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           isNumericID(id),
           typeHint(in: attributes, containsAnyOf: ["vod", "video"]) {
            return id
        }
        return nil
    }

    private static func dataAttributeClipSlug(
        in attributes: [String: String]
    ) -> String? {
        let keys = [
            "data-clip-id", "data-clipid", "data-clip-slug",
            "data-clipslug", "clip-id", "clip-slug"
        ]
        if let value = firstAttributeValue(
            in: attributes,
            keys: keys,
            matching: isValidSlug
        ) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           isValidSlug(id),
           typeHint(in: attributes, containsAnyOf: ["clip"]) {
            return id
        }
        return nil
    }

    private static func dataAttributeUsername(
        in attributes: [String: String]
    ) -> String? {
        firstAttributeValue(
            in: attributes,
            keys: [
                "data-channel-login", "data-channel", "data-username",
                "data-user-login", "username"
            ],
            matching: isValidSlug
        )
    }

    private static func dataAttributeLooksLikeVODCard(
        _ attributes: [String: String]
    ) -> Bool {
        let keys = [
            "data-vod-id", "data-vodid", "data-video-id",
            "data-videoid", "vod-id", "video-id"
        ]
        if keys.contains(where: {
            attributes[$0]?.trimmed.isEmpty == false
        }) {
            return true
        }
        return typeHint(in: attributes, containsAnyOf: ["vod", "video"])
    }

    private static func dataAttributeLooksLikeClipCard(
        _ attributes: [String: String]
    ) -> Bool {
        let keys = [
            "data-clip-id", "data-clipid", "data-clip-slug",
            "data-clipslug", "clip-id", "clip-slug"
        ]
        if keys.contains(where: {
            attributes[$0]?.trimmed.isEmpty == false
        }) {
            return true
        }
        return typeHint(in: attributes, containsAnyOf: ["clip"])
    }

    private static func clipsHost(for host: String) -> String {
        host.hasSuffix(".test") ? "clips.twitch.test" : "clips.twitch.tv"
    }

    private static func isNumericID(_ value: String) -> Bool {
        value.range(
            of: #"^[0-9]{4,}$"#,
            options: .regularExpression
        ) != nil
    }

    private static func isValidSlug(_ value: String) -> Bool {
        !value.isEmpty &&
            value.range(
                of: #"^[A-Za-z0-9][A-Za-z0-9_-]*$"#,
                options: .regularExpression
            ) != nil
    }

    private static func firstAttributeValue(
        in attributes: [String: String],
        keys: [String],
        matching predicate: (String) -> Bool
    ) -> String? {
        for key in keys {
            if let value = attributes[key]?.trimmed, predicate(value) {
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
}
