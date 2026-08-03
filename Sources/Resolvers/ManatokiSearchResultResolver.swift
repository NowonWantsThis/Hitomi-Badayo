import Foundation

struct ManatokiSearchResultResolver: SearchResultResolving {
    func supports(_ baseURL: URL) -> Bool {
        guard let host = baseURL.host?.lowercased() else { return false }
        return Self.isSupportedHost(host)
    }

    static func isSupportedHost(_ host: String) -> Bool {
        host.range(
            of: #"^(?:.*\.)?(?:mana|new)toki[0-9]*\.(?:com|net|test)$"#,
            options: .regularExpression
        ) != nil
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
                  section: content.section
              ) else {
            return nil
        }
        return "/\(content.section)/\(content.id)"
    }

    func extract(from context: SearchResultResolverContext) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByKey: [String: Int] = [:]

        for anchor in context.anchors {
            guard results.count < context.limit,
                  let absolute = context.resolvedURL(for: anchor),
                  let id = ManatokiResolver.contentID(from: absolute),
                  let target = ManatokiResolver.canonicalURL(for: absolute) else {
                continue
            }

            let title = context.title(
                for: anchor,
                fallback: "\(id.section) \(id.id)"
            )
            SearchResultResolverSupport.appendUniqueResult(
                title: title,
                url: target,
                id: "\(id.section):\(id.id)",
                sitePrefix: "manatoki",
                results: &results,
                indexByID: &indexByKey,
                metadata: metadata(
                    id: id,
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
        id: ManatokiContentID,
        title: String,
        contributorMetadata: [String: String]
    ) -> [String: String] {
        var metadata = contributorMetadata
        metadata.merge([
            "id": id.id,
            "post_id": id.id,
            "gallery_id": id.id,
            "media_id": id.id,
            "section": id.section,
            "tag": id.section,
            "category": "manatoki",
            "type": id.section,
            "title": title,
            "search_title": title
        ]) { current, _ in current }
        return DownloadMetadata.clean(metadata)
    }

    private static func dataAttributeContent(
        in attributes: [String: String]
    ) -> (section: String, id: String)? {
        let idKeys = [
            "data-content-id", "data-contentid", "data-post-id",
            "data-postid", "data-wr-id", "data-wrid", "wr-id", "content-id"
        ]
        let id = firstAttributeValue(
            in: attributes,
            keys: idKeys,
            matching: isPositiveNumericID
        ) ?? (typeHint(
            in: attributes,
            containsAnyOf: ["comic", "webtoon", "board", "article"]
        ) ? firstAttributeValue(
            in: attributes,
            keys: ["data-id", "id"],
            matching: isPositiveNumericID
        ) : nil)
        guard let id else { return nil }

        let section = firstAttributeValue(
            in: attributes,
            keys: [
                "data-section", "data-bo-table", "data-botable",
                "data-board", "section", "bo-table"
            ],
            matching: isManatokiSection
        ) ?? sectionHint(in: attributes)
        guard let section else { return nil }
        return (section, id)
    }

    private static func dataAttributeLooksLikeContentCard(
        _ attributes: [String: String],
        section: String
    ) -> Bool {
        let markerKeys = [
            "data-content-id", "data-contentid", "data-post-id",
            "data-postid", "data-wr-id", "data-wrid"
        ]
        if markerKeys.contains(where: {
            attributes[$0]?.trimmed.isEmpty == false
        }) {
            return true
        }
        return typeHint(
            in: attributes,
            containsAnyOf: [section, "board", "article"]
        )
    }

    private static func sectionHint(
        in attributes: [String: String]
    ) -> String? {
        if typeHint(in: attributes, containsAnyOf: ["webtoon"]) {
            return "webtoon"
        }
        if typeHint(
            in: attributes,
            containsAnyOf: ["comic", "board", "article"]
        ) {
            return "comic"
        }
        return nil
    }

    private static func isManatokiSection(_ value: String) -> Bool {
        ["comic", "webtoon"].contains(value.lowercased())
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
