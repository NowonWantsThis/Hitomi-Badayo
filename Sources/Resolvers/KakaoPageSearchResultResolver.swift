import Foundation

struct KakaoPageSearchResultResolver: SearchResultResolving {
    func supports(_ baseURL: URL) -> Bool {
        guard let host = baseURL.host?.lowercased() else { return false }
        return Self.isSupportedHost(host)
    }

    static func isSupportedHost(_ host: String) -> Bool {
        host == "page.kakao.com" ||
            host == "page.kakao.test"
    }

    static func dataAttributeLinkValue(
        in attributes: [String: String],
        baseURL: URL
    ) -> String? {
        guard let host = baseURL.host?.lowercased(),
              isSupportedHost(host),
              let item = dataAttributeItem(in: attributes),
              dataAttributeLooksLikeItemCard(attributes, item: item) else {
            return nil
        }
        if let productID = item.productID {
            return "/content/\(item.seriesID)/viewer/\(productID)"
        }
        return "/content/\(item.seriesID)"
    }

    func extract(from context: SearchResultResolverContext) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByKey: [String: Int] = [:]

        for anchor in context.anchors {
            guard results.count < context.limit,
                  let absolute = context.resolvedURL(for: anchor),
                  let target = KakaoPageResolver.canonicalURL(for: absolute) else {
                continue
            }

            let title = context.title(for: anchor, fallbackURL: target)
            SearchResultResolverSupport.appendUniqueResult(
                title: title,
                url: target,
                id: resultKey(for: target),
                sitePrefix: "kakaopage",
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

    private func resultKey(for url: URL) -> String {
        if let ids = KakaoPageResolver.viewerIDs(from: url) {
            return "viewer:\(ids.seriesID):\(ids.productID)"
        }
        if let seriesID = KakaoPageResolver.seriesID(from: url) {
            return "series:\(seriesID)"
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
            "category": "kakaopage",
            "title": title,
            "search_title": title
        ]) { current, _ in current }
        if let ids = KakaoPageResolver.viewerIDs(from: target) {
            metadata["id"] = ids.productID
            metadata["post_id"] = ids.productID
            metadata["episode_id"] = ids.productID
            metadata["product_id"] = ids.productID
            metadata["media_id"] = ids.productID
            metadata["series_id"] = ids.seriesID
            metadata["gallery_id"] = ids.seriesID
            metadata["type"] = "episode"
        } else if let seriesID = KakaoPageResolver.seriesID(from: target) {
            metadata["id"] = seriesID
            metadata["series_id"] = seriesID
            metadata["gallery_id"] = seriesID
            metadata["type"] = "series"
        }
        return DownloadMetadata.clean(metadata)
    }

    private static func dataAttributeItem(
        in attributes: [String: String]
    ) -> (seriesID: String, productID: String?)? {
        let seriesID = firstAttributeValue(
            in: attributes,
            keys: [
                "data-series-id", "data-seriesid", "data-content-id",
                "data-contentid", "data-work-id", "data-workid", "series-id"
            ],
            matching: isPositiveNumericID
        ) ?? (typeHint(
            in: attributes,
            containsAnyOf: ["series", "content", "work"]
        ) ? firstAttributeValue(
            in: attributes,
            keys: ["data-id", "id"],
            matching: isPositiveNumericID
        ) : nil)
        guard let seriesID else { return nil }

        let productID = firstAttributeValue(
            in: attributes,
            keys: [
                "data-product-id", "data-productid", "data-episode-id",
                "data-episodeid", "data-viewer-id", "data-viewerid",
                "product-id", "episode-id"
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
        return (seriesID, productID)
    }

    private static func dataAttributeLooksLikeItemCard(
        _ attributes: [String: String],
        item: (seriesID: String, productID: String?)
    ) -> Bool {
        if item.productID != nil {
            let markerKeys = [
                "data-product-id", "data-productid", "data-episode-id",
                "data-episodeid", "data-viewer-id", "data-viewerid"
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

        let markerKeys = [
            "data-series-id", "data-seriesid", "data-content-id",
            "data-contentid", "data-work-id", "data-workid"
        ]
        if markerKeys.contains(where: {
            attributes[$0]?.trimmed.isEmpty == false
        }) {
            return true
        }
        return typeHint(
            in: attributes,
            containsAnyOf: ["series", "content", "work"]
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
