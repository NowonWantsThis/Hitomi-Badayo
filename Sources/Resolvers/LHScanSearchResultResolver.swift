import Foundation

struct LHScanSearchResultResolver: SearchResultResolving {
    func supports(_ baseURL: URL) -> Bool {
        guard let host = baseURL.host?.lowercased() else { return false }
        return Self.isSupportedHost(host)
    }

    static func isSupportedHost(_ host: String) -> Bool {
        host == "lovehug.net" ||
            host == "welovemanga.one" ||
            host == "welovemanga.net" ||
            host.hasSuffix(".welovemanga.one") ||
            host.hasSuffix(".welovemanga.net") ||
            host == "nicomanga.com" ||
            host.hasSuffix(".nicomanga.com") ||
            host == "lhscan.test" ||
            host == "welovemanga.test" ||
            host == "nicomanga.test"
    }

    static func dataAttributeLinkValue(
        in attributes: [String: String],
        baseURL: URL
    ) -> String? {
        guard let host = baseURL.host?.lowercased(),
              isSupportedHost(host),
              let content = dataAttributeContent(in: attributes),
              dataAttributeLooksLikeContentCard(
                  attributes,
                  hasChapter: content.chapterSlug != nil
              ) else {
            return nil
        }
        if let chapterSlug = content.chapterSlug {
            return "/manga/\(content.seriesSlug)/\(chapterSlug)"
        }
        return "/manga/\(content.seriesSlug)"
    }

    func extract(from context: SearchResultResolverContext) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByURL: [String: Int] = [:]

        for anchor in context.anchors {
            guard results.count < context.limit,
                  let absolute = context.resolvedURL(for: anchor),
                  let target = LHScanResolver.canonicalURL(for: absolute) else {
                continue
            }

            let title = context.title(for: anchor, fallbackURL: target)
            SearchResultResolverSupport.appendUniqueResult(
                title: title,
                url: target,
                id: URLIdentity.normalize(target.absoluteString),
                sitePrefix: "lhscan",
                results: &results,
                indexByID: &indexByURL,
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

    private func metadata(
        target: URL,
        title: String,
        contributorMetadata: [String: String]
    ) -> [String: String] {
        let parts = target.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        let series = parts.count >= 2 ? parts[1] : ""
        let chapter = parts.count >= 3 ? parts[2] : ""
        var metadata = contributorMetadata
        metadata.merge([
            "id": chapter.isEmpty ? series : chapter,
            "post_id": chapter,
            "chapter_id": chapter,
            "series": series,
            "series_id": series,
            "gallery_id": series,
            "category": "lhscan",
            "type": chapter.isEmpty ? "series" : "chapter",
            "title": title,
            "search_title": title
        ]) { current, _ in current }
        return DownloadMetadata.clean(metadata)
    }

    private static func dataAttributeContent(
        in attributes: [String: String]
    ) -> (seriesSlug: String, chapterSlug: String?)? {
        let seriesSlug = firstAttributeValue(
            in: attributes,
            keys: [
                "data-series-slug", "data-seriesslug", "data-manga-slug",
                "data-mangaslug", "data-series-id", "data-manga-id",
                "series-slug", "manga-slug"
            ],
            matching: isSlug
        ) ?? (typeHint(
            in: attributes,
            containsAnyOf: ["series", "manga"]
        ) ? firstAttributeValue(
            in: attributes,
            keys: ["data-id", "id"],
            matching: isSlug
        ) : nil)
        guard let seriesSlug else { return nil }

        let chapterSlug = firstAttributeValue(
            in: attributes,
            keys: [
                "data-chapter-slug", "data-chapterslug", "data-chapter-id",
                "data-chapterid", "data-episode-slug", "chapter-slug"
            ],
            matching: isSlug
        ) ?? (typeHint(
            in: attributes,
            containsAnyOf: ["chapter", "episode"]
        ) ? firstAttributeValue(
            in: attributes,
            keys: ["data-id", "id"],
            matching: isSlug
        ) : nil)
        return (seriesSlug, chapterSlug)
    }

    private static func dataAttributeLooksLikeContentCard(
        _ attributes: [String: String],
        hasChapter: Bool
    ) -> Bool {
        if hasChapter {
            let markerKeys = [
                "data-chapter-slug", "data-chapterslug", "data-chapter-id",
                "data-chapterid", "data-episode-slug"
            ]
            if markerKeys.contains(where: {
                attributes[$0]?.trimmed.isEmpty == false
            }) {
                return true
            }
            return typeHint(
                in: attributes,
                containsAnyOf: ["chapter", "episode"]
            )
        }

        let markerKeys = [
            "data-series-slug", "data-seriesslug", "data-manga-slug",
            "data-mangaslug", "data-series-id", "data-manga-id"
        ]
        if markerKeys.contains(where: {
            attributes[$0]?.trimmed.isEmpty == false
        }) {
            return true
        }
        return typeHint(
            in: attributes,
            containsAnyOf: ["series", "manga"]
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

    private static func isSlug(_ value: String) -> Bool {
        value.count <= 160 &&
            value.range(
                of: #"^[A-Za-z0-9][A-Za-z0-9_-]*$"#,
                options: .regularExpression
            ) != nil
    }
}
