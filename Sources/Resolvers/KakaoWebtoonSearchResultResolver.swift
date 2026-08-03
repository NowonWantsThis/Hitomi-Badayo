import Foundation

struct KakaoWebtoonSearchResultResolver: SearchResultResolving {
    func supports(_ baseURL: URL) -> Bool {
        guard let host = baseURL.host?.lowercased() else { return false }
        return Self.isSupportedHost(host)
    }

    static func isSupportedHost(_ host: String) -> Bool {
        host == "webtoon.kakao.com" ||
            host == "webtoon.kakao.test"
    }

    static func dataAttributeLinkValue(
        in attributes: [String: String],
        baseURL: URL
    ) -> String? {
        guard let host = baseURL.host?.lowercased(),
              isSupportedHost(host) else {
            return nil
        }
        if let episode = dataAttributeEpisode(in: attributes),
           dataAttributeLooksLikeEpisodeCard(attributes) {
            return "/viewer/\(episode.seoID)/\(episode.episodeID)"
        }
        if let contentID = dataAttributeContentID(in: attributes),
           dataAttributeLooksLikeContentCard(attributes) {
            return "/content/\(contentID)"
        }
        return nil
    }

    func extract(from context: SearchResultResolverContext) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByKey: [String: Int] = [:]

        for anchor in context.anchors {
            guard results.count < context.limit,
                  let absolute = context.resolvedURL(for: anchor),
                  let target = canonicalURL(from: absolute) else {
                continue
            }

            let title = context.title(for: anchor, fallbackURL: target)
            SearchResultResolverSupport.appendUniqueResult(
                title: title,
                url: target,
                id: resultKey(for: target),
                sitePrefix: "kakaowebtoon",
                results: &results,
                indexByID: &indexByKey,
                metadata: metadata(
                    target: target,
                    title: title,
                    contributorMetadata: context.contributorMetadata(
                        for: anchor
                    )
                )
            )
        }

        return results
    }

    private func canonicalURL(from url: URL) -> URL? {
        guard let host = url.host?.lowercased(),
              Self.isSupportedHost(host) else {
            return nil
        }
        let canonicalHost = host.hasSuffix(".test")
            ? "webtoon.kakao.test"
            : "webtoon.kakao.com"

        if let episode = KakaoWebtoonResolver.viewerEpisode(from: url) {
            var components = URLComponents()
            components.scheme = url.scheme ?? "https"
            components.host = canonicalHost
            components.path = "/viewer/\(episode.seoID)/\(episode.episodeID)"
            return components.url
        }

        guard let contentID = KakaoWebtoonResolver.contentID(
            fromPath: url.path
        ) else {
            return nil
        }
        var components = URLComponents()
        components.scheme = url.scheme ?? "https"
        components.host = canonicalHost
        components.path = "/content/\(contentID)"
        return components.url
    }

    private func resultKey(for url: URL) -> String {
        if let episode = KakaoWebtoonResolver.viewerEpisode(from: url) {
            return "viewer:\(episode.seoID):\(episode.episodeID)"
        }
        if let contentID = KakaoWebtoonResolver.contentID(fromPath: url.path) {
            return "content:\(contentID)"
        }
        return url.absoluteString.lowercased()
    }

    private func metadata(
        target: URL,
        title: String,
        contributorMetadata: [String: String]
    ) -> [String: String] {
        var metadata = contributorMetadata
        metadata.merge([
            "category": "kakao_webtoon",
            "title": title,
            "search_title": title
        ]) { current, _ in current }
        if let episode = KakaoWebtoonResolver.viewerEpisode(from: target) {
            metadata["id"] = episode.episodeID
            metadata["post_id"] = episode.episodeID
            metadata["episode_id"] = episode.episodeID
            metadata["media_id"] = episode.episodeID
            metadata["seo_id"] = episode.seoID
            metadata["content_id"] = episode.contentID
            metadata["gallery_id"] = episode.contentID.isEmpty
                ? episode.seoID
                : episode.contentID
            metadata["type"] = "episode"
        } else if let contentID = KakaoWebtoonResolver.contentID(
            fromPath: target.path
        ) {
            metadata["id"] = contentID
            metadata["content_id"] = contentID
            metadata["gallery_id"] = contentID
            metadata["type"] = "series"
        }
        return DownloadMetadata.clean(metadata)
    }

    private static func dataAttributeEpisode(
        in attributes: [String: String]
    ) -> (seoID: String, episodeID: String)? {
        let episodeID = firstAttributeValue(
            in: attributes,
            keys: [
                "data-episode-id", "data-episodeid", "data-product-id",
                "data-productid", "data-viewer-id", "data-viewerid",
                "episode-id", "product-id"
            ],
            matching: isPositiveNumericID
        ) ?? (typeHint(
            in: attributes,
            containsAnyOf: ["episode", "viewer", "product"]
        ) ? firstAttributeValue(
            in: attributes,
            keys: ["data-id", "id"],
            matching: isPositiveNumericID
        ) : nil)
        guard let episodeID else { return nil }

        let seoID = firstAttributeValue(
            in: attributes,
            keys: [
                "data-seo-id", "data-seoid", "data-seo", "data-slug",
                "data-title-slug", "data-content-slug", "seo-id", "slug"
            ],
            matching: isValidPathSlug
        ) ?? dataAttributeContentID(in: attributes)
        guard let seoID else { return nil }
        return (seoID, episodeID)
    }

    private static func dataAttributeContentID(
        in attributes: [String: String]
    ) -> String? {
        let explicitKeys = [
            "data-content-id", "data-contentid", "data-series-id",
            "data-seriesid", "data-work-id", "data-workid", "content-id"
        ]
        if let value = firstAttributeValue(
            in: attributes,
            keys: explicitKeys,
            matching: isPositiveNumericID
        ) {
            return value
        }
        guard typeHint(
            in: attributes,
            containsAnyOf: ["content", "series", "work"]
        ) else {
            return nil
        }
        return firstAttributeValue(
            in: attributes,
            keys: ["data-id", "id"],
            matching: isPositiveNumericID
        )
    }

    private static func dataAttributeLooksLikeEpisodeCard(
        _ attributes: [String: String]
    ) -> Bool {
        let markerKeys = [
            "data-episode-id", "data-episodeid", "data-product-id",
            "data-productid", "data-viewer-id", "data-viewerid"
        ]
        if markerKeys.contains(where: {
            attributes[$0]?.trimmed.isEmpty == false
        }) {
            return true
        }
        return typeHint(
            in: attributes,
            containsAnyOf: ["episode", "viewer", "product"]
        )
    }

    private static func dataAttributeLooksLikeContentCard(
        _ attributes: [String: String]
    ) -> Bool {
        let markerKeys = [
            "data-content-id", "data-contentid", "data-series-id",
            "data-seriesid", "data-work-id", "data-workid"
        ]
        if markerKeys.contains(where: {
            attributes[$0]?.trimmed.isEmpty == false
        }) {
            return true
        }
        return typeHint(
            in: attributes,
            containsAnyOf: ["content", "series", "work"]
        )
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

    private static func isPositiveNumericID(_ value: String) -> Bool {
        guard value.range(
            of: #"^[0-9]+$"#,
            options: .regularExpression
        ) != nil, let number = Int(value) else {
            return false
        }
        return number > 0
    }

    private static func isValidPathSlug(_ value: String) -> Bool {
        !value.isEmpty &&
            value.range(
                of: #"^[A-Za-z0-9][A-Za-z0-9_-]*$"#,
                options: .regularExpression
            ) != nil
    }
}
