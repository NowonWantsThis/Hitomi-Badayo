import Foundation

struct IwaraSearchResultResolver: SearchResultResolving {
    func supports(_ baseURL: URL) -> Bool {
        guard let host = baseURL.host?.lowercased() else { return false }
        return Self.isSupportedHost(host)
    }

    static func isSupportedHost(_ host: String) -> Bool {
        host == "iwara.tv" ||
            host == "www.iwara.tv" ||
            host == "iwara.test" ||
            host == "www.iwara.test"
    }

    static func dataAttributeLinkValue(
        in attributes: [String: String],
        baseURL: URL?
    ) -> String? {
        guard let host = baseURL?.host?.lowercased(),
              isSupportedHost(host) else {
            return nil
        }

        if let id = dataAttributeImageID(in: attributes),
           dataAttributeLooksLikeImageCard(attributes) {
            return "/image/\(id)"
        }
        if let id = dataAttributeVideoID(in: attributes),
           dataAttributeLooksLikeVideoCard(attributes) {
            return "/video/\(id)"
        }
        return nil
    }

    static func mediaURL(from url: URL) -> URL? {
        guard let host = url.host?.lowercased(),
              isSupportedHost(host),
              let clean = cleanedURL(url) else {
            return nil
        }
        let parts = clean.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        let lower = parts.map { $0.lowercased() }
        guard ["image", "video", "videos"].contains(lower.first ?? ""),
              parts.count >= 2,
              isValidPathSlug(parts[1]) else {
            return nil
        }
        if lower.first == "image" {
            return cleanedURL(clean, path: "/image/\(parts[1])")
        }
        return clean
    }

    func extract(from context: SearchResultResolverContext) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByID: [String: Int] = [:]

        for anchor in context.anchors {
            guard results.count < context.limit,
                  let absolute = context.resolvedURL(for: anchor),
                  let target = Self.queueURL(from: absolute),
                  let key = Self.resultKey(for: target) else {
                continue
            }

            let title = context.title(for: anchor, fallbackURL: target)
            SearchResultResolverSupport.appendUniqueResult(
                title: title,
                url: target,
                id: key,
                sitePrefix: "iwara",
                results: &results,
                indexByID: &indexByID,
                metadata: metadata(
                    key: key,
                    title: title,
                    target: target,
                    contributorMetadata: context.contributorMetadata(
                        for: anchor
                    )
                )
            )
        }

        return results
    }

    private func metadata(
        key: String,
        title: String,
        target: URL,
        contributorMetadata: [String: String]
    ) -> [String: String] {
        var metadata = [
            "id": key,
            "category": "iwara",
            "title": title,
            "search_title": title
        ]
        if let imageID = IwaraImageResolver.imageID(from: target) {
            metadata["id"] = imageID
            metadata["image_id"] = imageID
            metadata["media_id"] = imageID
            metadata["gallery_id"] = imageID
            metadata["type"] = "image"
            metadata["media_type"] = "image"
        } else if let videoID = IwaraVideoResolver.videoID(from: target) {
            metadata["id"] = videoID
            metadata["video_id"] = videoID
            metadata["media_id"] = videoID
            metadata["gallery_id"] = videoID
            metadata["type"] = "video"
            metadata["media_type"] = "video"
        }
        metadata.merge(contributorMetadata) { current, _ in current }
        return DownloadMetadata.clean(metadata)
    }

    private static func queueURL(from url: URL) -> URL? {
        if let imageID = IwaraImageResolver.imageID(from: url) {
            return IwaraImageResolver.canonicalURL(
                for: imageID,
                sourceURL: url
            )
        }
        if let videoID = IwaraVideoResolver.videoID(from: url) {
            return IwaraVideoResolver.canonicalURL(
                for: videoID,
                sourceURL: url
            )
        }

        guard let host = url.host?.lowercased(),
              isSupportedHost(host) else {
            return nil
        }
        let parts = url.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        let lower = parts.map { $0.lowercased() }
        if lower.first == "videos",
           parts.count >= 2,
           isValidPathSlug(parts[1]) {
            return IwaraVideoResolver.canonicalURL(
                for: parts[1],
                sourceURL: url
            )
        }
        return nil
    }

    private static func resultKey(for url: URL) -> String? {
        if let imageID = IwaraImageResolver.imageID(from: url) {
            return "image-\(imageID)"
        }
        if let videoID = IwaraVideoResolver.videoID(from: url) {
            return "video-\(videoID)"
        }
        return nil
    }

    private static func dataAttributeImageID(
        in attributes: [String: String]
    ) -> String? {
        let keys = ["data-image-id", "data-imageid", "image-id"]
        if let value = firstAttributeValue(
            in: attributes,
            keys: keys,
            matching: isValidPathSlug
        ) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           isValidPathSlug(id),
           typeHint(in: attributes, containsAnyOf: ["image", "photo"]) {
            return id
        }
        return nil
    }

    private static func dataAttributeVideoID(
        in attributes: [String: String]
    ) -> String? {
        let keys = ["data-video-id", "data-videoid", "video-id"]
        if let value = firstAttributeValue(
            in: attributes,
            keys: keys,
            matching: isValidPathSlug
        ) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           isValidPathSlug(id),
           typeHint(in: attributes, containsAnyOf: ["video"]) {
            return id
        }
        return nil
    }

    private static func dataAttributeLooksLikeImageCard(
        _ attributes: [String: String]
    ) -> Bool {
        if ["data-image-id", "data-imageid", "image-id"].contains(
            where: { attributes[$0]?.trimmed.isEmpty == false }
        ) {
            return true
        }
        return typeHint(in: attributes, containsAnyOf: ["image", "photo"])
    }

    private static func dataAttributeLooksLikeVideoCard(
        _ attributes: [String: String]
    ) -> Bool {
        if ["data-video-id", "data-videoid", "video-id"].contains(
            where: { attributes[$0]?.trimmed.isEmpty == false }
        ) {
            return true
        }
        return typeHint(in: attributes, containsAnyOf: ["video"])
    }

    private static func isValidPathSlug(_ value: String) -> Bool {
        !value.isEmpty &&
            value.range(
                of: #"^[A-Za-z0-9][A-Za-z0-9_-]*$"#,
                options: .regularExpression
            ) != nil
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

    private static func cleanedURL(
        _ url: URL,
        path: String? = nil
    ) -> URL? {
        guard var components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        ) else {
            return nil
        }
        if let path {
            components.path = path
        }
        components.queryItems = nil
        components.fragment = nil
        return components.url
    }
}
