import Foundation

struct FlickrSearchResultResolver: SearchResultResolving {
    func supports(_ baseURL: URL) -> Bool {
        guard let host = baseURL.host?.lowercased() else { return false }
        return Self.isSupportedHost(host)
    }

    static func isSupportedHost(_ host: String) -> Bool {
        host == "flickr.com" ||
            host == "www.flickr.com" ||
            host == "flickr.test" ||
            host.hasSuffix(".flickr.com") ||
            host.hasSuffix(".flickr.test")
    }

    static func dataAttributeLinkValue(
        in attributes: [String: String],
        baseURL: URL?
    ) -> String? {
        guard let host = baseURL?.host?.lowercased(),
              isSupportedHost(host),
              let photoID = dataAttributePhotoID(in: attributes),
              let userID = dataAttributeUserID(in: attributes),
              dataAttributeLooksLikePhotoCard(attributes) else {
            return nil
        }
        return "/photos/\(userID)/\(photoID)"
    }

    func extract(from context: SearchResultResolverContext) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByContentID: [String: Int] = [:]

        for anchor in context.anchors {
            guard results.count < context.limit,
                  let absolute = context.resolvedURL(for: anchor) else {
                continue
            }

            let target: URL
            let resultID: String
            let fallback: String
            if let photoID = FlickrResolver.photoID(from: absolute),
               let photoURL = FlickrResolver.canonicalPhotoURL(for: absolute) {
                target = photoURL
                resultID = "photo:\(photoID)"
                fallback = "Flickr \(photoID)"
            } else if let userID = FlickrResolver.userID(from: absolute),
                      let userURL = FlickrResolver.canonicalUserPhotosURL(for: absolute) {
                target = userURL
                resultID = "user:\(userID.lowercased())"
                fallback = userID
            } else {
                continue
            }

            let title = context.title(for: anchor, fallback: fallback)
            SearchResultResolverSupport.appendUniqueResult(
                title: title,
                url: target,
                id: resultID,
                sitePrefix: "flickr",
                results: &results,
                indexByID: &indexByContentID,
                metadata: metadata(
                    resultID: resultID,
                    title: title,
                    target: target
                )
            )
        }

        return results
    }

    private func metadata(
        resultID: String,
        title: String,
        target: URL
    ) -> [String: String] {
        let photoID = resultID.hasPrefix("photo:")
            ? String(resultID.dropFirst("photo:".count))
            : nil
        let userID = resultID.hasPrefix("user:")
            ? String(resultID.dropFirst("user:".count))
            : FlickrResolver.userID(from: target)
        var metadata = [
            "id": photoID ?? userID ?? resultID,
            "category": "flickr",
            "type": photoID == nil ? "photostream" : "photo",
            "title": title,
            "search_title": title
        ]
        if let photoID {
            metadata["photo_id"] = photoID
            metadata["media_id"] = photoID
            metadata["gallery_id"] = photoID
        }
        if let userID {
            metadata["artist"] = userID
            metadata["author"] = userID
            metadata["creator"] = userID
            metadata["uploader"] = userID
            metadata["user"] = userID
            metadata["username"] = userID
            metadata["user_id"] = userID
        }
        metadata["source_url"] = target.absoluteString
        metadata["page_url"] = target.absoluteString
        return DownloadMetadata.clean(metadata)
    }

    private static func dataAttributePhotoID(
        in attributes: [String: String]
    ) -> String? {
        let keys = [
            "data-photo-id", "data-photoid", "data-image-id",
            "data-imageid", "photo-id"
        ]
        if let value = firstAttributeValue(
            in: attributes,
            keys: keys,
            matching: isPhotoID
        ) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           isPhotoID(id),
           typeHint(
               in: attributes,
               containsAnyOf: ["photo", "image", "picture"]
           ) {
            return id
        }
        return nil
    }

    private static func dataAttributeUserID(
        in attributes: [String: String]
    ) -> String? {
        firstAttributeValue(
            in: attributes,
            keys: [
                "data-owner", "data-owner-id", "data-ownerid",
                "data-path-alias", "data-user-id", "data-userid",
                "data-user-name", "data-username", "data-user",
                "username", "user"
            ],
            matching: isUserIDValue
        )
    }

    private static func dataAttributeLooksLikePhotoCard(
        _ attributes: [String: String]
    ) -> Bool {
        let keys = [
            "data-photo-id", "data-photoid", "data-image-id",
            "data-imageid", "photo-id"
        ]
        if keys.contains(where: {
            attributes[$0]?.trimmed.isEmpty == false
        }) {
            return true
        }
        if typeHint(
            in: attributes,
            containsAnyOf: ["profile", "user", "people", "photostream"]
        ) {
            return false
        }
        return typeHint(
            in: attributes,
            containsAnyOf: ["photo", "image", "picture"]
        )
    }

    private static func isPhotoID(_ value: String) -> Bool {
        value.range(
            of: #"^[0-9]{3,}$"#,
            options: .regularExpression
        ) != nil
    }

    private static func isUserIDValue(_ value: String) -> Bool {
        let reserved: Set<String> = [
            "explore", "groups", "photos", "search", "tags"
        ]
        return value.range(
            of: #"^[A-Za-z0-9][A-Za-z0-9@._-]{1,80}$"#,
            options: .regularExpression
        ) != nil &&
            !reserved.contains(value.lowercased())
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
}
