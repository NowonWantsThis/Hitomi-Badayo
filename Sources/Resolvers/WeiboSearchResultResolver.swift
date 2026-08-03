import Foundation

struct WeiboSearchResultResolver: SearchResultResolving {
    func supports(_ baseURL: URL) -> Bool {
        guard let host = baseURL.host?.lowercased() else { return false }
        return Self.isSupportedHost(host)
    }

    static func isSupportedHost(_ host: String) -> Bool {
        host == "weibo.com" ||
            host == "www.weibo.com" ||
            host == "m.weibo.cn" ||
            host == "weibo.cn" ||
            host == "sina.com.cn" ||
            host.hasSuffix(".sina.com.cn") ||
            host == "weibo.test" ||
            host == "www.weibo.test" ||
            host == "m.weibo.test"
    }

    static func dataAttributeLinkValue(
        in attributes: [String: String],
        baseURL: URL?
    ) -> String? {
        guard let host = baseURL?.host?.lowercased(),
              isSupportedHost(host) else {
            return nil
        }

        if let id = dataAttributeTVID(in: attributes),
           dataAttributeLooksLikeTVCard(attributes) {
            return "/tv/show/\(id)"
        }
        if let id = dataAttributeDetailID(in: attributes),
           dataAttributeLooksLikeDetailCard(attributes) {
            return "/detail/\(id)"
        }
        if let id = dataAttributeStatusID(in: attributes),
           dataAttributeLooksLikeStatusCard(attributes) {
            if let profileID = dataAttributeProfileID(in: attributes) {
                return "/\(profileID)/status/\(id)"
            }
            return "/status/\(id)"
        }
        return nil
    }

    static func mediaURL(from url: URL) -> URL? {
        guard let host = url.host?.lowercased(),
              isSupportedHost(host) else {
            return nil
        }

        let parts = url.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        let lower = parts.map { $0.lowercased() }

        if let marker = lower.firstIndex(of: "status"),
           marker + 1 < parts.count {
            return cleanedURL(
                url,
                path: "/" + parts[0...(marker + 1)].joined(separator: "/")
            )
        }
        if let marker = lower.firstIndex(of: "detail"),
           marker + 1 < parts.count {
            return cleanedURL(
                url,
                path: "/" + parts[0...(marker + 1)].joined(separator: "/")
            )
        }
        if lower.count >= 3, lower[0] == "tv", lower[1] == "show" {
            return cleanedURL(url, path: "/tv/show/\(parts[2])")
        }
        return nil
    }

    func extract(from context: SearchResultResolverContext) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByID: [String: Int] = [:]

        for anchor in context.anchors {
            guard results.count < context.limit,
                  let absolute = context.resolvedURL(for: anchor),
                  let target = Self.mediaURL(from: absolute),
                  let id = WeiboStatusResolver.statusID(from: target) else {
                continue
            }

            let title = context.title(
                for: anchor,
                fallback: "Weibo \(id)"
            )
            SearchResultResolverSupport.appendUniqueResult(
                title: title,
                url: target,
                id: id,
                sitePrefix: "weibo",
                results: &results,
                indexByID: &indexByID,
                metadata: metadata(
                    id: id,
                    title: title,
                    target: target,
                    contributorMetadata: context.contributorMetadata(
                        for: anchor,
                        fallbackName: nil,
                        fallbackUsername: Self.statusProfileID(from: target),
                        fallbackUserID: Self.statusProfileID(from: target)
                    )
                )
            )
        }

