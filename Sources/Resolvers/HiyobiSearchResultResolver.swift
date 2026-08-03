import Foundation

struct HiyobiSearchResultResolver: SearchResultResolving {
    func supports(_ baseURL: URL) -> Bool {
        guard let host = baseURL.host?.lowercased() else { return false }
        return Self.isSupportedHost(host)
    }

    static func isSupportedHost(_ host: String) -> Bool {
        host == "hiyobi.me" ||
            host == "www.hiyobi.me" ||
            host == "hiyobi.test" ||
            host == "www.hiyobi.test"
    }

    static func dataAttributeLinkValue(
        in attributes: [String: String],
        baseURL: URL
    ) -> String? {
        guard let host = baseURL.host?.lowercased(),
              isSupportedHost(host),
              let galleryID = dataAttributeGalleryID(in: attributes),
              dataAttributeLooksLikeGalleryCard(attributes) else {
            return nil
        }
        return "/reader/\(galleryID)"
    }

    func extract(from context: SearchResultResolverContext) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByGallery: [String: Int] = [:]

        for anchor in context.anchors {
            guard results.count < context.limit,
                  let absolute = context.resolvedURL(for: anchor),
                  let host = absolute.host?.lowercased(),
                  Self.isSupportedHost(host),
                  let galleryID = HiyobiResolver.galleryID(from: absolute),
                  let target = canonicalSearchURL(
                      absolute,
                      galleryID: galleryID
                  ) else {
                continue
            }

            let title = context.title(
                for: anchor,
                fallback: "Hiyobi \(galleryID)"
            )
            SearchResultResolverSupport.appendUniqueResult(
                title: title,
                url: target,
                id: galleryID,
                sitePrefix: "hiyobi",
                results: &results,
                indexByID: &indexByGallery,
                metadata: metadata(
                    galleryID: galleryID,
                    title: title,
                    contributorMetadata: context.contributorMetadata(
                        for: anchor
                    )
                )
            )
        }

        return results
    }

    private func canonicalSearchURL(
        _ url: URL,
        galleryID: String
    ) -> URL? {
        guard var components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        ) else {
            return nil
        }
        components.path = "/reader/\(galleryID)"
        components.queryItems = nil
        components.fragment = nil
        return components.url
    }

    private func metadata(
        galleryID: String,
        title: String,
        contributorMetadata: [String: String]
    ) -> [String: String] {
        var metadata = contributorMetadata
        metadata.merge([
            "id": galleryID,
            "post_id": galleryID,
            "gallery_id": galleryID,
            "media_id": galleryID,
            "category": "hiyobi",
            "type": "gallery",
            "title": title,
            "search_title": title
        ]) { current, _ in current }
        return DownloadMetadata.clean(metadata)
    }

    private static func dataAttributeGalleryID(
        in attributes: [String: String]
    ) -> String? {
        let explicitKeys = [
            "data-gallery-id", "data-galleryid", "data-reader-id",
            "data-readerid", "data-post-id", "data-postid", "gallery-id"
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
            containsAnyOf: ["gallery", "reader", "post"]
        ) else {
            return nil
        }
        return firstAttributeValue(
            in: attributes,
            keys: ["data-id", "id"],
            matching: isPositiveNumericID
        )
    }

    private static func dataAttributeLooksLikeGalleryCard(
        _ attributes: [String: String]
    ) -> Bool {
        let markerKeys = [
            "data-gallery-id", "data-galleryid", "data-reader-id",
            "data-readerid", "data-post-id", "data-postid"
        ]
        if markerKeys.contains(where: {
            attributes[$0]?.trimmed.isEmpty == false
        }) {
            return true
        }
        return typeHint(
            in: attributes,
            containsAnyOf: ["gallery", "reader", "post"]
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
