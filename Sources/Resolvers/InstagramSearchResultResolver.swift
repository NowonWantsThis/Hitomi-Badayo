import Foundation

struct InstagramSearchResultResolver: SearchResultResolving {
    func supports(_ baseURL: URL) -> Bool {
        guard let host = baseURL.host?.lowercased() else { return false }
        return Self.isSupportedHost(host)
    }

    static func isSupportedHost(_ host: String) -> Bool {
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

    static func dataAttributeLinkValue(
        in attributes: [String: String],
        baseURL: URL?
    ) -> String? {
        guard let host = baseURL?.host?.lowercased(),
              isSupportedHost(host) else {
            return nil
        }

        if let id = dataAttributeShortcode(in: attributes),
           dataAttributeLooksLikeMediaCard(attributes) {
            return "/\(dataAttributeMediaKind(in: attributes))/\(id)/"
        }
        if let storyID = dataAttributeStoryID(in: attributes),
           let username = dataAttributeUsername(in: attributes),
           dataAttributeLooksLikeStoryCard(attributes) {
            return "/stories/\(username)/\(storyID)/"
        }
        return nil
    }

    func extract(from context: SearchResultResolverContext) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByID: [String: Int] = [:]

        for anchor in context.anchors {
            guard results.count < context.limit,
                  let absolute = context.resolvedURL(for: anchor),
                  let target = InstagramResolver.canonicalInputURL(
                      for: absolute
                  ),
                  let key = Self.resultKey(for: target) else {
                continue
            }

            let title = context.title(
                for: anchor,
                fallback: "Instagram \(key)"
            )
            SearchResultResolverSupport.appendUniqueResult(
                title: title,
                url: target,
                id: key,
                sitePrefix: "instagram",
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
            "category": "instagram",
            "title": title,
            "search_title": title
        ]
        if let shortcode = InstagramResolver.shortcode(from: target) {
            metadata["id"] = shortcode
            metadata["shortcode"] = shortcode
            metadata["media_id"] = shortcode
            metadata["gallery_id"] = shortcode
            metadata["type"] = Self.mediaKind(from: target)
            metadata["media_type"] = "media"
        } else if let storyID = InstagramResolver.storyID(from: target) {
            metadata["id"] = storyID
            metadata["story_id"] = storyID
            metadata["media_id"] = storyID
            metadata["type"] = "story"
            metadata["media_type"] = "story"
            if let username = Self.storyUsername(from: target) {
                metadata["username"] = username
                metadata["user"] = username
            }
        }
        metadata.merge(contributorMetadata) { current, _ in current }
        return DownloadMetadata.clean(metadata)
    }

    private static func resultKey(for url: URL) -> String? {
        if let shortcode = InstagramResolver.shortcode(from: url) {
            return "media-\(shortcode)"
        }
        if let storyID = InstagramResolver.storyID(from: url) {
            return "story-\(storyID)"
        }
        return nil
    }

    private static func mediaKind(from url: URL) -> String {
        url.path.split(separator: "/", omittingEmptySubsequences: true)
            .first
            .map { String($0).lowercased() } ?? "media"
    }

    private static func storyUsername(from url: URL) -> String? {
        let parts = url.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        guard parts.count >= 3,
              parts[0].lowercased() == "stories" else {
            return nil
        }
        return parts[1]
    }

    private static func dataAttributeShortcode(
        in attributes: [String: String]
    ) -> String? {
        let keys = [
            "data-shortcode", "data-media-shortcode",
            "data-post-shortcode", "data-reel-shortcode",
            "data-tv-shortcode", "shortcode"
        ]
        if let value = firstAttributeValue(
            in: attributes,
            keys: keys,
            matching: isValidShortcode
        ) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           isValidShortcode(id),
           typeHint(
               in: attributes,
               containsAnyOf: ["post", "media", "reel", "tv"]
           ) {
            return id
        }
        return nil
    }

    private static func dataAttributeStoryID(
        in attributes: [String: String]
    ) -> String? {
        let keys = ["data-story-id", "data-storyid", "story-id"]
        if let value = firstAttributeValue(
            in: attributes,
            keys: keys,
            matching: isNumericID
        ) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           isNumericID(id),
           typeHint(in: attributes, containsAnyOf: ["story"]) {
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
                "data-username", "data-user-username",
                "data-owner-username", "username"
            ],
            matching: isValidUsername
        )
    }

    private static func dataAttributeMediaKind(
        in attributes: [String: String]
    ) -> String {
        let hint = [
            "data-type", "data-kind", "data-content-type", "class", "role"
        ]
            .compactMap { attributes[$0]?.lowercased() }
            .joined(separator: " ")
        if hint.contains("reel") {
            return "reel"
        }
        if hint.contains("tv") {
            return "tv"
        }
        return "p"
    }

    private static func dataAttributeLooksLikeMediaCard(
        _ attributes: [String: String]
    ) -> Bool {
        let keys = [
            "data-shortcode", "data-media-shortcode",
            "data-post-shortcode", "data-reel-shortcode",
            "data-tv-shortcode", "shortcode"
        ]
        if keys.contains(where: {
            attributes[$0]?.trimmed.isEmpty == false
        }) {
            return true
        }
        return typeHint(
            in: attributes,
            containsAnyOf: ["post", "media", "reel", "tv"]
        )
    }

    private static func dataAttributeLooksLikeStoryCard(
        _ attributes: [String: String]
    ) -> Bool {
        if ["data-story-id", "data-storyid", "story-id"].contains(
            where: { attributes[$0]?.trimmed.isEmpty == false }
        ) {
            return true
        }
        return typeHint(in: attributes, containsAnyOf: ["story"])
    }

    private static func isValidShortcode(_ value: String) -> Bool {
        value.range(
            of: #"^[A-Za-z0-9_-]{2,}$"#,
            options: .regularExpression
        ) != nil
    }

    private static func isNumericID(_ value: String) -> Bool {
        value.range(
            of: #"^[0-9]{4,}$"#,
            options: .regularExpression
        ) != nil
    }

    private static func isValidUsername(_ value: String) -> Bool {
        value.range(
            of: #"^[A-Za-z0-9._]{1,80}$"#,
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
