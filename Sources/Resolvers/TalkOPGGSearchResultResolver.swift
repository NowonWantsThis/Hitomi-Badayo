import Foundation

struct TalkOPGGSearchResultResolver: SearchResultResolving {
    func supports(_ baseURL: URL) -> Bool {
        guard let host = baseURL.host?.lowercased() else { return false }
        return Self.isSupportedHost(host)
    }

    static func isSupportedHost(_ host: String) -> Bool {
        host == "talk.op.gg" ||
            host == "www.talk.op.gg" ||
            host == "talk.op.gg.test" ||
            host == "www.talk.op.gg.test"
    }

    static func dataAttributeLinkValue(
        in attributes: [String: String],
        baseURL: URL?
    ) -> String? {
        guard let baseURL,
              let host = baseURL.host?.lowercased(),
              isSupportedHost(host),
              let article = dataAttributeArticle(
                  in: attributes,
                  baseURL: baseURL
              ),
              dataAttributeLooksLikeArticleCard(attributes) else {
            return nil
        }
        let slugSuffix = article.slug.map { "/\($0)" } ?? ""
        return "/s/\(article.game)/\(article.section)/" +
            "\(article.id)\(slugSuffix)"
    }

    func extract(from context: SearchResultResolverContext) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByArticleID: [String: Int] = [:]

        for anchor in context.anchors {
            guard results.count < context.limit,
                  let absolute = context.resolvedURL(for: anchor),
                  let articleID = TalkOPGGResolver.articleID(from: absolute),
                  let target = TalkOPGGResolver.canonicalArticleURL(for: absolute) else {
                continue
            }

            let title = context.title(
                for: anchor,
                fallback: "Talk OP.GG \(articleID)"
            )
            SearchResultResolverSupport.appendUniqueResult(
                title: title,
                url: target,
                id: articleID,
                sitePrefix: "talkopgg",
                results: &results,
                indexByID: &indexByArticleID,
                metadata: metadata(
                    articleID: articleID,
                    target: target,
                    title: title,
                    contributorMetadata: context.contributorMetadata(for: anchor)
                )
            )
        }

        return results
    }

    private func metadata(
        articleID: String,
        target: URL,
        title: String,
        contributorMetadata: [String: String]
    ) -> [String: String] {
        let parts = target.path.split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        let game = parts.count > 1 ? parts[1] : ""
        let section = parts.count > 2 ? parts[2] : ""
        var metadata = contributorMetadata
        metadata.merge([
            "id": articleID,
            "post_id": articleID,
            "article_id": articleID,
            "gallery_id": articleID,
            "media_id": articleID,
            "game": game,
            "section": section,
            "tag": section,
            "category": "talk_opgg",
            "type": "article",
            "title": title,
            "search_title": title
        ]) { current, _ in current }
        return DownloadMetadata.clean(metadata)
    }

    private static func dataAttributeArticle(
        in attributes: [String: String],
        baseURL: URL
    ) -> (
        game: String,
        section: String,
        id: String,
        slug: String?
    )? {
        let idKeys = [
            "data-article-id", "data-articleid", "data-post-id",
            "data-postid", "article-id"
        ]
        let id = firstAttributeValue(
            in: attributes,
            keys: idKeys,
            matching: isArticleID
        ) ??
            (typeHint(
                in: attributes,
                containsAnyOf: ["article", "post"]
            )
                ? firstAttributeValue(
                    in: attributes,
                    keys: ["data-id", "id"],
                    matching: isArticleID
                )
                : nil)
        guard let id else { return nil }

        let game = firstAttributeValue(
            in: attributes,
            keys: ["data-game", "data-game-id", "game", "game-id"],
            matching: isValidPathSlug
        ) ?? pathPart(baseURL, offset: 1)
        let section = firstAttributeValue(
            in: attributes,
            keys: [
                "data-section", "data-board", "data-category",
                "section", "board"
            ],
            matching: isValidPathSlug
        ) ?? pathPart(baseURL, offset: 2)

        guard let game,
              let section,
              !["all", "search"].contains(section.lowercased()) else {
            return nil
        }

        let slug = firstAttributeValue(
            in: attributes,
            keys: ["data-slug", "data-title-slug", "slug"],
            matching: isValidPathSlug
        )
        return (game, section, id, slug)
    }

    private static func pathPart(
        _ url: URL,
        offset: Int
    ) -> String? {
        let parts = url.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        guard parts.first?.lowercased() == "s",
              offset < parts.count,
              isValidPathSlug(parts[offset]) else {
            return nil
        }
        return parts[offset]
    }

    private static func dataAttributeLooksLikeArticleCard(
        _ attributes: [String: String]
    ) -> Bool {
        let keys = [
            "data-article-id", "data-articleid", "data-post-id",
            "data-postid", "article-id"
        ]
        if keys.contains(where: {
            attributes[$0]?.trimmed.isEmpty == false
        }) {
            return true
        }
        return typeHint(
            in: attributes,
            containsAnyOf: ["article", "post"]
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

    private static func typeHint(
        in attributes: [String: String],
        containsAnyOf needles: [String]
    ) -> Bool {
        let keys = [
            "data-type", "data-kind", "data-content-type",
            "data-renderer", "class", "role"
        ]
        let values = keys.compactMap {
            attributes[$0]?.lowercased()
        }
        return values.contains { value in
            needles.contains { value.contains($0) }
        }
    }

    private static func isArticleID(_ value: String) -> Bool {
        value.range(
            of: #"^[0-9]{3,}$"#,
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
}
