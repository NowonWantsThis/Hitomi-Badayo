import Foundation

struct WebtoonSearchResultResolver: SearchResultResolving {
    func supports(_ baseURL: URL) -> Bool {
        guard let host = baseURL.host?.lowercased() else { return false }
        return Self.isSupportedHost(host)
    }

    static func isSupportedHost(_ host: String) -> Bool {
        host == "webtoon.com" ||
            host == "www.webtoon.com" ||
            host == "webtoons.com" ||
            host == "www.webtoons.com" ||
            host == "webtoon.test" ||
            host == "webtoons.test"
    }

    static func dataAttributeLinkValue(
        in attributes: [String: String],
        baseURL: URL
    ) -> String? {
        guard let host = baseURL.host?.lowercased(),
              isSupportedHost(host),
              let episode = dataAttributeEpisode(in: attributes),
              dataAttributeLooksLikeEpisodeCard(attributes) else {
            return nil
        }
        var components = URLComponents()
        components.path = "/viewer"
        components.queryItems = [
            URLQueryItem(name: "title_no", value: episode.titleNo),
            URLQueryItem(name: "episode_no", value: episode.episodeNo)
        ]
        return components.string
    }

    func extract(from context: SearchResultResolverContext) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByEpisode: [String: Int] = [:]

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
                sitePrefix: "webtoon",
                results: &results,
                indexByID: &indexByEpisode,
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
              Self.isSupportedHost(host),
              var components = URLComponents(
                  url: url,
                  resolvingAgainstBaseURL: false
              ) else {
            return nil
        }
        let items = components.queryItems ?? []
        let episode = queryValue("episode_no", in: items)
        guard episode != nil ||
                url.path.lowercased().contains("/viewer") else {
            return nil
        }
        components.host = host.hasSuffix(".test")
            ? "webtoons.test"
            : "www.webtoons.com"
        components.fragment = nil
        components.queryItems = items.filter {
            ["title_no", "episode_no"].contains($0.name.lowercased())
        }
        return components.url
    }

    private func resultKey(for url: URL) -> String {
        let items = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        )?.queryItems ?? []
        let title = queryValue("title_no", in: items) ?? "title"
        let episode = queryValue("episode_no", in: items) ?? url.path
        return "\(title):\(episode)"
    }

    private func metadata(
        target: URL,
        title: String,
        contributorMetadata: [String: String]
    ) -> [String: String] {
        let items = URLComponents(
            url: target,
            resolvingAgainstBaseURL: false
        )?.queryItems ?? []
        let titleID = queryValue("title_no", in: items) ?? ""
        let episodeID = queryValue("episode_no", in: items) ?? ""
        var metadata = contributorMetadata
        metadata.merge([
            "id": episodeID.isEmpty ? titleID : episodeID,
            "post_id": episodeID,
            "episode_id": episodeID,
            "media_id": episodeID,
            "title_id": titleID,
            "series_id": titleID,
            "gallery_id": titleID,
            "category": "webtoon",
            "type": "episode",
            "title": title,
            "search_title": title
        ]) { current, _ in current }
        return DownloadMetadata.clean(metadata)
    }

    private static func dataAttributeEpisode(
        in attributes: [String: String]
    ) -> (titleNo: String, episodeNo: String)? {
        let titleNo = firstAttributeValue(
            in: attributes,
            keys: [
                "data-title-no", "data-titleno", "data-title-id",
                "data-titleid", "title-no", "titleno"
            ],
            matching: isPositiveNumericID
        )
        let episodeNo = firstAttributeValue(
            in: attributes,
            keys: [
                "data-episode-no", "data-episodeno", "data-episode-id",
                "data-episodeid", "episode-no", "episodeno"
            ],
            matching: isPositiveNumericID
        ) ?? (typeHint(
            in: attributes,
            containsAnyOf: ["episode", "viewer"]
        ) ? firstAttributeValue(
            in: attributes,
            keys: ["data-id", "id"],
            matching: isPositiveNumericID
        ) : nil)
        guard let titleNo, let episodeNo else { return nil }
        return (titleNo, episodeNo)
    }

    private static func dataAttributeLooksLikeEpisodeCard(
        _ attributes: [String: String]
    ) -> Bool {
        let markerKeys = [
            "data-title-no", "data-titleno",
            "data-episode-no", "data-episodeno"
        ]
        if markerKeys.contains(where: {
            attributes[$0]?.trimmed.isEmpty == false
        }) {
            return true
        }
        return typeHint(
            in: attributes,
            containsAnyOf: ["episode", "viewer", "webtoon"]
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

    private func queryValue(
        _ name: String,
        in items: [URLQueryItem]
    ) -> String? {
        items.first { $0.name == name }?.value
    }
}
