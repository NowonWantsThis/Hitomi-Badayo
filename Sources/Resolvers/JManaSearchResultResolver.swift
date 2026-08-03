import Foundation

struct JManaSearchResultResolver: SearchResultResolving {
    private enum DataAttributeKind {
        case chapter
        case series
        case title
    }

    func supports(_ baseURL: URL) -> Bool {
        guard let host = baseURL.host?.lowercased() else { return false }
        return Self.isSupportedHost(host)
    }

    static func isSupportedHost(_ host: String) -> Bool {
        host.range(
            of: #"(^|\.)jmana[0-9]*(\.|$)"#,
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
                  kind: content.kind
              ) else {
            return nil
        }

        switch content.kind {
        case .chapter:
            return relativeURL(
                path: "/bookdetail",
                queryItems: [
                    URLQueryItem(name: "book", value: content.book),
                    URLQueryItem(
                        name: "bookdetailid",
                        value: content.detailID
                    )
                ]
            )
        case .series:
            return relativeURL(
                path: "/book",
                queryItems: [
                    URLQueryItem(name: "book", value: content.book)
                ]
            )
        case .title:
            return relativeURL(
                path: "/book_by_title",
                queryItems: [
                    URLQueryItem(name: "title", value: content.title)
                ]
            )
        }
    }

    func extract(from context: SearchResultResolverContext) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByURL: [String: Int] = [:]

        for anchor in context.anchors {
            guard results.count < context.limit,
                  let absolute = context.resolvedURL(for: anchor),
                  let target = JManaResolver.canonicalURL(for: absolute) else {
                continue
            }

            let title = context.title(for: anchor, fallbackURL: target)
            SearchResultResolverSupport.appendUniqueResult(
                title: title,
                url: target,
                id: URLIdentity.normalize(target.absoluteString),
                sitePrefix: "jmana",
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
        let items = URLComponents(
            url: target,
            resolvingAgainstBaseURL: false
        )?.queryItems ?? []
        let book = queryValue("book", in: items) ?? ""
        let detailID = queryValue("bookdetailid", in: items) ?? ""
        let titleQuery = queryValue("title", in: items) ?? ""
        var metadata = contributorMetadata
        metadata.merge([
            "category": "jmana",
            "title": title,
            "search_title": title
        ]) { current, _ in current }
        if !detailID.isEmpty {
            metadata["id"] = detailID
            metadata["post_id"] = detailID
            metadata["chapter_id"] = detailID
            metadata["media_id"] = detailID
            metadata["book"] = book
            metadata["series_id"] = book
            metadata["gallery_id"] = book.isEmpty ? detailID : book
            metadata["type"] = "chapter"
        } else if !book.isEmpty {
            metadata["id"] = book
            metadata["book"] = book
            metadata["series_id"] = book
            metadata["gallery_id"] = book
            metadata["type"] = "series"
        } else if !titleQuery.isEmpty {
            metadata["id"] = titleQuery
            metadata["tag"] = titleQuery
            metadata["type"] = "search"
        }
        return DownloadMetadata.clean(metadata)
    }

    private static func dataAttributeContent(
        in attributes: [String: String]
    ) -> (
        kind: DataAttributeKind,
        book: String,
        detailID: String,
        title: String
    )? {
        let book = firstAttributeValue(
            in: attributes,
            keys: [
                "data-book", "data-book-id", "data-bookid",
                "data-series-id", "data-seriesid", "book", "book-id"
            ],
            matching: isToken
        )
        let detailID = firstAttributeValue(
            in: attributes,
            keys: [
                "data-bookdetailid", "data-book-detail-id", "data-detail-id",
                "data-detailid", "data-chapter-id", "data-chapterid",
                "bookdetailid", "book-detail-id"
            ],
            matching: isPositiveNumericID
        ) ?? (typeHint(
            in: attributes,
            containsAnyOf: ["chapter", "detail"]
        ) ? firstAttributeValue(
            in: attributes,
            keys: ["data-id", "id"],
            matching: isPositiveNumericID
        ) : nil)

        if let book, let detailID {
            return (.chapter, book, detailID, "")
        }
        if let book, dataAttributeLooksLikeSeriesCard(attributes) {
            return (.series, book, "", "")
        }

        let title = firstAttributeValue(
            in: attributes,
            keys: [
                "data-title", "data-title-query", "data-keyword",
                "data-query", "title"
            ],
            matching: isToken
        )
        if let title, dataAttributeLooksLikeTitleCard(attributes) {
            return (.title, "", "", title)
        }

        return nil
    }

    private static func dataAttributeLooksLikeContentCard(
        _ attributes: [String: String],
        kind: DataAttributeKind
    ) -> Bool {
        switch kind {
        case .chapter:
            let markerKeys = [
                "data-bookdetailid", "data-book-detail-id",
                "data-detail-id", "data-detailid",
                "data-chapter-id", "data-chapterid"
            ]
            if markerKeys.contains(where: {
                attributes[$0]?.trimmed.isEmpty == false
            }) {
                return true
            }
            return typeHint(
                in: attributes,
                containsAnyOf: ["chapter", "detail"]
            )
        case .series:
            return dataAttributeLooksLikeSeriesCard(attributes)
        case .title:
            return dataAttributeLooksLikeTitleCard(attributes)
        }
    }

    private static func dataAttributeLooksLikeSeriesCard(
        _ attributes: [String: String]
    ) -> Bool {
        let markerKeys = ["data-book", "data-book-id", "data-bookid"]
        if markerKeys.contains(where: {
            attributes[$0]?.trimmed.isEmpty == false
        }) {
            return true
        }
        return typeHint(
            in: attributes,
            containsAnyOf: ["book", "series"]
        )
    }

    private static func dataAttributeLooksLikeTitleCard(
        _ attributes: [String: String]
    ) -> Bool {
        let markerKeys = [
            "data-title", "data-title-query", "data-keyword", "data-query"
        ]
        if markerKeys.contains(where: {
            attributes[$0]?.trimmed.isEmpty == false
        }) {
            return true
        }
        return typeHint(
            in: attributes,
            containsAnyOf: ["title", "search", "keyword"]
        )
    }

    private static func relativeURL(
        path: String,
        queryItems: [URLQueryItem]
    ) -> String? {
        var components = URLComponents()
        components.path = path
        components.queryItems = queryItems
        return components.string
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

    private static func isToken(_ value: String) -> Bool {
        value.count <= 160 &&
            value.range(
                of: #"^[A-Za-z0-9][A-Za-z0-9_-]*$"#,
                options: .regularExpression
            ) != nil
    }

    private func queryValue(
        _ name: String,
        in items: [URLQueryItem]
    ) -> String? {
        items.first { $0.name.lowercased() == name.lowercased() }?.value
    }
}
