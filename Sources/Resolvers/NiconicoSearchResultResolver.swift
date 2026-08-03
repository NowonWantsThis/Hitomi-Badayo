import Foundation

struct NiconicoSearchResultResolver: SearchResultResolving {
    func supports(_ baseURL: URL) -> Bool {
        guard let host = baseURL.host?.lowercased() else { return false }
        return Self.isSupportedHost(host)
    }

    static func isSupportedHost(_ host: String) -> Bool {
        host == "nico.ms" ||
            host == "www.nico.ms" ||
            host == "nicovideo.jp" ||
            host == "www.nicovideo.jp" ||
            host == "ch.nicovideo.jp" ||
            host == "live.nicovideo.jp" ||
            host == "niconico.com" ||
            host == "www.niconico.com" ||
            host == "nicovideo.test" ||
            host == "www.nicovideo.test" ||
            host == "ch.nicovideo.test" ||
            host == "live.nicovideo.test" ||
            host == "niconico.test" ||
            host == "www.niconico.test"
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
            return "https://\(webHost(for: host))/watch/\(id)"
        }
        if let id = dataAttributeLiveID(in: attributes),
           dataAttributeLooksLikeLiveCard(attributes) {
            return "https://\(liveHost(for: host))/watch/\(id)"
        }
        if let id = dataAttributeUserID(in: attributes),
           dataAttributeLooksLikeUserCard(attributes) {
            return "https://\(webHost(for: host))/user/\(id)"
        }
        if let id = dataAttributeChannelID(in: attributes),
           dataAttributeLooksLikeChannelCard(attributes) {
            return "https://\(channelHost(for: host))/\(id)"
        }
        return nil
    }

    static func mediaURL(from url: URL) -> URL? {
        guard let host = url.host?.lowercased() else {
            return nil
        }
        let parts = url.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        let lower = parts.map { $0.lowercased() }

        if host == "nico.ms" || host == "www.nico.ms" {
            guard let id = parts.first, !id.isEmpty else {
                return nil
            }
            var components = URLComponents()
            components.scheme = url.scheme ?? "https"
            components.host = "www.nicovideo.jp"
            components.path = "/watch/\(id)"
            return components.url
        }

        if let liveURL = NiconicoLiveResolver.canonicalInputURL(for: url) {
            return liveURL
        }

        if host == "live.nicovideo.jp" ||
            host == "live.nicovideo.test" {
            return lower.first == "watch" && parts.count >= 2
                ? url
                : nil
        }

        return lower.first == "watch" && parts.count >= 2 ? url : nil
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
                sitePrefix: "niconico",
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
            "category": "niconico",
            "title": title,
            "search_title": title
        ]
        if let videoID = NiconicoResolver.videoID(from: target) {
            metadata["id"] = videoID
            metadata["video_id"] = videoID
            metadata["media_id"] = videoID
            metadata["type"] = "video"
            metadata["media_type"] = "video"
        } else if let liveID = NiconicoLiveResolver.liveID(from: target) {
            metadata["id"] = liveID
            metadata["live_id"] = liveID
            metadata["media_id"] = liveID
            metadata["type"] = "live"
            metadata["media_type"] = "live"
        } else if let userID = NiconicoLiveResolver.userID(from: target) {
            metadata["id"] = userID
            metadata["user_id"] = userID
            metadata["type"] = "user"
        } else if let channelID = NiconicoLiveResolver.channelID(
            from: target
        ) {
            metadata["id"] = channelID
            metadata["channel_id"] = channelID
            metadata["type"] = "channel"
        }
        metadata.merge(contributorMetadata) { current, _ in current }
        return DownloadMetadata.clean(metadata)
    }

    private static func queueURL(from url: URL) -> URL? {
        if NiconicoResolver.videoID(from: url) != nil {
            return NiconicoResolver.canonicalURL(for: url)
        }
        guard let host = url.host?.lowercased(),
              isSupportedHost(host),
              let clean = cleanedURL(url) else {
            return nil
        }
        return mediaURL(from: clean)
    }

    private static func resultKey(for url: URL) -> String? {
        if let id = NiconicoResolver.videoID(from: url) {
            return "video-\(id)"
        }
        let parts = url.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        if let host = url.host?.lowercased(),
           host.hasPrefix("live."),
           parts.first?.lowercased() == "watch",
           parts.count >= 2 {
            return "live-\(parts[1])"
        }
        return URLIdentity.normalize(url.absoluteString)
    }

    private static func dataAttributeVideoID(
        in attributes: [String: String]
    ) -> String? {
        let keys = [
            "data-video-id", "data-videoid", "data-watch-id",
            "data-watchid", "video-id", "watch-id"
        ]
        if let value = firstAttributeValue(
            in: attributes,
            keys: keys,
            matching: isValidVideoID
        ) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           isValidVideoID(id),
           typeHint(
               in: attributes,
               containsAnyOf: ["video", "watch", "movie"]
           ) {
            return id
        }
        return nil
    }

    private static func dataAttributeLiveID(
        in attributes: [String: String]
    ) -> String? {
        let keys = [
            "data-live-id", "data-liveid", "data-program-id",
            "data-programid", "live-id"
        ]
        if let value = firstAttributeValue(
            in: attributes,
            keys: keys,
            matching: isValidLiveID
        ) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           isValidLiveID(id),
           typeHint(in: attributes, containsAnyOf: ["live", "program"]) {
            return id
        }
        return nil
    }

    private static func dataAttributeUserID(
        in attributes: [String: String]
    ) -> String? {
        let keys = [
            "data-user-id", "data-userid", "data-owner-id",
            "data-ownerid", "user-id"
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
               containsAnyOf: ["user", "profile", "owner"]
           ) {
            return id
        }
        return nil
    }

    private static func dataAttributeChannelID(
        in attributes: [String: String]
    ) -> String? {
        let keys = [
            "data-channel-id", "data-channelid", "data-channel-slug",
            "channel-id"
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
           typeHint(in: attributes, containsAnyOf: ["channel"]) {
            return id
        }
        return nil
    }

    private static func dataAttributeLooksLikeVideoCard(
        _ attributes: [String: String]
    ) -> Bool {
        let keys = [
            "data-video-id", "data-videoid", "data-watch-id",
            "data-watchid", "video-id", "watch-id"
        ]
        if keys.contains(where: {
            attributes[$0]?.trimmed.isEmpty == false
        }) {
            return true
        }
        return typeHint(
            in: attributes,
            containsAnyOf: ["video", "watch", "movie"]
        )
    }

    private static func dataAttributeLooksLikeLiveCard(
        _ attributes: [String: String]
    ) -> Bool {
        let keys = [
            "data-live-id", "data-liveid", "data-program-id",
            "data-programid", "live-id"
        ]
        if keys.contains(where: {
            attributes[$0]?.trimmed.isEmpty == false
        }) {
            return true
        }
        return typeHint(in: attributes, containsAnyOf: ["live", "program"])
    }

    private static func dataAttributeLooksLikeUserCard(
        _ attributes: [String: String]
    ) -> Bool {
        typeHint(
            in: attributes,
            containsAnyOf: ["user", "profile", "owner"]
        )
    }

    private static func dataAttributeLooksLikeChannelCard(
        _ attributes: [String: String]
    ) -> Bool {
        let keys = [
            "data-channel-id", "data-channelid", "data-channel-slug",
            "channel-id"
        ]
        if keys.contains(where: {
            attributes[$0]?.trimmed.isEmpty == false
        }) {
            return true
        }
        return typeHint(in: attributes, containsAnyOf: ["channel"])
    }

    private static func webHost(for host: String) -> String {
        host.hasSuffix(".test") ? "www.nicovideo.test" : "www.nicovideo.jp"
    }

    private static func liveHost(for host: String) -> String {
        host.hasSuffix(".test")
            ? "live.nicovideo.test"
            : "live.nicovideo.jp"
    }

    private static func channelHost(for host: String) -> String {
        host.hasSuffix(".test") ? "ch.nicovideo.test" : "ch.nicovideo.jp"
    }

    private static func isValidVideoID(_ value: String) -> Bool {
        value.range(
            of: #"^(?:sm|so|nm)?[0-9]+$"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    private static func isValidLiveID(_ value: String) -> Bool {
        value.range(
            of: #"^lv[0-9]+$"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    private static func isNumericID(_ value: String) -> Bool {
        value.range(
            of: #"^[0-9]+$"#,
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

    private static func cleanedURL(_ url: URL) -> URL? {
        guard var components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        ) else {
            return nil
        }
        components.queryItems = nil
        components.fragment = nil
        return components.url
    }
}
