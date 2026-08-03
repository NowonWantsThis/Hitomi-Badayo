import Foundation

struct DeviantArtSearchResultResolver: SearchResultResolving {
    func supports(_ baseURL: URL) -> Bool {
        guard let host = baseURL.host?.lowercased() else { return false }
        return Self.isSupportedHost(host)
    }

    static func isSupportedHost(_ host: String) -> Bool {
        host == "deviantart.com" ||
            host == "www.deviantart.com" ||
            host == "deviantart.test" ||
            host.hasSuffix(".deviantart.com") ||
            host.hasSuffix(".deviantart.test")
    }

    static func dataAttributeLinkValue(
        in attributes: [String: String],
        baseURL: URL?
    ) -> String? {
        guard let host = baseURL?.host?.lowercased(),
              isSupportedHost(host),
              let id = dataAttributeArtworkID(in: attributes),
              let username = dataAttributeUsername(in: attributes),
              let rawSlug = firstAttributeValue(
                  in: attributes,
                  keys: [
                      "data-deviation-slug", "data-artwork-slug",
                      "data-title-slug", "data-slug", "slug"
                  ],
                  matching: isValidPathSlug
              ),
              dataAttributeLooksLikeArtworkCard(attributes) else {
            return nil
        }
        let slug = rawSlug.hasSuffix("-\(id)") ?
            rawSlug : "\(rawSlug)-\(id)"
        return "/\(username)/art/\(slug)"
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
            if DeviantArtResolver.isArtworkURL(absolute),
               let artworkURL = Self.cleanedURL(absolute) {
                target = artworkURL
                fallback = nil
            } else if let profileURL = Self.profileURL(from: absolute),
                      let username = DeviantArtResolver.username(
                          from: profileURL
                      ) {
                target = profileURL
                fallback = username
            } else {
                continue
            }

            let title = fallback.map {
                context.title(for: anchor, fallback: $0)
            } ?? context.title(for: anchor, fallbackURL: target)
            let resultID = Self.artworkInfo(from: target).map {
                "art:\($0.id)"
            } ?? Self.collectionInfo(from: target).map {
                "\($0.type):\($0.id)"
            } ?? URLIdentity.normalize(target.absoluteString)
            SearchResultResolverSupport.appendUniqueResult(
                title: title,
                url: target,
                id: resultID,
                sitePrefix: "deviantart",
                results: &results,
                indexByID: &indexByID,
                metadata: metadata(
                    title: title,
                    anchor: anchor,
                    target: target,
                    fallbackUsername: fallback,
                    context: context
                )
            )
        }

