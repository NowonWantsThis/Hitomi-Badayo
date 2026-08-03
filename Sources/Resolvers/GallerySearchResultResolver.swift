import Foundation

struct GallerySearchResultResolver: SearchResultResolving {
    private enum Site {
        case nhentai
        case nhentaiCom
        case eHentai
        case nozomi
    }

    func supports(_ baseURL: URL) -> Bool {
        site(for: baseURL) != nil
    }

    static func dataAttributeLinkValue(
        in attributes: [String: String],
        baseURL: URL?
    ) -> String? {
        guard let host = baseURL?.host?.lowercased() else {
            return nil
        }

        if isNHentaiHost(host),
           let id = nhentaiDataAttributeGalleryID(in: attributes),
           nhentaiDataAttributeLooksLikeGalleryCard(attributes) {
            return "/g/\(id)/"
        }

        if isNHentaiComHost(host),
           let slug = nhentaiComDataAttributeComicSlug(in: attributes),
           nhentaiComDataAttributeLooksLikeComicCard(attributes) {
            return "/comic/\(slug)"
        }

        if isEHentaiHost(host),
           let id = ehentaiDataAttributeGalleryID(in: attributes),
           let token = ehentaiDataAttributeGalleryToken(in: attributes),
           ehentaiDataAttributeLooksLikeGalleryCard(attributes) {
            let isLoFi =
                typeHint(in: attributes, containsAnyOf: ["lofi"]) ||
                attributes["data-mode"]?.lowercased().trimmed ==
                    "lofi" ||
                attributes["mode"]?.lowercased().trimmed == "lofi"
            return isLoFi
                ? "/lofi/g/\(id)/\(token)/"
                : "/g/\(id)/\(token)/"
        }

        if isNozomiHost(host),
           let id = nozomiDataAttributePostID(in: attributes),
           nozomiDataAttributeLooksLikePostCard(attributes) {
            return "/post/\(id).html"
        }

        return nil
    }

    func extract(from context: SearchResultResolverContext) -> [SearchResultLink] {
        guard let site = site(for: context.baseURL) else { return [] }

        switch site {
        case .nhentai:
            return extractNHentai(from: context)
        case .nhentaiCom:
            return extractNHentaiCom(from: context)
        case .eHentai:
            return extractEHentai(from: context)
        case .nozomi:
            return extractNozomi(from: context)
        }
    }

    private func extractNHentai(from context: SearchResultResolverContext) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByGalleryID: [String: Int] = [:]

        for anchor in context.anchors {
            guard results.count < context.limit,
                  let absolute = context.resolvedURL(for: anchor),
                  let galleryID = nhentaiGalleryID(from: absolute),
                  let target = nhentaiGalleryURL(galleryID: galleryID, baseURL: context.baseURL) else {
                continue
            }

            let title = context.title(for: anchor, fallback: "nHentai \(galleryID)")
            SearchResultResolverSupport.appendUniqueResult(
                title: title,
                url: target,
                id: galleryID,
                sitePrefix: "nhentai",
                results: &results,
                indexByID: &indexByGalleryID,
                metadata: galleryMetadata(
                    id: galleryID,
                    category: "nhentai",
                    type: "gallery",
                    title: title,
                    contributorMetadata: context.contributorMetadata(for: anchor)
                )
            )
        }

