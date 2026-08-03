import Foundation

struct PixivSearchResultResolver: SearchResultResolving {
    func supports(_ baseURL: URL) -> Bool {
        guard let host = baseURL.host?.lowercased() else { return false }
        return Self.isSupportedHost(host)
    }

    static func isSupportedHost(_ host: String) -> Bool {
        host == "pixiv.net" ||
            host == "www.pixiv.net" ||
            host == "pixiv.com" ||
            host == "www.pixiv.com" ||
            host == "pixiv.co" ||
            host == "www.pixiv.co" ||
            host == "pixiv.me" ||
            host.hasSuffix(".pixiv.me") ||
            host == "pixiv.test" ||
            host == "www.pixiv.test"
    }

    static func dataAttributeLinkValue(
        in attributes: [String: String],
        baseURL: URL?
    ) -> String? {
        guard let host = baseURL?.host?.lowercased(),
              isSupportedHost(host),
              let id = dataAttributeArtworkID(in: attributes),
              dataAttributeLooksLikeArtworkCard(attributes) else {
            return nil
        }
        return "/artworks/\(id)"
    }

    func extract(from context: SearchResultResolverContext) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByArtworkID: [String: Int] = [:]

        for anchor in context.anchors {
            guard results.count < context.limit,
                  let absolute = context.resolvedURL(for: anchor),
                  let artworkID = PixivArtworkResolver.artworkID(
                      from: absolute
                  ) else {
                continue
            }

            let target = PixivArtworkResolver.artworkURL(
                for: artworkID,
                sourceURL: absolute
            )
            let title = context.title(
                for: anchor,
                fallback: "Pixiv \(artworkID)"
            )
            SearchResultResolverSupport.appendUniqueResult(
                title: title,
                url: target,
                id: artworkID,
                sitePrefix: "pixiv",
                results: &results,
                indexByID: &indexByArtworkID,
                metadata: metadata(
                    artworkID: artworkID,
                    title: title,
                    anchor: anchor,
                    target: target,
                    context: context
                )
            )
        }

        return results
    }

    private func metadata(
        artworkID: String,
        title: String,
        anchor: AnchorEntry,
        target: URL,
        context: SearchResultResolverContext
    ) -> [String: String] {
        var metadata = [
            "id": artworkID,
            "artwork_id": artworkID,
            "illust_id": artworkID,
            "media_id": artworkID,
            "gallery_id": artworkID,
            "category": "pixiv",
            "type": "artwork",
            "title": title,
            "search_title": title
        ]
        let attributes = context.semanticAttributes(for: anchor)
        if let artist = Self.firstSemanticAttribute(
            attributes,
            keys: [
                "data-artist", "data-artist-name", "artist",
                "data-author", "data-author-name", "author",
                "data-user-name", "data-username", "username",
                "data-creator", "creator", "data-owner", "owner"
            ]
        ) ?? userInfo(
            from: anchor.contextHTML,
            baseURL: target,
            context: context
        )?.name {
            metadata["artist"] = artist
            metadata["author"] = artist
            metadata["creator"] = artist
            metadata["uploader"] = artist
            metadata["username"] = artist
        }
        if let userID = Self.firstSemanticAttribute(
            attributes,
            keys: ["data-user-id", "data-uid", "user-id", "uid"]
        ) ?? userInfo(
            from: anchor.contextHTML,
            baseURL: target,
            context: context
        )?.id {
            metadata["user_id"] = userID
            metadata["uploader_id"] = userID
            metadata["artist_id"] = userID
        }
        return DownloadMetadata.clean(metadata)
    }

    private func userInfo(
        from html: String,
        baseURL: URL,
        context: SearchResultResolverContext
    ) -> (id: String, name: String?)? {
        for entry in context.nestedAnchors(in: html) {
            guard let url = context.resolvedURL(
                for: entry,
                relativeTo: baseURL
            ),
                  let id = Self.firstCapture(
                      in: url.path,
                      pattern: #"/(?:en/)?users/([0-9]+)"#
                  ) else {
                continue
            }
            let name = context.title(for: entry, fallback: "").trimmed
            return (id, name.isEmpty ? nil : name)
        }
        return nil
    }

    private static func dataAttributeArtworkID(
        in attributes: [String: String]
    ) -> String? {
        let keys = [
            "data-illust-id", "data-illustid", "data-artwork-id",
            "data-artworkid", "data-work-id", "data-workid",
            "illust-id", "artwork-id"
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
               containsAnyOf: ["illust", "artwork", "work"]
           ) {
            return id
        }
        return nil
    }

    private static func dataAttributeLooksLikeArtworkCard(
        _ attributes: [String: String]
    ) -> Bool {
        let markerKeys = [
            "data-illust-id", "data-illustid", "data-artwork-id",
            "data-artworkid", "data-work-id", "data-workid",
            "illust-id", "artwork-id"
        ]
        if markerKeys.contains(
            where: { attributes[$0]?.trimmed.isEmpty == false }
        ) {
            return true
        }
        return typeHint(
            in: attributes,
            containsAnyOf: ["illust", "artwork", "work"]
        )
    }

    private static func isNumericID(_ value: String) -> Bool {
        value.range(
            of: #"^[0-9]+$"#,
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
}
