import Foundation

struct PornhubSearchResultResolver: SearchResultResolving {
    func supports(_ baseURL: URL) -> Bool {
        guard let host = baseURL.host?.lowercased() else { return false }
        return Self.isSupportedHost(host)
    }

    static func isSupportedHost(_ host: String) -> Bool {
        host == "pornhub.com" ||
            host == "www.pornhub.com" ||
            host == "pornhubthbh7ap3u.onion" ||
            host == "www.pornhubthbh7ap3u.onion" ||
            host == "pornhubpremium.com" ||
            host == "www.pornhubpremium.com" ||
            host == "pornhub.test" ||
            host == "www.pornhub.test"
    }

    static func dataAttributeLinkValue(
        in attributes: [String: String],
        baseURL: URL?
    ) -> String? {
        guard let host = baseURL?.host?.lowercased(),
              isSupportedHost(host) else {
            return nil
        }

        if let id = dataAttributeVideoID(in: attributes),
           dataAttributeLooksLikeVideoCard(attributes) {
            return "/view_video.php?viewkey=\(id)"
        }
        if let id = dataAttributeGifID(in: attributes),
           dataAttributeLooksLikeGifCard(attributes) {
            return "/gif/\(id)"
        }
        if let id = dataAttributePhotoID(in: attributes),
           dataAttributeLooksLikePhotoCard(attributes) {
            return "/photo/\(id)"
        }
        if let id = dataAttributeAlbumID(in: attributes),
           dataAttributeLooksLikeAlbumCard(attributes) {
            return "/album/\(id)"
        }
        return nil
    }

    static func mediaURL(from url: URL) -> URL? {
        if let video = videoURL(from: url) {
            return video
        }

        let parts = url.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        let lower = parts.map { $0.lowercased() }
        guard let first = lower.first,
              ["gif", "photo", "album"].contains(first),
              parts.count >= 2,
              isMediaID(parts[1]) else {
            return nil
        }
        return cleanedURL(url, path: "/\(first)/\(parts[1])")
    }

    func extract(from context: SearchResultResolverContext) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByID: [String: Int] = [:]

        for anchor in context.anchors {
            guard results.count < context.limit,
                  let absolute = context.resolvedURL(for: anchor),
                  let target = Self.mediaURL(from: absolute),
                  let key = Self.resultKey(for: target) else {
                continue
            }

            let title = context.title(for: anchor, fallbackURL: target)
            SearchResultResolverSupport.appendUniqueResult(
                title: title,
                url: target,
                id: key,
                sitePrefix: "pornhub",
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
            "category": "pornhub",
            "title": title,
            "search_title": title
        ]
        if let request = PornhubMediaResolver.request(from: target) {
            metadata["id"] = request.id
            metadata["media_id"] = request.id
            metadata["gallery_id"] = request.id
            metadata["type"] = request.kind.rawValue
            switch request.kind {
            case .video:
                metadata["video_id"] = request.id
                metadata["media_type"] = "video"
            case .gif:
                metadata["gif_id"] = request.id
                metadata["media_type"] = "video"
            case .photo:
                metadata["photo_id"] = request.id
                metadata["media_type"] = "image"
            case .album:
                metadata["album_id"] = request.id
                metadata["media_type"] = "gallery"
            }
        }
        metadata.merge(contributorMetadata) { current, _ in current }
        return DownloadMetadata.clean(metadata)
    }

