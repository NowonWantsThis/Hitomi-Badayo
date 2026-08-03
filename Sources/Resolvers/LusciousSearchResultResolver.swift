import Foundation

struct LusciousSearchResultResolver: SearchResultResolving {
    private typealias Content = (id: String, key: String, path: String)

    func supports(_ baseURL: URL) -> Bool {
        guard let host = baseURL.host?.lowercased() else { return false }
        return Self.isSupportedHost(host)
    }

    static func isSupportedHost(_ host: String) -> Bool {
        host == "luscious.net" ||
            host == "www.luscious.net" ||
            host == "members.luscious.net" ||
            host == "luscious.test" ||
            host == "www.luscious.test" ||
            host == "members.luscious.test"
    }

    static func dataAttributeLinkValue(
        in attributes: [String: String],
        baseURL: URL?
    ) -> String? {
        guard let host = baseURL?.host?.lowercased(),
              isSupportedHost(host) else {
            return nil
        }
        return dataAttributeLinkValue(in: attributes)
    }

    static func dataAttributeLinkValue(
        in attributes: [String: String]
    ) -> String? {
        if let album = dataAttributeAlbumToken(in: attributes) {
            return "/albums/\(album)"
        }
        if let video = dataAttributeVideoSlug(in: attributes) {
            return "/videos/\(video)"
        }
        return nil
    }

    func extract(from context: SearchResultResolverContext) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByContent: [String: Int] = [:]

        for anchor in context.anchors {
            guard results.count < context.limit,
                  let absolute = context.resolvedURL(for: anchor),
                  let canonical = LusciousResolver.canonicalURL(for: absolute),
                  let content = content(from: canonical),
                  let target = cleanedURL(canonical, path: content.path) else {
                continue
            }

            let title = context.title(
                for: anchor,
                fallback: "Luscious \(content.id)"
            )
            SearchResultResolverSupport.appendUniqueResult(
                title: title,
                url: target,
                id: content.key,
                sitePrefix: "luscious",
                results: &results,
                indexByID: &indexByContent,
                metadata: metadata(
                    content: content,
                    title: title,
                    contributorMetadata: context.contributorMetadata(for: anchor)
                )
            )
        }

        return results
    }

    private func content(from url: URL) -> Content? {
        guard let host = url.host?.lowercased(), Self.isSupportedHost(host) else {
            return nil
        }
        if let albumID = LusciousResolver.albumID(from: url) {
            return (albumID, "album:\(albumID)", "/albums/\(albumID)")
        }

        let parts = url.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        guard let index = parts.firstIndex(where: {
            $0.lowercased() == "videos"
        }), index + 1 < parts.count else {
            return nil
        }
        let slug = (parts[index + 1] as NSString)
            .deletingPathExtension
            .trimmed
        guard Self.isValidPathSlug(slug) else { return nil }
        return (slug, "video:\(slug)", "/videos/\(slug)")
    }

    private func cleanedURL(_ url: URL, path: String) -> URL? {
        guard var components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        ) else {
            return nil
        }
        components.path = path
        components.queryItems = nil
        components.fragment = nil
        return components.url
    }

    private func metadata(
        content: Content,
        title: String,
        contributorMetadata: [String: String]
    ) -> [String: String] {
        let kind = content.key
            .split(separator: ":", omittingEmptySubsequences: true)
            .first
            .map(String.init) ?? "media"
        var metadata = contributorMetadata
        metadata.merge([
            "id": content.id,
            "gallery_id": content.id,
            "media_id": content.id,
            "category": "luscious",
            "type": kind,
            "media_type": kind == "video" ? "video" : "image",
            "title": title,
            "search_title": title
        ]) { current, _ in current }
        if kind == "album" {
            metadata["album_id"] = content.id
        } else if kind == "video" {
            metadata["video_id"] = content.id
        }
        return DownloadMetadata.clean(metadata)
    }

    private static func dataAttributeAlbumToken(
        in attributes: [String: String]
    ) -> String? {
        let explicitKeys = [
            "data-album-id", "data-albumid", "data-album-slug",
            "data-gallery-id", "data-galleryid", "album-id"
        ]
        if let value = firstAttributeValue(
            in: attributes,
            keys: explicitKeys,
            matching: isAlbumToken
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
            matching: isAlbumToken
        )
    }

    private static func dataAttributeVideoSlug(
        in attributes: [String: String]
    ) -> String? {
        let explicitKeys = [
            "data-video-slug", "data-video-id", "data-videoid",
            "data-movie-id", "data-movieid", "video-id"
        ]
        if let value = firstAttributeValue(
            in: attributes,
            keys: explicitKeys,
            matching: isValidPathSlug
        ) {
            return value
        }
        guard typeHint(
            in: attributes,
            containsAnyOf: ["video", "movie"]
        ) else {
            return nil
        }
        return firstAttributeValue(
            in: attributes,
            keys: ["data-id", "id"],
            matching: isValidPathSlug
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

    private static func isAlbumToken(_ value: String) -> Bool {
        isValidPathSlug(value) &&
            value.range(
                of: #"[0-9]{2,}$"#,
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
