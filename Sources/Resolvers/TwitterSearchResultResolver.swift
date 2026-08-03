import Foundation

struct TwitterSearchResultResolver: SearchResultResolving {
    func supports(_ baseURL: URL) -> Bool {
        guard let host = baseURL.host?.lowercased() else { return false }
        return Self.isSupportedHost(host)
    }

    static func isSupportedHost(_ host: String) -> Bool {
        host == "twitter.com" ||
            host == "www.twitter.com" ||
            host == "mobile.twitter.com" ||
            host == "x.com" ||
            host == "www.x.com" ||
            host == "twitter.test" ||
            host == "www.twitter.test" ||
            host == "x.test" ||
            host == "www.x.test"
    }

    static func dataAttributeLinkValue(
        in attributes: [String: String],
        baseURL: URL?
    ) -> String? {
        guard let host = baseURL?.host?.lowercased(),
              isSupportedHost(host) else {
            return nil
        }
        if let id = dataAttributeTweetID(in: attributes),
           dataAttributeLooksLikeTweetCard(attributes) {
            if let username = dataAttributeUsername(in: attributes) {
                return "/\(username)/status/\(id)"
            }
            return "/i/web/status/\(id)"
        }
        if let id = dataAttributeSpaceID(in: attributes),
           dataAttributeLooksLikeSpaceCard(attributes) {
            return "/i/spaces/\(id)"
        }
        if let id = dataAttributeBroadcastID(in: attributes),
           dataAttributeLooksLikeBroadcastCard(attributes) {
            return "/i/broadcasts/\(id)"
        }
        if let id = dataAttributeUserID(in: attributes),
           dataAttributeLooksLikeUserCard(attributes) {
            return "/i/user/\(id)"
        }
        return nil
    }

    func extract(from context: SearchResultResolverContext) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByKey: [String: Int] = [:]

        for anchor in context.anchors {
            guard results.count < context.limit,
                  let absolute = context.resolvedURL(for: anchor) else {
                continue
            }

            if let id = TwitterResolver.tweetID(from: absolute),
               let target = Self.cleanedURL(absolute) {
                append(
                    anchor: anchor,
                    id: id,
                    kind: "tweet",
                    fallback: "Tweet \(id)",
                    target: target,
                    sitePrefix: "tweet",
                    context: context,
                    results: &results,
                    indexByKey: &indexByKey
                )
                continue
            }

            if let id = Self.spaceID(from: absolute),
               let target = Self.spaceURL(
                   id: id,
                   sourceURL: absolute
               ) {
                append(
                    anchor: anchor,
                    id: id,
                    kind: "space",
                    fallback: "Space \(id)",
                    target: target,
                    sitePrefix: "space",
                    context: context,
                    results: &results,
                    indexByKey: &indexByKey
                )
                continue
            }

            if let id = Self.broadcastID(from: absolute),
               let target = Self.broadcastURL(
                   id: id,
                   sourceURL: absolute
               ) {
                append(
                    anchor: anchor,
                    id: id,
                    kind: "broadcast",
                    fallback: "Broadcast \(id)",
                    target: target,
                    sitePrefix: "broadcast",
                    context: context,
                    results: &results,
                    indexByKey: &indexByKey
                )
                continue
            }

            if let id = Self.userID(from: absolute),
               let target = Self.userURL(
                   id: id,
                   sourceURL: absolute
               ) {
                append(
                    anchor: anchor,
                    id: id,
                    kind: "user",
                    fallback: "User \(id)",
                    target: target,
                    sitePrefix: "user",
                    context: context,
                    results: &results,
                    indexByKey: &indexByKey
                )
            }
        }