    private static func resultKey(for url: URL) -> String? {
        if let request = PornhubMediaResolver.request(from: url) {
            return "\(request.kind.rawValue)-\(request.id)"
        }
        guard let components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        ) else {
            return nil
        }
        let parts = url.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        let lower = parts.map { $0.lowercased() }
        if lower.first == "view_video.php",
           let viewKey = components.queryItems?.first(where: {
               $0.name.lowercased() == "viewkey"
           })?.value?.trimmed,
           !viewKey.isEmpty {
            return "video-\(viewKey)"
        }
        if let first = lower.first,
           ["embed", "video"].contains(first),
           parts.count >= 2 {
            return "video-\(parts[1])"
        }
        return nil
    }

    private static func videoURL(from url: URL) -> URL? {
        guard var components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        ) else {
            return nil
        }
        let parts = url.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        let lower = parts.map { $0.lowercased() }
        if lower.first == "view_video.php",
           let viewKey = components.queryItems?.first(where: {
               $0.name.lowercased() == "viewkey"
           })?.value?.trimmed,
           !viewKey.isEmpty {
            components.queryItems = [
                URLQueryItem(name: "viewkey", value: viewKey)
            ]
            components.fragment = nil
            return components.url
        }
        if ["embed", "video"].contains(lower.first ?? ""),
           parts.count >= 2,
           isValidPathSlug(parts[1]),
           ![
               "search", "categories", "category", "channels", "channel",
               "model", "models", "pornstar", "pornstars", "playlist",
               "playlists"
           ].contains(parts[1].lowercased()) {
            return cleanedURL(url)
        }
        return nil
    }

    private static func dataAttributeVideoID(
        in attributes: [String: String]
    ) -> String? {
        let keys = [
            "data-viewkey", "data-view-key", "data-video-id",
            "data-videoid", "data-media-id", "data-mediaid",
            "viewkey", "video-id"
        ]
        if let value = firstAttributeValue(
            in: attributes,
            keys: keys,
            matching: isMediaID
        ) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           isMediaID(id),
           typeHint(
               in: attributes,
               containsAnyOf: ["video", "watch", "viewkey"]
           ) {
            return id
        }
        return nil
    }

    private static func dataAttributeGifID(
        in attributes: [String: String]
    ) -> String? {
        let keys = ["data-gif-id", "data-gifid", "gif-id"]
        if let value = firstAttributeValue(
            in: attributes,
            keys: keys,
            matching: isMediaID
        ) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           isMediaID(id),
           typeHint(in: attributes, containsAnyOf: ["gif"]) {
            return id
        }
        return nil
    }

    private static func dataAttributePhotoID(
        in attributes: [String: String]
    ) -> String? {
        let keys = [
            "data-photo-id", "data-photoid", "data-image-id", "photo-id"
        ]
        if let value = firstAttributeValue(
            in: attributes,
            keys: keys,
            matching: isMediaID
        ) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           isMediaID(id),
           typeHint(in: attributes, containsAnyOf: ["photo", "image"]) {
            return id
        }
        return nil
    }

    private static func dataAttributeAlbumID(
        in attributes: [String: String]
    ) -> String? {
        let keys = ["data-album-id", "data-albumid", "album-id"]
        if let value = firstAttributeValue(
            in: attributes,
            keys: keys,
            matching: isMediaID
        ) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           isMediaID(id),
           typeHint(in: attributes, containsAnyOf: ["album", "gallery"]) {
            return id
        }
        return nil
    }

    private static func dataAttributeLooksLikeVideoCard(
        _ attributes: [String: String]
    ) -> Bool {
        let keys = [
            "data-viewkey", "data-view-key", "data-video-id",
            "data-videoid", "video-id"
        ]
        if keys.contains(where: {
            attributes[$0]?.trimmed.isEmpty == false
        }) {
            return true
        }
        return typeHint(
            in: attributes,
            containsAnyOf: ["video", "watch", "viewkey"]
        )
    }

    private static func dataAttributeLooksLikeGifCard(
        _ attributes: [String: String]
    ) -> Bool {
        if ["data-gif-id", "data-gifid", "gif-id"].contains(
            where: { attributes[$0]?.trimmed.isEmpty == false }
        ) {
            return true
        }
        return typeHint(in: attributes, containsAnyOf: ["gif"])
    }

    private static func dataAttributeLooksLikePhotoCard(
        _ attributes: [String: String]
    ) -> Bool {
        let keys = [
            "data-photo-id", "data-photoid", "data-image-id", "photo-id"
        ]
        if keys.contains(where: {
            attributes[$0]?.trimmed.isEmpty == false
        }) {
            return true
        }
        return typeHint(in: attributes, containsAnyOf: ["photo", "image"])
    }

    private static func dataAttributeLooksLikeAlbumCard(
        _ attributes: [String: String]
    ) -> Bool {
        if ["data-album-id", "data-albumid", "album-id"].contains(
            where: { attributes[$0]?.trimmed.isEmpty == false }
        ) {
            return true
        }
        return typeHint(in: attributes, containsAnyOf: ["album", "gallery"])
    }

    private static func isMediaID(_ value: String) -> Bool {
        value.range(
            of: #"^[A-Za-z0-9_-]+$"#,
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
