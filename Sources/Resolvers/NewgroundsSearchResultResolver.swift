import Foundation

struct NewgroundsSearchResultResolver: SearchResultResolving {
    func supports(_ baseURL: URL) -> Bool {
        guard let host = baseURL.host?.lowercased() else { return false }
        return Self.isSupportedHost(host)
    }

    static func isSupportedHost(_ host: String) -> Bool {
        host == "newgrounds.com" ||
            host == "www.newgrounds.com" ||
            host == "newgrounds.test" ||
            host.hasSuffix(".newgrounds.com")
    }

    static func dataAttributeLinkValue(
        in attributes: [String: String],
        baseURL: URL?
    ) -> String? {
        guard let host = baseURL?.host?.lowercased(),
              isSupportedHost(host),
              let username = dataAttributeUsername(in: attributes),
              let slug = dataAttributeArtworkSlug(in: attributes),
              dataAttributeLooksLikeArtworkCard(attributes) else {
            return nil
        }
        return "/art/view/\(username)/\(slug)"
    }

    func extract(from context: SearchResultResolverContext) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByID: [String: Int] = [:]

        for anchor in context.anchors {
            guard results.count < context.limit,
                  let absolute = context.resolvedURL(for: anchor) else {
                continue
            }

            let target: URL
            let fallback: String?
            let resultID: String
            let username: String?
            let slug: String?
            let type: String
            if let artist = NewgroundsResolver.artistUsername(from: absolute) {
                target = NewgroundsResolver.artistArtURL(
                    username: artist,
                    sourceURL: absolute
                )
                fallback = "\(artist) Art"
                resultID = "artist:\(artist)"
                username = artist
                slug = nil
                type = "artist"
            } else if absolute.path.lowercased().contains("/art/view/"),
                      let clean = Self.cleanedURL(absolute) {
                target = clean
                fallback = nil
                let info = Self.artInfo(from: clean)
                resultID = info.map {
                    "art:\($0.username):\($0.slug)"
                } ?? URLIdentity.normalize(clean.absoluteString)
                username = info?.username
                slug = info?.slug
                type = "artwork"
            } else {
                continue
            }

            let title = fallback.map {
                context.title(for: anchor, fallback: $0)
            } ?? context.title(for: anchor, fallbackURL: target)
            SearchResultResolverSupport.appendUniqueResult(
                title: title,
                url: target,
                id: resultID,
                sitePrefix: "newgrounds",
                results: &results,
                indexByID: &indexByID,
                metadata: metadata(
                    resultID: resultID,
                    title: title,
                    anchor: anchor,
                    username: username,
                    slug: slug,
                    type: type,
                    context: context
                )
            )
        }

        return results
    }

    private func metadata(
        resultID: String,
        title: String,
        anchor: AnchorEntry,
        username: String?,
        slug: String?,
        type: String,
        context: SearchResultResolverContext
    ) -> [String: String] {
        var metadata = [
            "id": resultID,
            "category": "newgrounds",
            "type": type,
            "title": title,
            "search_title": title
        ]
        let attributes = context.semanticAttributes(for: anchor)
        let displayName = Self.firstSemanticAttribute(
            attributes,
            keys: [
                "data-artist-name", "data-artist", "artist",
                "data-author", "data-author-name", "author",
                "data-uploader-name", "data-uploader", "uploader"
            ]
        )
        let usernameValue = Self.firstSemanticAttribute(
            attributes,
            keys: [
                "data-username", "username", "data-user", "data-user-name"
            ]
        ) ?? username
        let artist = displayName ?? usernameValue
        if let artist {
            metadata["artist"] = artist
            metadata["author"] = artist
            metadata["creator"] = artist
            metadata["uploader"] = artist
        }
        if let usernameValue {
            metadata["user"] = usernameValue
            metadata["username"] = usernameValue
        }
        if let slug {
            metadata["slug"] = slug
            metadata["artwork"] = slug
            metadata["artwork_id"] = slug
            metadata["media_id"] = slug
            metadata["gallery_id"] = slug
        } else if let username {
            metadata["user_id"] = username
            metadata["gallery_id"] = username
        }
        return DownloadMetadata.clean(metadata)
    }

    private static func artInfo(
        from url: URL
    ) -> (username: String, slug: String)? {
        let parts = url.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        guard parts.count >= 4,
              parts[0].lowercased() == "art",
              parts[1].lowercased() == "view" else {
            return nil
        }
        return (parts[2], parts[3])
    }

    private static func dataAttributeUsername(
        in attributes: [String: String]
    ) -> String? {
        firstAttributeValue(
            in: attributes,
            keys: [
                "data-artist-username", "data-author-username",
                "data-user-name", "data-username", "username",
                "data-user", "user"
            ],
            matching: isValidPathSlug
        )
    }

    private static func dataAttributeArtworkSlug(
        in attributes: [String: String]
    ) -> String? {
        let keys = [
            "data-art-slug", "data-artwork-slug", "data-submission-slug",
            "data-title-slug", "data-slug", "art-slug", "slug"
        ]
        if let value = firstAttributeValue(
            in: attributes,
            keys: keys,
            matching: isValidPathSlug
        ) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           isValidPathSlug(id),
           typeHint(
               in: attributes,
               containsAnyOf: ["artwork", "submission"]
           ) {
            return id
        }
        return nil
    }

    private static func dataAttributeLooksLikeArtworkCard(
        _ attributes: [String: String]
    ) -> Bool {
        let markerKeys = [
            "data-art-slug", "data-artwork-slug", "data-submission-slug",
            "data-title-slug", "data-slug", "art-slug", "slug"
        ]
        if typeHint(
            in: attributes,
            containsAnyOf: ["artist", "profile", "portal", "search", "nav"]
        ) {
            return false
        }
        if markerKeys.contains(
            where: { attributes[$0]?.trimmed.isEmpty == false }
        ) {
            return true
        }
        return typeHint(
            in: attributes,
            containsAnyOf: ["artwork", "submission"]
        )
    }

    private static func firstSemanticAttribute(
        _ attributes: [String: String],
        keys: [String]
    ) -> String? {
        for key in keys {
            guard let value = attributes.first(
                where: { $0.key.lowercased() == key }
            )?.value.trimmed,
                  !value.isEmpty else {
                continue
            }
            return value
        }
        return nil
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
        let values = keys.compactMap { attributes[$0]?.lowercased() }
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

    private static func cleanedURL(_ url: URL) -> URL? {
        guard var components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        ) else {
            return nil
        }
        components.queryItems = nil
        components.fragment = nil
        return components.url
    }
}
