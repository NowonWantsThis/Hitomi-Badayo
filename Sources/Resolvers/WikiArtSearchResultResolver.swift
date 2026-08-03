import Foundation

struct WikiArtSearchResultResolver: SearchResultResolving {
    func supports(_ baseURL: URL) -> Bool {
        guard let host = baseURL.host?.lowercased() else { return false }
        return Self.isSupportedHost(host)
    }

    static func isSupportedHost(_ host: String) -> Bool {
        host == "wikiart.org" ||
            host.hasSuffix(".wikiart.org") ||
            host == "wikiart.test" ||
            host.hasSuffix(".wikiart.test")
    }

    static func dataAttributeLinkValue(
        in attributes: [String: String],
        baseURL: URL?
    ) -> String? {
        guard let host = baseURL?.host?.lowercased(),
              isSupportedHost(host),
              let artist = dataAttributeArtistSlug(in: attributes),
              dataAttributeLooksLikeArtistCard(attributes) else {
            return nil
        }
        return "/en/\(artist)"
    }

    func extract(from context: SearchResultResolverContext) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByArtist: [String: Int] = [:]

        for anchor in context.anchors {
            guard results.count < context.limit,
                  let absolute = context.resolvedURL(for: anchor),
                  let artist = artistSlug(from: absolute),
                  let target = artistURL(artist: artist, sourceURL: absolute) else {
                continue
            }

            let title = context.title(
                for: anchor,
                fallback: artist.replacingOccurrences(of: "-", with: " ")
            )
            SearchResultResolverSupport.appendUniqueResult(
                title: title,
                url: target,
                id: artist,
                sitePrefix: "wikiart",
                results: &results,
                indexByID: &indexByArtist,
                metadata: metadata(
                    artist: artist,
                    title: title,
                    attributes: context.attributesIncludingEmbeddedImage(for: anchor)
                )
            )
        }

        return results
    }

    private func artistSlug(from url: URL) -> String? {
        guard let host = url.host?.lowercased(), Self.isSupportedHost(host) else { return nil }
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 2, parts[0].lowercased() == "en" else {
            return nil
        }

        let artist = parts[1].trimmed
        let reserved: Set<String> = [
            "app", "artists-by-art-movement", "paintings-by-genre",
            "paintings-by-style", "search"
        ]
        guard isValidSlug(artist), !reserved.contains(artist.lowercased()) else {
            return nil
        }
        return artist
    }

    private func artistURL(artist: String, sourceURL: URL) -> URL? {
        var components = URLComponents()
        components.scheme = sourceURL.scheme ?? "https"
        let sourceHost = sourceURL.host?.lowercased() ?? ""
        components.host = sourceHost == "wikiart.test" || sourceHost.hasSuffix(".wikiart.test")
            ? "wikiart.test"
            : "www.wikiart.org"
        components.path = "/en/\(artist)"
        return components.url
    }

    private func metadata(
        artist: String,
        title: String,
        attributes: [String: String]
    ) -> [String: String] {
        let displayName = firstAttribute(attributes, keys: [
            "data-artist-name", "data-artist", "artist",
            "data-author-name", "data-author", "author"
        ]) ?? displayName(from: artist)
        var metadata = [
            "id": artist,
            "artist_slug": artist,
            "username": artist,
            "gallery_id": artist,
            "category": "wikiart",
            "type": "artist",
            "title": title,
            "search_title": title
        ]
        if !displayName.isEmpty {
            metadata["artist"] = displayName
            metadata["author"] = displayName
            metadata["creator"] = displayName
            metadata["uploader"] = displayName
            metadata["channel"] = displayName
        }
        return DownloadMetadata.clean(metadata)
    }

    private func displayName(from slug: String) -> String {
        slug.split(separator: "-", omittingEmptySubsequences: true)
            .map { part in
                let lower = part.lowercased()
                return lower.prefix(1).uppercased() + lower.dropFirst()
            }
            .joined(separator: " ")
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

    private func isValidSlug(_ value: String) -> Bool {
        !value.isEmpty &&
            value.range(
                of: #"^[A-Za-z0-9][A-Za-z0-9_-]*$"#,
                options: .regularExpression
            ) != nil
    }

    private static func dataAttributeArtistSlug(
        in attributes: [String: String]
    ) -> String? {
        let keys = [
            "data-artist-slug", "data-artistslug", "data-artist-id",
            "data-artistid", "data-slug", "artist-slug"
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
           typeHint(in: attributes, containsAnyOf: ["artist"]) {
            return id
        }
        return nil
    }

    private static func dataAttributeLooksLikeArtistCard(
        _ attributes: [String: String]
    ) -> Bool {
        let keys = [
            "data-artist-slug", "data-artistslug", "data-artist-id",
            "data-artistid", "artist-slug"
        ]
        if keys.contains(where: {
            attributes[$0]?.trimmed.isEmpty == false
        }) {
            return true
        }
        return typeHint(in: attributes, containsAnyOf: ["artist"])
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
