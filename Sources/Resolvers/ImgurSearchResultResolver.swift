import Foundation

struct ImgurSearchResultResolver: SearchResultResolving {
    private typealias Content = (id: String, key: String, path: String)

    func supports(_ baseURL: URL) -> Bool {
        guard let host = baseURL.host?.lowercased() else { return false }
        return Self.isSupportedHost(host)
    }

    static func isSupportedHost(_ host: String) -> Bool {
        host == "imgur.com" ||
            host == "www.imgur.com" ||
            host == "m.imgur.com" ||
            host == "imgur.test" ||
            host == "www.imgur.test" ||
            host == "m.imgur.test"
    }

    static func dataAttributeLinkValue(
        in attributes: [String: String],
        baseURL: URL?
    ) -> String? {
        guard let host = baseURL?.host?.lowercased(),
              isSupportedHost(host) else {
            return nil
        }
        if let tag = dataAttributeTag(in: attributes),
           let id = dataAttributeImageID(in: attributes),
           dataAttributeLooksLikeTagCard(attributes) {
            return "/t/\(tag)/\(id)"
        }
        if let id = dataAttributeAlbumID(in: attributes),
           dataAttributeLooksLikeAlbumCard(attributes) {
            return "/a/\(id)"
        }
        if let id = dataAttributeGalleryID(in: attributes),
           dataAttributeLooksLikeGalleryCard(attributes) {
            return "/gallery/\(id)"
        }
        if let id = dataAttributeImageID(in: attributes),
           dataAttributeLooksLikeImageCard(attributes) {
            return "/\(id)"
        }
        return nil
    }

    func extract(from context: SearchResultResolverContext) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByKey: [String: Int] = [:]

