import Foundation

struct PixivComicSearchResultResolver: SearchResultResolving {
    func supports(_ baseURL: URL) -> Bool {
        guard let host = baseURL.host?.lowercased() else { return false }
        return Self.isSupportedHost(host)
    }

    static func isSupportedHost(_ host: String) -> Bool {
        host == "comic.pixiv.net" ||
            host == "comic.pixiv.test"
    }

    static func dataAttributeLinkValue(
        in attributes: [String: String],
        baseURL: URL
    ) -> String? {
        guard let host = baseURL.host?.lowercased(),
              isSupportedHost(host) else {
            return nil
        }
        if let episodeID = dataAttributeEpisodeID(in: attributes),
           dataAttributeLooksLikeEpisodeCard(attributes) {
            return "/viewer/stories/\(episodeID)"
        }
        if let workID = dataAttributeWorkID(in: attributes),
           dataAttributeLooksLikeWorkCard(attributes) {
            return "/works/\(workID)"
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
                sitePrefix: "pixivcomic",
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
            ? "comic.pixiv.test"
            : "comic.pixiv.net"

        if let episodeID = PixivComicResolver.episodeID(from: url) {
            var components = URLComponents()
            components.scheme = url.scheme ?? "https"
            components.host = canonicalHost
            components.path = "/viewer/stories/\(episodeID)"
            return components.url
        }

        guard let workID = PixivComicResolver.workID(from: url) else {
            return nil
        }
        var components = URLComponents()
        components.scheme = url.scheme ?? "https"
        components.host = canonicalHost
        components.path = "/works/\(workID)"
        return components.url
    }

    private func resultKey(for url: URL) -> String {
        if let episodeID = PixivComicResolver.episodeID(from: url) {
            return "episode:\(episodeID)"
        }
        if let workID = PixivComicResolver.workID(from: url) {
            return "work:\(workID)"
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
            "category": "pixiv_comic",
            "title": title,
            "search_title": title
        ]) { current, _ in current }
        if let episodeID = PixivComicResolver.episodeID(from: target) {
            metadata["id"] = episodeID
            metadata["post_id"] = episodeID
            metadata["episode_id"] = episodeID
            metadata["media_id"] = episodeID
            metadata["gallery_id"] = episodeID
            metadata["type"] = "episode"
        } else if let workID = PixivComicResolver.workID(from: target) {
            metadata["id"] = workID
            metadata["work_id"] = workID
            metadata["gallery_id"] = workID
            metadata["type"] = "work"
        }
        return DownloadMetadata.clean(metadata)
    }

    private static func dataAttributeEpisodeID(
        in attributes: [String: String]
    ) -> String? {
        let explicitKeys = [
            "data-episode-id", "data-episodeid", "data-story-id",
            "data-storyid", "data-comic-episode-id", "episode-id", "story-id"
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
            containsAnyOf: ["episode", "story", "viewer"]
        ) else {
            return nil
        }
        return firstAttributeValue(
            in: attributes,
            keys: ["data-id", "id"],
            matching: isPositiveNumericID
        )
    }

    private static func dataAttributeWorkID(
        in attributes: [String: String]
    ) -> String? {
        let explicitKeys = [
            "data-work-id", "data-workid", "data-series-id",
            "data-seriesid", "data-comic-id", "work-id", "series-id"
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
            containsAnyOf: ["work", "series", "comic"]
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
            "data-episode-id", "data-episodeid", "data-story-id",
            "data-storyid", "data-comic-episode-id"
        ]
        if markerKeys.contains(where: {
            attributes[$0]?.trimmed.isEmpty == false
        }) {
            return true
        }
        return typeHint(
            in: attributes,
            containsAnyOf: ["episode", "story", "viewer"]
        )
    }

    private static func dataAttributeLooksLikeWorkCard(
        _ attributes: [String: String]
    ) -> Bool {
        let markerKeys = [
            "data-work-id", "data-workid", "data-series-id",
            "data-seriesid", "data-comic-id"
        ]
        if markerKeys.contains(where: {
            attributes[$0]?.trimmed.isEmpty == false
        }) {
            return true
        }
        return typeHint(
            in: attributes,
            containsAnyOf: ["work", "series", "comic"]
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
}