        return results
    }

    private func append(
        anchor: AnchorEntry,
        id: String,
        kind: String,
        fallback: String,
        target: URL,
        sitePrefix: String,
        context: SearchResultResolverContext,
        results: inout [SearchResultLink],
        indexByKey: inout [String: Int]
    ) {
        let title = context.title(for: anchor, fallback: fallback)
        SearchResultResolverSupport.appendUniqueResult(
            title: title,
            url: target,
            id: "\(kind)-\(id)",
            sitePrefix: sitePrefix,
            results: &results,
            indexByID: &indexByKey,
            metadata: metadata(
                id: id,
                kind: kind,
                title: title,
                contributorMetadata: context.contributorMetadata(
                    for: anchor,
                    fallbackName: nil,
                    fallbackUsername: Self.username(from: target)
                )
            )
        )
    }

    private func metadata(
        id: String,
        kind: String,
        title: String,
        contributorMetadata: [String: String]
    ) -> [String: String] {
        var metadata = [
            "id": id,
            "category": "twitter",
            "type": kind,
            "title": title,
            "search_title": title
        ]
        if kind == "tweet" {
            metadata["tweet_id"] = id
            metadata["status_id"] = id
            metadata["media_id"] = id
        } else if kind == "space" {
            metadata["space_id"] = id
            metadata["media_id"] = id
            metadata["media_type"] = "audio"
        } else if kind == "broadcast" {
            metadata["broadcast_id"] = id
            metadata["media_id"] = id
            metadata["media_type"] = "video"
            metadata["live_status"] = "broadcast"
        } else {
            metadata["user_id"] = id
        }
        metadata.merge(contributorMetadata) { current, _ in current }
        return DownloadMetadata.clean(metadata)
    }

    private static func spaceID(from url: URL) -> String? {
        guard let host = url.host?.lowercased(),
              isSupportedHost(host) else {
            return nil
        }
        let parts = url.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        let lower = parts.map { $0.lowercased() }
        if let marker = lower.firstIndex(of: "spaces"),
           marker + 1 < parts.count,
           isValidPathSlug(parts[marker + 1]) {
            return parts[marker + 1]
        }
        return nil
    }

    private static func spaceURL(id: String, sourceURL: URL) -> URL? {
        cleanedURL(sourceURL, path: "/i/spaces/\(id)")
    }

    private static func broadcastID(from url: URL) -> String? {
        guard let host = url.host?.lowercased(),
              isSupportedHost(host) else {
            return nil
        }
        let parts = url.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        guard parts.count >= 3,
              parts[0].lowercased() == "i",
              parts[1].lowercased() == "broadcasts",
              isValidPathSlug(parts[2]) else {
            return nil
        }
        return parts[2]
    }

    private static func broadcastURL(
        id: String,
        sourceURL: URL
    ) -> URL? {
        cleanedURL(sourceURL, path: "/i/broadcasts/\(id)")
    }

    private static func userID(from url: URL) -> String? {
        guard let host = url.host?.lowercased(),
              isSupportedHost(host) else {
            return nil
        }
        let parts = url.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        guard parts.count >= 3,
              parts[0].lowercased() == "i",
              parts[1].lowercased() == "user" else {
            return nil
        }
        let id = parts[2].trimmed
        return id.range(
            of: #"^[0-9]+$"#,
            options: .regularExpression
        ) != nil ? id : nil
    }

    private static func userURL(id: String, sourceURL: URL) -> URL? {
        cleanedURL(sourceURL, path: "/i/user/\(id)")
    }

    private static func username(from url: URL) -> String? {
        let parts = url.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        guard parts.count >= 3,
              ["status", "statuses"].contains(
                  parts[1].lowercased()
              ) else {
            return nil
        }
        return parts[0]
    }

    private static func dataAttributeTweetID(
        in attributes: [String: String]
    ) -> String? {
        let keys = [
            "data-tweet-id", "data-tweetid", "data-status-id",
            "data-statusid", "data-conversation-id",
            "data-conversationid", "tweet-id", "status-id"
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
           typeHint(
               in: attributes,
               containsAnyOf: ["tweet", "status", "post"]
           ) {
            return id
        }
        return nil
    }

    private static func dataAttributeSpaceID(
        in attributes: [String: String]
    ) -> String? {
        let keys = ["data-space-id", "data-spaceid", "space-id"]
        if let value = firstAttributeValue(
            in: attributes,
            keys: keys,
            matching: isValidPathSlug
        ) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           isValidPathSlug(id),
           typeHint(in: attributes, containsAnyOf: ["space"]) {
            return id
        }
        return nil
    }

    private static func dataAttributeBroadcastID(
        in attributes: [String: String]
    ) -> String? {
        let keys = [
            "data-broadcast-id", "data-broadcastid", "broadcast-id"
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
           typeHint(in: attributes, containsAnyOf: ["broadcast"]) {
            return id
        }
        return nil
    }

    private static func dataAttributeUserID(
        in attributes: [String: String]
    ) -> String? {
        let keys = ["data-user-id", "data-userid", "user-id"]
        if let value = firstAttributeValue(
            in: attributes,
            keys: keys,
            matching: isNumericID
        ) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           isNumericID(id),
           typeHint(
               in: attributes,
               containsAnyOf: ["user", "profile", "account"]
           ) {
            return id
        }
        return nil
    }

    private static func dataAttributeUsername(
        in attributes: [String: String]
    ) -> String? {
        let keys = [
            "data-screen-name", "data-screenname", "data-username",
            "data-author-username", "username", "screen-name"
        ]
        return firstAttributeValue(
            in: attributes,
            keys: keys,
            matching: isValidUsername
        )
    }

    private static func dataAttributeLooksLikeTweetCard(
        _ attributes: [String: String]
    ) -> Bool {
        let keys = [
            "data-tweet-id", "data-tweetid", "data-status-id",
            "data-statusid", "data-conversation-id",
            "data-conversationid", "tweet-id", "status-id"
        ]
        if keys.contains(where: {
            attributes[$0]?.trimmed.isEmpty == false
        }) {
            return true
        }
        return typeHint(
            in: attributes,
            containsAnyOf: ["tweet", "status", "post"]
        )
    }

    private static func dataAttributeLooksLikeSpaceCard(
        _ attributes: [String: String]
    ) -> Bool {
        let keys = ["data-space-id", "data-spaceid", "space-id"]
        if keys.contains(where: {
            attributes[$0]?.trimmed.isEmpty == false
        }) {
            return true
        }
        return typeHint(in: attributes, containsAnyOf: ["space"])
    }

    private static func dataAttributeLooksLikeBroadcastCard(
        _ attributes: [String: String]
    ) -> Bool {
        let keys = [
            "data-broadcast-id", "data-broadcastid", "broadcast-id"
        ]
        if keys.contains(where: {
            attributes[$0]?.trimmed.isEmpty == false
        }) {
            return true
        }
        return typeHint(in: attributes, containsAnyOf: ["broadcast"])
    }

    private static func dataAttributeLooksLikeUserCard(
        _ attributes: [String: String]
    ) -> Bool {
        typeHint(
            in: attributes,
            containsAnyOf: ["user", "profile", "account"]
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

    private static func isNumericID(_ value: String) -> Bool {
        value.range(
            of: #"^[0-9]{4,}$"#,
            options: .regularExpression
        ) != nil
    }

    private static func isValidUsername(_ value: String) -> Bool {
        value.range(
            of: #"^[A-Za-z0-9_]{1,20}$"#,
            options: .regularExpression
        ) != nil
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
        let values = keys.compactMap { attributes[$0]?.lowercased() }
        return values.contains { value in
            needles.contains { value.contains($0) }
        }
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
}
