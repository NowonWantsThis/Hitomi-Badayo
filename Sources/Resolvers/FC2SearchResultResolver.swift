import Foundation

struct FC2SearchResultResolver: SearchResultResolving {
    func supports(_ baseURL: URL) -> Bool {
        guard let host = baseURL.host?.lowercased() else { return false }
        return Self.isSupportedHost(host)
    }

    static func isSupportedHost(_ host: String) -> Bool {
        host == "fc2.com" ||
            host == "www.fc2.com" ||
            host == "video.fc2.com" ||
            host == "fc2.com.test" ||
            host == "www.fc2.com.test" ||
            host == "video.fc2.com.test"
    }

    static func dataAttributeLinkValue(
        in attributes: [String: String],
        baseURL: URL?
    ) -> String? {
        guard let host = baseURL?.host?.lowercased(),
              isSupportedHost(host),
              let id = dataAttributeContentID(in: attributes),
              dataAttributeLooksLikeContentCard(attributes) else {
            return nil
        }
        return "/content/\(id)"
    }

    func extract(from context: SearchResultResolverContext) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByVideoID: [String: Int] = [:]

        for anchor in context.anchors {
            guard results.count < context.limit,
                  let absolute = context.resolvedURL(for: anchor),
                  let videoID = FC2Resolver.contentID(from: absolute),
                  let target = FC2Resolver.canonicalURL(for: absolute) else {
                continue
            }

            let title = context.title(for: anchor, fallback: "FC2 \(videoID)")
            SearchResultResolverSupport.appendUniqueResult(
                title: title,
                url: target,
                id: videoID,
                sitePrefix: "fc2",
                results: &results,
                indexByID: &indexByVideoID,
                metadata: metadata(
                    videoID: videoID,
                    title: title,
                    attributes: context.semanticAttributes(for: anchor)
                )
            )
        }

        return results
    }

    private func metadata(
        videoID: String,
        title: String,
        attributes: [String: String]
    ) -> [String: String] {
        var metadata = [
            "id": videoID,
            "content_id": videoID,
            "video_id": videoID,
            "media_id": videoID,
            "category": "fc2",
            "type": "video",
            "media_type": "video",
            "title": title,
            "search_title": title
        ]
        if let uploader = firstAttribute(attributes, keys: [
            "data-uploader", "data-uploader-name", "uploader",
            "data-author", "data-author-name", "author",
            "data-artist", "data-artist-name", "artist",
            "data-channel", "data-channel-name", "channel",
            "data-user", "data-user-name", "username"
        ]) {
            metadata["artist"] = uploader
            metadata["author"] = uploader
            metadata["creator"] = uploader
            metadata["uploader"] = uploader
            metadata["username"] = uploader
            metadata["channel"] = uploader
        }
        if let userID = firstAttribute(attributes, keys: [
            "data-user-id", "data-uploader-id", "data-channel-id", "uid", "user-id"
        ]) {
            metadata["user_id"] = userID
            metadata["uploader_id"] = userID
            metadata["channel_id"] = userID
        }
        return DownloadMetadata.clean(metadata)
    }

    private func firstAttribute(
        _ attributes: [String: String],
        keys: [String]
    ) -> String? {
        for key in keys {
            guard let value = attributes.first(where: { $0.key.lowercased() == key })?.value.trimmed,
                  !value.isEmpty else {
                continue
            }
            return value
        }
        return nil
    }

    private static func dataAttributeContentID(
        in attributes: [String: String]
    ) -> String? {
        let keys = [
            "data-content-id", "data-contentid", "data-video-id",
            "data-videoid", "data-movie-id", "data-movieid",
            "content-id", "video-id"
        ]
        for key in keys {
            if let value = attributes[key]?.trimmed,
               isValidPathSlug(value) {
                return value
            }
        }
        if let id = attributes["data-id"]?.trimmed,
           isValidPathSlug(id),
           typeHint(
               in: attributes,
               containsAnyOf: ["content", "video", "movie"]
           ) {
            return id
        }
        return nil
    }

    private static func dataAttributeLooksLikeContentCard(
        _ attributes: [String: String]
    ) -> Bool {
        let keys = [
            "data-content-id", "data-contentid", "data-video-id",
            "data-videoid", "data-movie-id", "data-movieid",
            "content-id", "video-id"
        ]
        if keys.contains(where: {
            attributes[$0]?.trimmed.isEmpty == false
        }) {
            return true
        }
        return typeHint(
            in: attributes,
            containsAnyOf: ["content", "video", "movie"]
        )
    }

    private static func isValidPathSlug(_ value: String) -> Bool {
        !value.isEmpty &&
            value.range(
                of: #"^[A-Za-z0-9][A-Za-z0-9_-]*$"#,
                options: .regularExpression
            ) != nil
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
