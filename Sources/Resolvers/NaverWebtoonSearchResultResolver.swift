import Foundation

struct NaverWebtoonSearchResultResolver: SearchResultResolving {
    func supports(_ baseURL: URL) -> Bool {
        guard let host = baseURL.host?.lowercased() else { return false }
        return Self.isSupportedHost(host)
    }

    static func isSupportedHost(_ host: String) -> Bool {
        host == "comic.naver.com" ||
            host == "m.comic.naver.com" ||
            host == "comic.naver.test" ||
            host == "m.comic.naver.test"
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
        components.path = "/webtoon/detail"
        components.queryItems = [
            URLQueryItem(name: "titleId", value: episode.titleID),
            URLQueryItem(name: "no", value: episode.episodeNo)
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
                sitePrefix: "naverwebtoon",
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
        guard let titleID = queryValue("titleId", in: items),
              let episodeNo = queryValue("no", in: items) else {
            return nil
        }
        components.host = host.hasSuffix(".test")
            ? "comic.naver.test"
            : "comic.naver.com"
        components.path = "/webtoon/detail"
        components.fragment = nil
        components.queryItems = [
            URLQueryItem(name: "titleId", value: titleID),
            URLQueryItem(name: "no", value: episodeNo)
        ]
        return components.url
    }

    private func resultKey(for url: URL) -> String {
        let items = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        )?.queryItems ?? []
        return "\(queryValue("titleId", in: items) ?? "title"):" +
            "\(queryValue("no", in: items) ?? "episode")"
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
        let titleID = queryValue("titleId", in: items) ?? ""
        let episodeID = queryValue("no", in: items) ?? ""
        var metadata = contributorMetadata
        metadata.merge([
            "id": episodeID.isEmpty ? titleID : episodeID,
            "post_id": episodeID,
            "episode_id": episodeID,
            "media_id": episodeID,
            "title_id": titleID,
            "series_id": titleID,
            "gallery_id": titleID,
            "category": "naver_webtoon",
            "type": "episode",
            "title": title,
            "search_title": title
        ]) { current, _ in current }
        return DownloadMetadata.clean(metadata)
    }

    private static func dataAttributeEpisode(
        in attributes: [String: String]
    ) -> (titleID: String, episodeNo: String)? {
        let titleID = firstAttributeValue(
            in: attributes,
            keys: [
                "data-title-id", "data-titleid", "data-title-no",
                "data-titleno", "titleid", "title-id"
            ],
            matching: isPositiveNumericID
        )
        let episodeNo = firstAttributeValue(
            in: attributes,
            keys: [
                "data-episode-no", "data-episodeno", "data-no",
                "data-episode-id", "data-episodeid", "episode-no", "no"
            ],
            matching: isPositiveNumericID
        ) ?? (typeHint(
            in: attributes,
            containsAnyOf: ["episode", "detail", "viewer"]
        ) ? firstAttributeValue(
            in: attributes,
            keys: ["data-id", "id"],
            matching: isPositiveNumericID
        ) : nil)
        guard let titleID, let episodeNo else { return nil }
        return (titleID, episodeNo)
    }

    private static func dataAttributeLooksLikeEpisodeCard(
        _ attributes: [String: String]
    ) -> Bool {
        let markerKeys = [
            "data-title-id", "data-titleid", "data-episode-no",
            "data-episodeno", "data-no"
        ]
        if markerKeys.contains(where: {
            attributes[$0]?.trimmed.isEmpty == false
        }) {
            return true
        }
        return typeHint(
            in: attributes,
            containsAnyOf: ["episode", "detail", "viewer", "webtoon"]
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
