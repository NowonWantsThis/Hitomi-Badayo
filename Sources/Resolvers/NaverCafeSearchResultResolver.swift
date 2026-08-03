import Foundation

struct NaverCafeSearchResultResolver: SearchResultResolving {
    func supports(_ baseURL: URL) -> Bool {
        guard let host = baseURL.host?.lowercased() else { return false }
        return Self.isSupportedHost(host)
    }

    static func isSupportedHost(_ host: String) -> Bool {
        host == "cafe.naver.com" ||
            host == "m.cafe.naver.com" ||
            host == "cafe.naver.test" ||
            host == "m.cafe.naver.test"
    }

    static func dataAttributeLinkValue(
        in attributes: [String: String],
        baseURL: URL
    ) -> String? {
        guard let host = baseURL.host?.lowercased(),
              isSupportedHost(host),
              let article = dataAttributeArticle(
                  in: attributes,
                  baseURL: baseURL
              ),
              dataAttributeLooksLikeArticleCard(attributes) else {
            return nil
        }
        if let clubID = article.clubID {
            return "/ca-fe/web/cafes/\(clubID)/articles/\(article.articleID)"
        }
        if let cafeName = article.cafeName {
            return "/\(cafeName)/\(article.articleID)"
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
            let id = NaverCafeResolver.articleID(from: target)
            let channel = id?.clubID ?? id?.cafeName ?? ""
            SearchResultResolverSupport.appendUniqueResult(
                title: title,
                url: target,
                id: resultKey(for: target),
                sitePrefix: "navercafe",
                results: &results,
                indexByID: &indexByKey,
                metadata: metadata(
                    target: target,
                    title: title,
                    contributorMetadata: context.contributorMetadata(
                        for: anchor,
                        fallbackName: nil,
                        fallbackUsername: id?.cafeName,
                        fallbackUserID: channel.isEmpty ? nil : channel
                    )
                )
            )
        }

        return results
    }

    private func canonicalURL(from url: URL) -> URL? {
        guard let host = url.host?.lowercased(),
              Self.isSupportedHost(host),
              let id = NaverCafeResolver.articleID(from: url) else {
            return nil
        }

        if id.clubID != nil {
            return NaverCafeResolver.mobileArticleURL(
                for: id,
                sourceURL: url
            )
        }

        guard let cafeName = id.cafeName else {
            return nil
        }
        var components = URLComponents()
        components.scheme = url.scheme ?? "https"
        components.host = host.hasSuffix(".test")
            ? "cafe.naver.test"
            : "cafe.naver.com"
        components.path = "/\(cafeName)/\(id.articleID)"
        return components.url
    }

    private func resultKey(for url: URL) -> String {
        guard let id = NaverCafeResolver.articleID(from: url) else {
            return url.absoluteString.lowercased()
        }
        return "\(id.clubID ?? id.cafeName ?? "cafe"):\(id.articleID)"
    }

    private func metadata(
        target: URL,
        title: String,
        contributorMetadata: [String: String]
    ) -> [String: String] {
        guard let id = NaverCafeResolver.articleID(from: target) else {
            return DownloadMetadata.clean([
                "title": title,
                "search_title": title
            ])
        }
        let channel = id.clubID ?? id.cafeName ?? ""
        var metadata = contributorMetadata
        metadata.merge([
            "id": id.articleID,
            "post_id": id.articleID,
            "article_id": id.articleID,
            "media_id": id.articleID,
            "gallery_id": id.articleID,
            "club_id": id.clubID ?? "",
            "cafe_name": id.cafeName ?? "",
            "channel_id": channel,
            "category": "cafe",
            "type": "article",
            "title": title,
            "search_title": title
        ]) { current, _ in current }
        return DownloadMetadata.clean(metadata)
    }

    private static func dataAttributeArticle(
        in attributes: [String: String],
        baseURL: URL
    ) -> (clubID: String?, cafeName: String?, articleID: String)? {
        let articleKeys = [
            "data-article-id", "data-articleid", "data-post-id",
            "data-postid", "article-id", "articleid"
        ]
        let articleID = firstAttributeValue(
            in: attributes,
            keys: articleKeys,
            matching: isPositiveNumericID
        ) ?? (typeHint(
            in: attributes,
            containsAnyOf: ["article", "post", "cafe"]
        ) ? firstAttributeValue(
            in: attributes,
            keys: ["data-id", "id"],
            matching: isPositiveNumericID
        ) : nil)
        guard let articleID else { return nil }

        let clubID = firstAttributeValue(
            in: attributes,
            keys: [
                "data-club-id", "data-clubid", "data-cafe-id",
                "data-cafeid", "clubid", "club-id"
            ],
            matching: isPositiveNumericID
        )
        let cafeName = firstAttributeValue(
            in: attributes,
            keys: [
                "data-cafe-name", "data-cafename", "data-cafe",
                "data-board", "cafe-name", "cafe"
            ],
            matching: isCafeName
        ) ?? cafeName(from: baseURL)

        guard clubID != nil || cafeName != nil else { return nil }
        return (clubID, cafeName, articleID)
    }

    private static func dataAttributeLooksLikeArticleCard(
        _ attributes: [String: String]
    ) -> Bool {
        let markerKeys = [
            "data-article-id", "data-articleid", "data-club-id",
            "data-clubid", "data-cafe-id", "data-cafeid"
        ]
        if markerKeys.contains(where: {
            attributes[$0]?.trimmed.isEmpty == false
        }) {
            return true
        }
        return typeHint(
            in: attributes,
            containsAnyOf: ["article", "post", "cafe"]
        )
    }

    private static func cafeName(from url: URL) -> String? {
        let parts = url.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        guard let cafeName = parts.first, isCafeName(cafeName) else {
            return nil
        }
        return cafeName
    }

    private static func isCafeName(_ value: String) -> Bool {
        let reserved: Set<String> = [
            "articlelist.nhn", "articlesearchlist.nhn", "articleview.nhn",
            "cafemembernetworkview.nhn", "ca-fe", "cafe", "cafehome",
            "cafes", "members", "search", "searchlist", "search.naver"
        ]
        return isPathSlug(value) &&
            !reserved.contains(value.lowercased())
    }

    private static func isPathSlug(_ value: String) -> Bool {
        !value.isEmpty &&
            value.count <= 80 &&
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
