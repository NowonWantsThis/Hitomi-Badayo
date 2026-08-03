import Foundation

struct XVideoSearchResultResolver: SearchResultResolving {
    func supports(_ baseURL: URL) -> Bool {
        guard let host = baseURL.host?.lowercased() else { return false }
        return Self.isXVideosHost(host) || Self.isXNXXHost(host)
    }

    static func isXNXXHost(_ host: String) -> Bool {
        if host == "xnxx.test" || host == "www.xnxx.test" {
            return true
        }
        guard let labels = hostLabels(host), labels.count >= 2 else {
            return false
        }
        let base = labels[labels.count - 2]
        let topLevelDomain = labels[labels.count - 1]
        guard topLevelDomain == "com" || topLevelDomain == "es" else {
            return false
        }
        return base.range(
            of: #"^xnxx[0-9]*$"#,
            options: .regularExpression
        ) != nil
    }

    static func isXVideosHost(_ host: String) -> Bool {
        if host == "xvideos.test" || host == "www.xvideos.test" {
            return true
        }
        guard let labels = hostLabels(host), labels.count >= 2 else {
            return false
        }
        let base = labels[labels.count - 2]
        let topLevelDomain = labels[labels.count - 1]
        guard ["com", "in", "es"].contains(topLevelDomain) else {
            return false
        }
        return base.range(
            of: #"^xvideos[0-9]*$"#,
            options: .regularExpression
        ) != nil
    }

    static func dataAttributeLinkValue(
        in attributes: [String: String],
        baseURL: URL?
    ) -> String? {
        guard let host = baseURL?.host?.lowercased(),
              isXVideosHost(host) || isXNXXHost(host),
              let id = dataAttributeVideoID(
                  in: attributes,
                  host: host
              ),
              dataAttributeLooksLikeVideoCard(attributes) else {
            return nil
        }
        let suffix = dataAttributeSlug(in: attributes).map {
            "/\($0)"
        } ?? ""
        if isXNXXHost(host) {
            return "/video-\(id)\(suffix)"
        }
        return "/video\(id)\(suffix)"
    }

    func extract(from context: SearchResultResolverContext) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByID: [String: Int] = [:]

        for anchor in context.anchors {
            guard results.count < context.limit,
                  let absolute = context.resolvedURL(for: anchor),
                  let target = XVideoPageResolver.canonicalURL(for: absolute),
                  let videoID = XVideoPageResolver.videoID(from: target) else {
                continue
            }

            let host = absolute.host?.lowercased() ?? ""
            let isXNXX = Self.isXNXXHost(host)
            let siteName = isXNXX ? "XNXX" : "XVideos"
            let sitePrefix = isXNXX ? "xnxx" : "xvideos"
            SearchResultResolverSupport.appendUniqueResult(
                title: context.title(
                    for: anchor,
                    fallback: "\(siteName) \(videoID)"
                ),
                url: target,
                id: "\(sitePrefix)-\(videoID.lowercased())",
                sitePrefix: sitePrefix,
                results: &results,
                indexByID: &indexByID
            )
        }

        return results
    }

    private static func dataAttributeVideoID(
        in attributes: [String: String],
        host: String
    ) -> String? {
        let predicate: (String) -> Bool = { value in
            if isXNXXHost(host) {
                return isVideoID(value)
            }
            return value.range(
                of: #"^[0-9][0-9A-Za-z]*$"#,
                options: .regularExpression
            ) != nil
        }
        let keys = [
            "data-video-id", "data-videoid", "data-media-id",
            "data-mediaid", "video-id"
        ]
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
               containsAnyOf: ["video", "watch"]
           ) {
            return id
        }
        return nil
    }

    private static func dataAttributeSlug(
        in attributes: [String: String]
    ) -> String? {
        firstAttributeValue(
            in: attributes,
            keys: [
                "data-video-slug", "data-videoslug", "data-title-slug",
                "data-slug", "video-slug"
            ],
            matching: isPathSlug
        )
    }

    private static func dataAttributeLooksLikeVideoCard(
        _ attributes: [String: String]
    ) -> Bool {
        let keys = [
            "data-video-id", "data-videoid", "data-media-id",
            "data-mediaid", "video-id"
        ]
        if keys.contains(where: {
            attributes[$0]?.trimmed.isEmpty == false
        }) {
            return true
        }
        return typeHint(
            in: attributes,
            containsAnyOf: ["video", "watch"]
        )
    }

    private static func isVideoID(_ value: String) -> Bool {
        value.range(
            of: #"^[0-9A-Za-z]+$"#,
            options: .regularExpression
        ) != nil
    }

    private static func isPathSlug(_ value: String) -> Bool {
        value.range(
            of: #"^[A-Za-z0-9][A-Za-z0-9_-]*$"#,
            options: .regularExpression
        ) != nil
    }

    private static func hostLabels(_ host: String) -> [String]? {
        let labels = host
            .lowercased()
            .split(separator: ".")
            .map(String.init)
            .filter { !$0.isEmpty }
        return labels.count >= 2 ? labels : nil
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