        return results
    }

    private func metadata(
        title: String,
        anchor: AnchorEntry,
        target: URL,
        fallbackUsername: String?,
        context: SearchResultResolverContext
    ) -> [String: String] {
        let attributes = context.semanticAttributes(for: anchor)
        let artworkInfo = Self.artworkInfo(from: target)
        let collectionInfo = Self.collectionInfo(from: target)
        let pathUsername = artworkInfo?.username ??
            collectionInfo?.username ??
            fallbackUsername
        let displayName = Self.firstSemanticAttribute(
            attributes,
            keys: [
                "data-artist-name", "data-artist", "artist",
                "data-author", "data-author-name", "author",
                "data-creator", "creator"
            ]
        )
        let username = Self.firstSemanticAttribute(
            attributes,
            keys: [
                "data-username", "username", "data-user", "data-user-name",
                "data-profile", "data-profile-name"
            ]
        ) ?? pathUsername
        let artist = displayName ?? username
        var metadata = [
            "category": "deviantart",
            "title": title,
            "search_title": title
        ]
        if let artist {
            metadata["artist"] = artist
            metadata["author"] = artist
            metadata["creator"] = artist
            metadata["uploader"] = artist
        }
        if let username {
            metadata["user"] = username
            metadata["username"] = username
        }
        if let artworkInfo {
            metadata["id"] = artworkInfo.id
            metadata["artwork_id"] = artworkInfo.id
            metadata["media_id"] = artworkInfo.id
            metadata["gallery_id"] = artworkInfo.id
            metadata["slug"] = artworkInfo.slug
            metadata["type"] = "artwork"
        } else if let collectionInfo {
            metadata["id"] = collectionInfo.id
            metadata["gallery_id"] = collectionInfo.id
            metadata["slug"] = collectionInfo.slug
            metadata["type"] = collectionInfo.type
        } else if let username {
            metadata["id"] = username
            metadata["user_id"] = username
            metadata["type"] = "profile"
        }
        if let userID = Self.firstSemanticAttribute(
            attributes,
            keys: ["data-user-id", "data-uid", "user-id", "uid"]
        ) {
            metadata["user_id"] = userID
            metadata["uploader_id"] = userID
        }
        return DownloadMetadata.clean(metadata)
    }

    private static func artworkInfo(
        from url: URL
    ) -> (username: String, slug: String, id: String)? {
        let parts = url.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        guard parts.count >= 3,
              parts[1].lowercased() == "art" else {
            return nil
        }
        let username = parts[0]
        let slug = parts[2]
        guard let id = firstCapture(
            in: slug,
            pattern: #"(?:^|-)([0-9]{3,})$"#
        ) else {
            return nil
        }
        return (username, slug, id)
    }

    private static func collectionInfo(
        from url: URL
    ) -> (username: String, id: String, slug: String, type: String)? {
        let parts = url.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        guard let username = parts.first else { return nil }
        guard parts.count >= 2,
              parts[1].lowercased() == "gallery" else {
            return (username, username, username, "profile")
        }
        if parts.count >= 4, parts[2].allSatisfy(\.isNumber) {
            return (username, parts[2], parts[3], "gallery")
        }
        if parts.count >= 3 {
            return (
                username,
                "\(username)-\(parts[2])",
                parts[2],
                "gallery"
            )
        }
        return (username, username, username, "gallery")
    }

    private static func profileURL(from url: URL) -> URL? {
        guard let host = url.host?.lowercased(),
              isSupportedHost(host),
              !DeviantArtResolver.isArtworkURL(url),
              isLikelyProfileURL(url, host: host),
              let canonical = DeviantArtResolver.canonicalCollectionURL(
                  for: url
              ) else {
            return nil
        }
        return canonical
    }

    private static func isLikelyProfileURL(
        _ url: URL,
        host: String
    ) -> Bool {
        let parts = url.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        if isLegacySubdomain(host) {
            return parts.isEmpty || isLikelyCollectionTail(parts)
        }
        guard parts.count > 1 else { return parts.count == 1 }
        return isLikelyCollectionTail(Array(parts.dropFirst()))
    }

    private static func isLikelyCollectionTail(_ parts: [String]) -> Bool {
        guard let first = parts.first?.lowercased() else { return false }
        switch first {
        case "gallery":
            return parts.count >= 2 && parts.count <= 3
        case "favourites", "favorites":
            return parts.count <= 3
        default:
            return false
        }
    }

    private static func isLegacySubdomain(_ host: String) -> Bool {
        guard host.hasSuffix(".deviantart.com") ||
                host.hasSuffix(".deviantart.test"),
              let first = host.split(separator: ".").first.map(
                  String.init
              ) else {
            return false
        }
        return !["www", "m", "deviantart"].contains(first)
    }

    private static func dataAttributeArtworkID(
        in attributes: [String: String]
    ) -> String? {
        let keys = [
            "data-deviation-id", "data-deviationid", "data-artwork-id",
            "data-artworkid", "data-work-id", "data-workid"
        ]
        if let value = firstAttributeValue(
            in: attributes,
            keys: keys,
            matching: isArtworkID
        ) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           isArtworkID(id),
           typeHint(
               in: attributes,
               containsAnyOf: ["deviation", "artwork"]
           ) {
            return id
        }
        return nil
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

    private static func dataAttributeLooksLikeArtworkCard(
        _ attributes: [String: String]
    ) -> Bool {
        let markerKeys = [
            "data-deviation-id", "data-deviationid", "data-artwork-id",
            "data-artworkid", "data-work-id", "data-workid"
        ]
        if markerKeys.contains(
            where: { attributes[$0]?.trimmed.isEmpty == false }
        ) {
            return true
        }
        if typeHint(
            in: attributes,
            containsAnyOf: ["profile", "gallery", "folder", "user"]
        ) {
            return false
        }
        return typeHint(
            in: attributes,
            containsAnyOf: ["deviation", "artwork"]
        )
    }

    private static func isArtworkID(_ value: String) -> Bool {
        value.range(
            of: #"^[0-9]{3,}$"#,
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

    private static func firstCapture(
        in text: String,
        pattern: String
    ) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive]
        ) else {
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