        for anchor in context.anchors {
            guard results.count < context.limit,
                  let absolute = context.resolvedURL(for: anchor),
                  let content = Self.content(from: absolute),
                  let target = Self.cleanedURL(
                      absolute,
                      path: content.path
                  ) else {
                continue
            }

            let title = context.title(
                for: anchor,
                fallback: "Imgur \(content.id)"
            )
            SearchResultResolverSupport.appendUniqueResult(
                title: title,
                url: target,
                id: content.key,
                sitePrefix: "imgur",
                results: &results,
                indexByID: &indexByKey,
                metadata: metadata(
                    content: content,
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
        content: Content,
        title: String,
        contributorMetadata: [String: String]
    ) -> [String: String] {
        let kind = content.key
            .split(separator: ":", omittingEmptySubsequences: true)
            .first
            .map(String.init) ?? "media"
        var metadata = [
            "id": content.id,
            "media_id": content.id,
            "category": "imgur",
            "type": kind,
            "media_type": kind == "media" ? "media" : "gallery",
            "title": title,
            "search_title": title
        ]
        switch kind {
        case "a":
            metadata["album_id"] = content.id
            metadata["gallery_id"] = content.id
        case "gallery":
            metadata["gallery_id"] = content.id
        case "t":
            metadata["gallery_id"] = content.id
            if let tag = content.key
                .split(separator: ":", omittingEmptySubsequences: true)
                .dropFirst()
                .first {
                metadata["tag"] = String(tag)
            }
        default:
            metadata["image_id"] = content.id
            metadata["gallery_id"] = content.id
        }
        metadata.merge(contributorMetadata) { current, _ in current }
        return DownloadMetadata.clean(metadata)
    }

    private static func content(from url: URL) -> Content? {
        guard let host = url.host?.lowercased(),
              isSupportedHost(host) else {
            return nil
        }
        let parts = url.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        guard let first = parts.first?.trimmed, !first.isEmpty else {
            return nil
        }

        let lowerFirst = first.lowercased()
        if ["a", "gallery"].contains(lowerFirst), parts.count >= 2 {
            let id = (parts[1] as NSString).deletingPathExtension.trimmed
            guard isValidID(id) else { return nil }
            return (id, "\(lowerFirst):\(id)", "/\(lowerFirst)/\(id)")
        }

        if lowerFirst == "t", parts.count >= 3 {
            let tag = parts[1].trimmed
            let id = (parts[2] as NSString).deletingPathExtension.trimmed
            guard isValidID(tag), isValidID(id) else { return nil }
            return (id, "t:\(tag):\(id)", "/t/\(tag)/\(id)")
        }

        let reserved: Set<String> = [
            "about", "account", "advertise", "apps", "blog", "download",
            "explore", "jobs", "privacy", "register", "search", "signin",
            "signout", "terms", "tos", "upload"
        ]
        let id = (first as NSString).deletingPathExtension.trimmed
        guard parts.count == 1,
              !reserved.contains(id.lowercased()),
              isValidID(id) else {
            return nil
        }
        return (id, "media:\(id)", "/\(id)")
    }

    private static func cleanedURL(_ url: URL, path: String) -> URL? {
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

    private static func dataAttributeGalleryID(
        in attributes: [String: String]
    ) -> String? {
        let keys = [
            "data-gallery-id", "data-galleryid", "data-gallery-hash",
            "gallery-id"
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
           typeHint(in: attributes, containsAnyOf: ["gallery"]) {
            return id
        }
        return nil
    }

    private static func dataAttributeAlbumID(
        in attributes: [String: String]
    ) -> String? {
        let keys = [
            "data-album-id", "data-albumid", "data-album-hash",
            "album-id"
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
           typeHint(in: attributes, containsAnyOf: ["album"]) {
            return id
        }
        return nil
    }

    private static func dataAttributeImageID(
        in attributes: [String: String]
    ) -> String? {
        let keys = [
            "data-image-id", "data-imageid", "data-media-id",
            "data-mediaid", "data-hash", "image-id"
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
               containsAnyOf: ["image", "media", "photo", "post"]
           ) {
            return id
        }
        return nil
    }

    private static func dataAttributeTag(
        in attributes: [String: String]
    ) -> String? {
        firstAttributeValue(
            in: attributes,
            keys: ["data-tag", "data-tag-name", "tag"],
            matching: isValidID
        )
    }

    private static func dataAttributeLooksLikeGalleryCard(
        _ attributes: [String: String]
    ) -> Bool {
        let keys = [
            "data-gallery-id", "data-galleryid", "data-gallery-hash",
            "gallery-id"
        ]
        if keys.contains(where: {
            attributes[$0]?.trimmed.isEmpty == false
        }) {
            return true
        }
        return typeHint(in: attributes, containsAnyOf: ["gallery"])
    }

    private static func dataAttributeLooksLikeAlbumCard(
        _ attributes: [String: String]
    ) -> Bool {
        let keys = [
            "data-album-id", "data-albumid", "data-album-hash",
            "album-id"
        ]
        if keys.contains(where: {
            attributes[$0]?.trimmed.isEmpty == false
        }) {
            return true
        }
        return typeHint(in: attributes, containsAnyOf: ["album"])
    }

    private static func dataAttributeLooksLikeImageCard(
        _ attributes: [String: String]
    ) -> Bool {
        let keys = [
            "data-image-id", "data-imageid", "data-media-id",
            "data-mediaid", "data-hash", "image-id"
        ]
        if keys.contains(where: {
            attributes[$0]?.trimmed.isEmpty == false
        }) {
            return true
        }
        return typeHint(
            in: attributes,
            containsAnyOf: ["image", "media", "photo", "post"]
        )
    }

    private static func dataAttributeLooksLikeTagCard(
        _ attributes: [String: String]
    ) -> Bool {
        let keys = ["data-tag", "data-tag-name", "tag"]
        if keys.contains(where: {
            attributes[$0]?.trimmed.isEmpty == false
        }) {
            return true
        }
        return typeHint(in: attributes, containsAnyOf: ["tag"])
    }

    private static func isValidID(_ value: String) -> Bool {
        value.count <= 80 &&
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
}