        return results
    }

    private func metadata(
        id: String,
        title: String,
        target: URL,
        contributorMetadata: [String: String]
    ) -> [String: String] {
        var metadata = [
            "id": id,
            "status_id": id,
            "media_id": id,
            "category": "weibo",
            "type": Self.searchKind(from: target),
            "media_type": "status",
            "title": title,
            "search_title": title
        ]
        if let profile = Self.statusProfileID(from: target) {
            metadata["profile_id"] = profile
            metadata["user_id"] = profile
        }
        metadata.merge(contributorMetadata) { current, _ in current }
        return DownloadMetadata.clean(metadata)
    }

    private static func searchKind(from url: URL) -> String {
        let parts = url.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        let lower = parts.map { $0.lowercased() }
        if lower.count >= 3, lower[0] == "tv", lower[1] == "show" {
            return "tv"
        }
        if lower.contains("detail") {
            return "detail"
        }
        return "status"
    }

    private static func statusProfileID(from url: URL) -> String? {
        let parts = url.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        let lower = parts.map { $0.lowercased() }
        guard let statusIndex = lower.firstIndex(of: "status"),
              statusIndex > 0 else {
            return nil
        }
        let value = parts[statusIndex - 1].trimmed
        guard value.range(
            of: #"^[A-Za-z0-9_-]+$"#,
            options: .regularExpression
        ) != nil else {
            return nil
        }
        return value
    }

    private static func dataAttributeStatusID(
        in attributes: [String: String]
    ) -> String? {
        let keys = [
            "data-status-id", "data-statusid", "data-mid", "data-mblog-id",
            "data-mblogid", "data-weibo-id", "data-post-id", "status-id"
        ]
        if let value = firstAttributeValue(
            in: attributes,
            keys: keys,
            matching: isStatusID
        ) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           isStatusID(id),
           typeHint(
               in: attributes,
               containsAnyOf: ["status", "post", "weibo"]
           ) {
            return id
        }
        return nil
    }

    private static func dataAttributeDetailID(
        in attributes: [String: String]
    ) -> String? {
        let keys = ["data-detail-id", "data-detailid", "detail-id"]
        if let value = firstAttributeValue(
            in: attributes,
            keys: keys,
            matching: isStatusID
        ) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           isStatusID(id),
           typeHint(in: attributes, containsAnyOf: ["detail"]) {
            return id
        }
        return nil
    }

    private static func dataAttributeTVID(
        in attributes: [String: String]
    ) -> String? {
        let keys = [
            "data-tv-id", "data-tvid", "data-sina-id", "data-sinaid",
            "tv-id"
        ]
        if let value = firstAttributeValue(
            in: attributes,
            keys: keys,
            matching: isStatusID
        ) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           isStatusID(id),
           typeHint(in: attributes, containsAnyOf: ["tv", "sina"]) {
            return id
        }
        return nil
    }

    private static func dataAttributeProfileID(
        in attributes: [String: String]
    ) -> String? {
        firstAttributeValue(
            in: attributes,
            keys: [
                "data-profile-id", "data-profileid", "data-user-id",
                "data-userid", "data-uid", "profile-id", "user-id", "uid"
            ],
            matching: isValidPathSlug
        )
    }

    private static func dataAttributeLooksLikeStatusCard(
        _ attributes: [String: String]
    ) -> Bool {
        let markerKeys = [
            "data-status-id", "data-statusid", "data-mid", "data-mblog-id",
            "data-mblogid", "data-weibo-id", "data-post-id", "status-id"
        ]
        if markerKeys.contains(where: {
            attributes[$0]?.trimmed.isEmpty == false
        }) {
            return true
        }
        return typeHint(
            in: attributes,
            containsAnyOf: ["status", "post", "weibo"]
        )
    }

    private static func dataAttributeLooksLikeDetailCard(
        _ attributes: [String: String]
    ) -> Bool {
        if ["data-detail-id", "data-detailid", "detail-id"].contains(
            where: { attributes[$0]?.trimmed.isEmpty == false }
        ) {
            return true
        }
        return typeHint(in: attributes, containsAnyOf: ["detail"])
    }

    private static func dataAttributeLooksLikeTVCard(
        _ attributes: [String: String]
    ) -> Bool {
        let keys = [
            "data-tv-id", "data-tvid", "data-sina-id", "data-sinaid",
            "tv-id"
        ]
        if keys.contains(where: {
            attributes[$0]?.trimmed.isEmpty == false
        }) {
            return true
        }
        return typeHint(in: attributes, containsAnyOf: ["tv", "sina"])
    }

    private static func isStatusID(_ value: String) -> Bool {
        value.range(
            of: #"^[0-9A-Za-z:_-]+$"#,
            options: .regularExpression
        ) != nil &&
            !["ajax", "detail", "login", "search", "status", "tv"]
                .contains(value.lowercased())
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

    private static func cleanedURL(_ url: URL, path: String) -> URL? {
        guard var components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        ) else {
            return nil
        }
        components.path = path
        components.queryItems = nil
        components.fragment = nil
        return components.url
    }
}
