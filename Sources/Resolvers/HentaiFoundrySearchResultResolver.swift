import Foundation

struct HentaiFoundrySearchResultResolver: SearchResultResolving {
    func supports(_ baseURL: URL) -> Bool {
        guard let host = baseURL.host?.lowercased() else { return false }
        return Self.isSupportedHost(host)
    }

    static func isSupportedHost(_ host: String) -> Bool {
        host == "hentai-foundry.com" ||
            host == "www.hentai-foundry.com" ||
            host == "hentai-foundry.test" ||
            host == "www.hentai-foundry.test"
    }

    static func dataAttributeLinkValue(
        in attributes: [String: String],
        baseURL: URL?
    ) -> String? {
        guard let baseURL,
              let host = baseURL.host?.lowercased(),
              isSupportedHost(host) else {
            return nil
        }

        if let picture = dataAttributePicture(in: attributes),
           dataAttributeLooksLikePictureCard(attributes) {
            return "/pictures/user/\(picture.username)/\(picture.id)"
        }

        if let username = dataAttributeGalleryUsername(in: attributes),
           dataAttributeLooksLikeGalleryCard(attributes) {
            return "/pictures/user/\(username)"
        }

        return nil
    }

    func extract(from context: SearchResultResolverContext) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByContentID: [String: Int] = [:]

        for anchor in context.anchors {
            guard results.count < context.limit,
                  let absolute = context.resolvedURL(for: anchor),
                  let target = HentaiFoundryResolver.canonicalContentURL(from: absolute) else {
                continue
            }

            let resultID: String
            let fallback: String
            if let picture = HentaiFoundryResolver.picturePageInfo(from: target) {
                resultID = "picture:\(picture.username.lowercased()):\(picture.id)"
                fallback = "Hentai Foundry \(picture.id)"
            } else if let username = HentaiFoundryResolver.galleryUsername(from: target) {
                resultID = "gallery:\(username.lowercased())"
                fallback = username
            } else {
                continue
            }

            let title = context.title(for: anchor, fallback: fallback)
            SearchResultResolverSupport.appendUniqueResult(
                title: title,
                url: target,
                id: resultID,
                sitePrefix: "hentaifoundry",
                results: &results,
                indexByID: &indexByContentID,
                metadata: metadata(
                    target: target,
                    title: title,
                    contributorMetadata: context.contributorMetadata(for: anchor)
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
        var metadata = contributorMetadata
        metadata.merge([
            "category": "hentai_foundry",
            "title": title,
            "search_title": title
        ]) { current, _ in current }
        if let picture = HentaiFoundryResolver.picturePageInfo(from: target) {
            metadata["id"] = picture.id
            metadata["post_id"] = picture.id
            metadata["picture_id"] = picture.id
            metadata["gallery_id"] = picture.id
            metadata["media_id"] = picture.id
            metadata["username"] = picture.username
            metadata["uploader"] = metadata["uploader"] ?? picture.username
            metadata["uploader_id"] = picture.username
            metadata["type"] = "picture"
        } else if let username = HentaiFoundryResolver.galleryUsername(from: target) {
            metadata["id"] = username
            metadata["username"] = username
            metadata["user"] = username
            metadata["uploader"] = metadata["uploader"] ?? username
            metadata["uploader_id"] = username
            metadata["gallery_id"] = username
            metadata["type"] = "gallery"
        }
        return DownloadMetadata.clean(metadata)
    }

    private static func dataAttributePicture(
        in attributes: [String: String]
    ) -> (username: String, id: String)? {
        let idKeys = [
            "data-picture-id", "data-pictureid", "data-post-id",
            "data-postid", "data-art-id", "data-artid", "picture-id"
        ]
        let id = firstAttributeValue(
            in: attributes,
            keys: idKeys,
            matching: isPositiveNumericID
        ) ??
            (typeHint(
                in: attributes,
                containsAnyOf: ["picture", "post", "art"]
            )
                ? firstAttributeValue(
                    in: attributes,
                    keys: ["data-id", "id"],
                    matching: isPositiveNumericID
                )
                : nil)
        guard let id,
              let username = dataAttributeUsername(in: attributes) else {
            return nil
        }
        return (username, id)
    }

    private static func dataAttributeGalleryUsername(
        in attributes: [String: String]
    ) -> String? {
        let keys = [
            "data-gallery-user", "data-gallery-username", "data-artist",
            "data-username", "data-user", "username", "user", "artist"
        ]
        if let username = firstAttributeValue(
            in: attributes,
            keys: keys,
            matching: isValidPathSlug
        ) {
            return username
        }
        guard typeHint(
            in: attributes,
            containsAnyOf: ["gallery", "artist", "user", "profile"]
        ) else {
            return nil
        }
        return firstAttributeValue(
            in: attributes,
            keys: ["data-id", "id"],
            matching: isValidPathSlug
        )
    }

    private static func dataAttributeUsername(
        in attributes: [String: String]
    ) -> String? {
        firstAttributeValue(
            in: attributes,
            keys: [
                "data-artist", "data-username", "data-user",
                "username", "user", "artist"
            ],
            matching: isValidPathSlug
        )
    }

    private static func dataAttributeLooksLikePictureCard(
        _ attributes: [String: String]
    ) -> Bool {
        let keys = [
            "data-picture-id", "data-pictureid", "data-post-id",
            "data-postid", "data-art-id", "data-artid", "picture-id"
        ]
        if keys.contains(where: {
            attributes[$0]?.trimmed.isEmpty == false
        }) {
            return true
        }
        return typeHint(
            in: attributes,
            containsAnyOf: ["picture", "post", "art"]
        )
    }

    private static func dataAttributeLooksLikeGalleryCard(
        _ attributes: [String: String]
    ) -> Bool {
        let keys = [
            "data-gallery-user", "data-gallery-username"
        ]
        if keys.contains(where: {
            attributes[$0]?.trimmed.isEmpty == false
        }) {
            return true
        }
        return typeHint(
            in: attributes,
            containsAnyOf: ["gallery", "artist", "user", "profile"]
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

    private static func isValidPathSlug(_ value: String) -> Bool {
        !value.isEmpty &&
            value.range(
                of: #"^[A-Za-z0-9][A-Za-z0-9_-]*$"#,
                options: .regularExpression
            ) != nil
    }
}
