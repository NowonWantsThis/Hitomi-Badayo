import Foundation

struct AsmHentaiSearchResultResolver: SearchResultResolving {
    func supports(_ baseURL: URL) -> Bool {
        guard let host = baseURL.host?.lowercased() else { return false }
        return Self.isSupportedHost(host)
    }

    static func isSupportedHost(_ host: String) -> Bool {
        host == "asmhentai.com" ||
            host == "www.asmhentai.com" ||
            host == "asmhentai.test" ||
            host == "www.asmhentai.test"
    }

    static func dataAttributeLinkValue(
        in attributes: [String: String],
        baseURL: URL?
    ) -> String? {
        guard let baseURL,
              let host = baseURL.host?.lowercased(),
              isSupportedHost(host),
              let galleryID = dataAttributeGalleryID(in: attributes),
              dataAttributeLooksLikeGalleryCard(attributes) else {
            return nil
        }
        return "/gallery/\(galleryID)"
    }

    func extract(from context: SearchResultResolverContext) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByGalleryID: [String: Int] = [:]

        for anchor in context.anchors {
            guard results.count < context.limit,
                  let absolute = context.resolvedURL(for: anchor),
                  let host = absolute.host?.lowercased(),
                  Self.isSupportedHost(host),
                  let galleryID = AsmHentaiResolver.galleryID(from: absolute) else {
                continue
            }

            let title = context.title(
                for: anchor,
                fallback: "AsmHentai \(galleryID)"
            )
            SearchResultResolverSupport.appendUniqueResult(
                title: title,
                url: AsmHentaiResolver.canonicalGalleryURL(
                    for: galleryID,
                    sourceURL: absolute
                ),
                id: galleryID,
                sitePrefix: "asmhentai",
                results: &results,
                indexByID: &indexByGalleryID,
                metadata: metadata(
                    galleryID: galleryID,
                    title: title,
                    contributorMetadata: context.contributorMetadata(for: anchor)
                )
            )
        }

        return results
    }

    private func metadata(
        galleryID: String,
        title: String,
        contributorMetadata: [String: String]
    ) -> [String: String] {
        var metadata = contributorMetadata
        metadata.merge([
            "id": galleryID,
            "gallery_id": galleryID,
            "media_id": galleryID,
            "category": "asmhentai",
            "type": "gallery",
            "slug": galleryID,
            "title": title,
            "search_title": title
        ]) { current, _ in current }
        return DownloadMetadata.clean(metadata)
    }

    private static func dataAttributeGalleryID(
        in attributes: [String: String]
    ) -> String? {
        let keys = [
            "data-gallery-id", "data-galleryid", "data-gid",
            "data-asmhentai-id", "gallery-id", "gid"
        ]
        if let value = firstAttributeValue(
            in: attributes,
            keys: keys,
            matching: isPositiveNumericID
        ) {
            return value
        }
        guard typeHint(
            in: attributes,
            containsAnyOf: ["gallery", "asmhentai"]
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
        let keys = [
            "data-gallery-id", "data-galleryid", "data-gid",
            "data-asmhentai-id", "gallery-id", "gid"
        ]
        if keys.contains(where: {
            attributes[$0]?.trimmed.isEmpty == false
        }) {
            return true
        }
        return typeHint(
            in: attributes,
            containsAnyOf: ["gallery", "asmhentai"]
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

    private static func isPositiveNumericID(_ value: String) -> Bool {
        value.range(
            of: #"^[0-9]+$"#,
            options: .regularExpression
        ) != nil
    }
}
