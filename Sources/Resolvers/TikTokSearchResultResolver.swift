import Foundation

struct TikTokSearchResultResolver: SearchResultResolving {
    func supports(_ baseURL: URL) -> Bool {
        guard let host = baseURL.host?.lowercased() else { return false }
        return Self.isSupportedHost(host)
    }

    static func isSupportedHost(_ host: String) -> Bool {
        host == "tiktok.com" ||
            host == "www.tiktok.com" ||
            host == "m.tiktok.com" ||
            host == "douyin.com" ||
            host == "www.douyin.com" ||
            host == "tiktok.test" ||
            host == "www.tiktok.test" ||
            host == "douyin.test" ||
            host == "www.douyin.test" ||
            host.hasSuffix(".tiktok.com") ||
            host.hasSuffix(".douyin.com") ||
            host.hasSuffix(".tiktok.test") ||
            host.hasSuffix(".douyin.test")
    }

    static func dataAttributeLinkValue(
        in attributes: [String: String],
        baseURL: URL?
    ) -> String? {
        guard let host = baseURL?.host?.lowercased(),
              isSupportedHost(host) else {
            return nil
        }
        if let id = dataAttributeVideoID(in: attributes),
           dataAttributeLooksLikeVideoCard(attributes) {
            if !host.contains("douyin"),
               let username = dataAttributeUsername(in: attributes) {
                return "/@\(username)/video/\(id)"
            }
            return "/video/\(id)"
        }
        if let username = dataAttributeUsername(in: attributes),
           dataAttributeLooksLikeProfileCard(attributes) {
            return host.contains("douyin")
                ? "/user/\(username)"
                : "/@\(username)"
        }
        return nil
    }

    func extract(from context: SearchResultResolverContext) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByID: [String: Int] = [:]

        for anchor in context.anchors {
            guard results.count < context.limit,
                  let absolute = context.resolvedURL(for: anchor),
                  let target = TikTokResolver.canonicalContentURL(
                      from: absolute
                  ) else {
                continue
            }

            let id: String
            let fallback: String
            if let videoID = TikTokResolver.videoID(from: target) {
                id = "video:\(videoID)"
                fallback = "TikTok \(videoID)"
            } else if let username = TikTokResolver.profileUsername(
                from: target
            ) {
                id = "profile:\(username.lowercased())"
                fallback = "@\(username)"
            } else {
                continue
            }

            let title = context.title(for: anchor, fallback: fallback)
            let metadataID = id.hasPrefix("video:")
                ? String(id.dropFirst("video:".count))
                : String(id.dropFirst("profile:".count))
            let kind = id.hasPrefix("video:") ? "video" : "profile"
            SearchResultResolverSupport.appendUniqueResult(
                title: title,
                url: target,
                id: id,
                sitePrefix: "tiktok",
                results: &results,
                indexByID: &indexByID,
                metadata: metadata(
                    id: metadataID,
                    kind: kind,
                    title: title,
                    contributorMetadata: context.contributorMetadata(
                        for: anchor,
                        fallbackName: nil,
                        fallbackUsername: username(from: target)
                    )
                )
            )
        }

        return results
    }

    private func metadata(
        id: String,
        kind: String,
        title: String,
        contributorMetadata: [String: String]
    ) -> [String: String] {
        var metadata = [
            "id": id,
            "category": "tiktok",
            "type": kind,
            "title": title,
            "search_title": title
        ]
        if kind == "video" {
            metadata["video_id"] = id
            metadata["media_id"] = id
            metadata["media_type"] = "video"
        } else {
            metadata["user_id"] = id
        }
        metadata.merge(contributorMetadata) { current, _ in current }
        return DownloadMetadata.clean(metadata)
    }

    private func username(from url: URL) -> String? {
        TikTokResolver.profileUsername(from: url) ?? pathUsername(from: url)
    }

    private func pathUsername(from url: URL) -> String? {
        let parts = url.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        return parts.first(where: { $0.hasPrefix("@") })
            .map { String($0.dropFirst()) }
    }

    private static func dataAttributeVideoID(
        in attributes: [String: String]
    ) -> String? {
        let keys = [
            "data-video-id", "data-videoid", "data-item-id",
            "data-itemid", "data-aweme-id", "data-awemeid",
            "video-id", "item-id"
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
               containsAnyOf: [
                   "tiktok", "douyin", "video", "photo"
               ]
           ) {
            return id
        }
        return nil
    }

    private static func dataAttributeUsername(
        in attributes: [String: String]
    ) -> String? {
        let keys = [
            "data-unique-id", "data-uniqueid", "data-username",
            "data-author-username", "data-user-username", "username"
        ]
        return firstAttributeValue(
            in: attributes,
            keys: keys,
            matching: isValidUsername
        )
    }

    private static func dataAttributeLooksLikeVideoCard(
        _ attributes: [String: String]
    ) -> Bool {
        let keys = [
            "data-video-id", "data-videoid", "data-item-id",
            "data-itemid", "data-aweme-id", "data-awemeid",
            "video-id", "item-id"
        ]
        if keys.contains(where: {
            attributes[$0]?.trimmed.isEmpty == false
        }) {
            return true
        }
        return typeHint(
            in: attributes,
            containsAnyOf: ["tiktok", "douyin", "video", "photo"]
        )
    }

    private static func dataAttributeLooksLikeProfileCard(
        _ attributes: [String: String]
    ) -> Bool {
        typeHint(
            in: attributes,
            containsAnyOf: ["user", "profile", "author", "creator"]
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
            of: #"^[0-9]{6,}$"#,
            options: .regularExpression
        ) != nil
    }

    private static func isValidUsername(_ value: String) -> Bool {
        value.range(
            of: #"^[A-Za-z0-9._-]{1,80}$"#,
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
}
