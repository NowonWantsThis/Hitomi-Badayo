import Foundation

struct V2PHSearchResultResolver: SearchResultResolving {
    func supports(_ baseURL: URL) -> Bool {
        guard let host = baseURL.host?.lowercased() else { return false }
        return Self.isSupportedHost(host)
    }

    static func isSupportedHost(_ host: String) -> Bool {
        host == "v2ph.com" ||
            host == "www.v2ph.com" ||
            host == "v2ph.test" ||
            host == "www.v2ph.test"
    }

    static func dataAttributeLinkValue(
        in attributes: [String: String],
        baseURL: URL?
    ) -> String? {
        guard let baseURL,
              let host = baseURL.host?.lowercased(),
              isSupportedHost(host),
              let albumID = dataAttributeAlbumID(in: attributes),
              dataAttributeLooksLikeAlbumCard(attributes) else {
            return nil
        }
        return "/album/\(albumID)"
    }

    func extract(from context: SearchResultResolverContext) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByAlbumID: [String: Int] = [:]

        for anchor in context.anchors {
            guard results.count < context.limit,
                  let absolute = context.resolvedURL(for: anchor),
                  let host = absolute.host?.lowercased(),
                  Self.isSupportedHost(host),
                  let albumID = V2PHResolver.albumID(from: absolute),
                  let target = V2PHResolver.canonicalAlbumURL(for: absolute) else {
                continue
            }

            let title = context.title(for: anchor, fallback: "V2PH \(albumID)")
            SearchResultResolverSupport.appendUniqueResult(
                title: title,
                url: target,
                id: albumID,
                sitePrefix: "v2ph",
                results: &results,
                indexByID: &indexByAlbumID,
                metadata: metadata(
                    albumID: albumID,
                    title: title,
                    contributorMetadata: context.contributorMetadata(for: anchor)
                )
            )
        }

        return results
    }

    private func metadata(
        albumID: String,
        title: String,
        contributorMetadata: [String: String]
    ) -> [String: String] {
        var metadata = contributorMetadata
        metadata.merge([
            "id": albumID,
            "album_id": albumID,
            "gallery_id": albumID,
            "media_id": albumID,
            "category": "v2ph",
            "type": "album",
            "title": title,
            "search_title": title
        ]) { current, _ in current }
        return DownloadMetadata.clean(metadata)
    }

    private static func dataAttributeAlbumID(
        in attributes: [String: String]
    ) -> String? {
        let keys = [
            "data-album-id", "data-albumid", "data-gallery-id",
            "data-galleryid", "album-id"
        ]
        if let value = firstAttributeValue(
            in: attributes,
            keys: keys,
            matching: isValidPathSlug
        ) {
            return value
        }
        guard typeHint(
            in: attributes,
            containsAnyOf: ["album", "gallery"]
        ) else {
            return nil
        }
        return firstAttributeValue(
            in: attributes,
            keys: ["data-id", "id"],
            matching: isValidPathSlug
        )
    }

    private static func dataAttributeLooksLikeAlbumCard(
        _ attributes: [String: String]
    ) -> Bool {
        let keys = [
            "data-album-id", "data-albumid", "data-gallery-id",
            "data-galleryid", "album-id"
        ]
        if keys.contains(where: {
            attributes[$0]?.trimmed.isEmpty == false
        }) {
            return true
        }
        return typeHint(
            in: attributes,
            containsAnyOf: ["album", "gallery"]
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

    private static func isValidPathSlug(_ value: String) -> Bool {
        !value.isEmpty &&
            value.range(
                of: #"^[A-Za-z0-9][A-Za-z0-9_-]*$"#,
                options: .regularExpression
            ) != nil
    }
}