        return results
    }

    private func extractNHentaiCom(from context: SearchResultResolverContext) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexBySlug: [String: Int] = [:]

        for anchor in context.anchors {
            guard results.count < context.limit,
                  let absolute = context.resolvedURL(for: anchor),
                  let slug = NHentaiComResolver.slug(from: absolute),
                  let target = NHentaiComResolver.canonicalURL(for: absolute) else {
                continue
            }

            let title = context.title(for: anchor, fallback: "nhentai.com \(slug)")
            var metadata = galleryMetadata(
                id: slug,
                category: "nhentai.com",
                type: "comic",
                title: title,
                contributorMetadata: context.contributorMetadata(for: anchor)
            )
            metadata["comic_id"] = slug
            metadata["slug"] = slug
            SearchResultResolverSupport.appendUniqueResult(
                title: title,
                url: target,
                id: slug,
                sitePrefix: "nhentaicom",
                results: &results,
                indexByID: &indexBySlug,
                metadata: metadata
            )
        }

        return results
    }

    private func extractEHentai(from context: SearchResultResolverContext) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByGalleryID: [String: Int] = [:]

        for anchor in context.anchors {
            guard results.count < context.limit,
                  let absolute = context.resolvedURL(for: anchor),
                  let gallery = ehentaiGalleryID(from: absolute),
                  let target = ehentaiGalleryURL(
                    gallery: gallery,
                    sourceURL: absolute,
                    baseURL: context.baseURL
                  ) else {
                continue
            }

            let title = context.title(for: anchor, fallback: "E-Hentai \(gallery.id)")
            var metadata = galleryMetadata(
                id: gallery.id,
                category: target.host?.lowercased().contains("exhentai") == true
                    ? "exhentai"
                    : "e-hentai",
                type: "gallery",
                title: title,
                contributorMetadata: context.contributorMetadata(for: anchor)
            )
            metadata["gallery_token"] = gallery.token
            metadata["token"] = gallery.token
            if gallery.isLoFi {
                metadata["mode"] = "lofi"
            }
            SearchResultResolverSupport.appendUniqueResult(
                title: title,
                url: target,
                id: gallery.id,
                sitePrefix: "e-hentai",
                results: &results,
                indexByID: &indexByGalleryID,
                metadata: DownloadMetadata.clean(metadata)
            )
        }

        return results
    }

    private func extractNozomi(from context: SearchResultResolverContext) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByPostID: [String: Int] = [:]

        for anchor in context.anchors {
            guard results.count < context.limit,
                  let absolute = context.resolvedURL(for: anchor),
                  let postID = nozomiPostID(from: absolute),
                  let target = nozomiPostURL(postID: postID, baseURL: context.baseURL) else {
                continue
            }

            let title = context.title(for: anchor, fallback: "Nozomi \(postID)")
            SearchResultResolverSupport.appendUniqueResult(
                title: title,
                url: target,
                id: postID,
                sitePrefix: "nozomi",
                results: &results,
                indexByID: &indexByPostID,
                metadata: galleryMetadata(
                    id: postID,
                    category: "nozomi",
                    type: "post",
                    title: title,
                    contributorMetadata: context.contributorMetadata(for: anchor)
                )
            )
        }

        return results
    }

    private func galleryMetadata(
        id: String,
        category: String,
        type: String,
        title: String,
        contributorMetadata: [String: String]
    ) -> [String: String] {
        var metadata = [
            "id": id,
            "post_id": id,
            "gallery_id": id,
            "media_id": id,
            "category": category,
            "type": type,
            "media_type": "image",
            "title": title,
            "search_title": title
        ]
        metadata.merge(contributorMetadata) { current, _ in current }
        return DownloadMetadata.clean(metadata)
    }

    private func site(for url: URL) -> Site? {
        guard let host = url.host?.lowercased() else { return nil }
        if Self.isNHentaiHost(host) {
            return .nhentai
        }
        if Self.isNHentaiComHost(host) {
            return .nhentaiCom
        }
        if Self.isEHentaiHost(host) {
            return .eHentai
        }
        if Self.isNozomiHost(host) {
            return .nozomi
        }
        return nil
    }

    private func nhentaiGalleryID(from url: URL) -> String? {
        firstCapture(in: url.path, pattern: #"/(?:g|gallery|api/gallery)/([0-9]+)"#)
    }

    private func nhentaiGalleryURL(galleryID: String, baseURL: URL) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = Self.isNHentaiHost(baseURL.host?.lowercased() ?? "")
            ? baseURL.host
            : "nhentai.net"
        components.path = "/g/\(galleryID)/"
        return components.url
    }

    private func ehentaiGalleryID(from url: URL) -> (id: String, token: String, isLoFi: Bool)? {
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        let isLoFi = parts.first?.lowercased() == "lofi"
        let normalizedParts = isLoFi ? Array(parts.dropFirst()) : parts
        guard normalizedParts.count >= 3,
              normalizedParts[0].lowercased() == "g",
              normalizedParts[1].range(of: #"^[0-9]+$"#, options: .regularExpression) != nil else {
            return nil
        }
        let token = normalizedParts[2].trimmed
        guard !token.isEmpty else { return nil }
        return (normalizedParts[1], token, isLoFi)
    }

    private func ehentaiGalleryURL(
        gallery: (id: String, token: String, isLoFi: Bool),
        sourceURL: URL,
        baseURL: URL
    ) -> URL? {
        var components = URLComponents()
        components.scheme = sourceURL.scheme ?? "https"
        components.host = Self.isEHentaiHost(sourceURL.host?.lowercased() ?? "")
            ? sourceURL.host
            : baseURL.host
        components.path = gallery.isLoFi
            ? "/lofi/g/\(gallery.id)/\(gallery.token)/"
            : "/g/\(gallery.id)/\(gallery.token)/"
        return components.url
    }

    private func nozomiPostID(from url: URL) -> String? {
        firstCapture(in: url.path, pattern: #"/post/([0-9]+)(?:\.html)?/?$"#)
    }

    private func nozomiPostURL(postID: String, baseURL: URL) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = Self.isNozomiHost(baseURL.host?.lowercased() ?? "")
            ? baseURL.host
            : "nozomi.la"
        components.path = "/post/\(postID).html"
        return components.url
    }

    private func firstCapture(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let capture = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[capture])
    }

    static func isNHentaiHost(_ host: String) -> Bool {
        host == "nhentai.net" || host == "nhentai.test" || host.hasSuffix(".nhentai.net")
    }

    static func isNHentaiComHost(_ host: String) -> Bool {
        host == "nhentai.com" ||
            host == "www.nhentai.com" ||
            host == "nhentai.com.test" ||
            host == "www.nhentai.com.test"
    }

    static func isEHentaiHost(_ host: String) -> Bool {
        host == "e-hentai.org" ||
            host == "exhentai.org" ||
            host == "e-hentai.test" ||
            host == "exhentai.test" ||
            host.hasSuffix(".e-hentai.org") ||
            host.hasSuffix(".exhentai.org")
    }

    static func isNozomiHost(_ host: String) -> Bool {
        host == "nozomi.la" ||
            host == "www.nozomi.la" ||
            host == "nozomi.test" ||
            host == "www.nozomi.test"
    }

    private static func nhentaiDataAttributeGalleryID(
        in attributes: [String: String]
    ) -> String? {
        let keys = [
            "data-gallery-id", "data-galleryid", "data-doujin-id",
            "data-doujinid", "data-media-id", "data-mediaid",
            "gallery-id", "doujin-id"
        ]
        if let value = firstAttributeValue(
            in: attributes,
            keys: keys,
            matching: isNumericID
        ) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           isNumericID(id),
           typeHint(
               in: attributes,
               containsAnyOf: ["gallery", "doujin", "comic", "manga"]
           ) {
            return id
        }
        return nil
    }

    private static func nhentaiDataAttributeLooksLikeGalleryCard(
        _ attributes: [String: String]
    ) -> Bool {
        let keys = [
            "data-gallery-id", "data-galleryid", "data-doujin-id",
            "data-doujinid", "data-media-id", "data-mediaid",
            "gallery-id", "doujin-id"
        ]
        if typeHint(
            in: attributes,
            containsAnyOf: [
                "tag", "search", "nav", "menu", "filter", "profile",
                "user"
            ]
        ) {
            return false
        }
        if keys.contains(where: {
            attributes[$0]?.trimmed.isEmpty == false
        }) {
            return true
        }
        return typeHint(
            in: attributes,
            containsAnyOf: ["gallery", "doujin", "comic", "manga"]
        )
    }

    private static func nhentaiComDataAttributeComicSlug(
        in attributes: [String: String]
    ) -> String? {
        let keys = [
            "data-comic-slug", "data-comicslug", "data-title-slug",
            "data-slug", "comic-slug", "slug"
        ]
        if let value = firstValidPathSlug(
            in: attributes,
            keys: keys
        ) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           isValidPathSlug(id),
           typeHint(
               in: attributes,
               containsAnyOf: ["comic", "gallery", "doujin", "manga"]
           ) {
            return id
        }
        return nil
    }

    private static func nhentaiComDataAttributeLooksLikeComicCard(
        _ attributes: [String: String]
    ) -> Bool {
        let keys = [
            "data-comic-slug", "data-comicslug", "data-title-slug",
            "data-slug", "comic-slug", "slug"
        ]
        if typeHint(
            in: attributes,
            containsAnyOf: [
                "profile", "user", "tag", "search", "nav", "menu",
                "filter"
            ]
        ) {
            return false
        }
        if keys.contains(where: {
            attributes[$0]?.trimmed.isEmpty == false
        }) {
            return true
        }
        return typeHint(
            in: attributes,
            containsAnyOf: ["comic", "gallery", "doujin", "manga"]
        )
    }

    private static func ehentaiDataAttributeGalleryID(
        in attributes: [String: String]
    ) -> String? {
        let keys = [
            "data-gallery-id", "data-galleryid", "data-gid", "gid",
            "gallery-id"
        ]
        if let value = firstAttributeValue(
            in: attributes,
            keys: keys,
            matching: isNumericID
        ) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           isNumericID(id),
           typeHint(
               in: attributes,
               containsAnyOf: ["gallery", "lofi"]
           ) {
            return id
        }
        return nil
    }

    private static func ehentaiDataAttributeGalleryToken(
        in attributes: [String: String]
    ) -> String? {
        firstValidPathSlug(
            in: attributes,
            keys: [
                "data-gallery-token", "data-gtoken", "data-token",
                "data-key", "gallery-token", "gtoken", "token"
            ]
        )
    }

    private static func ehentaiDataAttributeLooksLikeGalleryCard(
        _ attributes: [String: String]
    ) -> Bool {
        let keys = [
            "data-gallery-id", "data-galleryid", "data-gid", "gid",
            "gallery-id", "data-gallery-token", "data-gtoken",
            "data-token", "gallery-token"
        ]
        if typeHint(
            in: attributes,
            containsAnyOf: [
                "image", "tag", "search", "nav", "menu", "filter",
                "profile", "user"
            ]
        ) {
            return false
        }
        if keys.contains(where: {
            attributes[$0]?.trimmed.isEmpty == false
        }) {
            return true
        }
        return typeHint(
            in: attributes,
            containsAnyOf: ["gallery", "lofi"]
        )
    }

    private static func nozomiDataAttributePostID(
        in attributes: [String: String]
    ) -> String? {
        let keys = [
            "data-post-id", "data-postid", "data-nozomi-id",
            "data-nozomiid", "post-id", "nozomi-id"
        ]
        if let value = firstAttributeValue(
            in: attributes,
            keys: keys,
            matching: isNumericID
        ) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           isNumericID(id),
           typeHint(
               in: attributes,
               containsAnyOf: ["post", "image", "picture"]
           ) {
            return id
        }
        return nil
    }

    private static func nozomiDataAttributeLooksLikePostCard(
        _ attributes: [String: String]
    ) -> Bool {
        let keys = [
            "data-post-id", "data-postid", "data-nozomi-id",
            "data-nozomiid", "post-id", "nozomi-id"
        ]
        if typeHint(
            in: attributes,
            containsAnyOf: [
                "tag", "search", "nav", "menu", "filter", "profile",
                "user"
            ]
        ) {
            return false
        }
        if keys.contains(where: {
            attributes[$0]?.trimmed.isEmpty == false
        }) {
            return true
        }
        return typeHint(
            in: attributes,
            containsAnyOf: ["post", "image", "picture"]
        )
    }

    private static func isNumericID(_ value: String) -> Bool {
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

    private static func firstValidPathSlug(
        in attributes: [String: String],
        keys: [String]
    ) -> String? {
        firstAttributeValue(
            in: attributes,
            keys: keys,
            matching: isValidPathSlug
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
}
