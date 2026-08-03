import Foundation

struct SpankBangSearchResultResolver: SearchResultResolving {
    func supports(_ baseURL: URL) -> Bool {
        guard let host = baseURL.host?.lowercased() else { return false }
        return Self.isSupportedHost(host)
    }

    static func isSupportedHost(_ host: String) -> Bool {
        host == "spankbang.com" ||
            host == "www.spankbang.com" ||
            host == "spankbang.test" ||
            host == "www.spankbang.test"
    }

    static func dataAttributeLinkValue(
        in attributes: [String: String],
        baseURL: URL?
    ) -> String? {
        guard let host = baseURL?.host?.lowercased(),
              isSupportedHost(host),
              let id = dataAttributeVideoID(in: attributes),
              dataAttributeLooksLikeVideoCard(attributes) else {
            return nil
        }
        return "/\(id)/video"
    }

    func extract(from context: SearchResultResolverContext) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByID: [String: Int] = [:]

        for anchor in context.anchors {
            guard results.count < context.limit,
                  let absolute = context.resolvedURL(for: anchor),
                  let videoID = SpankBangResolver.videoID(from: absolute) else {
                continue
            }
            let target = SpankBangResolver.canonicalURL(
                for: videoID,
                sourceURL: absolute
            )
            let title = context.title(
                for: anchor,
                fallback: "SpankBang \(videoID)"
            )
            SearchResultResolverSupport.appendUniqueResult(
                title: title,
                url: target,
                id: videoID,
                sitePrefix: "spankbang",
                results: &results,
                indexByID: &indexByID,
                metadata: metadata(
                    videoID: videoID,
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
        videoID: String,
        title: String,
        contributorMetadata: [String: String]
    ) -> [String: String] {
        var metadata = [
            "id": videoID,
            "video_id": videoID,
            "media_id": videoID,
            "gallery_id": videoID,
            "category": "spankbang",
            "type": "video",
            "media_type": "video",
            "title": title,
            "search_title": title
        ]
        metadata.merge(contributorMetadata) { current, _ in current }
        return DownloadMetadata.clean(metadata)
    }

    private static func dataAttributeVideoID(
        in attributes: [String: String]
    ) -> String? {
        let keys = [
            "data-video-id", "data-videoid", "data-media-id",
            "data-mediaid", "video-id"
        ]
        if let value = firstAttributeValue(
            in: attributes,
            keys: keys,
            matching: isValidID
        ) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           isValidID(id),
           typeHint(
               in: attributes,
               containsAnyOf: ["video", "watch"]
           ) {
            return id
        }
        return nil
    }

    private static func dataAttributeLooksLikeVideoCard(
        _ attributes: [String: String]
    ) -> Bool {
        let keys = [
            "data-video-id", "data-videoid", "data-media-id",
            "data-mediaid", "video-id"
        ]
        if keys.contains(where: {
            attributes[$0]?.trimmed.isEmpty == false
        }) {
            return true
        }
        return typeHint(
            in: attributes,
            containsAnyOf: ["video", "watch"]
        )
    }

    private static func isValidID(_ value: String) -> Bool {
        guard value.range(
            of: #"^[0-9A-Za-z_-]+$"#,
            options: .regularExpression
        ) != nil else {
            return false
        }
        let reserved: Set<String> = [
            "s", "search", "tag", "tags", "category", "categories",
            "users", "user", "channels", "channel", "pornstars",
            "playlist"
        ]
        return !reserved.contains(value.lowercased())
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
}
